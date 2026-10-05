import Foundation
import XCTest
@testable import CaminoCore

/// shared/conformance/distance_accumulator.json — §5.
final class DistanceAccumulatorConformanceTests: XCTestCase {
    private func loadCases() throws -> (tolerance: Double, cases: [[String: Any]]) {
        let root = try RepoFiles.conformance("distance_accumulator.json")
        let tolerance = jsonDouble(root["tolerance_m"]) ?? 0.01
        let cases = jsonArray(root["cases"]).map { jsonDict($0) }
        return (tolerance, cases)
    }

    /// El acumulador aislado reproduce distancia y `lastFix`.
    func testAccumulatorVectors() throws {
        let (tolerance, cases) = try loadCases()
        XCTAssertFalse(cases.isEmpty)

        for c in cases {
            let name = jsonString(c["name"]) ?? "?"
            let fixes = jsonArray(c["fixes"]).map { jsonFix($0) }
            var accumulator = DistanceAccumulator()
            var lastIndex: Int?
            for (i, fix) in fixes.enumerated() {
                let outcome = accumulator.add(fix)
                if outcome.movedAnchor {
                    lastIndex = i
                }
            }
            let expectedDistance = jsonDouble(c["distance_m"]) ?? .nan
            XCTAssertEqual(accumulator.distanceMeters, expectedDistance, accuracy: tolerance, "distancia en \(name)")

            let expectedIndex = jsonInt(c["last_fix_index"])
            XCTAssertEqual(lastIndex, expectedIndex, "índice de lastFix en \(name)")
            if let idx = expectedIndex {
                XCTAssertEqual(accumulator.lastFix, fixes[idx], "lastFix en \(name)")
            } else {
                XCTAssertNil(accumulator.lastFix, "lastFix debería ser nil en \(name)")
            }
        }
    }

    /// Los mismos vectores pasando por la máquina de estados (sesión activa, sin POIs).
    func testVectorsThroughStateMachine() throws {
        let (tolerance, cases) = try loadCases()
        for c in cases {
            let name = jsonString(c["name"]) ?? "?"
            let fixes = jsonArray(c["fixes"]).map { jsonFix($0) }
            var machine = StageSessionMachine(knownStageIds: ["s"], ids: SequentialIdGenerator())
            _ = try machine.start(stageId: "s", sessionId: "S1", now: epoch(0))
            for fix in fixes {
                _ = try machine.updateLocation(fix, pois: [], now: fix.timestamp)
            }
            let session = try XCTUnwrap(machine.activeSession)
            XCTAssertEqual(session.distanceMeters, jsonDouble(c["distance_m"]) ?? .nan, accuracy: tolerance, "máquina: \(name)")
            if let idx = jsonInt(c["last_fix_index"]) {
                XCTAssertEqual(session.lastFix, fixes[idx], "máquina lastFix: \(name)")
            } else {
                XCTAssertNil(session.lastFix, "máquina lastFix nil: \(name)")
            }
        }
    }

    func testUpdateLocationWhenIdleIsNotActive() {
        var machine = StageSessionMachine(knownStageIds: ["s"], ids: SequentialIdGenerator())
        let fix = LocationFix(point: GeoPoint(lat: 42.78, lon: -7.41), accuracyMeters: 5, timestamp: epoch(0))
        XCTAssertThrowsError(try machine.updateLocation(fix, pois: [], now: fix.timestamp)) { error in
            XCTAssertEqual(error as? SessionError, .notActive)
        }
    }
}
