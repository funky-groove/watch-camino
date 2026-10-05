import Foundation

/// Sistema de unidades preferido (V1.1 §G).
public enum UnitSystem: String, Codable, CaseIterable, Sendable {
    case metric
    case imperial
}

/// Ritmo (min/km) o velocidad (km/h) en la pantalla Trayecto (V1.1 §G).
public enum PaceMode: String, Codable, CaseIterable, Sendable {
    case pace
    case speed
}

/// Idioma de presentación: fija separadores decimal y de miles (V1.1 §G).
public enum AppLanguage: String, Codable, CaseIterable, Sendable {
    case es
    case en

    /// Primer idioma soportado de la lista (p. ej. `Locale.preferredLanguages`); español si ninguno.
    public static func preferred(from identifiers: [String]) -> AppLanguage {
        for identifier in identifiers {
            let code = identifier.lowercased().split(whereSeparator: { $0 == "-" || $0 == "_" }).first.map(String.init) ?? ""
            if let match = AppLanguage(rawValue: code) {
                return match
            }
        }
        return .es
    }

    /// Separador decimal: es `,` · en `.`.
    public var decimalSeparator: String {
        return self == .es ? "," : "."
    }

    /// Separador de miles: es `.` · en `,`.
    public var groupingSeparator: String {
        return self == .es ? "." : ","
    }
}

/// Formato con unidades e idioma — V1.1 §G. Reproduce `fmt_distance_u`, `fmt_elevation`,
/// `fmt_steps_l`, `pace_text` y `speed_text` de `shared/conformance/reference.py`.
///
/// Como `Formatters`, implementa la regla a mano (nada de `NumberFormatter`).
/// `pace`/`speed` devuelven `nil` cuando no hay datos: la UI muestra "sin datos", nunca 0.
public enum UnitFormatter {
    public static let metersPerMile: Double = 1609.344
    public static let feetPerMeter: Double = 3.28084
    static let mphPerMetersPerSecond: Double = 2.2369362920544
    static let kmhPerMetersPerSecond: Double = 3.6

    /// Distancia: métrico como `Formatters.distance` con el separador del idioma;
    /// imperial `"X ft"` (< 0,1 mi, a la decena), `"X.Y mi"` (< 10 mi) o `"X mi"`.
    public static func distance(meters input: Double, units: UnitSystem, lang: AppLanguage) -> String {
        let m = (input.isFinite && input > 0) ? min(input, 1.0e12) : 0
        let dec = lang.decimalSeparator
        switch units {
        case .metric:
            return Formatters.distance(meters: m).replacingOccurrences(of: ",", with: dec)
        case .imperial:
            let mi = m / metersPerMile
            if mi < 0.1 {
                return "\(Int(floor(m * feetPerMeter / 10 + 0.5)) * 10) ft"
            }
            let tenths = Int(floor(mi * 10 + 0.5))
            if tenths < 100 {
                return "\(tenths / 10)\(dec)\(tenths % 10) mi"
            }
            return "\(Int(floor(mi + 0.5))) mi"
        }
    }

    /// Altitud o desnivel: entero con redondeo half-up simétrico, `"812 m"` / `"2665 ft"`.
    public static func elevation(meters input: Double, units: UnitSystem) -> String {
        let m = input.isFinite ? max(-1.0e9, min(input, 1.0e9)) : 0
        let v = units == .metric ? m : m * feetPerMeter
        let n = v >= 0 ? Int(floor(v + 0.5)) : -Int(floor(-v + 0.5))
        return "\(n) \(units == .metric ? "m" : "ft")"
    }

    /// Pasos con el separador de miles del idioma: es `1.234` · en `1,234`.
    public static func steps(_ n: Int, lang: AppLanguage) -> String {
        return Formatters.steps(n).replacingOccurrences(of: ".", with: lang.groupingSeparator)
    }

    /// Ritmo `"M:SS /km"` o `"M:SS /mi"`. `nil` si `< 100 m`, `< 60 s` en movimiento o `> 99:59`.
    public static func pace(distanceMeters: Double, movingSeconds: Double, units: UnitSystem) -> String? {
        guard hasData(distanceMeters: distanceMeters, movingSeconds: movingSeconds) else {
            return nil
        }
        let unitMeters = units == .metric ? 1000.0 : metersPerMile
        let raw = floor(movingSeconds / (distanceMeters / unitMeters) + 0.5)
        guard raw.isFinite, raw <= Double(99 * 60 + 59) else {
            return nil
        }
        let total = Int(raw)
        let seconds = total % 60
        return "\(total / 60):\(seconds < 10 ? "0" : "")\(seconds) /\(units == .metric ? "km" : "mi")"
    }

    /// Velocidad `"4,2 km/h"` / `"2.6 mph"`. `nil` si `< 100 m` o `< 60 s` en movimiento.
    public static func speed(
        distanceMeters: Double,
        movingSeconds: Double,
        units: UnitSystem,
        lang: AppLanguage
    ) -> String? {
        guard hasData(distanceMeters: distanceMeters, movingSeconds: movingSeconds) else {
            return nil
        }
        let factor = units == .metric ? kmhPerMetersPerSecond : mphPerMetersPerSecond
        let v = distanceMeters / movingSeconds * factor
        let rawTenths = floor(v * 10 + 0.5)
        guard rawTenths.isFinite, rawTenths < 1.0e12 else {
            return nil
        }
        let tenths = Int(rawTenths)
        return "\(tenths / 10)\(lang.decimalSeparator)\(tenths % 10) \(units == .metric ? "km/h" : "mph")"
    }

    /// Ritmo o velocidad según la preferencia.
    public static func paceOrSpeed(
        distanceMeters: Double,
        movingSeconds: Double,
        units: UnitSystem,
        mode: PaceMode,
        lang: AppLanguage
    ) -> String? {
        switch mode {
        case .pace:
            return pace(distanceMeters: distanceMeters, movingSeconds: movingSeconds, units: units)
        case .speed:
            return speed(distanceMeters: distanceMeters, movingSeconds: movingSeconds, units: units, lang: lang)
        }
    }

    private static func hasData(distanceMeters: Double, movingSeconds: Double) -> Bool {
        // Comparaciones positivas: NaN → sin datos.
        return distanceMeters >= 100 && movingSeconds >= 60 && distanceMeters.isFinite && movingSeconds.isFinite
    }
}
