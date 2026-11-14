//
//  LineProfile.swift
//  Role: the intensity along a line segment on a CalibratedImage, averaged across a width. The type and the numbers are
//        ImagoKit's `LineProfile` (order 1 (bilinear), mode "reflect", the mean across the width, float64 arithmetic;
//        tools/parity/profile-parity checks it against scikit-image 0.26.0).
//
//  What stays here is the seam, two answers that differ from the kit's, as the app's always did: a width below 1 is read as 1
//  (the kit throws), and a segment the kit refuses (a non-finite end, an end beyond 1e15 px, more than 2²⁴ samples) is an EMPTY
//  profile, not an error.
//

import ImagoCore

extension LineProfile {
    package nonisolated static func sample(_ image: CalibratedImage, from: ImagePoint, to: ImagePoint, width: Int) -> LineProfile {
        let w = max(1, width)
        let (micrograph, a, b) = around(image, from: from.pixelPoint, to: to.pixelPoint, width: w)
        if let p = try? sample(micrograph, from: a, to: b, linewidth: w,
                               order: .linear, mode: .reflect, reduce: .mean, arithmetic: .float64) {
            return p
        }
        let length = ImageMeasurement.distance(from, to, x: image.x, y: image.y)
        return LineProfile(samples: [], positions: [], unit: length.unit ?? "px", isPhysical: length.unit != nil, width: w)
    }
}

extension LineProfile {
    /// The pixels a profile reads, as the kit's image, and its ends in that image's pixels. A Float32 image is itself (no copy).
    /// An 8- or 16-bit image is widened only in the box the profile can touch (#566): the segment's bounds, half the width and two
    /// pixels for the bilinear neighbours each side, and the mirror of any part past an image edge (mode reflect reads it back
    /// inside), clipped to the image: an edge the box shares with the image reflects as the image's does, and no sample reads
    /// past a box edge inside the image. The ends move by whole pixels; the positions are
    /// lengths along the line, the same in either image.
    nonisolated static func around(_ image: CalibratedImage, from: PixelPoint, to: PixelPoint,
                                   width: Int) -> (Micrograph, PixelPoint, PixelPoint) {
        if case .float32 = image.stored { return (image.micrograph, from, to) }
        let margin = Double(width) / 2 + 2
        var lowX = min(from.x, to.x) - margin, highX = max(from.x, to.x) + margin
        var lowY = min(from.y, to.y) - margin, highY = max(from.y, to.y) + margin
        // reflect: −k reads k − 1, n − 1 + k reads n − k; the reach past an edge comes back that far inside it.
        let n = Double(image.width), m = Double(image.height)
        if lowX < 0 { highX = max(highX, -lowX) }
        if highX > n - 1 { lowX = min(lowX, 2 * n - 2 - highX) }
        if lowY < 0 { highY = max(highY, -lowY) }
        if highY > m - 1 { lowY = min(lowY, 2 * m - 2 - highY) }
        // A segment the kit refuses (a non-finite or far end) is handed over whole, so the kit refuses it as before.
        guard [lowX, highX, lowY, highY].allSatisfy({ $0.isFinite && abs($0) < 1e9 }) else { return (image.micrograph, from, to) }
        let x0 = min(max(Int(lowX.rounded(.down)), 0), image.width - 1), x1 = min(max(Int(highX.rounded(.up)) + 1, x0 + 1), image.width)
        let y0 = min(max(Int(lowY.rounded(.down)), 0), image.height - 1), y1 = min(max(Int(highY.rounded(.up)) + 1, y0 + 1), image.height)
        let w = x1 - x0, h = y1 - y0
        var pixels = [Float](repeating: 0, count: w * h)
        for r in 0..<h {
            let source = (y0 + r) * image.width + x0
            for c in 0..<w { pixels[r * w + c] = image.value(at: source + c) }
        }
        guard let box = try? Micrograph(width: w, height: h, pixels: pixels, x: image.x, y: image.y) else {
            return (image.micrograph, from, to)
        }
        let dx = Double(x0), dy = Double(y0)
        return (box, PixelPoint(x: from.x - dx, y: from.y - dy), PixelPoint(x: to.x - dx, y: to.y - dy))
    }
}

extension LineProfile: @retroactive Equatable {
    public static func == (a: LineProfile, b: LineProfile) -> Bool {
        a.samples == b.samples && a.positions == b.positions && a.unit == b.unit && a.isPhysical == b.isPhysical && a.width == b.width
    }
}
