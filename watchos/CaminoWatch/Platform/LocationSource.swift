import Foundation
import CoreLocation
import CaminoCore

enum LocationPermission: Equatable {
    case notDetermined
    case denied
    case granted
}

/// Fuente de posiciones GPS (§12): precisión ~10 m, `distanceFilter` 20 m,
/// intervalo mínimo 10 s, ubicación en segundo plano sólo con sesión activa.
///
/// Se crea en el hilo principal, así que CoreLocation entrega los callbacks del
/// delegado en el hilo principal.
final class LocationSource: NSObject, CLLocationManagerDelegate {
    static let minimumInterval: TimeInterval = 10

    /// Fix nuevo (ya filtrado por validez e intervalo mínimo).
    var onFix: ((LocationFix) -> Void)?
    /// Cambio de permiso.
    var onPermissionChange: ((LocationPermission) -> Void)?

    private let manager: CLLocationManager
    private var isRunning = false
    private var lastDelivered: Date?

    override init() {
        manager = CLLocationManager()
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
        manager.distanceFilter = 20
    }

    var permission: LocationPermission {
        return LocationSource.map(manager.authorizationStatus)
    }

    /// Se llama al pulsar "Comenzar etapa" (permiso en contexto, §11).
    func requestPermissionIfNeeded() {
        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
    }

    /// Empieza a recibir posiciones. Si aún no hay permiso, empezará al concederse.
    func start() {
        guard !isRunning else {
            return
        }
        isRunning = true
        lastDelivered = nil
        if permission == .granted {
            beginUpdates()
        }
        Log.sensors.info("Ubicación: inicio solicitado")
    }

    func stop() {
        guard isRunning else {
            return
        }
        isRunning = false
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        Log.sensors.info("Ubicación: parada")
    }

    private func beginUpdates() {
        // Requiere UIBackgroundModes = [location] en Info.plist (lo genera project.yml).
        manager.allowsBackgroundLocationUpdates = true
        manager.startUpdatingLocation()
    }

    // MARK: - CLLocationManagerDelegate

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let current = permission
        onPermissionChange?(current)
        if isRunning && current == .granted {
            beginUpdates()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard isRunning else {
            return
        }
        for location in locations {
            // Precisión negativa = posición inválida.
            guard location.horizontalAccuracy >= 0 else {
                continue
            }
            if let last = lastDelivered,
               location.timestamp.timeIntervalSince(last) < LocationSource.minimumInterval {
                continue
            }
            lastDelivered = location.timestamp
            let fix = LocationFix(
                point: GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude),
                accuracyMeters: location.horizontalAccuracy,
                timestamp: location.timestamp
            )
            onFix?(fix)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Log.sensors.error("Ubicación: error \(Log.describe(error), privacy: .public)")
    }

    // MARK: - Privado

    private static func map(_ status: CLAuthorizationStatus) -> LocationPermission {
        switch status {
        case .notDetermined:
            return .notDetermined
        case .restricted, .denied:
            return .denied
        case .authorizedAlways, .authorizedWhenInUse:
            return .granted
        @unknown default:
            return .denied
        }
    }
}
