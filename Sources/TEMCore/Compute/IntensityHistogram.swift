//
//  IntensityHistogram.swift
//  Role: the Image room's histogram of the RAW pixels, on ImagoKit's `IntensityHistogram` (ImagoCore): the kit's
//        `compute(_:bins:range:)` is numpy's `np.histogram` of the finite pixels (gated by ImagoKit's parity tests). What stays here is the room's choice of 96 bins.
//
//  Stays: 96 bins is the room's own choice, not a gap in the kit.
//

import ImagoCore

extension IntensityHistogram {
    /// The bins the room draws.
    package nonisolated static let binCount = 96

    /// The histogram of `pixels` over their finite range in `binCount` bins; nil when no pixel is finite.
    package nonisolated static func compute(_ pixels: [Float]) -> IntensityHistogram? {
        compute(pixels, bins: binCount)
    }

    /// The histogram of an 8-bit image's stored values (ImagoKit's `compute(stored:bins:range:)`, no Float32 copy).
    package nonisolated static func compute(stored pixels: [UInt8]) -> IntensityHistogram? {
        compute(stored: pixels, bins: binCount)
    }

    /// The histogram of a 16-bit image's stored values.
    package nonisolated static func compute(stored pixels: [UInt16]) -> IntensityHistogram? {
        compute(stored: pixels, bins: binCount)
    }
}
