import Foundation
import CaminoCore

/// Variantes habladas de los valores (§10): VoiceOver lee "4,2 kilómetros restantes",
/// no "4,2 km". Las cifras con unidades se derivan de `UnitDisplay` (preferencias del
/// usuario) para que el número leído coincida exactamente con el mostrado.
enum Spoken {
    static func distance(meters: Double, _ display: UnitDisplay) -> String {
        return display.spokenDistance(meters)
    }

    static func distance(meters: Int, _ display: UnitDisplay) -> String {
        return display.spokenDistance(meters)
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

    static func duration(interval: TimeInterval) -> String {
        guard interval.isFinite, interval > 0 else {
            return duration(seconds: 0)
        }
        return duration(seconds: Int(min(interval, Double(Int32.max)).rounded(.down)))
    }

    static func steps(_ count: Int, _ display: UnitDisplay) -> String {
        return display.spokenSteps(count)
    }

    static func remaining(meters: Double, _ display: UnitDisplay) -> String {
        return display.spokenDistance(meters) + " " + L10n.remaining
    }

    static func poiAlert(_ alert: PoiAlert, _ display: UnitDisplay) -> String {
        return alert.poi.name + ", " + display.spokenDistance(alert.distanceMeters)
    }
}
