import XCTest
@testable import CaminoDesign

final class ContrastTests: XCTestCase {
    func testKnownContrastValues() {
        XCTAssertEqual(RGB.contrast(RGB(0x000000), RGB(0xFFFFFF)), 21, accuracy: 0.001)
        XCTAssertEqual(RGB.contrast(RGB(0x777777), RGB(0xFFFFFF)), 4.48, accuracy: 0.01)
        XCTAssertEqual(RGB.contrast(RGB(0x123456), RGB(0x123456)), 1, accuracy: 0.0001)
        XCTAssertEqual(RGB(0xA8291F).description, "#A8291F")
    }

    /// Cada par de color que usa la interfaz cumple su umbral en cada paleta comprobada
    /// (Negro, Perla de watchOS y Perla de referencia).
    func testEveryRequiredPairMeetsThresholdInEveryPalette() {
        for (name, palette) in Palette.checked {
            for requirement in ContrastRequirement.all {
                let fg = palette[keyPath: requirement.foreground]
                let bg = palette[keyPath: requirement.background]
                let ratio = RGB.contrast(fg, bg)
                XCTAssertGreaterThanOrEqual(
                    ratio, requirement.minimum,
                    "\(name): \(requirement.name) \(fg) / \(bg) = \(String(format: "%.2f", ratio))"
                )
            }
        }
    }

    /// watchOS usa `perlaWatch` para Perla; la Perla de referencia (Wear OS) no cambia.
    func testWatchOSPerlaKeepsBlackBackgroundAndSharedPerlaIsUntouched() {
        XCTAssertEqual(Palette.watchOS(.negro), Palette.negro)
        XCTAssertEqual(Palette.watchOS(.perla), Palette.perlaWatch)
        XCTAssertEqual(Palette.of(.perla), Palette.perla)
        // La hora del sistema es siempre blanca: el fondo de pantalla de watchOS es negro.
        for theme in ThemeID.allCases {
            XCTAssertEqual(Palette.watchOS(theme).background, RGB(0x000000))
        }
        XCTAssertEqual(Palette.perla.background, RGB(0xF3EFE7))
        XCTAssertEqual(Palette.perla.textPrimary, RGB(0x1C1B19))
        // Negro y la Perla de referencia: texto sobre superficie = texto sobre fondo.
        for palette in [Palette.negro, Palette.perla] {
            XCTAssertEqual(palette.onSurfacePrimary, palette.textPrimary)
            XCTAssertEqual(palette.onSurfaceSecondary, palette.textSecondary)
            XCTAssertEqual(palette.positiveOnSurface, palette.positive)
            XCTAssertEqual(palette.warningOnSurface, palette.warning)
            XCTAssertEqual(palette.criticalOnSurface, palette.critical)
        }
    }

    /// Los estados no dependen sólo del color, pero además deben distinguirse entre sí
    /// por luminancia en cada tema para ayudar a personas con daltonismo.
    func testStatusColorsAreDistinctFromEachOther() {
        for (_, p) in Palette.checked {
            XCTAssertNotEqual(p.positive, p.warning)
            XCTAssertNotEqual(p.positive, p.critical)
            XCTAssertNotEqual(p.warning, p.critical)
            XCTAssertNotEqual(p.positiveOnSurface, p.warningOnSurface)
            XCTAssertNotEqual(p.positiveOnSurface, p.criticalOnSurface)
            XCTAssertNotEqual(p.warningOnSurface, p.criticalOnSurface)
        }
    }

    func testInitialThemeIsNegro() {
        XCTAssertEqual(ThemeID.initial, .negro)
    }

    /// Imprime la tabla de tokens con sus contrastes (se copia a docs/design/DESIGN_TOKENS.md).
    func testPrintTokenTable() {
        var lines: [String] = []
        for requirement in ContrastRequirement.all {
            let values = Palette.checked.map { entry -> String in
                let p = entry.palette
                let ratio = RGB.contrast(p[keyPath: requirement.foreground], p[keyPath: requirement.background])
                return String(format: "%.2f", ratio)
            }
            lines.append("| \(requirement.name) | \(requirement.minimum) | " + values.joined(separator: " | ") + " |")
        }
        print("CONTRAST_TABLE_BEGIN\n" + lines.joined(separator: "\n") + "\nCONTRAST_TABLE_END")
    }
}
