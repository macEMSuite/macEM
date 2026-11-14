//
//  StoredPixelsCanvasTests.swift
//  An 8- or 16-bit image is drawn at its own bit depth (#566): its canvas shares the stored pixels (`native`, no Float32 copy),
//  with the range, histogram and display values the Float32 canvas of the same values has; a line profile on it reads the
//  same numbers as on its Float32 image.
//

import XCTest
import ImagoCore
import ShellMetal
import TEMCore
import TEMSession
@testable import macTEM

nonisolated final class StoredPixelsCanvasTests: XCTestCase {
    private static let width = 37, height = 23

    private static func images() -> (stored: CalibratedImage, float: CalibratedImage) {
        let values = (0..<(width * height)).map { UInt8(truncatingIfNeeded: ($0 * 37 + $0 / width * 11) % 251) }
        let stored = CalibratedImage(width: width, height: height, stored: .uint8(values), x: AxisCalibration(scale: 0.5, unit: "nm"),
                                     y: AxisCalibration(scale: 0.5, unit: "nm"), fileName: "u8.tif", source: "", voltage: nil)
        let float = CalibratedImage(width: width, height: height, pixels: values.map(Float.init), x: stored.x, y: stored.y,
                                    fileName: "u8.tif", source: "", voltage: nil)
        return (stored, float)
    }

    /// Red before: the canvas of every image was its Float32 pixels.
    func testAn8BitCanvasHoldsTheStoredPixelsAndDrawsTheSameValues() {
        let (stored, float) = Self.images()
        let canvas = CanvasPixels.make(image: stored), reference = CanvasPixels.make(image: float)
        XCTAssertEqual(canvas.native, stored.stored, "the stored pixels, not a Float32 copy")
        XCTAssertTrue(canvas.values.isEmpty)
        XCTAssertNotNil(canvas.metalNative)
        XCTAssertNil(reference.native)
        XCTAssertEqual(canvas.count, Self.width * Self.height)
        XCTAssertEqual(canvas.rawRange, reference.rawRange)
        XCTAssertEqual(canvas.scale, reference.scale)
        XCTAssertEqual(canvas.histogram, reference.histogram)
        XCTAssertEqual(canvas.normalized, reference.normalized)
        XCTAssertEqual(canvas.thumbnail(), reference.thumbnail())
        let other = CanvasPixels.make(image: CalibratedImage(width: Self.width, height: Self.height,
                                                             stored: .uint8([UInt8](repeating: 7, count: Self.width * Self.height)),
                                                             x: nil, y: nil, fileName: "b", source: "", voltage: nil))
        XCTAssertNotEqual(canvas.contentVersion, other.contentVersion, "other pixels, another version")
    }

    /// A profile on the 8-bit image reads only the box around the line and gives the Float32 image's profile: the same
    /// positions, samples equal to rounding (the ends move by whole pixels). Red under: a box too small for the width.
    func testAProfileOnAStoredImageIsTheProfileOnItsFloatImage() {
        let (stored, float) = Self.images()
        for (a, b, w) in [(ImagePoint(x: 3.2, y: 4.7), ImagePoint(x: 30.1, y: 17.9), 1),
                          (ImagePoint(x: 0, y: 0), ImagePoint(x: 36, y: 22), 5),
                          (ImagePoint(x: 18, y: 2), ImagePoint(x: 18.5, y: 20), 9),
                          // Outside the image: reflect reads the mirrored pixels inside it.
                          (ImagePoint(x: -10, y: 5), ImagePoint(x: -3, y: 12), 3),
                          (ImagePoint(x: 40, y: -6), ImagePoint(x: 45, y: 30), 7)] {
            let p = LineProfile.sample(stored, from: a, to: b, width: w), q = LineProfile.sample(float, from: a, to: b, width: w)
            XCTAssertEqual(p.positions, q.positions)
            XCTAssertEqual(p.samples.count, q.samples.count)
            for (s, t) in zip(p.samples, q.samples) { XCTAssertEqual(s, t, accuracy: 1e-9, "\(a) → \(b), width \(w)") }
        }
    }
}
