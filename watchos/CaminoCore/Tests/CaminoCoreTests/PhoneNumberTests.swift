import Foundation
import XCTest
@testable import CaminoCore

/// Teléfono de POI — V1.1 §J.
final class PhoneNumberTests: XCTestCase {
    func testValidNumbers() {
        XCTAssertTrue(PhoneNumber.isValid("612345678"))
        XCTAssertTrue(PhoneNumber.isValid("982 12 34 56"))
        XCTAssertTrue(PhoneNumber.isValid("+34 612-345-678"))
        XCTAssertTrue(PhoneNumber.isValid("+351 21 123 4567"))
        XCTAssertTrue(PhoneNumber.isValid("+4930123456"))
        XCTAssertTrue(PhoneNumber.isValid("+0123456789"), "+ y 8–15 dígitos, aunque empiece por 0")
        XCTAssertEqual(PhoneNumber.normalized("982 12 34 56"), "+34982123456")
        XCTAssertEqual(PhoneNumber.normalized("(+34) 612 345 678"), nil, "el + sólo al principio")
        XCTAssertEqual(PhoneNumber.telURL("612 345 678")?.absoluteString, "tel:+34612345678")
    }

    func testEmergencyAndShortNumbersAreNotPlacePhones() {
        for n in ["112", "091", "062", "061", "016", "080", "085", "1006", "+112", "+34112", "+34 091", "00 34 612345678"] {
            XCTAssertFalse(PhoneNumber.isValid(n), n)
            XCTAssertNil(PhoneNumber.telURL(n), n)
        }
    }

    func testInvalidNumbers() {
        for n in ["", "   ", "512345678", "61234567", "6123456789", "+1234567", "+1234567890123456",
                  "612345678 ext 2", "tel:612345678", "6123a5678"] {
            XCTAssertFalse(PhoneNumber.isValid(n), n)
        }
        XCTAssertFalse(PhoneNumber.isValid(nil))
    }

    func testPoiPhoneIsOptionalAndBackwardCompatible() throws {
        let v1 = #"{"id":"p","stageId":"s","name":"Fuente","category":"water","location":{"lat":1,"lon":2}}"#
        let poi = try JSONDecoder().decode(Poi.self, from: Data(v1.utf8))
        XCTAssertNil(poi.phone)
        XCTAssertNil(poi.telURL)

        let withPhone = #"{"id":"p","stageId":"s","name":"Albergue","category":"shelter","location":{"lat":1,"lon":2},"phone":"+34 982 123 456"}"#
        let poi2 = try JSONDecoder().decode(Poi.self, from: Data(withPhone.utf8))
        XCTAssertEqual(poi2.telURL?.absoluteString, "tel:+34982123456")

        let emergency = Poi(id: "x", stageId: "s", name: "X", category: .health, location: GeoPoint(lat: 0, lon: 0), phone: "112")
        XCTAssertNil(emergency.telURL)
        let data = try CaminoJSON.encoder().encode(poi2)
        XCTAssertEqual(try CaminoJSON.decoder().decode(Poi.self, from: data), poi2)
    }
}
