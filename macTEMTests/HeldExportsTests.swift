//
//  HeldExportsTests.swift
//  What the app keeps after an export (#619): the session record keeps a picture no larger than the report draws, with its own size
//  noted; a room lets go of an export's bytes once its save panel is done.
//

import CoreGraphics
import Foundation
import ImageIO
import TEMCore
import TEMSession
import UniformTypeIdentifiers
import XCTest
@testable import macTEM

nonisolated final class HeldExportsTests: XCTestCase {
    private static let sdss = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        .appendingPathComponent("Fixtures").appendingPathComponent("ebsd-sdss-ferrite-austenite.ang")

    /// A grey PNG of `width` x `height`.
    private static func png(width: Int, height: Int) throws -> Data {
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                              space: CGColorSpaceCreateDeviceGray(), bitmapInfo: CGImageAlphaInfo.none.rawValue))
        context.setFillColor(gray: 0.5, alpha: 1)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try XCTUnwrap(context.makeImage())
        let out = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(out, UTType.png.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, nil)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        return out as Data
    }

    /// Red before: the record kept every exported PNG at its own size for the session's life.
    @MainActor func testTheRecordKeepsALargePictureSmallerWithItsOwnSize() throws {
        let record = SEMSessionRecord()
        record.wrote(SEMExportedFile(room: "Maps", what: "Map PNG", source: "big.ang", png: try Self.png(width: 4000, height: 500)))
        record.wrote(SEMExportedFile(room: "Maps", what: "Map PNG", source: "small.ang", png: try Self.png(width: 75, height: 55)))
        let big = try XCTUnwrap(SEMReportFigure(png: try XCTUnwrap(record.exports[0].png), caption: "", file: nil))
        XCTAssertEqual(big.pixelWidth, SEMSessionRecord.figureSide, "kept at most the figure side")
        XCTAssertEqual(record.exports[0].pixelWidth, 4000)
        XCTAssertEqual(record.exports[0].pixelHeight, 500)
        XCTAssertNil(record.exports[1].pixelWidth, "a small picture is kept as written")
        let rows = SEMSessionLedger.exportRows(record)
        XCTAssertEqual(rows[0].value, "Map PNG, 4000 × 500 px", "the report names the picture's own size")
        XCTAssertEqual(rows[1].value, "Map PNG, 75 × 55 px")
    }

    /// Red before: the room kept the bytes of its last export until the next one.
    @MainActor func testARoomLetsGoOfItsExportOnceThePanelIsDone() async throws {
        let session = OrientationMapSession()
        await session.open(url: Self.sdss).value
        try await waitUntil("the map to be drawn", seconds: 30) { !session.isBusy && session.raster != nil }
        let state = MapsRoomState()
        state.exportMap(from: session) { _ in }
        XCTAssertFalse(state.exportData.isEmpty, "the panel's bytes")
        state.didWrite(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("map.png"))
        XCTAssertTrue(state.exportData.isEmpty, "let go once written")
        state.exportMap(from: session) { _ in }
        state.didFinishExport()
        XCTAssertTrue(state.exportData.isEmpty, "and when the panel closes without writing")
    }
}
