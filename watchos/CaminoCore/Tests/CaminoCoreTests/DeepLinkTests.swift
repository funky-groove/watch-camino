import Foundation
import XCTest
@testable import CaminoCore

final class DeepLinkTests: XCTestCase {
    private func parse(_ text: String) -> DeepLink? {
        guard let url = URL(string: text) else {
            return nil
        }
        return DeepLink.parse(url)
    }

    func testKnownLinks() {
        XCTAssertEqual(parse("caminoseguro://stage"), .stage)
        XCTAssertEqual(parse("caminoseguro://"), .stage)
        XCTAssertEqual(parse("CaminoSeguro://STATS"), .stats)
        XCTAssertEqual(parse("caminoseguro://nearby"), .nearby(waterOnly: false))
        XCTAssertEqual(parse("caminoseguro://nearby?c=water"), .nearby(waterOnly: true))
        XCTAssertEqual(parse("caminoseguro://nearby?c=food"), .nearby(waterOnly: false))
        XCTAssertEqual(parse("caminoseguro://poi?id=p01"), .poi(id: "p01"))
        XCTAssertEqual(parse("caminoseguro://settings"), .settings)
    }

    func testRejectsForeignOrMalformed() {
        XCTAssertNil(parse("https://stage"))
        XCTAssertNil(parse("tel://112"))
        XCTAssertNil(parse("caminoseguro://finish"), "un enlace nunca ejecuta acciones")
        XCTAssertNil(parse("caminoseguro://start"))
        XCTAssertNil(parse("caminoseguro://poi"))
        XCTAssertNil(parse("caminoseguro://poi?id="))
        XCTAssertNil(parse("caminoseguro://poi?id=../../etc"))
        XCTAssertNil(parse("caminoseguro://poi?id=%3Cscript%3E"))
        XCTAssertNil(parse("caminoseguro://poi?id=" + String(repeating: "a", count: 65)))
    }

    func testRoundTrip() {
        let links: [DeepLink] = [.stage, .stats, .nearby(waterOnly: true), .nearby(waterOnly: false), .poi(id: "p13"), .settings]
        for link in links {
            XCTAssertEqual(DeepLink.parse(link.url), link, link.url.absoluteString)
        }
    }
}
