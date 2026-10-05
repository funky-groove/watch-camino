import Foundation

/// Aviso de POI: el POI y su distancia al fix que lo disparó.
public struct PoiAlert: Equatable, Sendable {
    public let poi: Poi
    public let distanceMeters: Double

    public init(poi: Poi, distanceMeters: Double) {
        self.poi = poi
        self.distanceMeters = distanceMeters
    }
}

/// Motor de avisos POI — docs/WATCH_V1_SPEC.md §6.
public enum PoiEngine {
    public static let radiusMeters: Double = 300.0
    public static let minIntervalSeconds: Double = 60.0

    /// Devuelve el POI a avisar, o `nil`.
    /// - Parameters:
    ///   - pois: POIs de la etapa activa.
    ///   - alerted: `alertedPoiIds` de la sesión.
    ///   - lastAlertAt: instante del último aviso.
    ///   - now: instante de evaluación: hora del reloj del sistema al procesar el fix (§6).
    ///   - position: posición del fix.
    ///   - accuracyMeters: precisión del fix (si > 50 m, el fix no pasa el paso 1 de §5).
    public static func evaluate(
        pois: [Poi],
        alerted: Set<String>,
        lastAlertAt: Date?,
        now: Date,
        position: GeoPoint,
        accuracyMeters: Double
    ) -> PoiAlert? {
        guard accuracyMeters <= DistanceAccumulator.maxAccuracyMeters else {
            return nil
        }
        // 1. Candidatos.
        var candidates: [PoiAlert] = []
        for poi in pois where !alerted.contains(poi.id) {
            let d = Geo.haversine(position, poi.location)
            if d <= radiusMeters {
                candidates.append(PoiAlert(poi: poi, distanceMeters: d))
            }
        }
        // 2.
        if candidates.isEmpty {
            return nil
        }
        // 3. Límite de ritmo: sólo bloquea si 0 ≤ now − lastAlertAt < 60 s. Si el reloj ha
        //    ido hacia atrás (intervalo negativo) no se bloquea: el intervalo no es fiable.
        if let last = lastAlertAt {
            let interval = now.timeIntervalSince(last)
            if interval >= 0 && interval < minIntervalSeconds {
                return nil
            }
        }
        // 4. El más cercano; empate → menor id.
        return candidates.min(by: isCloser)
    }

    /// POI no avisado más cercano (sin límite de radio), para la línea "Próximo POI" (§10).
    public static func nearestPending(pois: [Poi], alerted: Set<String>, position: GeoPoint) -> PoiAlert? {
        var best: PoiAlert?
        for poi in pois where !alerted.contains(poi.id) {
            let candidate = PoiAlert(poi: poi, distanceMeters: Geo.haversine(position, poi.location))
            if let current = best {
                if isCloser(candidate, current) {
                    best = candidate
                }
            } else {
                best = candidate
            }
        }
        return best
    }

    static func isCloser(_ a: PoiAlert, _ b: PoiAlert) -> Bool {
        if a.distanceMeters != b.distanceMeters {
            return a.distanceMeters < b.distanceMeters
        }
        return a.poi.id < b.poi.id
    }
}
