import Foundation
import XCTest
@testable import CaminoCore

/// shared/conformance/sync_engine.json — §7.
final class SyncEngineConformanceTests: XCTestCase {
    @MainActor
    func testAllVectors() async throws {
        let root = try RepoFiles.conformance("sync_engine.json")
        let cases = jsonArray(root["cases"]).map { jsonDict($0) }
        XCTAssertFalse(cases.isEmpty)

        for c in cases {
            let name = jsonString(c["name"]) ?? "?"
            let queueIds = jsonStrings(c["queue"])
            let responses = jsonStrings(c["responses"]).map { sendResult(fromCode: $0) }
            let now = jsonDouble(c["now"]) ?? 0
            let manual = (c["manual"] as? Bool) ?? false
            let backoff = jsonDict(c["backoff"])
            let initial = SyncQueueState(
                queue: queueIds.map { makeEvent(id: $0) },
                deadLetters: [],
                attempt: jsonInt(backoff["attempt"]) ?? 0,
                nextAttemptAt: jsonDouble(backoff["nextAttemptAt"]).map { epoch($0) }
            )

            let store = InMemorySyncQueueStore(initial)
            let api = ScriptedCaminoApi(responses)
            let engine = SyncEngine(
                api: api,
                store: store,
                clock: FixedClock(secondsSince1970: now),
                jitter: { 0 }
            )

            let status = await engine.syncNow(manual: manual)

            let expected = jsonDict(c["expected"])
            XCTAssertEqual(status.code, jsonString(expected["status"]), "status en \(name)")
            XCTAssertEqual(engine.status, status, "status publicado en \(name)")
            XCTAssertEqual(api.sent, jsonStrings(expected["sent"]), "enviados en \(name)")
            XCTAssertEqual(engine.state.queue.map { $0.eventId }, jsonStrings(expected["remaining"]), "restantes en \(name)")
            XCTAssertEqual(engine.state.deadLetters.map { $0.eventId }, jsonStrings(expected["deadLetters"]), "dead-letter en \(name)")
            XCTAssertEqual(engine.state.attempt, jsonInt(expected["attempt"]), "attempt en \(name)")
            XCTAssertEqual(
                engine.state.nextAttemptAt?.timeIntervalSince1970,
                jsonDouble(expected["nextAttemptAt"]),
                "nextAttemptAt en \(name)"
            )
            XCTAssertFalse(engine.isSyncing, "no queda en vuelo en \(name)")

            // Lo persistido coincide con el estado en memoria (si hubo escritura).
            if let persisted = store.value {
                XCTAssertEqual(persisted.queue, engine.state.queue, "persistido en \(name)")
                XCTAssertEqual(persisted.deadLetters, engine.state.deadLetters, "dead-letter persistido en \(name)")
                XCTAssertEqual(persisted.attempt, engine.state.attempt, "attempt persistido en \(name)")
            }
        }
    }

    @MainActor
    func testStatusSurvivesRelaunch() async {
        let store = InMemorySyncQueueStore()
        let engine = SyncEngine(api: BlockedCaminoApi(), store: store, clock: FixedClock(secondsSince1970: 0), jitter: { 0 })
        engine.enqueue([makeEvent(id: "e1"), makeEvent(id: "e2")])
        let status = await engine.syncNow(manual: true)
        XCTAssertEqual(status, .blocked)
        XCTAssertEqual(engine.pendingCount, 2, "Blocked no pierde eventos")

        let relaunched = SyncEngine(api: BlockedCaminoApi(), store: store, clock: FixedClock(secondsSince1970: 10), jitter: { 0 })
        XCTAssertEqual(relaunched.status, .blocked)
        XCTAssertEqual(relaunched.pendingCount, 2)
    }

    @MainActor
    func testMockApiAcceptsEverything() async {
        let store = InMemorySyncQueueStore()
        let api = MockCaminoApi(latencySeconds: 0)
        let engine = SyncEngine(api: api, store: store, clock: FixedClock(secondsSince1970: 0), jitter: { 0 })
        XCTAssertTrue(engine.isDemo)
        engine.enqueue([makeEvent(id: "e1"), makeEvent(id: "e2")])
        XCTAssertEqual(engine.status, .pending(2))
        let status = await engine.syncNow(manual: false)
        XCTAssertEqual(status, .synced)
        XCTAssertEqual(api.sentEventIds, ["e1", "e2"])
        XCTAssertEqual(store.value?.queue.count, 0)
    }

    @MainActor
    func testRetryableUsesInjectedJitter() async {
        let store = InMemorySyncQueueStore(SyncQueueState(queue: [makeEvent(id: "e1")]))
        let engine = SyncEngine(
            api: ScriptedCaminoApi([.retryable(reason: "x")]),
            store: store,
            clock: FixedClock(secondsSince1970: 1000),
            jitter: { 0.2 }
        )
        _ = await engine.syncNow(manual: false)
        XCTAssertEqual(engine.state.attempt, 1)
        XCTAssertEqual(engine.state.nextAttemptAt?.timeIntervalSince1970 ?? 0, 1036, accuracy: 1e-6)
    }

    @MainActor
    func testPermanentFailuresAreCountedAsDeadLetters() async {
        let store = InMemorySyncQueueStore(SyncQueueState(queue: [makeEvent(id: "e1")]))
        let engine = SyncEngine(
            api: ScriptedCaminoApi([.permanent(reason: "x")]),
            store: store,
            clock: FixedClock(secondsSince1970: 0),
            jitter: { 0 }
        )
        _ = await engine.syncNow(manual: true)
        XCTAssertEqual(engine.deadLetterCount, 1)
        XCTAssertEqual(store.value?.deadLetters.count, 1)
        XCTAssertEqual(engine.status, .synced)
    }
}
