import XCTest
@testable import CaminoDesign

final class ContrastTests: XCTestCase {
    func testKnownContrastValues() {
        XCTAssertEqual(RGB.contrast(RGB(0x000000), RGB(0xFFFFFF)), 21, accuracy: 0.001)
        XCTAssertEqual(RGB.contrast(RGB(0x777777), RGB(0xFFFFFF)), 4.48, accuracy: 0.01)
        XCTAssertEqual(RGB.contrast(RGB(0x123456), RGB(0x123456)), 1, accuracy: 0.0001)
        XCTAssertEqual(RGB(0xA8291F).description, "#A8291F")
    }

    /// Cada par de color que usa la interfaz cumple su umbral en ambos temas.
    func testEveryRequiredPairMeetsThresholdInBothThemes() {
        for theme in ThemeID.allCases {
            let palette = Palette.of(theme)
            for requirement in ContrastRequirement.all {
                let fg = palette[keyPath: requirement.foreground]
                let bg = palette[keyPath: requirement.background]
                let ratio = RGB.contrast(fg, bg)
                XCTAssertGreaterThanOrEqual(
                    ratio, requirement.minimum,
                    "\(theme.rawValue): \(requirement.name) \(fg) / \(bg) = \(String(format: "%.2f", ratio))"
                )
            }
        }
    }

    /// Los estados no dependen sólo del color, pero además deben distinguirse entre sí
    /// por luminancia en cada tema para ayudar a personas con daltonismo.
    func testStatusColorsAreDistinctFromEachOther() {
        for theme in ThemeID.allCases {
            let p = Palette.of(theme)
            XCTAssertNotEqual(p.positive, p.warning)
            XCTAssertNotEqual(p.positive, p.critical)
            XCTAssertNotEqual(p.warning, p.critical)
        }
    }

    func testInitialThemeIsNegro() {
        XCTAssertEqual(ThemeID.initial, .negro)
    }

    /// Imprime la tabla de tokens con sus contrastes (se copia a docs/design/DESIGN_TOKENS.md).
    func testPrintTokenTable() {
        var lines: [String] = []
        for requirement in ContrastRequirement.all {
            let values = ThemeID.allCases.map { theme -> String in
                let p = Palette.of(theme)
                let ratio = RGB.contrast(p[keyPath: requirement.foreground], p[keyPath: requirement.background])
                return String(format: "%.2f", ratio)
            }
            lines.append("| \(requirement.name) | \(requirement.minimum) | " + values.joined(separator: " | ") + " |")
        }
        print("CONTRAST_TABLE_BEGIN\n" + lines.joined(separator: "\n") + "\nCONTRAST_TABLE_END")
    }
}
