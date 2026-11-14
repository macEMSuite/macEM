//
//  CalibratedImage.swift
//  Role: macTEM's image — one 2D image at the bit depth its file stores (`StoredPixels`, #566) and the calibration of each axis (ImagoKit's `AxisCalibration`: the physical value at pixel i is (i - origin) * scale) exactly as the file
//        states it. Reader-independent: DM3/DM4, TIFF and MRC produce it today; Velox EMD will produce the
//        same value. Nothing here converts, guesses or rounds a calibration: a unit is the file's own
//        string ("nm", "µm" with U+00B5, "1/nm"). An axis is nil when the file writes no calibration for it;
//        GMS writes scale 1 and no unit for an uncalibrated image, which `isCalibrated` reads as uncalibrated.
//

import Foundation
import ImagoCore

package nonisolated struct CalibratedImage: Sendable, Equatable {
    package let width: Int
    package let height: Int
    /// Row-major, `width` fastest; row 0 is the file's first row and is drawn at the top. At the file's own bit depth: an 8-bit
    /// image holds one byte a pixel, as ImageJ, GMS and Velox keep it (#566).
    package let stored: StoredPixels
    /// Calibration along columns (x, the file's fastest axis) and rows (y); nil when the file has none.
    package let x: AxisCalibration?
    package let y: AxisCalibration?
    /// The file's name, never its folders (`formatoDisplayFileName`).
    package let fileName: String
    /// Which object of a multi-object file this is, as the reader names it ("ImageList.2 · HAADF").
    package let source: String
    /// Accelerating voltage in volts as the file stores it; nil when absent.
    package let voltage: Double?
    /// What a reader must say about this image beyond its numbers, in its own words ("8-bit render, not
    /// counts", or the Velox TIFF scale note, both FormatoKit's words). Empty for a file read by a published convention.
    package let notes: [String]

    /// An image of Float32 pixels.
    package init(width: Int, height: Int, pixels: [Float], x: AxisCalibration?, y: AxisCalibration?,
                 fileName: String, source: String, voltage: Double?, notes: [String] = []) {
        self.init(width: width, height: height, stored: .float32(pixels), x: x, y: y, fileName: fileName, source: source,
                  voltage: voltage, notes: notes)
    }

    /// An image of pixels at their stored bit depth.
    package init(width: Int, height: Int, stored: StoredPixels, x: AxisCalibration?, y: AxisCalibration?,
                 fileName: String, source: String, voltage: Double?, notes: [String] = []) {
        precondition(width > 0 && height > 0 && stored.count == width * height,
                     "CalibratedImage: \(stored.count) pixels for \(width) × \(height)")
        self.width = width
        self.height = height
        self.stored = stored
        self.x = x
        self.y = y
        self.fileName = fileName
        self.source = source
        self.voltage = voltage
        self.notes = notes
    }

    /// The pixels as Float32, for a computation that needs them (an FFT, a filter, a fit): a Float32 image's own array, any
    /// other a new one, 4 bytes a pixel, made on each call. Read it once per computation and let it go when the computation
    /// ends; one pixel is `value(at:)`.
    package var pixels: [Float] { stored.floats() }

    /// Pixel `index` (row-major) as Float32, without widening the image.
    package func value(at index: Int) -> Float { stored[index] }

    /// This image with other axes (the SEM record's pixel size), the same pixels.
    package func withAxes(x: AxisCalibration?, y: AxisCalibration?) -> CalibratedImage {
        CalibratedImage(width: width, height: height, stored: stored, x: x, y: y, fileName: fileName, source: source,
                        voltage: voltage, notes: notes)
    }

    /// Rows `rows` of this image as an image of their own (the same axes, file and notes), at the same bit depth.
    package func rows(_ rows: Range<Int>) -> CalibratedImage {
        precondition(rows.lowerBound >= 0 && rows.upperBound <= height && !rows.isEmpty, "CalibratedImage: rows \(rows) of \(height)")
        return CalibratedImage(width: width, height: rows.count, stored: stored.slice((rows.lowerBound * width)..<(rows.upperBound * width)),
                               x: x, y: y, fileName: fileName, source: source, voltage: voltage, notes: notes)
    }

    /// Whether the two axes state the same sampling. Exact comparison of what the file wrote: macTEM reports
    /// the file, it does not decide how close is close enough. nil when either axis is uncalibrated.
    package var hasSquarePixels: Bool? {
        guard let x, let y, x.isCalibrated, y.isCalibrated else { return nil }
        return x.scale == y.scale && x.unit == y.unit
    }
}
