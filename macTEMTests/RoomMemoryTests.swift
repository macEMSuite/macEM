//
//  RoomMemoryTests.swift
//  The image rooms give their memory back (#577): a large image opened in a window that draws (`ContentView` in an `NSHostingView`),
//  shown in the Image, FFT, Diffraction and Results rooms and closed, leaves the process's physical footprint where it was before the
//  open. A view, `@State`, closure, binding or preference that kept the image (#574, #576) would keep its pixels after the close;
//  `PixelOwnershipTests` reads the sources for the stored ones, this test catches what the scan cannot see (a closure's capture).
//
//  THE TRUTH: a 3072 × 3072 16-bit TIFF (18 MB as stored, 38 MB as Float32), written here. The rooms are drawn once with a small copy
//  first, so what the first draw loads for good (the shaders, SwiftUI's caches) is in the baseline. The measure is
//  `ImageStackTests.footprint()`, taken with the window drawing and no file open, before and after.
//

import AppKit
import ShellLayout
import SwiftUI
import XCTest
import TEMSession
@testable import macTEM

nonisolated final class RoomMemoryTests: XCTestCase {

    private static let side = 3072
    private static let rooms: [WorkspaceArea] = [.image, .fft, .diffraction, .results]

    private func scratchImage(side: Int) throws -> URL {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("room-memory-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: dir) }
        let url = dir.appendingPathComponent("large-\(side).tif")
        try DemoDocuments.writeStackTIFF(to: url, frames: 1, width: side, height: side) { _, x, y in UInt16((x * 7 + y * 13) % 4096) }
        return url
    }

    /// Opens `url` in `state`, shows it in each image room with the window drawing, and closes it; waits until the item, its session
    /// and its presentation are gone. Returns the footprint while the file was open (the largest seen).
    @MainActor private func openVisitClose(_ url: URL, state: AppState, host: NSView) async throws -> Int {
        final class Weak<T: AnyObject> { weak var value: T?; init(_ value: T) { self.value = value } }
        await state.open(urls: [url])?.value
        let item = try XCTUnwrap(state.openItems.selected, "the image opened")
        XCTAssertNil(item.readFailure)
        let watched = (item: Weak(item), session: Weak(item.session), presentation: Weak(item.presentation))
        var peak = 0
        for room in Self.rooms {
            state.selectWorkspace(room)
            XCTAssertEqual(state.navigation.workspaceArea, room, "\(room.title) can be entered")
            host.layoutSubtreeIfNeeded()
            host.display()
            // The room's own work (the FFT's spectrum, the histogram) runs off the main actor; let it land and draw.
            try await Task.sleep(for: .milliseconds(300))
            host.layoutSubtreeIfNeeded()
            host.display()
            peak = max(peak, ImageStackTests.footprint())
        }
        state.selectWorkspace(.image)
        state.openItems.close(item.id)
        await state.openItems.settled()
        host.layoutSubtreeIfNeeded()
        host.display()
        try await waitUntil("the closed item, its session and its presentation to be released", seconds: 10) {
            watched.item.value == nil && watched.session.value == nil && watched.presentation.value == nil
        }
        return peak
    }

    /// Red under: a room's view, closure or preference keeping the image or its canvas after the close (#574 kept a 375 MB TIFF's
    /// 1.5 GB in a hover closure); the session or presentation not released.
    @MainActor func testTheImageRoomsGiveAClosedImagesMemoryBack() async throws {
        let small = try scratchImage(side: 256)
        let large = try scratchImage(side: Self.side)
        let state = AppState(launch: LaunchOptions(arguments: []))
        let host = NSHostingView(rootView: ContentView().environment(state))
        let window = NSWindow(contentRect: NSRect(origin: .zero, size: LayoutPolicy.datasetWindowIdealSize),
                              styleMask: [.titled, .resizable], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.contentView = host
        defer { window.contentView = nil; window.close() }

        _ = try await openVisitClose(small, state: state, host: host)
        let before = ImageStackTests.footprint()
        let open = try await openVisitClose(large, state: state, host: host)
        let after = ImageStackTests.footprint()

        let stored = Self.side * Self.side * 2
        XCTAssertGreaterThan(open - before, stored, "the measure sees the open image (\(open - before) bytes over the baseline)")
        XCTAssertLessThan(after - before, stored / 2,
                          "after the close the footprint is \(after - before) bytes over the baseline; the image is \(stored) bytes as stored")
    }
}
