import Foundation
import XCTest
@testable import CaminoCore

/// V1.1 §C–F: pausa/reanudar en la máquina y el controlador, resumen, payload y compatibilidad V1.
final class PauseResumeTests: XCTestCase {
    private let stage = "cf-sarria-portomarin"
    private let origin = GeoPoint(lat: 42.7808, lon: -7.4141)

    /// Fix a `northMeters` al norte del origen, en el instante `t`.
    private func fix(_ northMeters: Double, _ t: Double, alt: Double? = nil, vacc: Double? = nil) -> LocationFix {
        let dLat = northMeters / 6_371_008.8 * 180 / Double.pi
        return LocationFix(
            point: GeoPoint(lat: origin.lat + dLat, lon: origin.lon),
            accuracyMeters: 5,
            timestamp: epoch(t),
            altitudeMeters: alt,
            verticalAccuracyMeters: vacc
        )
    }

    private func startedMachine() throws -> StageSessionMachine {
        var machine = StageSessionMachine(knownStageIds: [stage], ids: SequentialIdGenerator(prefix: "ev-"))
        _ = try machine.start(stageId: stage, sessionId: "S1", now: epoch(0))
        return machine
    }

    func testPauseResumeErrorsAndState() throws {
        var idle = StageSessionMachine(knownStageIds: [stage], ids: SequentialIdGenerator())
        XCTAssertThrowsError(try idle.pause(now: epoch(0))) { XCTAssertEqual($0 as? SessionError, .notActive) }
        XCTAssertThrowsError(try idle.resume(now: epoch(0))) { XCTAssertEqual($0 as? SessionError, .notActive) }

        var machine = try startedMachine()
        XCTAssertFalse(machine.state.isPaused)
        XCTAssertThrowsError(try machine.resume(now: epoch(5))) { XCTAssertEqual($0 as? SessionError, .notPaused) }

        _ = try machine.updateLocation(fix(0, 0), pois: [], now: epoch(0))
        XCTAssertNotNil(machine.activeSession?.lastFix)
        try machine.pause(now: epoch(100))
        XCTAssertTrue(machine.state.isPaused)
        XCTAssertEqual(machine.activeSession?.pausedAt, epoch(100))
        XCTAssertNil(machine.activeSession?.lastFix, "pausar suelta el ancla")
        let before = machine.state
        XCTAssertThrowsError(try machine.pause(now: epoch(110))) { XCTAssertEqual($0 as? SessionError, .alreadyPaused) }
        XCTAssertEqual(machine.state, before, "sin cambios")
        XCTAssertEqual(machine.activeSession?.pausedSeconds(at: epoch(130)) ?? -1, 30, accuracy: 1e-9)

        try machine.resume(now: epoch(160))
        XCTAssertFalse(machine.state.isPaused)
        XCTAssertEqual(machine.activeSession?.pausedSeconds ?? -1, 60, accuracy: 1e-9)

        // Reloj hacia atrás: la pausa no resta.
        try machine.pause(now: epoch(200))
        try machine.resume(now: epoch(150))
        XCTAssertEqual(machine.activeSession?.pausedSeconds ?? -1, 60, accuracy: 1e-9)
    }

    func testLocationWhilePausedOnlyEvaluatesPoiAlerts() throws {
        var machine = try startedMachine()
        _ = try machine.updateLocation(fix(0, 0, alt: 400, vacc: 5), pois: [], now: epoch(0))
        _ = try machine.updateLocation(fix(14, 10, alt: 404, vacc: 5), pois: [], now: epoch(10))
        try machine.pause(now: epoch(20))
        let snapshot = try XCTUnwrap(machine.activeSession)

        let poi = Poi(id: "p1", stageId: stage, name: "Fuente", category: .water, location: fix(150, 0).point)
        let result = try machine.updateLocation(fix(100, 60, alt: 450, vacc: 5), pois: [poi], now: epoch(60))
        XCTAssertEqual(result.distance, .ignoredPaused)
        XCTAssertEqual(result.alert?.poi.id, "p1", "en pausa los avisos POI siguen")
        XCTAssertTrue(result.changedSession)
        let s = try XCTUnwrap(machine.activeSession)
        XCTAssertEqual(s.distanceMeters, snapshot.distanceMeters)
        XCTAssertEqual(s.movingSeconds, snapshot.movingSeconds)
        XCTAssertEqual(s.ascentMeters, snapshot.ascentMeters)
        XCTAssertEqual(s.altitude, snapshot.altitude)
        XCTAssertEqual(s.profile, snapshot.profile)
        XCTAssertNil(s.lastFix)
        XCTAssertEqual(s.alertedPoiIds, ["p1"])

        // Al reanudar, el primer fix sólo ancla: el tramo en pausa no se cuenta.
        try machine.resume(now: epoch(70))
        let r = try machine.updateLocation(fix(300, 80), pois: [], now: epoch(80))
        XCTAssertEqual(r.distance, .anchored)
        XCTAssertEqual(machine.activeSession?.distanceMeters ?? -1, snapshot.distanceMeters, accuracy: 1e-9)
    }

