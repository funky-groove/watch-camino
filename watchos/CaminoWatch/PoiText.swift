import Foundation
import CaminoCore

/// Textos de POI sin emoji: VoiceOver lee la categoría, no "gota" o "cruz".
enum PoiText {
    static func category(_ category: PoiCategory) -> String {
        switch category {
        case .water:
            return L10n.categoryWater
        case .shelter:
            return L10n.categoryShelter
        case .pharmacy:
            return L10n.categoryPharmacy
        case .health:
            return L10n.categoryHealth
        case .food:
            return L10n.categoryFood
        case .landmark:
            return L10n.categoryLandmark
        }
    }

    /// "Agua · Fuente de Barbadelo · 300 m" (texto de la notificación).
    static func alertText(_ alert: PoiAlert) -> String {
        return category(alert.poi.category) + " · " + alert.poi.name + " · "
            + Formatters.distance(meters: alert.distanceMeters)
    }

    /// Distancia, marcada como aproximada si la ubicación lo es ("≈ 340 m").
    static func distance(_ meters: Double, approximate: Bool) -> String {
        let text = Formatters.distance(meters: meters)
        return approximate ? "≈ " + text : text
    }

    static func spokenDistance(_ meters: Double, approximate: Bool) -> String {
        let text = Spoken.distance(meters: meters)
        return approximate ? L10n.spokenApproximately + " " + text : text
    }
}
