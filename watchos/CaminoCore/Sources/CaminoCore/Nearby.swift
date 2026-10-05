import Foundation

/// Calidad de la última ubicación conocida, para mostrar distancias con honestidad
/// (precisión y antigüedad coherentes con la ubicación disponible).
public enum LocationQuality: Equatable, Sendable {
    /// Sin ninguna posición todavía.
    case none
    /// Posición reciente y con precisión suficiente (≤ 50 m, §5).
    case good(accuracyMeters: Double, ageSeconds: Int)
    /// Posición con precisión peor que 50 m: las distancias son aproximadas.
    case imprecise(accuracyMeters: Double, ageSeconds: Int)
    /// Posición antigua (> `staleAfterSeconds`): las distancias pueden haber cambiado.
    case stale(accuracyMeters: Double, ageSeconds: Int)

    /// A partir de cuántos segundos una posición se considera antigua.
    public static let staleAfterSeconds = 300

    public static func of(_ fix: LocationFix?, now: Date) -> LocationQuality {
        guard let fix = fix else {
            return .none
        }
        let rawAge = now.timeIntervalSince(fix.timestamp)
        let age = rawAge.isFinite ? max(0, Int(rawAge.rounded(.down))) : 0
        if age > staleAfterSeconds {
            return .stale(accuracyMeters: fix.accuracyMeters, ageSeconds: age)
        }
        if fix.accuracyMeters > DistanceAccumulator.maxAccuracyMeters {
            return .imprecise(accuracyMeters: fix.accuracyMeters, ageSeconds: age)
        }
        return .good(accuracyMeters: fix.accuracyMeters, ageSeconds: age)
    }

    /// Si las distancias calculadas con esta posición deben presentarse como aproximadas.
    public var isApproximate: Bool {
        switch self {
        case .good:
            return false
        case .none, .imprecise, .stale:
            return true
        }
    }
}

/// Lista "Cerca": POIs ordenados por distancia a una posición.
public enum Nearby {
    /// POIs de `categories` ordenados por distancia (empate → menor id), como máximo `limit`.
    public static func list(
        pois: [Poi],
        from position: GeoPoint,
        categories: Set<PoiCategory>,
        limit: Int = 20
    ) -> [PoiAlert] {
        let items = pois
            .filter { categories.contains($0.category) }
            .map { PoiAlert(poi: $0, distanceMeters: Geo.haversine(position, $0.location)) }
            .sorted(by: PoiEngine.isCloser)
        return Array(items.prefix(max(0, limit)))
    }
}
