//
//  EELSStoredCounts.swift
//  A cube's counts as the file stores them (#620): single precision where every value is exact in Float32 (a float32 file,
//  and integer counts up to 2^24), Double only where Float32 would round one. The numbers are the file's, exactly: only the
//  bytes a count takes change, 4 instead of 8.
//

import Foundation
import FormatoCore
import SpectroEELS

extension EELSCounts {
    /// Integers up to this magnitude are exact in Float32 (its 24-bit significand).
    package static let exactFloatInteger: Int64 = 1 << 24

    /// The counts of `array`, held as Floats when every value is exactly a Float (float32, the 8- and 16-bit integers, and the
    /// wider integers while each is at most 2^24 in magnitude), else as Doubles (float64, and integers past 2^24). One pass over
    /// the stored bytes builds the Floats; no Double copy is made on that route.
    package init(stored array: FormatoArray) {
        let n = array.count * array.dataType.components
        func singles(_ value: (UnsafeRawBufferPointer, Int) -> Float) -> [Float] {
            array.bytes.withUnsafeBytes { p in
                [Float](unsafeUninitializedCapacity: n) { buffer, count in
                    for i in 0..<n { buffer[i] = value(p, i) }
                    count = n
                }
            }
        }
        /// True when every wide integer fits Float exactly.
        func fits<T: FixedWidthInteger>(_: T.Type) -> Bool {
            array.bytes.withUnsafeBytes { p in
                for i in 0..<n {
                    let v = Int64(clamping: T(littleEndian: p.loadUnaligned(fromByteOffset: i * MemoryLayout<T>.size, as: T.self)))
                    if v > Self.exactFloatInteger || v < -Self.exactFloatInteger { return false }
                }
                return true
            }
        }
        switch array.dataType {
        case .float32:
            self.init(singles { p, i in Float(bitPattern: UInt32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: UInt32.self))) })
        case .uint8, .rgb8, .rgba8:
            self.init(singles { p, i in Float(p.loadUnaligned(fromByteOffset: i, as: UInt8.self)) })
        case .int8:
            self.init(singles { p, i in Float(p.loadUnaligned(fromByteOffset: i, as: Int8.self)) })
        case .uint16, .rgb16, .rgba16:
            self.init(singles { p, i in Float(UInt16(littleEndian: p.loadUnaligned(fromByteOffset: 2 * i, as: UInt16.self))) })
        case .int16:
            self.init(singles { p, i in Float(Int16(littleEndian: p.loadUnaligned(fromByteOffset: 2 * i, as: Int16.self))) })
        case .uint32 where fits(UInt32.self):
            self.init(singles { p, i in Float(UInt32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: UInt32.self))) })
        case .int32 where fits(Int32.self):
            self.init(singles { p, i in Float(Int32(littleEndian: p.loadUnaligned(fromByteOffset: 4 * i, as: Int32.self))) })
        case .uint64 where fits(UInt64.self):
            self.init(singles { p, i in Float(UInt64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: UInt64.self))) })
        case .int64 where fits(Int64.self):
            self.init(singles { p, i in Float(Int64(littleEndian: p.loadUnaligned(fromByteOffset: 8 * i, as: Int64.self))) })
        default:
            self.init(array.doubles())
        }
    }
}
