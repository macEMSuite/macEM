//
//  StoredPixels.swift
//  Role: an image's pixels at the bit depth its file stores them (#566). ImageJ/Fiji, GMS and Velox keep an image at its own
//        depth and make Float32 only for a computation that needs it; so does macEM: an 8-bit SEM TIFF of 375 MP holds 375 MB,
//        not 1.5 GB. Unsigned 8 and 16 bit (what the canvas draws at its own depth, `MetalImageView.NativePixels`) stay as
//        stored; every other type is Float32, value for value what every image was before.
//

import Foundation
import FormatoCore

package nonisolated enum StoredPixels: Sendable, Equatable {
    case uint8([UInt8])
    case uint16([UInt16])
    case float32([Float])

    /// The pixels of a reader's array: its own type where it is one of the above, else its values as Float32
    /// (`FormatoArray.floats()`, value for value what the readers' Float32 images held).
    package init(_ array: FormatoArray) {
        let bytes = array.bytes
        func values<T>(_: T.Type) -> [T] {
            let count = bytes.count / MemoryLayout<T>.stride
            return [T](unsafeUninitializedCapacity: count) { buffer, initialised in
                _ = bytes.copyBytes(to: buffer)
                initialised = count
            }
        }
        switch array.dataType {
        case .uint8: self = .uint8(values(UInt8.self))
        // FormatoArray's bytes are little-endian, as every Mac's are: copied as they are, no second pass.
        case .uint16: self = .uint16(values(UInt16.self))
        case .float32: self = .float32(values(Float.self))
        default: self = .float32(array.floats())
        }
    }

    package var count: Int {
        switch self {
        case .uint8(let v): v.count
        case .uint16(let v): v.count
        case .float32(let v): v.count
        }
    }

    /// Bytes a pixel takes.
    package var bytesPerPixel: Int {
        switch self {
        case .uint8: 1
        case .uint16: 2
        case .float32: 4
        }
    }

    /// Pixel `index` as Float32 (exact: every stored type here is).
    package subscript(index: Int) -> Float {
        switch self {
        case .uint8(let v): Float(v[index])
        case .uint16(let v): Float(v[index])
        case .float32(let v): v[index]
        }
    }

    /// Every pixel as Float32: a Float32 image's own array (shared, no copy), any other a new one, value for value.
    package func floats() -> [Float] {
        switch self {
        case .uint8(let v): v.map(Float.init)
        case .uint16(let v): v.map(Float.init)
        case .float32(let v): v
        }
    }

    /// The same values, whatever the bit depth they are kept at: an 8-bit file and the Float32 image of its values are one image.
    package static func == (a: StoredPixels, b: StoredPixels) -> Bool {
        switch (a, b) {
        case (.uint8(let x), .uint8(let y)): x == y
        case (.uint16(let x), .uint16(let y)): x == y
        case (.float32(let x), .float32(let y)): x == y
        default: a.count == b.count && (0..<a.count).allSatisfy { a[$0] == b[$0] }
        }
    }

    /// Pixels `range`, at the same bit depth.
    package func slice(_ range: Range<Int>) -> StoredPixels {
        switch self {
        case .uint8(let v): .uint8(Array(v[range]))
        case .uint16(let v): .uint16(Array(v[range]))
        case .float32(let v): .float32(Array(v[range]))
        }
    }
}
