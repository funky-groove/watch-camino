import Foundation
import XCTest
@testable import CaminoCore

/// shared/conformance/formatting.json — §8.
final class FormattingConformanceTests: XCTestCase {
    func testDistanceVectors() throws {
        let root = try RepoFiles.conformance("formatting.json")
        let cases = jsonArray(root["distance"]).map { jsonDict($0) }
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let meters = jsonDouble(c["meters"]) ?? .nan
            XCTAssertEqual(Formatters.distance(meters: meters), jsonString(c["text"]), "distancia \(meters)")
        }
    }

    func testDurationVectors() throws {
        let root = try RepoFiles.conformance("formatting.json")
        let cases = jsonArray(root["duration"]).map { jsonDict($0) }
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let seconds = jsonInt(c["seconds"]) ?? 0
            XCTAssertEqual(Formatters.duration(seconds: seconds), jsonString(c["text"]), "duración \(seconds)")
        }
    }

    func testStepsVectors() throws {
        let root = try RepoFiles.conformance("formatting.json")
        let cases = jsonArray(root["steps"]).map { jsonDict($0) }
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let steps = jsonInt(c["steps"]) ?? 0
            XCTAssertEqual(Formatters.steps(steps), jsonString(c["text"]), "pasos \(steps)")
        }
    }

    func testDefensiveInputs() {
        XCTAssertEqual(Formatters.distance(meters: Double.nan), "0 m")
        XCTAssertEqual(Formatters.distance(meters: Double.infinity), "0 m")
        XCTAssertEqual(Formatters.distance(meters: 1.0e15), Formatters.distance(meters: 1.0e12))
        XCTAssertEqual(Formatters.duration(interval: -5), "0 min")
        XCTAssertEqual(Formatters.duration(interval: 3900.9), "1 h 05 min")
        XCTAssertEqual(Formatters.distance(meters: 22200), "22 km")
    }

    func testPoiAlertText() {
        let poi = Poi(
            id: "p01",
            stageId: "cf-sarria-portomarin",
            name: "Fuente de Barbadelo",
            category: .water,
            location: GeoPoint(lat: 0, lon: 0)
        )
        XCTAssertEqual(Formatters.poiAlertText(PoiAlert(poi: poi, distanceMeters: 120)), "💧 Fuente de Barbadelo · 120 m")
    }

    func testIconsMatchSpec() {
        XCTAssertEqual(PoiCategory.water.icon, "💧")
        XCTAssertEqual(PoiCategory.shelter.icon, "🛏")
        XCTAssertEqual(PoiCategory.pharmacy.icon, "➕")
        XCTAssertEqual(PoiCategory.health.icon, "🏥")
        XCTAssertEqual(PoiCategory.food.icon, "🍽")
        XCTAssertEqual(PoiCategory.landmark.icon, "⛪")
    }
}
