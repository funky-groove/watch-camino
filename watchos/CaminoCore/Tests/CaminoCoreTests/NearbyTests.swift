import Foundation
import XCTest
@testable import CaminoCore

/// Lista "Cerca", calidad de ubicación y filtro de avisos por categoría.
final class NearbyTests: XCTestCase {
    private let t0 = Date(timeIntervalSince1970: 1_700_000_000)

    private func fix(lat: Double, lon: Double, accuracy: Double, at date: Date) -> LocationFix {
        return LocationFix(point: GeoPoint(lat: lat, lon: lon), accuracyMeters: accuracy, timestamp: date)
    }

    func testLocationQuality() {
        XCTAssertEqual(LocationQuality.of(nil, now: t0), .none)
        XCTAssertEqual(
            LocationQuality.of(fix(lat: 0, lon: 0, accuracy: 12, at: t0.addingTimeInterval(-30)), now: t0),
            .good(accuracyMeters: 12, ageSeconds: 30)
        )
        XCTAssertEqual(
            LocationQuality.of(fix(lat: 0, lon: 0, accuracy: 50, at: t0), now: t0),
            .good(accuracyMeters: 50, ageSeconds: 0),
            "50 m todavía es precisión suficiente (§5)"
        )
        XCTAssertEqual(
            LocationQuality.of(fix(lat: 0, lon: 0, accuracy: 51, at: t0), now: t0),
            .imprecise(accuracyMeters: 51, ageSeconds: 0)
        )
        XCTAssertEqual(
            LocationQuality.of(fix(lat: 0, lon: 0, accuracy: 10, at: t0.addingTimeInterval(-301)), now: t0),
            .stale(accuracyMeters: 10, ageSeconds: 301)
        )
        XCTAssertEqual(
            LocationQuality.of(fix(lat: 0, lon: 0, accuracy: 10, at: t0.addingTimeInterval(60)), now: t0),
            .good(accuracyMeters: 10, ageSeconds: 0),
            "un fix con hora futura no da edad negativa"
        )
        XCTAssertTrue(LocationQuality.none.isApproximate)
        XCTAssertFalse(LocationQuality.good(accuracyMeters: 5, ageSeconds: 0).isApproximate)
    }

    func testNearbyOrdersByDistanceFiltersAndLimits() throws {
        let source = try FixturePoiSource(data: RepoFiles.data("shared/fixtures/pois.json"))
        let all = source.pois(forStage: "cf-palas-arzua")
        // Junto a la iglesia de Melide (p07); el centro de salud (p08) está a ~200 m.
        let here = GeoPoint(lat: 42.9140, lon: -8.0140)

        let everything = Nearby.list(pois: all, from: here, categories: Set(PoiCategory.allCases))
        XCTAssertEqual(everything.map { $0.poi.id }, ["p07", "p08", "p09"])
        XCTAssertEqual(everything.first?.distanceMeters ?? -1, 0, accuracy: 0.01)

        let health = Nearby.list(pois: all, from: here, categories: [.health])
        XCTAssertEqual(health.map { $0.poi.id }, ["p08"])

        let water = Nearby.list(pois: all, from: here, categories: [.water])
        XCTAssertTrue(water.isEmpty, "sin agua en la etapa: lista vacía, no se inventan datos")

        XCTAssertEqual(Nearby.list(pois: all, from: here, categories: Set(PoiCategory.allCases), limit: 1).count, 1)
        XCTAssertEqual(Nearby.list(pois: all, from: here, categories: Set(PoiCategory.allCases), limit: -1).count, 0)
    }

    @MainActor
    func testControllerNearbyAndPoiLookup() async throws {
        let controller = try makeController()
        let here = GeoPoint(lat: 42.7701, lon: -7.4552) // Fuente de Barbadelo (p01)

        // Sin etapa en curso: todas las etapas.
        let idleWater = controller.nearby(from: here, categories: [.water])
        XCTAssertEqual(idleWater.first?.poi.id, "p01")
        XCTAssertEqual(idleWater.count, 3, "las tres fuentes de las fixtures")

        // Con etapa en curso: sólo los POIs de esa etapa.
        try controller.start(stageId: "cf-portomarin-palas")
        XCTAssertEqual(controller.nearby(from: here, categories: [.water]).map { $0.poi.id }, ["p05"])

        XCTAssertEqual(controller.poi(id: "p13")?.name, "Catedral de Santiago")
        XCTAssertNil(controller.poi(id: "nope"))
    }

    @MainActor
    func testDisabledCategoryIsNotAlertedAndDoesNotConsumeRateLimit() async throws {
        let controller = try makeController()
        try controller.start(stageId: "cf-sarria-portomarin")
        controller.alertCategories = [.landmark]

        // En la fuente de Barbadelo (p01, agua) con el agua desactivada: sin aviso.
        let first = controller.updateLocation(fix(lat: 42.7701, lon: -7.4552, accuracy: 5, at: t0.addingTimeInterval(10)))
        XCTAssertNil(first?.alert)
        XCTAssertEqual(controller.activeSession?.alertedPoiIds, [])
        XCTAssertNil(controller.activeSession?.lastAlertAt)

        // Se reactiva el agua: el siguiente fix avisa sin esperar al límite de ritmo.
        controller.alertCategories = Set(PoiCategory.allCases)
        let second = controller.updateLocation(fix(lat: 42.7702, lon: -7.4553, accuracy: 5, at: t0.addingTimeInterval(20)))
        XCTAssertEqual(second?.alert?.poi.id, "p01")
    }

    @MainActor
    private func makeController() throws -> CaminoController {
        return CaminoController(
            catalog: try FixtureStageCatalog(data: RepoFiles.data("shared/fixtures/stages.json")),
            poiSource: try FixturePoiSource(data: RepoFiles.data("shared/fixtures/pois.json")),
            sessionStore: InMemorySessionStore(),
            syncStore: InMemorySyncQueueStore(),
            api: BlockedCaminoApi(),
            clock: FixedClock(t0),
            ids: SequentialIdGenerator(prefix: "id-"),
            jitter: { 0 },
            autoSync: false
        )
    }
}