    func testAltitudeOnlyFixPersistsAndStaleness() throws {
        var machine = try startedMachine()
        _ = try machine.updateLocation(fix(0, 0), pois: [], now: epoch(0))
        // Ruido horizontal (no mueve el ancla) pero con altitud válida: hay que persistir.
        let r = try machine.updateLocation(fix(2, 10, alt: 500, vacc: 3), pois: [], now: epoch(10))
        XCTAssertEqual(r.distance, .rejectedNoise)
        XCTAssertEqual(r.trip?.altitudeAccepted, true)
        XCTAssertTrue(r.changedSession)
        let s = try XCTUnwrap(machine.activeSession)
        XCTAssertFalse(s.isAltitudeStale(at: epoch(310)))
        XCTAssertTrue(s.isAltitudeStale(at: epoch(311)))
        XCTAssertTrue(StageSession(sessionId: "x", stageId: stage, startedAt: epoch(0)).isAltitudeStale(at: epoch(0)))
    }

    func testFinishWhilePausedClosesPauseAndFillsSummaryAndPayload() throws {
        var machine = try startedMachine()
        // 11 fixes cada 10 s, 14 m y +2 m de altitud por paso: 140 m, 100 s en movimiento, +20 m.
        for k in 0...10 {
            _ = try machine.updateLocation(fix(14 * Double(k), 10 * Double(k), alt: 400 + 2 * Double(k), vacc: 4), pois: [], now: epoch(0))
        }
        try machine.pause(now: epoch(1000))
        let result = try machine.finish(now: epoch(1600.6))
        XCTAssertEqual(machine.state, .idle)
        let summary = result.summary
        XCTAssertEqual(summary.activeSeconds, 1600)
        XCTAssertEqual(summary.pausedSeconds, 601, "half-up de 600,6")
        XCTAssertEqual(summary.movingSeconds, 100)
        XCTAssertEqual(summary.ascentMeters, 20)
        XCTAssertEqual(summary.descentMeters, 0)
        XCTAssertEqual(summary.distanceMeters, 140)
        XCTAssertFalse(summary.profile.isEmpty)

        let payload = try XCTUnwrap(result.events.first?.payload)
        XCTAssertEqual(result.events.first?.type, .stageFinished)
        XCTAssertEqual(payload.movingSeconds, 100)
        XCTAssertEqual(payload.pausedSeconds, 601)
        XCTAssertEqual(payload.ascentMeters, 20)
        XCTAssertEqual(payload.descentMeters, 0)
        let json = String(decoding: try CaminoJSON.encoder().encode(result.events[0]), as: UTF8.self)
        XCTAssertFalse(json.contains("profile"), "el perfil nunca se envía")
        XCTAssertFalse(json.contains("lat"), "nunca posiciones")
    }

    func testSummaryRoundingAndMovingClamp() throws {
        XCTAssertEqual(StageSessionMachine.roundHalfUp(2.5), 3)
        XCTAssertEqual(StageSessionMachine.roundHalfUp(2.49), 2)
        XCTAssertEqual(StageSessionMachine.roundHalfUp(-1), 0)
        XCTAssertEqual(StageSessionMachine.roundHalfUp(.nan), 0)

        // movingSeconds viene de fix.timestamp: si supera la duración, se limita.
        var machine = try startedMachine()
        for k in 0...10 {
            _ = try machine.updateLocation(fix(14 * Double(k), 10 * Double(k)), pois: [], now: epoch(0))
        }
        let summary = try machine.finish(now: epoch(50)).summary
        XCTAssertEqual(summary.activeSeconds, 50)
        XCTAssertEqual(summary.movingSeconds, 50)
    }

