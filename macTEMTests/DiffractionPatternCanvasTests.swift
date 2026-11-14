//
//  DiffractionPatternCanvasTests.swift
//  How the Diffraction room's pattern reaches the screen (#336): the canvas of the display values is TEMSession's
//  (`CanvasPixels.pattern`, beside the Image room's `CanvasPixels.make`), and showing a pattern is asked of the view's owner
//  (`DiffractionViewState.show`: the bind, the pattern's extent, the canvas), as the FFT room asks its own. The pixels drawn are the
//  ones the view built before: the same normalisation of the same values, the same histogram. Since #580 the canvas is the file's
//  own pixels and the log is the view's shader transfer: no log copy of a 375 MP pattern.
//  Red before the change: no `CanvasPixels.pattern`, no `DiffractionViewState.show`; the view's task did the three steps itself
//  through two statics no test reached.
//

import XCTest
import ShellMetal
import ImagoCore
import TEMCore
import TEMSession

nonisolated final class DiffractionPatternCanvasTests: XCTestCase {

    /// The canvas holds the file's own pixels (no copy) and draws them, log or linear, as `DisplayNormalization.normalizedLog` and `normalized` give the
    /// display values, bit for bit (ImagoKit's `DisplayNormalization`). Log: the view's transfer is `.log`, the range 0…1 and the histogram of the log values drawn.
    /// Linear: the Image room's canvas of the same image. Red under: a log copy of the pixels (#580); the raw pixels drawn linear
    /// for a log display; the histogram of the raw pixels for a log one; log and linear sharing a version (no upload on a switch).
    func testThePatternsCanvasIsItsPixelsDrawnAsItsDisplayValues() {
        let image = DemoDocuments.diffractionPattern()
        var versions: [Int] = []
        for log in [true, false] {
            let canvas = CanvasPixels.pattern(image: image, log: log)
            let expected = log ? DisplayNormalization.normalizedLog(image.pixels) : DisplayNormalization.normalized(image.pixels)
            XCTAssertEqual(canvas.width, image.width)
            XCTAssertEqual(canvas.height, image.height)
            XCTAssertEqual(canvas.values, image.pixels, "log \(log): the file's pixels, not display values")
            XCTAssertEqual(canvas.normalized, expected, "log \(log): the display values, bit for bit")
            XCTAssertEqual(canvas.transfer, log ? .log : .linear)
            if log {
                XCTAssertEqual(canvas.rawRange, Float(0)...Float(1))
                XCTAssertEqual(canvas.histogram, IntensityHistogram.compute(expected), "the histogram of what is drawn")
            } else {
                XCTAssertEqual(canvas, CanvasPixels.make(image: image), "linear is the Image room's canvas")
            }
            versions.append(canvas.contentVersion)
        }
        XCTAssertNotEqual(versions[0], versions[1], "log and linear are two pictures: the view uploads again")
    }

    /// A 16-bit pattern stays at two bytes a pixel, drawn log: the canvas shares the image's stored pixels and builds no Float32
    /// array. Over `histogramSampleCap` pixels the histogram reads an even sample with the extremes, so it spans 0…1 still.
    /// Red under: a Float32 log copy of the pixels; a histogram of every pixel of a 375 MP pattern.
    func testASixteenBitPatternIsDrawnLogFromItsStoredPixels() throws {
        let side = 1100
        let stored = (0..<(side * side)).map { UInt16(($0 * 37) % 60_000) }
        let image = CalibratedImage(width: side, height: side, stored: .uint16(stored), x: nil, y: nil, fileName: "p.tif",
                                    source: "planted", voltage: nil)
        let canvas = CanvasPixels.pattern(image: image, log: true)
        XCTAssertTrue(canvas.values.isEmpty, "no Float32 array")
        XCTAssertEqual(canvas.native, .uint16(stored))
        XCTAssertEqual(canvas.transfer, .log)
        XCTAssertEqual(canvas.normalizedValue(at: 0), 0, "the darkest pixel is 0")
        let brightest = try XCTUnwrap(stored.indices.max { stored[$0] < stored[$1] })
        XCTAssertEqual(canvas.normalizedValue(at: brightest), 1)
        let middle = 12_345
        let expected = log10(1 + Double(stored[middle])) / log10(1 + Double(stored[brightest]))
        XCTAssertEqual(Double(canvas.normalizedValue(at: middle)), expected, accuracy: 1e-6)
        let histogram = try XCTUnwrap(canvas.histogram)
        XCTAssertEqual(histogram.minimum, 0)
        XCTAssertEqual(histogram.maximum, 1)
        XCTAssertLessThanOrEqual(histogram.finiteCount, CanvasPixels.histogramSampleCap + 2)
    }

    /// Showing a pattern binds the results owner to the image, opens the view on the pattern's own extent and draws the canvas, in log
    /// first; switching Log draws the linear canvas and starts the contrast window whole again, and the same canvas again keeps it.
    /// Red under: the analysis left unbound (no centre), the extent not set (the pane opens on the whole frame), the window kept
    /// across a log switch (a window in log values over linear ones), or reset on every pass.
    @MainActor func testShowingAPatternBindsFindsTheExtentAndDrawsTheCanvas() async {
        let image = DemoDocuments.diffractionPattern()
        let analysis = DiffractionAnalysis()
        let view = DiffractionViewState()
        XCTAssertNil(analysis.centre)
        XCTAssertNil(view.presentation.canvas)

        await view.show(image: image, analysis: analysis)
        let centre = DiffractionCentre.imageCentre(width: image.width, height: image.height)
        XCTAssertEqual(analysis.centre, centre, "the results owner is bound to the image")
        let extent = DiffractionCompute.contentRadius(pixels: image.pixels, width: image.width, height: image.height, centre: centre)
        XCTAssertNotNil(extent, "the demo pattern has an extent of its own")
        XCTAssertEqual(view.autoHalfSide, extent, "the view opens on the pattern")
        XCTAssertEqual(view.presentation.canvas, CanvasPixels.pattern(image: image, log: true))

        view.presentation.windowLow = 0.25
        view.useLog = false
        await view.show(image: image, analysis: analysis)
        XCTAssertEqual(view.presentation.canvas, CanvasPixels.pattern(image: image, log: false))
        XCTAssertNil(view.presentation.windowLow, "a window in log values means nothing in linear ones")

        view.presentation.windowLow = 0.25
        await view.show(image: image, analysis: analysis)
        XCTAssertEqual(view.presentation.windowLow, 0.25, "the same picture again keeps its window")
    }

    /// The room's task makes the one call, and the view file computes nothing off the main actor itself.
    /// Red under: the bind, the extent or the canvas back in the view's task.
    func testTheRoomAsksItsOwnerToShowThePattern() throws {
        let room = try FFTRoomWiringTests.squeezedUI("DiffractionRoom.swift")
        XCTAssertTrue(room.contains(".task(id: DisplayKey(id: item.id, log: view.useLog, width: image.width, height: image.height)) { "
            + "await view.show(image: image, analysis: analysis) }"))
        XCTAssertFalse(room.contains("@concurrent"), "nothing is computed in the view file")
        XCTAssertFalse(room.contains("analysis.bind("), "the bind is the owner's")
        XCTAssertFalse(room.contains("CanvasPixels("), "the canvas is TEMSession's")
    }
}
