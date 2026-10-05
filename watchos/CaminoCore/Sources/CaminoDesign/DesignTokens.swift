import Foundation

// Tokens de diseño de Camino Seguro Watch (docs/design/DESIGN_TOKENS.md).
//
// Datos puros, sin SwiftUI, para poder verificar el contraste con tests en cualquier
// plataforma. La app los convierte a `Color` en `CaminoWatch/Design/Theme.swift`.
//
// PROCEDENCIA: todos los colores son ESTIMADOS (no confirmados en el código de la app
// principal, al que este repositorio no tiene acceso, ni medidos sobre capturas, que no
// se han recibido). Se han elegido para cumplir los umbrales de contraste verificados
// por `ContrastTests`. Sustituir por los valores confirmados cuando estén disponibles.

/// Color sRGB opaco, 8 bits por canal.
public struct RGB: Equatable, Hashable, Sendable, CustomStringConvertible {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(_ hex: UInt32) {
        red = UInt8((hex >> 16) & 0xFF)
        green = UInt8((hex >> 8) & 0xFF)
        blue = UInt8(hex & 0xFF)
    }

    public var description: String {
        return String(format: "#%02X%02X%02X", red, green, blue)
    }

    /// Luminancia relativa (WCAG 2.x).
    public var relativeLuminance: Double {
        func channel(_ value: UInt8) -> Double {
            let c = Double(value) / 255.0
            return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    /// Relación de contraste WCAG 2.x entre dos colores (1…21).
    public static func contrast(_ a: RGB, _ b: RGB) -> Double {
        let la = a.relativeLuminance
        let lb = b.relativeLuminance
        return (max(la, lb) + 0.05) / (min(la, lb) + 0.05)
    }
}

/// Temas disponibles. Negro es el valor inicial.
public enum ThemeID: String, CaseIterable, Codable, Sendable {
    case negro
    case perla

    public static let initial: ThemeID = .negro
}

/// Paleta semántica. Las pantallas sólo usan estos nombres, nunca valores sueltos.
public struct Palette: Equatable, Sendable {
    /// Fondo de pantalla.
    public let background: RGB
    /// Tarjetas y filas.
    public let surface: RGB
    /// Superficie elevada (fila pulsada, tarjeta dentro de tarjeta).
    public let surfaceRaised: RGB
    /// Texto principal.
    public let textPrimary: RGB
    /// Texto secundario y etiquetas.
    public let textSecondary: RGB
    /// Separadores y bordes finos decorativos.
    public let hairline: RGB
    /// Contorno de controles (acción secundaria): debe distinguirse del fondo.
    public let controlOutline: RGB
    /// Acción principal: fondo y texto.
    public let actionPrimaryFill: RGB
    public let actionPrimaryText: RGB
    /// Estados. Siempre acompañados de texto o símbolo.
    public let positive: RGB
    public let warning: RGB
    public let critical: RGB

    public static func of(_ theme: ThemeID) -> Palette {
        switch theme {
        case .negro:
            return .negro
        case .perla:
            return .perla
        }
    }

    public static let negro = Palette(
        background: RGB(0x000000),
        surface: RGB(0x1A1A19),
        surfaceRaised: RGB(0x262624),
        textPrimary: RGB(0xF2EFE8),
        textSecondary: RGB(0xA8A399),
        hairline: RGB(0x3B3936),
        controlOutline: RGB(0x77726A),
        actionPrimaryFill: RGB(0xF2EFE8),
        actionPrimaryText: RGB(0x141413),
        positive: RGB(0x5DBB7E),
        warning: RGB(0xE5A93D),
        critical: RGB(0xFF7A6B)
    )

    public static let perla = Palette(
        background: RGB(0xF3EFE7),
        surface: RGB(0xEAE4D8),
        surfaceRaised: RGB(0xE1D9CA),
        textPrimary: RGB(0x1C1B19),
        textSecondary: RGB(0x5B564E),
        hairline: RGB(0xCBC2B2),
        controlOutline: RGB(0x857D70),
        actionPrimaryFill: RGB(0x1C1B19),
        actionPrimaryText: RGB(0xF3EFE7),
        positive: RGB(0x24633A),
        warning: RGB(0x7E5200),
        critical: RGB(0xA8291F)
    )
}

/// Pares de color que la interfaz realmente combina, con el contraste mínimo exigido.
/// `ContrastTests` los comprueba en ambos temas.
public struct ContrastRequirement {
    public enum Kind: String, Sendable {
        /// Texto de cualquier tamaño (umbral de texto normal, 4,5:1, aunque sea grande).
        case text
        /// Componentes de interfaz y objetos gráficos (3:1).
        case nonText
    }

    public let name: String
    public let kind: Kind
    public let foreground: KeyPath<Palette, RGB>
    public let background: KeyPath<Palette, RGB>

    public var minimum: Double {
        switch kind {
        case .text:
            return 4.5
        case .nonText:
            return 3.0
        }
    }

    public static var all: [ContrastRequirement] {
        var list: [ContrastRequirement] = []
        let grounds: [(String, KeyPath<Palette, RGB>)] = [
            ("fondo", \Palette.background),
            ("superficie", \Palette.surface),
            ("superficie elevada", \Palette.surfaceRaised),
        ]
        let texts: [(String, KeyPath<Palette, RGB>)] = [
            ("texto principal", \Palette.textPrimary),
            ("texto secundario", \Palette.textSecondary),
            ("positivo", \Palette.positive),
            ("advertencia", \Palette.warning),
            ("crítico", \Palette.critical),
        ]
        for (textName, text) in texts {
            for (groundName, ground) in grounds {
                list.append(ContrastRequirement(
                    name: "\(textName) sobre \(groundName)", kind: .text, foreground: text, background: ground))
            }
        }
        list.append(ContrastRequirement(
            name: "texto de acción principal", kind: .text,
            foreground: \Palette.actionPrimaryText, background: \Palette.actionPrimaryFill))
        list.append(ContrastRequirement(
            name: "acción principal sobre fondo", kind: .nonText,
            foreground: \Palette.actionPrimaryFill, background: \Palette.background))
        // Acción de emergencia ("Llamar al 112"): relleno `critical` con el texto de acción
        // principal, que se invierte por tema (oscuro en Negro, claro en Perla).
        list.append(ContrastRequirement(
            name: "texto de acción de emergencia", kind: .text,
            foreground: \Palette.actionPrimaryText, background: \Palette.critical))
        list.append(ContrastRequirement(
            name: "acción de emergencia sobre fondo", kind: .nonText,
            foreground: \Palette.critical, background: \Palette.background))
        list.append(ContrastRequirement(
            name: "contorno de control sobre fondo", kind: .nonText,
            foreground: \Palette.controlOutline, background: \Palette.background))
        list.append(ContrastRequirement(
            name: "contorno de control sobre superficie", kind: .nonText,
            foreground: \Palette.controlOutline, background: \Palette.surface))
        return list
    }
}

/// Espaciados (pt). Escala de 4 pt.
public enum Spacing {
    public static let xxs: Double = 2
    public static let xs: Double = 4
    public static let s: Double = 8
    public static let m: Double = 12
    public static let l: Double = 16
}

/// Radios (pt).
public enum Radius {
    /// Tarjetas.
    public static let card: Double = 14
    /// Botones (cápsula si el alto lo permite).
    public static let control: Double = 22
    /// Barra de progreso.
    public static let bar: Double = 2
}

/// Grosores de línea (pt).
public enum Stroke {
    /// Separadores y bordes de tarjeta.
    public static let hairline: Double = 1
    /// Contorno de controles secundarios.
    public static let control: Double = 1.5
}

/// Tamaños de interacción (pt).
public enum Target {
    /// Alto mínimo de cualquier control pulsable. Ver docs/accessibility.
    public static let minimumHeight: Double = 44
    /// Alto de la acción principal de una pantalla.
    public static let primaryHeight: Double = 52
}
