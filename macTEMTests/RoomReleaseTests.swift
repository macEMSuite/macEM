//
//  RoomReleaseTests.swift
//  Release probes per room (#617, as #584 did for EELS): open, close, and every full-size array the room held is gone, even while a
//  view still holds the owner. The Image room's Diffraction canvas and particle mask preview go with the file; a window closed with
//  nothing to lose closes its orientation map; closing the Patterns, Maps and Indexing rooms lets go of their canvases.
//

import XCTest
@testable import macTEM
import TEMCore
import TEMSession

nonisolated final class RoomReleaseTests: XCTestCase {
    private static let sdss = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures").appendingPathComponent("ebsd-sdss-ferrite-austenite.ang")
    private static let scan = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures").appendingPathComponent("ebsd-kikuchipy-h5ebsd.h5")

    final class Weak<T: AnyObject> { weak var value: T?; init(_ value: T) { self.value = value } }

    private func plantedCopy() throws -> URL {
        let source = try XCTUnwrap(Bundle(for: RoomReleaseTests.self).url(forResource: "planted-2d", withExtension: "dm4"),
                                   "planted-2d.dm4 is not in the test bundle")
        let folder = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("mactem-release-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("planted.dm4")
        try FileManager.default.copyItem(at: source, to: url)
        return url
    }

    /// Red before: `releasePixels` left the Diffraction room's canvas and the particle mask preview (375 MB at 19433 × 19320) to whoever
    /// still held the view state or the analysis.
    @MainActor func testClosingAFileLetsGoOfItsDiffractionCanvasAndParticleMask() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.open(urls: [try plantedCopy()])?.value
        // The item is held only inside this scope: the test's own reference must not keep it alive past the close.
        let (view, particles, watched) = try await { @MainActor () async throws -> (DiffractionViewState, ParticleAnalysis, Weak<OpenItem>) in
            let item = try XCTUnwrap(state.openItems.selected)
            let image = try XCTUnwrap(item.session.image)
            let view = item.diffractionView, particles = item.particles
            await view.show(image: image, analysis: item.diffraction)
            particles.setPreviewsMask(true)
            await particles.updatePreview(image: image)?.value
            return (view, particles, Weak(item))
        }()
        XCTAssertNotNil(view.presentation.canvas, "the room drew the pattern")
        XCTAssertNotNil(particles.maskPreview, "the preview was made")

        state.openItems.closeSelected()
        await state.openItems.settled()
        XCTAssertNil(view.presentation.canvas, "the Diffraction canvas goes with the file, though the view state is still held")
        XCTAssertNil(particles.maskPreview, "the mask preview too")
        try await waitUntil("the closed item to be released") { watched.value == nil }
    }

    /// Red before: `releaseFiles` left the Maps room open, so a standalone map stayed for the app's life; `close` kept the property canvas.
    @MainActor func testAWindowClosedWithNothingToLoseClosesItsMap() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.maps.open(url: Self.sdss).value
        try await waitUntil("the map to be drawn", seconds: 30) { !state.maps.isBusy }
        XCTAssertTrue(state.maps.hasMap)
        let presentation = state.maps.propertyPresentation
        state.releaseFiles()
        XCTAssertFalse(state.maps.hasMap, "the window's map is closed with it")
        XCTAssertNil(state.maps.raster)
        XCTAssertNil(state.maps.rasterRGBA, "the coloured raster goes")
        XCTAssertNil(presentation.canvas, "and the property canvas")
    }

    /// Red before: closing the Patterns room kept the pattern and map canvases on their presentations.
    @MainActor func testClosingThePatternsRoomLetsGoOfItsCanvases() async throws {
        let state = AppState(launch: LaunchOptions(arguments: []))
        await state.ebsd.open(url: Self.scan).value
        try await waitUntil("the scan's passes to end", seconds: 30) {
            !state.ebsd.isBusy && !state.ebsd.isComputingMean && !state.maps.isBusy && state.ebsd.patternPresentation.canvas != nil
        }
        XCTAssertNotNil(state.ebsd.mapPresentation.canvas, "the mean map is drawn")
        state.ebsd.close()
        XCTAssertNil(state.ebsd.patternPresentation.canvas)
        XCTAssertNil(state.ebsd.mapPresentation.canvas)
        XCTAssertNil(state.indexing.mapPresentation.canvas)
        XCTAssertNil(state.indexing.patternPresentation.canvas)
        XCTAssertFalse(state.maps.hasMap, "the scan's own map goes with it")
    }
}
