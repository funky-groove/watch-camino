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
    /// Lectura única pendiente (pantalla "Cerca" sin etapa en curso).
    private var oneShotPending = false
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

    /// Pide UNA posición (sin seguimiento continuo). Si ya hay seguimiento, no hace nada:
    /// la siguiente posición llegará por `onFix`.
    func requestOnce() {
        guard !isRunning else {
            return
        }
        guard permission == .granted else {
            oneShotPending = true
            return
        }
        oneShotPending = true
        manager.requestLocation()
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
        } else if oneShotPending && current == .granted {
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        if !isRunning {
            // Respuesta a `requestOnce`: se entrega la más reciente y se termina.
            guard oneShotPending, let location = locations.last, location.horizontalAccuracy >= 0 else {
                return
            }
            oneShotPending = false
            onFix?(LocationSource.makeFix(location))
            return
        }
        for location in locations {
            // Precisión negativa = posición inválida.
            guard location.horizontalAccuracy >= 0 else {
                continue
            }
            // Si el reloj ha ido hacia atrás (intervalo negativo) no se descarta: se entrega
            // y se reinicia la referencia; si no, se perderían fixes hasta alcanzarla (V-06).
            if let last = lastDelivered {
                let interval = location.timestamp.timeIntervalSince(last)
                if interval >= 0 && interval < LocationSource.minimumInterval {
                    continue
                }
            }
            lastDelivered = location.timestamp
            onFix?(LocationSource.makeFix(location))
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        oneShotPending = false
        Log.sensors.error("Ubicación: error \(Log.describe(error), privacy: .public)")
    }

    // MARK: - Privado

    private static func makeFix(_ location: CLLocation) -> LocationFix {
        return LocationFix(
            point: GeoPoint(lat: location.coordinate.latitude, lon: location.coordinate.longitude),
            accuracyMeters: location.horizontalAccuracy,
            timestamp: location.timestamp
        )
    }

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
