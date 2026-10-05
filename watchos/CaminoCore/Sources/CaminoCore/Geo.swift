import Foundation

/// Geometría — docs/WATCH_V1_SPEC.md §5.
public enum Geo {
    /// Radio terrestre medio (m). Fijado por la spec para que ambas plataformas coincidan.
    public static let earthRadiusMeters: Double = 6_371_008.8

    /// Distancia de círculo máximo entre dos puntos, en metros.
    public static func haversine(_ a: GeoPoint, _ b: GeoPoint) -> Double {
        let degToRad = Double.pi / 180.0
        let phi1 = a.lat * degToRad
        let phi2 = b.lat * degToRad
        let dPhi = phi2 - phi1
        let dLambda = (b.lon - a.lon) * degToRad
        let sinDPhi = sin(dPhi / 2.0)
        let sinDLambda = sin(dLambda / 2.0)
        let h = sinDPhi * sinDPhi + cos(phi1) * cos(phi2) * sinDLambda * sinDLambda
        return 2.0 * earthRadiusMeters * asin(min(1.0, h.squareRoot()))
    }
}
