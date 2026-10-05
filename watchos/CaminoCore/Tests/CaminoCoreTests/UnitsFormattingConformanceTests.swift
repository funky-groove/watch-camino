import Foundation
import XCTest
@testable import CaminoCore

/// shared/conformance/units_formatting.json — V1.1 §G.
final class UnitsFormattingConformanceTests: XCTestCase {
    private func section(_ key: String) throws -> [[String: Any]] {
        let root = try RepoFiles.conformance("units_formatting.json")
        let cases = jsonArray(root[key]).map { jsonDict($0) }
        XCTAssertFalse(cases.isEmpty, key)
        return cases
    }

    private func units(_ c: [String: Any]) -> UnitSystem {
        let raw = jsonString(c["units"]) ?? ""
        let value = UnitSystem(rawValue: raw)
        XCTAssertNotNil(value, "unidades desconocidas: \(raw)")
        return value ?? .metric
    }

    private func lang(_ c: [String: Any]) -> AppLanguage {
        let raw = jsonString(c["lang"]) ?? ""
        let value = AppLanguage(rawValue: raw)
        XCTAssertNotNil(value, "idioma desconocido: \(raw)")
        return value ?? .es
    }

    func testDistance() throws {
        for c in try section("distance") {
            let m = jsonDouble(c["meters"]) ?? .nan
            XCTAssertEqual(UnitFormatter.distance(meters: m, units: units(c), lang: lang(c)), jsonString(c["text"]), "\(c)")
        }
    }

    func testElevation() throws {
        for c in try section("elevation") {
            let m = jsonDouble(c["meters"]) ?? .nan
            XCTAssertEqual(UnitFormatter.elevation(meters: m, units: units(c)), jsonString(c["text"]), "\(c)")
        }
    }

    func testSteps() throws {
        for c in try section("steps") {
            XCTAssertEqual(UnitFormatter.steps(jsonInt(c["steps"]) ?? -1, lang: lang(c)), jsonString(c["text"]), "\(c)")
        }
    }

    func testPace() throws {
        for c in try section("pace") {
            let text = UnitFormatter.pace(
                distanceMeters: jsonDouble(c["distanceM"]) ?? .nan,
                movingSeconds: jsonDouble(c["movingS"]) ?? .nan,
                units: units(c)
            )
            XCTAssertEqual(text, jsonString(c["text"]), "\(c)")
        }
    }

    func testSpeed() throws {
        for c in try section("speed") {
            let text = UnitFormatter.speed(
                distanceMeters: jsonDouble(c["distanceM"]) ?? .nan,
                movingSeconds: jsonDouble(c["movingS"]) ?? .nan,
                units: units(c),
                lang: lang(c)
            )
            XCTAssertEqual(text, jsonString(c["text"]), "\(c)")
        }
    }

    func testDefensiveInputsAndHelpers() {
        XCTAssertEqual(UnitFormatter.distance(meters: .nan, units: .imperial, lang: .en), "0 ft")
        XCTAssertEqual(UnitFormatter.elevation(meters: .infinity, units: .metric), "0 m")
        XCTAssertNil(UnitFormatter.pace(distanceMeters: .nan, movingSeconds: 600, units: .metric))
        XCTAssertNil(UnitFormatter.speed(distanceMeters: 1000, movingSeconds: .infinity, units: .metric, lang: .es))
        XCTAssertEqual(
            UnitFormatter.paceOrSpeed(distanceMeters: 1000, movingSeconds: 600, units: .metric, mode: .pace, lang: .es),
            UnitFormatter.pace(distanceMeters: 1000, movingSeconds: 600, units: .metric)
        )
        XCTAssertEqual(
            UnitFormatter.paceOrSpeed(distanceMeters: 1000, movingSeconds: 600, units: .metric, mode: .speed, lang: .es),
            "6,0 km/h"
        )
        XCTAssertEqual(AppLanguage.preferred(from: ["fr-FR", "en-GB", "es-ES"]), .en)
        XCTAssertEqual(AppLanguage.preferred(from: ["es_ES"]), .es)
        XCTAssertEqual(AppLanguage.preferred(from: []), .es)
        // Los Formatters de V1 (es, métrico) no cambian.
        XCTAssertEqual(Formatters.distance(meters: 1234), "1,2 km")
        XCTAssertEqual(UnitFormatter.distance(meters: 1234, units: .metric, lang: .es), Formatters.distance(meters: 1234))
        XCTAssertEqual(UnitFormatter.steps(1234, lang: .es), Formatters.steps(1234))
    }
}
