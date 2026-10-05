import Foundation
import XCTest
@testable import CaminoCore

private struct BrokenStoreError: Error {}

/// Almacén que siempre falla (disco lleno, fichero corrupto…).
private final class BrokenSessionStore: SessionStore {
    func load() throws -> PersistedSession? {
        throw BrokenStoreError()
    }

    func save(_ value: PersistedSession) throws {
        throw BrokenStoreError()
    }
}

/// Servicio de aplicación: persistencia en cada transición, restauración y sync.
final class CaminoControllerTests: XCTestCase {
    private struct Env {
        let catalog: FixtureStageCatalog
        let pois: FixturePoiSource
        let sessionStore: InMemorySessionStore
        let syncStore: InMemorySyncQueueStore
        let clock: FixedClock
    }

    private func makeEnv() throws -> Env {
        return Env(
            catalog: try FixtureStageCatalog(data: RepoFiles.data("shared/fixtures/stages.json")),
            pois: try FixturePoiSource(data: RepoFiles.data("shared/fixtures/pois.json")),
            sessionStore: InMemorySessionStore(),
            syncStore: InMemorySyncQueueStore(),
            clock: FixedClock(secondsSince1970: 1_700_000_000)
        )
    }

    @MainActor
    private func makeController(_ env: Env, api: any CaminoApi = BlockedCaminoApi()) -> CaminoController {
        return CaminoController(
            catalog: env.catalog,
            poiSource: env.pois,
            sessionStore: env.sessionStore,
            syncStore: env.syncStore,
            api: api,
            clock: env.clock,
            ids: SequentialIdGenerator(prefix: "id-"),
            jitter: { 0 },
            autoSync: false
        )
    }

    @MainActor
    func testStartPersistsAndRestoresAfterRelaunch() async throws {
        let env = try makeEnv()
        let controller = makeController(env)
        XCTAssertEqual(controller.state, .idle)

        let session = try controller.start(stageId: "cf-sarria-portomarin")
        XCTAssertEqual(env.sessionStore.value?.state, .active(session), "se persiste al empezar")
        XCTAssertEqual(env.syncStore.value?.queue.map { $0.type }, [SyncEventType.stageStarted], "se encola stage_started")

        controller.updateSteps(500)
        XCTAssertEqual(env.sessionStore.value?.state.activeSession?.steps, 500, "se persisten los pasos")

        // "El sistema mata la app": nuevo controlador sobre los mismos almacenes.
        env.clock.advance(by: 600)
        let relaunched = makeController(env)
        XCTAssertEqual(relaunched.activeSession?.sessionId, session.sessionId, "se restaura Active")
        XCTAssertEqual(relaunched.activeSession?.steps, 500)
        XCTAssertEqual(relaunched.elapsedSeconds(at: env.clock.now()), 600, "sigue contando el tiempo")
        XCTAssertEqual(relaunched.sync.pendingCount, 1, "la cola también se restaura")

        relaunched.updateSteps(800)
        let summary = try relaunched.finish()
        XCTAssertEqual(summary.steps, 800)
        XCTAssertEqual(summary.activeSeconds, 600)
        XCTAssertEqual(relaunched.state, .idle)
        XCTAssertEqual(relaunched.history.first, summary)
        XCTAssertEqual(env.sessionStore.value?.state, .idle)
        XCTAssertEqual(env.sessionStore.value?.history.count, 1)
        XCTAssertEqual(env.syncStore.value?.queue.map { $0.type }, [SyncEventType.stageStarted, SyncEventType.stageFinished])
    }

    @MainActor
    func testErrorsLeaveStateUntouched() async throws {
        let env = try makeEnv()
        let controller = makeController(env)
        XCTAssertThrowsError(try controller.start(stageId: "nope")) { error in
            XCTAssertEqual(error as? SessionError, .unknownStage)
        }
        XCTAssertThrowsError(try controller.finish()) { error in
            XCTAssertEqual(error as? SessionError, .notActive)
        }
        XCTAssertNil(env.sessionStore.value, "sin transición no se escribe nada")
        XCTAssertEqual(controller.sync.pendingCount, 0)

        try controller.start(stageId: "cf-sarria-portomarin")
        XCTAssertThrowsError(try controller.start(stageId: "cf-portomarin-palas")) { error in
            XCTAssertEqual(error as? SessionError, .alreadyActive)
        }
        XCTAssertEqual(controller.sync.pendingCount, 1)
    }

    @MainActor
    func testUpdatesWhenIdleAreIgnored() async throws {
        let env = try makeEnv()
        let controller = makeController(env)
        controller.updateSteps(100)
        let fix = LocationFix(point: GeoPoint(lat: 42.7808, lon: -7.4141), accuracyMeters: 5, timestamp: env.clock.now())
        XCTAssertNil(controller.updateLocation(fix))
        XCTAssertEqual(controller.state, .idle)
        XCTAssertNil(env.sessionStore.value)
    }

