import Foundation
import CaminoCore

/// Formato de todas las cifras de la app con las preferencias del usuario (V1.1 §G):
/// unidades (métrico / imperial), ritmo o velocidad e idioma (separadores).
///
/// Se apoya en `UnitFormatter` del núcleo (mismas reglas que Wear OS y `reference.py`).
/// Cada valor visible tiene su variante hablada para VoiceOver, derivada del MISMO texto
/// para que el número leído coincida con el mostrado.
struct UnitDisplay: Equatable {
    var units: UnitSystem
    var paceMode: PaceMode
    var lang: AppLanguage

    static let `default` = UnitDisplay(units: .metric, paceMode: .pace, lang: .es)

    // MARK: Distancia

    func distance(_ meters: Double) -> String {
        return UnitFormatter.distance(meters: meters, units: units, lang: lang)
    }

    func distance(_ meters: Int) -> String {
        return distance(Double(meters))
    }

    /// "4,2 kilómetros", "2.6 miles", "340 metros", "980 feet".
    func spokenDistance(_ meters: Double) -> String {
        return UnitDisplay.spokenUnits(distance(meters))
    }

    func spokenDistance(_ meters: Int) -> String {
        return spokenDistance(Double(meters))
    }

    // MARK: Altitud y desnivel

    func elevation(_ meters: Double) -> String {
        return UnitFormatter.elevation(meters: meters, units: units)
    }

    func elevation(_ meters: Int) -> String {
        return elevation(Double(meters))
    }

    func spokenElevation(_ meters: Double) -> String {
        return UnitDisplay.spokenUnits(elevation(meters))
    }

    func spokenElevation(_ meters: Int) -> String {
        return spokenElevation(Double(meters))
    }

    // MARK: Pasos y tiempo

    func steps(_ count: Int) -> String {
        return UnitFormatter.steps(count, lang: lang)
    }

    func spokenSteps(_ count: Int) -> String {
        return steps(count) + " " + L10n.spokenSteps
    }

    /// "1 h 05 min" (igual en ambos idiomas).
    func duration(seconds: Int) -> String {
        return Formatters.duration(seconds: seconds)
    }

    func duration(interval: TimeInterval) -> String {
        return Formatters.duration(interval: interval)
    }

    // MARK: Ritmo o velocidad

    /// Etiqueta de la cifra según la preferencia: "ritmo" / "velocidad".
    var paceOrSpeedLabel: String {
        return paceMode == .pace ? L10n.metricPace : L10n.metricSpeed
    }

    /// Etiqueta de la media del resumen: "ritmo medio" / "velocidad media".
    var averagePaceOrSpeedLabel: String {
        return paceMode == .pace ? L10n.metricPaceAverage : L10n.metricSpeedAverage
    }

    /// `nil` = sin datos (< 100 m o < 60 s en movimiento): la UI dice "sin datos", nunca 0.
    func paceOrSpeed(distanceMeters: Double, movingSeconds: Double) -> String? {
        return UnitFormatter.paceOrSpeed(
            distanceMeters: distanceMeters,
            movingSeconds: movingSeconds,
            units: units,
            mode: paceMode,
            lang: lang
        )
    }

    /// "12 minutos 30 segundos por kilómetro" / "4,2 kilómetros por hora".
    func spokenPaceOrSpeed(distanceMeters: Double, movingSeconds: Double) -> String? {
        guard let text = paceOrSpeed(distanceMeters: distanceMeters, movingSeconds: movingSeconds) else {
            return nil
        }
        return UnitDisplay.spokenPaceOrSpeed(text)
    }

    // MARK: - Variantes habladas

    /// Sustituye la unidad final abreviada por su nombre hablado.
    static func spokenUnits(_ text: String) -> String {
        let table: [(String, String)] = [
            (" km", L10n.spokenKilometers),
            (" mi", L10n.spokenMiles),
            (" ft", L10n.spokenFeet),
            (" m", L10n.spokenMeters)
        ]
        for (suffix, spoken) in table where text.hasSuffix(suffix) {
            return String(text.dropLast(suffix.count)) + " " + spoken
        }
        return text
    }

    static func spokenPaceOrSpeed(_ text: String) -> String {
        if text.hasSuffix(" km/h") {
            return String(text.dropLast(5)) + " " + L10n.spokenKmh
        }
        if text.hasSuffix(" mph") {
            return String(text.dropLast(4)) + " " + L10n.spokenMph
        }
        // Ritmo "M:SS /km" o "M:SS /mi".
        let parts = text.components(separatedBy: " /")
        guard parts.count == 2 else {
            return text
        }
        let clock = parts[0].components(separatedBy: ":")
        guard clock.count == 2, let minutes = Int(clock[0]), let seconds = Int(clock[1]) else {
            return text
        }
        var time = L10n.spokenMinutes(minutes)
        if seconds > 0 {
            time += " " + L10n.spokenSeconds(seconds)
        }
        let per = parts[1] == "mi" ? L10n.spokenPerMile : L10n.spokenPerKilometer
        return time + " " + per
    }
}
