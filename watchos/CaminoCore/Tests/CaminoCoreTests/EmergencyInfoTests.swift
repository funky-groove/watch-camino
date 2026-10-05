import Foundation
import XCTest
@testable import CaminoCore

/// Pantalla SOS: número, marcador simulado y resumen de ubicación.
/// Sólo se usa `MockEmergencyDialer`: ningún test abre ni simula abrir una llamada real.
final class EmergencyInfoTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_700_000_000)

    private func fix(
        lat: Double = 42.7808,
        lon: Double = -7.4141,
        accuracy: Double = 8,
        ageSeconds: TimeInterval
    ) -> LocationFix {
        return LocationFix(
            point: GeoPoint(lat: lat, lon: lon),
            accuracyMeters: accuracy,
            timestamp: now.addingTimeInterval(-ageSeconds)
        )
    }

    // MARK: - Número

    func testEmergencyNumberIs112WithTelURL() {
        XCTAssertEqual(EmergencyNumber.spainEU.digits, "112")
        XCTAssertEqual(EmergencyNumber.spainEU.telURL?.absoluteString, "tel:112")
    }

    func testInvalidNumbersHaveNoURL() {
        XCTAssertNil(EmergencyNumber(digits: "").telURL)
        XCTAssertNil(EmergencyNumber(digits: "11 2").telURL)
        XCTAssertNil(EmergencyNumber(digits: "112;x").telURL)
        XCTAssertNil(EmergencyNumber(digits: "١١٢").telURL, "dígitos no ASCII")
    }

    // MARK: - Marcador simulado

    func testMockRecordsRequestsAndHandsToSystem() {
        let dialer = MockEmergencyDialer()
        XCTAssertEqual(dialer.requestCall(number: .spainEU), .handedToSystem)
        XCTAssertEqual(dialer.requestCall(number: .spainEU), .handedToSystem)
        XCTAssertEqual(dialer.requests, [.spainEU, .spainEU])
    }

    func testMockFailsOnInvalidNumber() {
        let dialer = MockEmergencyDialer()
        XCTAssertEqual(dialer.requestCall(number: EmergencyNumber(digits: "")), .failed(.invalidURL))
        XCTAssertEqual(dialer.requests.count, 1)
    }

    func testMockCanSimulateFailure() {
        let dialer = MockEmergencyDialer(result: .failed(.notMainThread))
        XCTAssertEqual(dialer.requestCall(number: .spainEU), .failed(.notMainThread))
    }

    // MARK: - Coordenadas

    func testCoordinatesFiveDecimalsWithHemispheres() {
        let summary = EmergencyLocationSummary.of(
            fix: fix(lat: 42.780812, lon: -7.414096, ageSeconds: 10), now: now, permission: .granted)
        XCTAssertEqual(summary.latitude, EmergencyCoordinate(degrees: "42.78081", hemisphere: .north))
        XCTAssertEqual(summary.longitude, EmergencyCoordinate(degrees: "7.41410", hemisphere: .west))
        XCTAssertTrue(summary.hasCoordinates)
    }

    func testSouthernAndEasternHemispheres() {
        let summary = EmergencyLocationSummary.of(
            fix: fix(lat: -33.8688, lon: 151.2093, ageSeconds: 0), now: now, permission: .granted)
        XCTAssertEqual(summary.latitude, EmergencyCoordinate(degrees: "33.86880", hemisphere: .south))
        XCTAssertEqual(summary.longitude, EmergencyCoordinate(degrees: "151.20930", hemisphere: .east))
    }

    func testValueRoundingToZeroIsNotSouthOrWest() {
        XCTAssertEqual(EmergencyCoordinate.latitude(-0.000001), EmergencyCoordinate(degrees: "0.00000", hemisphere: .north))
        XCTAssertEqual(EmergencyCoordinate.longitude(-0.000001), EmergencyCoordinate(degrees: "0.00000", hemisphere: .east))
    }

    // MARK: - Clasificación por antigüedad

    func testCurrentUpTo60Seconds() {
        let at0 = EmergencyLocationSummary.of(fix: fix(ageSeconds: 0), now: now, permission: .granted)
        XCTAssertEqual(at0.status, .current)
        XCTAssertEqual(at0.ageSeconds, 0)
        let at60 = EmergencyLocationSummary.of(fix: fix(ageSeconds: 60), now: now, permission: .granted)
        XCTAssertEqual(at60.status, .current)
        XCTAssertEqual(at60.ageSeconds, 60)
    }

    func testLastKnownFrom61SecondsTo5Minutes() {
        let at61 = EmergencyLocationSummary.of(fix: fix(ageSeconds: 61), now: now, permission: .granted)
        XCTAssertEqual(at61.status, .lastKnown)
        let at120 = EmergencyLocationSummary.of(fix: fix(ageSeconds: 120), now: now, permission: .granted)
        XCTAssertEqual(at120.status, .lastKnown)
        XCTAssertEqual(at120.ageSeconds, 120, "hace 2 min")
        let at300 = EmergencyLocationSummary.of(fix: fix(ageSeconds: 300), now: now, permission: .granted)
        XCTAssertEqual(at300.status, .lastKnown)
    }

    func testStaleAfter5Minutes() {
        let summary = EmergencyLocationSummary.of(fix: fix(ageSeconds: 301), now: now, permission: .granted)
        XCTAssertEqual(summary.status, .stale)
        XCTAssertEqual(summary.ageSeconds, 301)
        XCTAssertTrue(summary.hasCoordinates, "una posición antigua se muestra, marcada como antigua")
    }

    func testFutureTimestampHasZeroAge() {
        let summary = EmergencyLocationSummary.of(fix: fix(ageSeconds: -30), now: now, permission: .granted)
        XCTAssertEqual(summary.status, .current)
        XCTAssertEqual(summary.ageSeconds, 0)
    }

    // MARK: - Precisión

    func testAccuracyRounded() {
        let summary = EmergencyLocationSummary.of(fix: fix(accuracy: 12.6, ageSeconds: 5), now: now, permission: .granted)
        XCTAssertEqual(summary.accuracyMeters, 13)
    }

    func testUnknownAccuracyIsNil() {
        let zero = EmergencyLocationSummary.of(fix: fix(accuracy: 0, ageSeconds: 5), now: now, permission: .granted)
        XCTAssertNil(zero.accuracyMeters)
        XCTAssertTrue(zero.hasCoordinates)
        let infinite = EmergencyLocationSummary.of(
            fix: fix(accuracy: .infinity, ageSeconds: 5), now: now, permission: .granted)
        XCTAssertNil(infinite.accuracyMeters)
    }

    // MARK: - Sin posición / sin permiso

    func testNoFixIsNoSignal() {
        for permission in [EmergencyLocationPermission.granted, .notDetermined] {
            let summary = EmergencyLocationSummary.of(fix: nil, now: now, permission: permission)
            XCTAssertEqual(summary.status, .noSignal)
            XCTAssertFalse(summary.hasCoordinates)
            XCTAssertNil(summary.ageSeconds)
            XCTAssertNil(summary.accuracyMeters)
            XCTAssertFalse(summary.permissionDenied)
        }
    }

    func testDeniedWithoutFixIsPermissionDenied() {
        let summary = EmergencyLocationSummary.of(fix: nil, now: now, permission: .denied)
        XCTAssertEqual(summary.status, .permissionDenied)
        XCTAssertTrue(summary.permissionDenied)
        XCTAssertFalse(summary.hasCoordinates)
    }

    func testDeniedKeepsPreviousFixFlagged() {
        let summary = EmergencyLocationSummary.of(fix: fix(ageSeconds: 600), now: now, permission: .denied)
        XCTAssertEqual(summary.status, .stale)
        XCTAssertTrue(summary.permissionDenied)
        XCTAssertTrue(summary.hasCoordinates)
    }

    func testInvalidFixesAreNoSignal() {
        let invalid = [
            fix(accuracy: -1, ageSeconds: 5),
            fix(accuracy: .nan, ageSeconds: 5),
            fix(lat: .nan, ageSeconds: 5),
            fix(lat: 91, ageSeconds: 5),
            fix(lon: -181, ageSeconds: 5),
            fix(lon: .infinity, ageSeconds: 5),
        ]
        for item in invalid {
            let summary = EmergencyLocationSummary.of(fix: item, now: now, permission: .granted)
            XCTAssertEqual(summary.status, .noSignal, "\(item)")
            XCTAssertFalse(summary.hasCoordinates)
        }
    }
}