    @MainActor
    func testPoiAlertFromFixtures() async throws {
        let env = try makeEnv()
        let controller = makeController(env)
        try controller.start(stageId: "cf-sarria-portomarin")

        // Junto a p01 (Fuente de Barbadelo).
        let nearP01 = GeoPoint(lat: 42.7701, lon: -7.4552)
        let fix = LocationFix(point: nearP01, accuracyMeters: 5, timestamp: env.clock.now())
        let result = try XCTUnwrap(controller.updateLocation(fix))
        XCTAssertEqual(result.alert?.poi.id, "p01")
        XCTAssertEqual(controller.activeSession?.alertedPoiIds, ["p01"])
        XCTAssertEqual(env.sessionStore.value?.state.activeSession?.alertedPoiIds, ["p01"], "el aviso se persiste")

        // El próximo POI ya no es p01.
        let next = try XCTUnwrap(controller.nextPoi(from: nearP01))
        XCTAssertNotEqual(next.poi.id, "p01")
        XCTAssertEqual(next.poi.stageId, "cf-sarria-portomarin")
    }

    @MainActor
    func testRemainingMetersAndTotals() async throws {
        let env = try makeEnv()
        let controller = makeController(env)
        try controller.start(stageId: "cf-sarria-portomarin")
        XCTAssertEqual(controller.remainingMeters, 22200)

        let start = GeoPoint(lat: 42.7808, lon: -7.4141)
        let t0 = env.clock.now()
        controller.updateLocation(LocationFix(point: start, accuracyMeters: 5, timestamp: t0))
        controller.updateLocation(LocationFix(point: GeoPoint(lat: 42.7816993, lon: -7.4141), accuracyMeters: 5, timestamp: t0.addingTimeInterval(70)))
        XCTAssertEqual(controller.remainingMeters ?? 0, 22200 - 99.9977, accuracy: 0.01)

        env.clock.advance(by: 3600)
        controller.updateSteps(5000)
        try controller.finish()
        XCTAssertNil(controller.remainingMeters)
        XCTAssertEqual(controller.totals, CaminoTotals(stages: 1, distanceMeters: 100, steps: 5000, activeSeconds: 3600))
    }

    @MainActor
    func testSuggestedStageFollowsLastFinished() async throws {
        let env = try makeEnv()
        let controller = makeController(env)
        XCTAssertEqual(controller.suggestedStage?.id, "cf-sarria-portomarin")
        XCTAssertEqual(controller.stagesForPicker.map { $0.id }.first, "cf-sarria-portomarin")

        try controller.start(stageId: "cf-sarria-portomarin")
        try controller.finish()
        XCTAssertEqual(controller.suggestedStage?.id, "cf-portomarin-palas")
        let picker = controller.stagesForPicker.map { $0.id }
        XCTAssertEqual(picker.first, "cf-portomarin-palas")
        XCTAssertEqual(picker.count, 5)
        XCTAssertEqual(Set(picker).count, 5)

        try controller.start(stageId: "cf-pedrouzo-santiago")
        try controller.finish()
        XCTAssertNil(controller.suggestedStage, "tras la última etapa no hay sugerida")
        XCTAssertEqual(controller.stagesForPicker.map { $0.id }.first, "cf-sarria-portomarin")
    }

    @MainActor
    func testBlockedApiKeepsEventsAndMockSyncs() async throws {
        let env = try makeEnv()
        let blocked = makeController(env, api: BlockedCaminoApi())
        XCTAssertFalse(blocked.isDemo)
        try blocked.start(stageId: "cf-sarria-portomarin")
        try blocked.finish()
        let status = await blocked.syncNow(manual: true)
        XCTAssertEqual(status, .blocked)
        XCTAssertEqual(blocked.sync.pendingCount, 2, "Release: no se pierde ningún evento")

        // Debug: mismo almacenamiento, adaptador Mock.
        let mock = MockCaminoApi(latencySeconds: 0)
        let demo = makeController(env, api: mock)
        XCTAssertTrue(demo.isDemo)
        let demoStatus = await demo.syncNow(manual: true)
        XCTAssertEqual(demoStatus, .synced)
        XCTAssertEqual(mock.sentEventIds.count, 2)
        XCTAssertEqual(env.syncStore.value?.queue.count, 0)
    }

    @MainActor
    func testCorruptStoreStartsCleanAndReportsError() async throws {
        let env = try makeEnv()
        var storageErrors = 0
        let controller = CaminoController(
            catalog: env.catalog,
            poiSource: env.pois,
            sessionStore: BrokenSessionStore(),
            syncStore: env.syncStore,
            api: BlockedCaminoApi(),
            clock: env.clock,
            ids: SequentialIdGenerator(),
            jitter: { 0 },
            autoSync: false
        )
        controller.onStorageError = { _ in storageErrors += 1 }
        XCTAssertEqual(controller.startupErrors.count, 1)
        XCTAssertEqual(controller.state, .idle)
        try controller.start(stageId: "cf-sarria-portomarin")
        XCTAssertTrue(controller.state.isActive, "el estado en memoria sigue siendo válido")
        XCTAssertEqual(storageErrors, 1)
    }

    @MainActor
    func testOnChangeIsCalledOnTransitions() async throws {
        let env = try makeEnv()
        let controller = makeController(env)
        var changes = 0
        controller.onChange = { changes += 1 }
        try controller.start(stageId: "cf-sarria-portomarin")
        XCTAssertGreaterThan(changes, 0)
        let before = changes
        try controller.finish()
        XCTAssertGreaterThan(changes, before)
    }
}