    func testDecodesV1PersistedState() throws {
        let v1 = """
        {"history":[{"activeSeconds":3661,"distanceMeters":22000,"finishedAt":3661.9,"sessionId":"s-0",\
        "stageId":"cf-sarria-portomarin","startedAt":0,"steps":120}],
        "state":{"kind":"active","session":{"alertedPoiIds":["p01"],"distanceMeters":12.5,"lastAlertAt":10,\
        "lastFix":{"accuracyMeters":8,"point":{"lat":42.78,"lon":-7.41},"timestamp":20},\
        "sessionId":"s-1","stageId":"cf-sarria-portomarin","startedAt":5,"steps":42}}}
        """
        let persisted = try CaminoJSON.decoder().decode(PersistedSession.self, from: Data(v1.utf8))
        let s = try XCTUnwrap(persisted.state.activeSession)
        XCTAssertEqual(s.steps, 42)
        XCTAssertEqual(s.distanceMeters, 12.5)
        XCTAssertNil(s.lastFix?.altitudeMeters)
        XCTAssertNil(s.lastFix?.verticalAccuracyMeters)
        XCTAssertFalse(s.isPaused)
        XCTAssertNil(s.pausedAt)
        XCTAssertEqual(s.pausedSeconds, 0)
        XCTAssertEqual(s.movingSeconds, 0)
        XCTAssertEqual(s.ascentMeters, 0)
        XCTAssertEqual(s.descentMeters, 0)
        XCTAssertNil(s.altitudeRef)
        XCTAssertNil(s.altitude)
        XCTAssertNil(s.altitudeAt)
        XCTAssertEqual(s.profile, [])
        XCTAssertEqual(s.profileSpacing, TripMetrics.profileSpacingMeters)
        let h = try XCTUnwrap(persisted.history.first)
        XCTAssertEqual(h.activeSeconds, 3661)
        XCTAssertEqual(h.movingSeconds, 0)
        XCTAssertEqual(h.pausedSeconds, 0)
        XCTAssertEqual(h.ascentMeters, 0)
        XCTAssertEqual(h.descentMeters, 0)
        XCTAssertEqual(h.profile, [])

        // Un stage_finished V1 encolado también se sigue leyendo.
        let ev = #"{"eventId":"e","occurredAt":1,"payload":{"activeSeconds":1,"distanceMeters":2,"finishedAt":1,"stageId":"x","startedAt":0,"steps":3},"sessionId":"s","type":"stage_finished"}"#
        let event = try CaminoJSON.decoder().decode(SyncEvent.self, from: Data(ev.utf8))
        XCTAssertNil(event.payload.movingSeconds)
    }

    func testV11StateRoundTrip() throws {
        var session = StageSession(sessionId: "s", stageId: stage, startedAt: epoch(0))
        session.lastFix = fix(0, 1, alt: 400, vacc: 3)
        session.pausedAt = epoch(50)
        session.pausedSeconds = 12.5
        session.movingSeconds = 33
        session.ascentMeters = 7
        session.descentMeters = 4
        session.altitudeRef = 403
        session.altitude = 401
        session.altitudeAt = epoch(40)
        session.profile = [ProfileSample(d: 0, alt: 400), ProfileSample(d: 260, alt: 401, gapBefore: true)]
        session.profileSpacing = 100
        let summary = SessionSummary(sessionId: "s", stageId: stage, startedAt: epoch(0), finishedAt: epoch(9),
                                     steps: 1, distanceMeters: 2, activeSeconds: 9, movingSeconds: 3,
                                     pausedSeconds: 4, ascentMeters: 5, descentMeters: 6, profile: session.profile)
        let value = PersistedSession(state: .active(session), history: [summary])
        let data = try CaminoJSON.encoder().encode(value)
        XCTAssertEqual(try CaminoJSON.decoder().decode(PersistedSession.self, from: data), value)
        XCTAssertEqual(CaminoTotals.of([summary, summary]),
                       CaminoTotals(stages: 2, distanceMeters: 4, steps: 2, activeSeconds: 18,
                                    movingSeconds: 6, ascentMeters: 10, descentMeters: 12))
    }

