import Foundation
import XCTest
@testable import CaminoCore

/// shared/conformance/trip_metrics.json — V1.1 §C (pausa), §D (movimiento), §E (altitud), §F (perfil).
final class TripMetricsConformanceTests: XCTestCase {
    private enum TripEvent {
        case fix(LocationFix)
        case pause(Date)
        case resume(Date)
    }

    private func parseEvents(_ value: Any?) -> [TripEvent] {
        return jsonArray(value).map { raw in
            let e = jsonDict(raw)
            let t = epoch(jsonDouble(e["t"]) ?? 0)
            switch jsonString(e["type"]) {
            case "pause":
                return .pause(t)
            case "resume":
                return .resume(t)
            default:
                var fix = jsonFix(e)
                fix.altitudeMeters = jsonDouble(e["alt"])
                fix.verticalAccuracyMeters = jsonDouble(e["vacc"])
                return .fix(fix)
            }
        }
    }

    private func loadCases() throws -> (tolerance: Double, cases: [[String: Any]]) {
        let root = try RepoFiles.conformance("trip_metrics.json")
        let constants = jsonDict(root["constants"])
        XCTAssertEqual(jsonDouble(constants["minMovingSpeedMps"]), TripMetrics.minMovingSpeedMetersPerSecond)
        XCTAssertEqual(jsonDouble(constants["maxVerticalAccuracyM"]), TripMetrics.maxVerticalAccuracyMeters)
        XCTAssertEqual(jsonDouble(constants["altitudeHysteresisM"]), TripMetrics.altitudeHysteresisMeters)
        XCTAssertEqual(jsonDouble(constants["profileSpacingM"]), TripMetrics.profileSpacingMeters)
        XCTAssertEqual(jsonDouble(constants["profileGapM"]), TripMetrics.profileGapMeters)
        let cases = jsonArray(root["cases"]).map { jsonDict($0) }
        XCTAssertFalse(cases.isEmpty)
        return (jsonDouble(root["tolerance"]) ?? 0.01, cases)
    }

    private func assertMatches(
        distance: Double, moving: Double, paused: Bool, pausedSeconds: Double,
        ascent: Double, descent: Double, altitude: Double?, altitudeAt: Date?,
        profile: [ProfileSample], expected e: [String: Any], tolerance: Double, label: String
    ) {
        XCTAssertEqual(distance, jsonDouble(e["distance_m"]) ?? .nan, accuracy: tolerance, "distancia \(label)")
        XCTAssertEqual(moving, jsonDouble(e["moving_s"]) ?? .nan, accuracy: tolerance, "movimiento \(label)")
        XCTAssertEqual(paused, (e["paused"] as? Bool) ?? false, "pausado \(label)")
        XCTAssertEqual(pausedSeconds, jsonDouble(e["paused_s"]) ?? .nan, accuracy: tolerance, "pausa \(label)")
        XCTAssertEqual(ascent, jsonDouble(e["ascent_m"]) ?? .nan, accuracy: tolerance, "subida \(label)")
        XCTAssertEqual(descent, jsonDouble(e["descent_m"]) ?? .nan, accuracy: tolerance, "bajada \(label)")
        if let expectedAlt = jsonDouble(e["altitude_m"]) {
            XCTAssertEqual(altitude ?? .nan, expectedAlt, accuracy: tolerance, "altitud \(label)")
        } else {
            XCTAssertNil(altitude, "altitud nil \(label)")
        }
        if let expectedT = jsonDouble(e["altitude_t"]) {
            XCTAssertEqual(altitudeAt?.timeIntervalSince1970 ?? .nan, expectedT, accuracy: tolerance, "altitudeAt \(label)")
        } else {
            XCTAssertNil(altitudeAt, "altitudeAt nil \(label)")
        }
        let expectedProfile = jsonArray(e["profile"]).map { jsonDict($0) }
        XCTAssertEqual(profile.count, expectedProfile.count, "muestras del perfil \(label)")
        for (i, (sample, exp)) in zip(profile, expectedProfile).enumerated() {
            XCTAssertEqual(sample.d, jsonDouble(exp["d"]) ?? .nan, accuracy: tolerance, "perfil[\(i)].d \(label)")
            XCTAssertEqual(sample.alt, jsonDouble(exp["alt"]) ?? .nan, accuracy: tolerance, "perfil[\(i)].alt \(label)")
            XCTAssertEqual(sample.gapBefore, (exp["gapBefore"] as? Bool) ?? false, "perfil[\(i)].gapBefore \(label)")
        }
    }

