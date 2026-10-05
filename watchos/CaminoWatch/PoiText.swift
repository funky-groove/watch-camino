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
    static func alertText(_ alert: PoiAlert, _ display: UnitDisplay) -> String {
        return category(alert.poi.category) + " · " + alert.poi.name + " · "
            + display.distance(alert.distanceMeters)
    }

    /// Distancia, marcada como aproximada si la ubicación lo es ("≈ 340 m").
    static func distance(_ meters: Double, approximate: Bool, _ display: UnitDisplay) -> String {
        let text = display.distance(meters)
        return approximate ? "≈ " + text : text
    }

    static func spokenDistance(_ meters: Double, approximate: Bool, _ display: UnitDisplay) -> String {
        let text = display.spokenDistance(meters)
        return approximate ? L10n.spokenApproximately + " " + text : text
    }

    /// "340 m en línea recta": no hay rutas, la distancia es geométrica (V1.1 §B-D, §J).
    static func straightLine(_ meters: Double, approximate: Bool, _ display: UnitDisplay) -> String {
        return L10n.placesStraightLine(distance(meters, approximate: approximate, display))
    }

    static func spokenStraightLine(_ meters: Double, approximate: Bool, _ display: UnitDisplay) -> String {
        return L10n.placesStraightLine(spokenDistance(meters, approximate: approximate, display))
    }
}
