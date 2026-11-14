//
//  PixelOwnershipTests.swift
//  The ownership rule, checked (#577): one owner holds a file's data (`OpenItem`, its session and presentation, the room
//  sessions); a view holds the owner and reads the pixels through it. A view that stores an image, a canvas or a pixel array
//  keeps it alive for as long as SwiftUI keeps any copy of the view, its hover and gesture closures included (#574: the
//  375 MB SEM TIFF's 1.5 GB of pixels outlived its tab in a HoverResponder's closure). The scan reads the views' stored
//  properties in `macTEM/UI`; CONTRIBUTING.md states the rule.
//

import XCTest

nonisolated final class PixelOwnershipTests: XCTestCase {

    /// The types that hold a file's data (an image, its display canvas, a pixel or sample array).
    static let heldTypes = ["CalibratedImage", "CanvasPixels", "SpectrumImage", "[Float]", "[Double]", "[UInt8]", "[UInt16]"]

    /// Views allowed to store one, each with its reason.
    static let allowed: [String: String] = [
        // The vendor databar's few rows, drawn once from a small grey CGImage; no closure, and Equatable so SwiftUI skips it.
        "DatabarStrip.strip": "a few rows, no closures",
        // The kinematical master pattern's preview (drawn 180 pt wide), a copy of the session's per-phase cache, not the file's data.
        "SimulationOverlayControls.masterPicture": "a preview, not the file's data",
    ]

    private static let root = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        .deletingLastPathComponent().deletingLastPathComponent()

    /// `Type.property: declared type` for every stored property of a `View` or `ViewModifier` declared in `text` whose type
    /// names one of `heldTypes`. A stored property is one at the type's member indent with no body (`{`); comments are dropped.
    static func heldProperties(in text: String) -> [String] {
        var found: [String] = []
        var current: String?
        let declaration = /^(?:(?:private|fileprivate|public|package)\s+)?(?:nonisolated\s+)?(?:final\s+)?(?:struct|class|enum|extension|actor)\s+(\w+)([^{]*)/
        let property = /^    (?:@\w+(?:\([^)]*\))?\s+)*(?:(?:private|fileprivate)(?:\(set\))?\s+)?(?:let|var)\s+(\w+)\s*:\s*([^={]+?)\s*(=.*)?$/
        for raw in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = raw.range(of: "//").map { String(raw[..<$0.lowerBound]) } ?? String(raw)
            if let match = line.firstMatch(of: declaration) {
                let header = String(match.2)
                current = header.contains("View") || header.contains("ViewModifier") ? String(match.1) : nil
                continue
            }
            guard let type = current, !line.contains("{"), let match = line.firstMatch(of: property) else { continue }
            let declared = String(match.2)
            if heldTypes.contains(where: { declared.contains($0) }) { found.append("\(type).\(match.1): \(declared)") }
        }
        return found
    }

    /// Red before: 24 views stored the image (`let image: CalibratedImage`), the Info section the canvas, the compared map tile
    /// its pixels; a closure SwiftUI kept of any of them kept the file's pixels after its tab closed.
    func testNoViewStoresAFilesPixels() throws {
        let folder = Self.root.appendingPathComponent("macTEM/UI")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertGreaterThan(files.count, 40, "the scan reads the UI folder")
        var offenders: [String] = []
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8)
            offenders += Self.heldProperties(in: text).filter { held in
                !Self.allowed.keys.contains { held.hasPrefix($0 + ":") }
            }.map { "\(file.lastPathComponent): \($0)" }
        }
        XCTAssertEqual(offenders, [], "hold the owner (OpenItem, ImageSession, ImagePresentation, the room session) and read the pixels through it")
    }

    /// The scan finds a stored image, an `@State` array and an optional canvas in a view, and passes a computed property, a
    /// non-view type and a comment. Red under: a scan that finds nothing.
    func testTheScanFindsAStoredImage() {
        let text = """
        struct Pane: View, Equatable {
            let image: CalibratedImage
            @State private var mask: [UInt8]? = nil
            var canvas: CanvasPixels?
            private var shown: CalibratedImage { session.imageOrBlank }
            // let old: CalibratedImage
            let item: OpenItem
        }
        nonisolated struct Layer {
            let canvas: CanvasPixels
        }
        """
        XCTAssertEqual(Self.heldProperties(in: text),
                       ["Pane.image: CalibratedImage", "Pane.mask: [UInt8]?", "Pane.canvas: CanvasPixels?"])
    }
}
