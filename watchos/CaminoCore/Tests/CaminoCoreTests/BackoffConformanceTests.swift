import Foundation
import XCTest
@testable import CaminoCore

/// shared/conformance/backoff.json — §7.
final class BackoffConformanceTests: XCTestCase {
    func testAllVectors() throws {
        let root = try RepoFiles.conformance("backoff.json")
        let jitter = jsonDouble(root["jitter"]) ?? 0
        let cases = jsonArray(root["cases"]).map { jsonDict($0) }
        XCTAssertFalse(cases.isEmpty)

        for c in cases {
            let attempt = jsonInt(c["attempt"]) ?? 0
            let expected = jsonDouble(c["seconds"]) ?? .nan
            XCTAssertEqual(Backoff.seconds(attempt: attempt), expected, "backoff(\(attempt))")
            XCTAssertEqual(Backoff.delaySeconds(attempt: attempt, jitterFraction: jitter), expected, "backoff+jitter(\(attempt))")
        }
    }

    func testJitterIsBoundedToTwentyPercent() {
        XCTAssertEqual(Backoff.delaySeconds(attempt: 1, jitterFraction: 0.2), 36, accuracy: 1e-9)
        XCTAssertEqual(Backoff.delaySeconds(attempt: 1, jitterFraction: 5), 36, accuracy: 1e-9)
        XCTAssertEqual(Backoff.delaySeconds(attempt: 1, jitterFraction: -1), 30, accuracy: 1e-9)
        XCTAssertEqual(Backoff.delaySeconds(attempt: 1, jitterFraction: .nan), 30, accuracy: 1e-9)
        for _ in 0..<100 {
            let j = Backoff.systemJitter()
            XCTAssertGreaterThanOrEqual(j, 0)
            XCTAssertLessThanOrEqual(j, 0.2)
        }
    }

    func testLargeAttemptsDoNotOverflow() {
        XCTAssertEqual(Backoff.seconds(attempt: 1_000), 1800)
        XCTAssertEqual(Backoff.seconds(attempt: Int.max), 1800)
        XCTAssertEqual(Backoff.seconds(attempt: 0), 0)
    }
}
