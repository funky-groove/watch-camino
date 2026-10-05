import Foundation
import XCTest
@testable import CaminoCore

/// shared/fixtures/*.json se decodifican con los adaptadores del núcleo.
final class FixtureTests: XCTestCase {
    func testStagesFixtureLoadsFiveStages() throws {
        let catalog = try FixtureStageCatalog(data: RepoFiles.data("shared/fixtures/stages.json"))
        let stages = catalog.allStages()
        XCTAssertEqual(stages.count, 5)
        XCTAssertEqual(stages.first?.id, "cf-sarria-portomarin")
        XCTAssertEqual(stages.first?.distanceMeters, 22200)
        XCTAssertEqual(stages.last?.to, "Santiago de Compostela")
        XCTAssertEqual(Set(stages.map { $0.id }).count, 5, "ids únicos")
        XCTAssertNotNil(catalog.notice, "el aviso de datos de demostración se conserva")
        XCTAssertEqual(catalog.stage(id: "cf-palas-arzua")?.name, "Palas de Rei – Arzúa")
        XCTAssertNil(catalog.stage(id: "nope"))
    }

    func testPoisFixtureLoadsThirteenPois() throws {
        let catalog = try FixtureStageCatalog(data: RepoFiles.data("shared/fixtures/stages.json"))
        let source = try FixturePoiSource(data: RepoFiles.data("shared/fixtures/pois.json"))
        XCTAssertEqual(source.pois.count, 13)
        XCTAssertEqual(Set(source.pois.map { $0.id }).count, 13, "ids únicos")
        XCTAssertNotNil(source.notice)

        let stageIds = Set(catalog.allStages().map { $0.id })
        for poi in source.pois {
            XCTAssertTrue(stageIds.contains(poi.stageId), "\(poi.id) apunta a una etapa existente")
        }
        XCTAssertEqual(source.pois(forStage: "cf-sarria-portomarin").count, 3)
        XCTAssertEqual(source.pois(forStage: "cf-portomarin-palas").count, 3)
        XCTAssertEqual(source.pois(forStage: "cf-palas-arzua").count, 3)
        XCTAssertEqual(source.pois(forStage: "cf-arzua-pedrouzo").count, 2)
        XCTAssertEqual(source.pois(forStage: "cf-pedrouzo-santiago").count, 2)
        XCTAssertEqual(source.pois(forStage: "nope").count, 0)

        let categories = Set(source.pois.map { $0.category })
        XCTAssertEqual(categories, Set(PoiCategory.allCases), "las 6 categorías aparecen en las fixtures")
    }

    func testMalformedFixtureThrows() {
        XCTAssertThrowsError(try FixtureStageCatalog(data: Data("{}".utf8)))
        XCTAssertThrowsError(try FixturePoiSource(data: Data("not json".utf8)))
    }
}
