import Foundation
import CoreMotion

/// Pasos acumulados desde `startedAt` con `CMPedometer.startUpdates(from:)` (§4).
/// Re-consultable tras relanzar: al restaurar se vuelve a pedir desde el mismo
/// `startedAt` y CoreMotion devuelve el acumulado completo.
///
/// Los callbacks de CoreMotion llegan en una cola interna: quien consume
/// `onSteps` / `onUnavailable` debe saltar al hilo principal.
final class StepSource {
    var onSteps: ((Int) -> Void)?
    /// Sin podómetro o permiso de movimiento denegado.
    var onUnavailable: (() -> Void)?

    private let pedometer = CMPedometer()
    private var isRunning = false

    static var isAvailable: Bool {
        return CMPedometer.isStepCountingAvailable()
    }

    static var isDenied: Bool {
        let status = CMPedometer.authorizationStatus()
        return status == .denied || status == .restricted
    }

    /// La primera llamada dispara la petición de permiso de movimiento del sistema.
    func start(from startedAt: Date) {
        stop()
        guard StepSource.isAvailable, !StepSource.isDenied else {
            onUnavailable?()
            return
        }
        isRunning = true
        let unavailable = onUnavailable
        let deliver = onSteps
        pedometer.startUpdates(from: startedAt) { data, error in
            if let error = error {
                Log.sensors.error("Podómetro: error \(Log.describe(error), privacy: .public)")
                unavailable?()
                return
            }
            guard let data = data else {
                return
            }
            deliver?(data.numberOfSteps.intValue)
        }
        Log.sensors.info("Podómetro: inicio")
    }

    func stop() {
        guard isRunning else {
            return
        }
        isRunning = false
        pedometer.stopUpdates()
        Log.sensors.info("Podómetro: parada")
    }
}