    /// Todos los casos sobre `TripMetrics` pura, con su `profileCap`.
    func testAllVectors() throws {
        let (tolerance, cases) = try loadCases()
        for c in cases {
            let name = jsonString(c["name"]) ?? "?"
            let cap = jsonInt(c["profileCap"]) ?? TripMetrics.defaultProfileCap
            var metrics = TripMetrics(profileCap: cap)
            var ignored: [Int] = []
            for (i, event) in parseEvents(c["events"]).enumerated() {
                switch event {
                case .fix(let fix):
                    metrics.add(fix)
                case .pause(let t):
                    do { try metrics.pause(at: t) } catch { ignored.append(i) }
                case .resume(let t):
                    do { try metrics.resume(at: t) } catch { ignored.append(i) }
                }
            }
            let e = jsonDict(c["expected"])
            XCTAssertEqual(ignored, jsonArray(e["ignored_events"]).compactMap { jsonInt($0) }, "ignorados \(name)")
            assertMatches(
                distance: metrics.distanceMeters, moving: metrics.movingSeconds, paused: metrics.isPaused,
                pausedSeconds: metrics.pausedSeconds, ascent: metrics.ascentMeters, descent: metrics.descentMeters,
                altitude: metrics.altitude, altitudeAt: metrics.altitudeAt, profile: metrics.profile,
                expected: e, tolerance: tolerance, label: name
            )
        }
    }

    /// Los casos con el tope por defecto, pasando por la máquina de estados (errores de pausa incluidos).
    func testVectorsThroughStateMachine() throws {
        let (tolerance, cases) = try loadCases()
        var checked = 0
        for c in cases where (jsonInt(c["profileCap"]) ?? 0) == TripMetrics.defaultProfileCap {
            let name = jsonString(c["name"]) ?? "?"
            var machine = StageSessionMachine(knownStageIds: ["s"], ids: SequentialIdGenerator())
            _ = try machine.start(stageId: "s", sessionId: "S1", now: epoch(0))
            var ignored: [Int] = []
            for (i, event) in parseEvents(c["events"]).enumerated() {
                switch event {
                case .fix(let fix):
                    _ = try machine.updateLocation(fix, pois: [], now: fix.timestamp)
                case .pause(let t):
                    do {
                        try machine.pause(now: t)
                    } catch let error as SessionError {
                        XCTAssertEqual(error, .alreadyPaused, name)
                        ignored.append(i)
                    }
                case .resume(let t):
                    do {
                        try machine.resume(now: t)
                    } catch let error as SessionError {
                        XCTAssertEqual(error, .notPaused, name)
                        ignored.append(i)
                    }
                }
            }
            let s = try XCTUnwrap(machine.activeSession)
            let e = jsonDict(c["expected"])
            XCTAssertEqual(ignored, jsonArray(e["ignored_events"]).compactMap { jsonInt($0) }, "máquina ignorados \(name)")
            assertMatches(
                distance: s.distanceMeters, moving: s.movingSeconds, paused: s.isPaused,
                pausedSeconds: s.pausedSeconds, ascent: s.ascentMeters, descent: s.descentMeters,
                altitude: s.altitude, altitudeAt: s.altitudeAt, profile: s.profile,
                expected: e, tolerance: tolerance, label: "máquina \(name)"
            )
            checked += 1
        }
        XCTAssertGreaterThan(checked, 0)
    }
}
