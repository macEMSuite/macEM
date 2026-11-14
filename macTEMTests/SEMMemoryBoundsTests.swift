//
//  SEMMemoryBoundsTests.swift
//  The SEM results that grew without a bound (#621): a dictionary run keeps at most what fits 1 GiB of matches and says how many to
//  keep; a fundamental-zone sample refuses a step that would hold more than five million orientations before it walks the grid; a pole
//  figure bins its directions as it makes them, the same counts as the held array gave.
//

import Foundation
import TEMCore
import XCTest

nonisolated final class SEMMemoryBoundsTests: XCTestCase {

    /// Red before: no budget (50 matches at 1 M points held 2.4 GB). kikuchipy's default of 20 fits a million points.
    func testKeptMatchesAreBoundedWithASentence() {
        XCTAssertEqual(DictionaryIndexingSettings.mostKept(points: 1_000_000), 22)
        var settings = DictionaryIndexingSettings()
        settings.keep = 20
        XCTAssertNil(settings.keptMatchesRefusal(points: 1_000_000), "kikuchipy's default keep_n fits")
        settings.keep = 50
        XCTAssertEqual(settings.keptMatchesRefusal(points: 1_000_000),
                       "Keeping 50 matches at each of 1000000 points needs 2.4 GB; keep at most 22.")
        XCTAssertNil(settings.keptMatchesRefusal(points: 10_000), "a small scan keeps 50")
    }

    /// Red before: a triclinic sample at 1° walked about 2 × 10⁷ orientations. The estimate refuses it before the walk; m-3m at 1° is
    /// under the cap.
    func testATooFineSampleIsRefusedBeforeTheWalk() throws {
        let cubic = try OrientationSampling.estimatedFundamentalCount(resolution: 1, pointGroup: PointGroup.oh)
        XCTAssertLessThan(cubic, OrientationSampling.maximumRotations)
        XCTAssertEqual(Double(cubic), 857_000, accuracy: 20_000, "about 274³ / 24")
        XCTAssertThrowsError(try OrientationSampling.fundamental(resolution: 1, pointGroup: PointGroup.c1)) { error in
            guard case .tooManyRotations(let n, let r)? = error as? OrientationSampling.Error else { return XCTFail("\(error)") }
            XCTAssertGreaterThan(n, OrientationSampling.maximumRotations)
            XCTAssertEqual(r, 1)
            XCTAssertTrue((error as? OrientationSampling.Error)?.sentence.hasSuffix("choose a coarser step.") == true)
        }
    }

    /// The pole figure binned as it goes equals the held directions' density bin for bin. Red if a direction were binned twice or
    /// lost, or the order of the sum changed.
    func testThePoleFigureBinsAsItGoes() throws {
        var generator = SystemRandomNumberGenerator()
        let quaternions: [SIMD4<Double>] = (0..<2_000).map { _ in
            let q = SIMD4<Double>(Double.random(in: -1...1, using: &generator), Double.random(in: -1...1, using: &generator),
                                  Double.random(in: -1...1, using: &generator), Double.random(in: -1...1, using: &generator))
            return q / (q * q).sum().squareRoot()
        }
        let orientations = Orientations(quaternions: quaternions, symmetry: PointGroup.oh)
        let poles = try PoleFigures.poles(family: [1, 1, 0], lattice: CrystalLattice(a: 1, b: 1, c: 1, alpha: 90, beta: 90, gamma: 90),
                                          group: PointGroup.oh)
        let streamed = PoleFigures.poleFigure(orientations, poles: poles)
        let held = PoleDensityFunction.compute(PoleFigures.sampleDirections(orientations, poles: poles))
        XCTAssertEqual(streamed.values.map(\.bitPattern), held.values.map(\.bitPattern))
        XCTAssertEqual(streamed.mask, held.mask)
    }
}
