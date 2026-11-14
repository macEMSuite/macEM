//
//  EELSStoredCountsTests.swift
//  A Velox EELS cube's counts are held at the precision the file needs (#620): Floats for float32 and for integers up to 2^24, which
//  Float32 holds exactly, Doubles past that and for float64. Every count equals the file's value exactly either way.
//

import XCTest
import FormatoCore
import SpectroEELS
import TEMCore

nonisolated final class EELSStoredCountsTests: XCTestCase {
    private func array<T: FixedWidthInteger>(_ type: FormatoDataType, _ values: [T]) throws -> FormatoArray {
        try FormatoArray(dataType: type, shape: [values.count], bytes: values.map(\.littleEndian).withUnsafeBytes { Data($0) })
    }

    func testIntegerCountsFloat32HoldsExactlyAreFloats() throws {
        let u16 = try array(.uint16, [0, 1, 65_535] as [UInt16])
        let counts = EELSCounts(stored: u16)
        XCTAssertEqual(counts.precision, .single)
        XCTAssertEqual(Array(counts), u16.doubles())
        let u32 = try array(.uint32, [0, 7, 1 << 24] as [UInt32])
        XCTAssertEqual(EELSCounts(stored: u32).precision, .single)
        XCTAssertEqual(Array(EELSCounts(stored: u32)), u32.doubles())
        let i32 = try array(.int32, [-(1 << 24), 3] as [Int32])
        XCTAssertEqual(EELSCounts(stored: i32).precision, .single)
        XCTAssertEqual(Array(EELSCounts(stored: i32)), [-16_777_216, 3])
    }

    func testCountsPastFloat32sIntegersStayDoubles() throws {
        let u32 = try array(.uint32, [1, (1 << 24) + 1] as [UInt32])
        let counts = EELSCounts(stored: u32)
        XCTAssertEqual(counts.precision, .double, "16777217 is not a Float")
        XCTAssertEqual(Array(counts), [1, 16_777_217])
        let i64 = try array(.int64, [-(1 << 40)] as [Int64])
        XCTAssertEqual(EELSCounts(stored: i64).precision, .double)
        XCTAssertEqual(Array(EELSCounts(stored: i64)), [-1_099_511_627_776])
    }

    func testFloatCubesKeepTheirPrecision() throws {
        let f32 = try FormatoArray(dataType: .float32, shape: [3], bytes: [Float(0.1), -2.5, 3e7].withUnsafeBytes { Data($0) })
        let single = EELSCounts(stored: f32)
        XCTAssertEqual(single.precision, .single)
        XCTAssertEqual(single.singles, [0.1, -2.5, 3e7])
        let f64 = try FormatoArray(dataType: .float64, shape: [2], bytes: [0.1, 1e300].withUnsafeBytes { Data($0) })
        let double = EELSCounts(stored: f64)
        XCTAssertEqual(double.precision, .double)
        XCTAssertEqual(Array(double), [0.1, 1e300])
    }
}
