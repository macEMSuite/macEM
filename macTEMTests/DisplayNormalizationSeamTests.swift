//
//  DisplayNormalizationSeamTests.swift
//  `FloatImage` normalises for display through ImagoKit's `DisplayNormalization`: the same values, the same masked sentinel,
//  the same finite range, linear and symmetric. A pattern's log display is `CanvasPixels.pattern` (DiffractionPatternCanvasTests).
//

import XCTest
import ImagoCore
import TEMCore

nonisolated final class DisplayNormalizationSeamTests: XCTestCase {

    private let pixels: [Float] = [-3, 0, 0.5, 7, .nan, .infinity, 1e6, -.infinity]

    func testFloatImageIsTheKitNormalisation() {
        let image = FloatImage(width: 4, height: 2, pixels: pixels)
        XCTAssertEqual(FloatImage.invalidDisplayValue, DisplayNormalization.invalidValue)
        XCTAssertEqual(image.normalized(), DisplayNormalization.normalized(pixels))
        XCTAssertEqual(image.normalized(symmetric: true), DisplayNormalization.normalized(pixels, symmetric: true))
        XCTAssertEqual(image.minMax.0, -3)
        XCTAssertEqual(image.minMax.1, 1e6)
    }
}
