import Foundation
import CaminoCore

/// Variantes habladas de los valores (§10): VoiceOver lee "4,2 kilómetros restantes",
/// no "4,2 km". Se derivan de los mismos `Formatters` del núcleo para que el número
/// leído coincida exactamente con el mostrado.
enum Spoken {
    static func distance(meters: Double) -> String {
        let text = Formatters.distance(meters: meters)
        if text.hasSuffix(" km") {
            return String(text.dropLast(3)) + " " + L10n.spokenKilometers
        }
        if text.hasSuffix(" m") {
            return String(text.dropLast(2)) + " " + L10n.spokenMeters
        }
        return text
    }

    static func distance(meters: Int) -> String {
        return distance(meters: Double(meters))
    }

    static func duration(seconds input: Int) -> String {
        let seconds = max(0, input)
        let hours = seconds / 3600
        let minutes = (seconds % 3600) / 60
        if hours == 0 {
            return L10n.spokenMinutes(minutes)
        }
        return L10n.spokenHours(hours) + " " + L10n.spokenMinutes(minutes)
    }

    static func steps(_ count: Int) -> String {
        return Formatters.steps(count) + " " + L10n.spokenSteps
    }

    static func remaining(meters: Double) -> String {
        return distance(meters: meters) + " " + L10n.remaining
    }

    static func poiAlert(_ alert: PoiAlert) -> String {
        return alert.poi.name + ", " + distance(meters: alert.distanceMeters)
    }
}
