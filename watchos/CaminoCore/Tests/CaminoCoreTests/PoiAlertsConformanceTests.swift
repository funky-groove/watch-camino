import Foundation
import XCTest
@testable import CaminoCore

/// shared/conformance/poi_alerts.json — §6.
final class PoiAlertsConformanceTests: XCTestCase {
    func testConstantsMatchVectors() throws {
        let root = try RepoFiles.conformance("poi_alerts.json")
        XCTAssertEqual(jsonDouble(root["radius_m"]), PoiEngine.radiusMeters)
        XCTAssertEqual(jsonDouble(root["min_interval_s"]), PoiEngine.minIntervalSeconds)
    }

    /// Motor POI aislado.
    func testEngineVectors() throws {
        let root = try RepoFiles.conformance("poi_alerts.json")
        let cases = jsonArray(root["cases"]).map { jsonDict($0) }
        XCTAssertFalse(cases.isEmpty)

        for c in cases {
            let name = jsonString(c["name"]) ?? "?"
            let pois = jsonArray(c["pois"]).map { jsonPoi($0) }
            let alerted = Set(jsonStrings(c["alreadyAlerted"]))
            let lastAlertAt = jsonDouble(c["lastAlertAt"]).map { epoch($0) }
            let now = epoch(jsonDouble(c["now"]) ?? 0)
            let position = jsonDict(c["position"])
            let point = GeoPoint(lat: jsonDouble(position["lat"]) ?? .nan, lon: jsonDouble(position["lon"]) ?? .nan)
            let accuracy = jsonDouble(position["acc"]) ?? .nan

            let alert = PoiEngine.evaluate(
                pois: pois,
                alerted: alerted,
                lastAlertAt: lastAlertAt,
                now: now,
                position: point,
                accuracyMeters: accuracy
            )
            XCTAssertEqual(alert?.poi.id, jsonString(c["expected"]), "caso \(name)")
        }
    }

    /// Los mismos vectores a través de la máquina de estados: se fija el estado de
    /// la sesión (avisados, último aviso) y se entrega un fix con `timestamp = now`.
    func testVectorsThroughStateMachine() throws {
        let root = try RepoFiles.conformance("poi_alerts.json")
        let cases = jsonArray(root["cases"]).map { jsonDict($0) }

        for c in cases {
            let name = jsonString(c["name"]) ?? "?"
            let pois = jsonArray(c["pois"]).map { jsonPoi($0) }
            let alerted = Set(jsonStrings(c["alreadyAlerted"]))
            let lastAlertAt = jsonDouble(c["lastAlertAt"]).map { epoch($0) }
            let now = epoch(jsonDouble(c["now"]) ?? 0)
            let position = jsonDict(c["position"])
            let fix = LocationFix(
                point: GeoPoint(lat: jsonDouble(position["lat"]) ?? .nan, lon: jsonDouble(position["lon"]) ?? .nan),
                accuracyMeters: jsonDouble(position["acc"]) ?? .nan,
                timestamp: now
            )
            let stageId = pois.first?.stageId ?? "s"
            let session = StageSession(
                sessionId: "S1",
                stageId: stageId,
                startedAt: epoch(0),
                alertedPoiIds: alerted,
                lastAlertAt: lastAlertAt
            )
            var machine = StageSessionMachine(
                state: .active(session),
                knownStageIds: [stageId],
                ids: SequentialIdGenerator()
            )
            let result = try machine.updateLocation(fix, pois: pois)
            let expected = jsonString(c["expected"])
            XCTAssertEqual(result.alert?.poi.id, expected, "máquina: \(name)")

            let after = try XCTUnwrap(machine.activeSession)
            if let expected = expected {
                XCTAssertTrue(after.alertedPoiIds.contains(expected), "máquina marca avisado: \(name)")
                XCTAssertEqual(after.lastAlertAt, now, "máquina actualiza lastAlertAt: \(name)")
            } else {
                XCTAssertEqual(after.alertedPoiIds, alerted, "máquina no cambia avisados: \(name)")
                XCTAssertEqual(after.lastAlertAt, lastAlertAt, "máquina no cambia lastAlertAt: \(name)")
            }
        }
    }

    func testPoiOfOtherStageIsIgnoredByMachine() throws {
        let here = GeoPoint(lat: 42.7808, lon: -7.4141)
        let foreign = Poi(id: "x", stageId: "otra", name: "x", category: .water, location: here)
        var machine = StageSessionMachine(knownStageIds: ["s"], ids: SequentialIdGenerator())
        _ = try machine.start(stageId: "s", sessionId: "S1", now: epoch(0))
        let fix = LocationFix(point: here, accuracyMeters: 5, timestamp: epoch(10))
        let result = try machine.updateLocation(fix, pois: [foreign])
        XCTAssertNil(result.alert)
    }

    func testEachPoiAlertsOncePerSession() throws {
        let here = GeoPoint(lat: 42.7808, lon: -7.4141)
        let poi = Poi(id: "p", stageId: "s", name: "Fuente", category: .water, location: here)
        var machine = StageSessionMachine(knownStageIds: ["s"], ids: SequentialIdGenerator())
        _ = try machine.start(stageId: "s", sessionId: "S1", now: epoch(0))
        let first = try machine.updateLocation(LocationFix(point: here, accuracyMeters: 5, timestamp: epoch(10)), pois: [poi])
        XCTAssertEqual(first.alert?.poi.id, "p")
        let second = try machine.updateLocation(LocationFix(point: here, accuracyMeters: 5, timestamp: epoch(500)), pois: [poi])
        XCTAssertNil(second.alert)
    }
}