    @MainActor
    func testControllerPauseResumePersistsWithoutSync() async throws {
        let store = InMemorySessionStore()
        let syncStore = InMemorySyncQueueStore()
        let clock = FixedClock(secondsSince1970: 1_700_000_000)
        let catalog = try FixtureStageCatalog(data: RepoFiles.data("shared/fixtures/stages.json"))
        let pois = try FixturePoiSource(data: RepoFiles.data("shared/fixtures/pois.json"))
        let controller = CaminoController(
            catalog: catalog, poiSource: pois, sessionStore: store, syncStore: syncStore,
            api: BlockedCaminoApi(), clock: clock, ids: SequentialIdGenerator(prefix: "id-"),
            jitter: { 0 }, autoSync: false
        )
        var changes = 0
        controller.onChange = { changes += 1 }

        XCTAssertThrowsError(try controller.pause()) { XCTAssertEqual($0 as? SessionError, .notActive) }
        try controller.start(stageId: stage)
        let queuedAfterStart = syncStore.value?.queue.count
        changes = 0

        clock.advance(by: 60)
        try controller.pause()
        XCTAssertTrue(controller.isPaused)
        XCTAssertEqual(store.value?.state.isPaused, true, "se persiste la pausa")
        XCTAssertEqual(changes, 1)
        XCTAssertThrowsError(try controller.pause()) { XCTAssertEqual($0 as? SessionError, .alreadyPaused) }

        // Relanzar en pausa restaura la pausa.
        let relaunched = CaminoController(
            catalog: catalog, poiSource: pois, sessionStore: store, syncStore: syncStore,
            api: BlockedCaminoApi(), clock: clock, ids: SequentialIdGenerator(prefix: "id2-"),
            jitter: { 0 }, autoSync: false
        )
        XCTAssertTrue(relaunched.isPaused)

        clock.advance(by: 30)
        try controller.resume()
        XCTAssertFalse(controller.isPaused)
        XCTAssertEqual(store.value?.state.activeSession?.pausedSeconds ?? -1, 30, accuracy: 1e-9)
        XCTAssertEqual(changes, 2)
        XCTAssertThrowsError(try controller.resume()) { XCTAssertEqual($0 as? SessionError, .notPaused) }
        XCTAssertEqual(syncStore.value?.queue.count, queuedAfterStart, "pausar/reanudar no encola eventos")

        try controller.pause()
        clock.advance(by: 10)
        let summary = try controller.finish()
        XCTAssertEqual(summary.pausedSeconds, 40)
        XCTAssertEqual(summary.activeSeconds, 100)
        XCTAssertFalse(controller.isPaused)
    }

    /// F-06: en vivo, el tiempo en movimiento nunca supera la duración (reloj hacia atrás).
    func testLiveMovingSecondsIsBoundedByElapsed() {
        var session = StageSession(sessionId: "s", stageId: stage, startedAt: epoch(100))
        session.movingSeconds = 20
        XCTAssertEqual(session.liveMovingSeconds(at: epoch(90)), 0, "reloj hacia atrás: 0, no 20")
        XCTAssertEqual(session.liveMovingSeconds(at: epoch(110)), 10)
        XCTAssertEqual(session.liveMovingSeconds(at: epoch(200)), 20)
    }

    /// F-03: la subida hecha en pausa (bus, teleférico) no se suma al reanudar.
    func testAscentDuringPauseIsNotCounted() throws {
        var metrics = TripMetrics()
        metrics.add(fix(0, 0, alt: 500, vacc: 5))
        try metrics.pause(at: epoch(10))
        XCTAssertNil(metrics.altitudeRef)
        try metrics.resume(at: epoch(600))
        metrics.add(fix(3_000, 610, alt: 900, vacc: 5))
        metrics.add(fix(3_014, 620, alt: 901, vacc: 5))
        XCTAssertEqual(metrics.ascentMeters, 0, accuracy: 1e-9)
        XCTAssertEqual(metrics.descentMeters, 0, accuracy: 1e-9)
    }
}
