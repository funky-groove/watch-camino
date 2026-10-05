import Foundation
import XCTest
@testable import CaminoCore

/// shared/conformance/haversine.json — §5.
final class HaversineConformanceTests: XCTestCase {
    func testAllVectors() throws {
        let root = try RepoFiles.conformance("haversine.json")
        let tolerance = jsonDouble(root["tolerance_m"]) ?? 0.01
        let cases = jsonArray(root["cases"])
        XCTAssertFalse(cases.isEmpty, "haversine.json sin casos")

        for (index, raw) in cases.enumerated() {
            let c = jsonDict(raw)
            let a = jsonPoint(c["a"])
            let b = jsonPoint(c["b"])
            guard let expected = jsonDouble(c["meters"]) else {
                XCTFail("caso \(index) sin 'meters'")
                continue
            }
            XCTAssertEqual(Geo.haversine(a, b), expected, accuracy: tolerance, "haversine caso \(index)")
            // Simetría.
            XCTAssertEqual(Geo.haversine(b, a), expected, accuracy: tolerance, "haversine simétrico caso \(index)")
        }
    }

    func testEarthRadiusIsFixedBySpec() {
        XCTAssertEqual(Geo.earthRadiusMeters, 6_371_008.8)
    }
}
