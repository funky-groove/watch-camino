import Foundation
import XCTest
@testable import CaminoCore

final class CodableRoundTripTests: XCTestCase {
    private func roundTrip<T: Codable & Equatable>(_ value: T, file: StaticString = #filePath, line: UInt = #line) throws {
        let data = try CaminoJSON.encoder().encode(value)
        let decoded = try CaminoJSON.decoder().decode(T.self, from: data)
        XCTAssertEqual(decoded, value, file: file, line: line)
    }

    private func sampleSession() -> StageSession {
        return StageSession(
            sessionId: "3f1c2a1e-0000-4000-8000-000000000001",
            stageId: "cf-sarria-portomarin",
            startedAt: epoch(1_700_000_000),
            steps: 4321,
            distanceMeters: 1234.5678,
            lastFix: LocationFix(point: GeoPoint(lat: 42.7808, lon: -7.4141), accuracyMeters: 8, timestamp: epoch(1_700_000_600.25)),
            alertedPoiIds: ["p01", "p02"],
            lastAlertAt: epoch(1_700_000_500)
        )
    }

    func testSessionStateIdle() throws {
        try roundTrip(SessionState.idle)
    }

    func testSessionStateActive() throws {
        try roundTrip(SessionState.active(sampleSession()))
    }

    func testPersistedSessionWithHistory() throws {
        let summary = SessionSummary(
            sessionId: "s-1",
            stageId: "cf-sarria-portomarin",
            startedAt: epoch(1000),
            finishedAt: epoch(4661.9),
            steps: 120,
            distanceMeters: 22000,
            activeSeconds: 3661
        )
        try roundTrip(PersistedSession(state: .active(sampleSession()), history: [summary]))
        try roundTrip(PersistedSession(state: .idle, history: []))
    }

    func testSyncQueueState() throws {
        let finished = SyncEvent(
            eventId: "e2",
            type: .stageFinished,
            sessionId: "s-1",
            occurredAt: epoch(2000),
            payload: SyncPayload(stageId: "x", startedAt: epoch(1000), finishedAt: epoch(2000), steps: 10, distanceMeters: 20, activeSeconds: 1000)
        )
        let state = SyncQueueState(
            queue: [makeEvent(id: "e1", at: 1000), finished],
            deadLetters: [makeEvent(id: "e0")],
            attempt: 3,
            nextAttemptAt: epoch(1234.5),
            lastOutcome: .blocked
        )
        try roundTrip(state)
        try roundTrip(SyncQueueState())
    }

    func testFixtureModelsRoundTrip() throws {
        let stage = Stage(
            id: "a",
            name: "A – B",
            from: "A",
            to: "B",
            distanceMeters: 100,
            start: GeoPoint(lat: 1, lon: 2),
            end: GeoPoint(lat: 3, lon: 4)
        )
        try roundTrip(stage)
        try roundTrip(Poi(id: "p", stageId: "a", name: "Fuente", category: .water, location: GeoPoint(lat: 1, lon: 2)))
    }

    func testSyncEventTypeWireNames() throws {
        XCTAssertEqual(SyncEventType.stageStarted.rawValue, "stage_started")
        XCTAssertEqual(SyncEventType.stageFinished.rawValue, "stage_finished")
        let json = String(decoding: try CaminoJSON.encoder().encode(makeEvent(id: "e1")), as: UTF8.self)
        XCTAssertTrue(json.contains("\"stage_started\""))
    }

    func testSessionStateDecodingRejectsUnknownKind() {
        let data = Data("{\"kind\":\"paused\"}".utf8)
        XCTAssertThrowsError(try CaminoJSON.decoder().decode(SessionState.self, from: data))
    }
}
