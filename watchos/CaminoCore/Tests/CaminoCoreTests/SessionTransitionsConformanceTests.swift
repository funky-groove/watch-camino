import Foundation
import XCTest
@testable import CaminoCore

/// shared/conformance/session_transitions.json — §4.
final class SessionTransitionsConformanceTests: XCTestCase {
    func testAllVectors() throws {
        let root = try RepoFiles.conformance("session_transitions.json")
        let known = Set(jsonStrings(root["knownStageIds"]))
        let cases = jsonArray(root["cases"]).map { jsonDict($0) }
        XCTAssertFalse(known.isEmpty)
        XCTAssertFalse(cases.isEmpty)

        for c in cases {
            let caseName = jsonString(c["name"]) ?? "?"
            var machine = StageSessionMachine(knownStageIds: known, ids: SequentialIdGenerator(prefix: "ev-"))
            var queue: [SyncEvent] = []

            for (stepIndex, rawStep) in jsonArray(c["steps"]).enumerated() {
                let step = jsonDict(rawStep)
                let op = jsonString(step["op"]) ?? "?"
                let label = "\(caseName)#\(stepIndex) (\(op))"
                var errorCode: String?

                do {
                    switch op {
                    case "start":
                        let stageId = jsonString(step["stageId"]) ?? ""
                        let sessionId = jsonString(step["sessionId"]) ?? ""
                        let t = epoch(jsonDouble(step["t"]) ?? 0)
                        let events = try machine.start(stageId: stageId, sessionId: sessionId, now: t)
                        queue.append(contentsOf: events)
                        XCTAssertEqual(machine.activeSession?.sessionId, sessionId, label)
                        XCTAssertEqual(machine.activeSession?.stageId, stageId, label)
                        XCTAssertEqual(machine.activeSession?.startedAt, t, label)
                    case "updateSteps":
                        try machine.updateSteps(jsonInt(step["n"]) ?? 0)
                    case "finish":
                        let result = try machine.finish(now: epoch(jsonDouble(step["t"]) ?? 0))
                        queue.append(contentsOf: result.events)
                        XCTAssertEqual(machine.history.first, result.summary, label)
                    default:
                        XCTFail("op desconocida en \(label)")
                    }
                } catch let error as SessionError {
                    errorCode = error.rawValue
                }

                let expect = jsonDict(step["expect"])
                let expectedState = jsonString(expect["state"])
                XCTAssertEqual(machine.state.isActive ? "active" : "idle", expectedState, "estado \(label)")
                XCTAssertEqual(errorCode, jsonString(expect["error"]), "error \(label)")
                if let expectedSteps = jsonInt(expect["steps"]) {
                    XCTAssertEqual(machine.activeSession?.steps, expectedSteps, "pasos \(label)")
                }
                if let expectedHistory = jsonInt(expect["history"]) {
                    XCTAssertEqual(machine.history.count, expectedHistory, "historial \(label)")
                }
                if let expectedSeconds = jsonInt(expect["activeSeconds"]) {
                    XCTAssertEqual(machine.history.first?.activeSeconds, expectedSeconds, "activeSeconds \(label)")
                }
                if let expectedSummarySteps = jsonInt(expect["summarySteps"]) {
                    XCTAssertEqual(machine.history.first?.steps, expectedSummarySteps, "summarySteps \(label)")
                }
                let queuedTypes = queue.map { $0.type.rawValue }
                XCTAssertEqual(queuedTypes, jsonStrings(expect["queued"]), "cola \(label)")
            }

            // Ids de evento únicos (idempotencia).
            XCTAssertEqual(Set(queue.map { $0.eventId }).count, queue.count, "eventId únicos en \(caseName)")
        }
    }

    func testUpdateStepsWhenIdleThrowsNotActive() {
        var machine = StageSessionMachine(knownStageIds: ["s"], ids: SequentialIdGenerator())
        XCTAssertThrowsError(try machine.updateSteps(10)) { error in
            XCTAssertEqual(error as? SessionError, .notActive)
        }
    }

    func testFinishedPayloadCarriesOnlyAggregates() throws {
        var machine = StageSessionMachine(knownStageIds: ["s"], ids: SequentialIdGenerator())
        _ = try machine.start(stageId: "s", sessionId: "S1", now: epoch(100))
        try machine.updateSteps(1500)
        let result = try machine.finish(now: epoch(3700))
        let event = try XCTUnwrap(result.events.first)
        XCTAssertEqual(event.type, .stageFinished)
        XCTAssertEqual(event.sessionId, "S1")
        XCTAssertEqual(event.payload.stageId, "s")
        XCTAssertEqual(event.payload.startedAt, epoch(100))
        XCTAssertEqual(event.payload.finishedAt, epoch(3700))
        XCTAssertEqual(event.payload.steps, 1500)
        XCTAssertEqual(event.payload.distanceMeters, 0)
        XCTAssertEqual(event.payload.activeSeconds, 3600)

        // Privacidad (§7): el evento serializado no contiene posiciones.
        let json = String(decoding: try CaminoJSON.encoder().encode(event), as: UTF8.self)
        XCTAssertFalse(json.contains("lat"))
        XCTAssertFalse(json.contains("lon"))
        XCTAssertFalse(json.contains("lastFix"))
    }
}
