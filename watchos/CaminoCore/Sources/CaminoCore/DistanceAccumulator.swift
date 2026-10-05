import Foundation

/// Qué hizo el acumulador con un fix (útil para tests y para logs sin coordenadas).
public enum DistanceStepOutcome: Equatable, Sendable {
    /// Paso 1: precisión > 50 m. No cambia nada.
    case rejectedAccuracy
    /// Paso 2: primer fix válido; se ancla `lastFix`.
    case anchored
    /// Paso 4: desplazamiento menor que el ruido; `lastFix` NO cambia.
    case rejectedNoise
    /// Paso 5: salto, vehículo o dt <= 0; se re-ancla `lastFix` sin sumar.
    case reanchored
    /// Paso 6: se suman estos metros.
    case added(Double)

    /// `true` si `lastFix` cambió.
    public var movedAnchor: Bool {
        switch self {
        case .anchored, .reanchored, .added:
            return true
        case .rejectedAccuracy, .rejectedNoise:
            return false
        }
    }
}

/// Acumulador de distancia por GPS — docs/WATCH_V1_SPEC.md §5.
public struct DistanceAccumulator: Equatable, Sendable {
    public static let maxAccuracyMeters: Double = 50.0
    public static let minStepMeters: Double = 10.0
    public static let maxSpeedMetersPerSecond: Double = 4.0

    public var distanceMeters: Double
    public var lastFix: LocationFix?

    public init(distanceMeters: Double = 0, lastFix: LocationFix? = nil) {
        self.distanceMeters = distanceMeters
        self.lastFix = lastFix
    }

    /// Paso 1 de §5 (también filtra el motor POI, §6).
    public static func isAccurateEnough(_ fix: LocationFix) -> Bool {
        // NaN compara como falso → se descarta.
        return fix.accuracyMeters <= maxAccuracyMeters
    }

    @discardableResult
    public mutating func add(_ fix: LocationFix) -> DistanceStepOutcome {
        // 1. Precisión insuficiente.
        guard DistanceAccumulator.isAccurateEnough(fix) else {
            return .rejectedAccuracy
        }
        // 2. Primer fix.
        guard let last = lastFix else {
            lastFix = fix
            return .anchored
        }
        // 3.
        let d = Geo.haversine(last.point, fix.point)
        let dt = fix.timestamp.timeIntervalSince(last.timestamp)
        // 4. Ruido.
        if d < max(DistanceAccumulator.minStepMeters, fix.accuracyMeters) {
            return .rejectedNoise
        }
        // 5. Salto / vehículo.
        if dt <= 0 || d / dt > DistanceAccumulator.maxSpeedMetersPerSecond {
            lastFix = fix
            return .reanchored
        }
        // 6. Suma.
        distanceMeters += d
        lastFix = fix
        return .added(d)
    }
}
