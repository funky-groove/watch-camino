import Foundation

/// Formato de presentación es-ES — docs/WATCH_V1_SPEC.md §8.
///
/// Se implementa la regla a mano a propósito: NO usar `NumberFormatter` /
/// `MeasurementFormatter` (difieren entre plataformas y locales).
public enum Formatters {
    /// Distancia: `0 m`, `340 m`, `1,0 km`, `9,9 km`, `10 km`, `22 km`.
    public static func distance(meters input: Double) -> String {
        // Tope defensivo para que la conversión a Int nunca desborde.
        let m = (input.isFinite && input > 0) ? min(input, 1.0e12) : 0
        let rounded10 = Int(floor(m / 10.0 + 0.5)) * 10
        if rounded10 < 1000 {
            return "\(rounded10) m"
        }
        let tenths = Int(floor(m / 100.0 + 0.5))
        if tenths < 100 {
            return "\(tenths / 10),\(tenths % 10) km"
        }
        return "\(Int(floor(m / 1000.0 + 0.5))) km"
    }

    public static func distance(meters: Int) -> String {
        return distance(meters: Double(meters))
    }

    /// Duración: `0 min`, `45 min`, `1 h 05 min`.
    public static func duration(seconds input: Int) -> String {
        let s = max(0, input)
        if s < 3600 {
            return "\(s / 60) min"
        }
        let hours = s / 3600
        let minutes = (s % 3600) / 60
        return "\(hours) h \(twoDigits(minutes)) min"
    }

    /// Duración desde un `TimeInterval` (se trunca a segundos enteros).
    public static func duration(interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else {
            return duration(seconds: 0)
        }
        let capped = min(interval, Double(Int32.max))
        return duration(seconds: Int(capped.rounded(.down)))
    }

    /// Pasos con separador de miles `.`: `999`, `1.234`, `25.000`.
    public static func steps(_ input: Int) -> String {
        let n = max(0, input)
        let digits = Array(String(n))
        var out = ""
        for (index, digit) in digits.enumerated() {
            let remaining = digits.count - index
            if index > 0 && remaining % 3 == 0 {
                out.append(".")
            }
            out.append(digit)
        }
        return out
    }

    /// Texto del aviso POI: `"<icono> <nombre> · <distancia>"`.
    public static func poiAlertText(_ alert: PoiAlert) -> String {
        return "\(alert.poi.category.icon) \(alert.poi.name) · \(distance(meters: alert.distanceMeters))"
    }

    private static func twoDigits(_ value: Int) -> String {
        return value < 10 ? "0\(value)" : "\(value)"
    }
}
