import Foundation
import WatchKit
import CaminoCore

/// Entrega la llamada al sistema con `WKApplication.shared().openSystemURL(_:)` (watchOS 7+,
/// no deprecado; `WKExtension.openSystemURL` lo está desde watchOS 9.2).
///
/// Lo documentado (docs/accessibility/SOS_FEASIBILITY.md §1): la URL `tel:` se envía a la
/// app del sistema, que pide confirmación al usuario antes de llamar. La API no devuelve
/// nada: la app sólo sabe que entregó la petición (`.handedToSystem`), nunca si la llamada
/// se conectó. Por eso no hay confirmación propia, cuenta atrás ni pulsación prolongada.
///
/// Escenarios DEMO, capturas y tests usan `MockEmergencyDialer` (no abre nada).
final class SystemEmergencyDialer: EmergencyDialer {
    func requestCall(number: EmergencyNumber) -> DialResult {
        guard let url = number.telURL else {
            Log.app.error("SOS: número de emergencia no válido")
            return .failed(.invalidURL)
        }
        // La API del sistema es de hilo principal; la vista SOS siempre llama desde él.
        guard Thread.isMainThread else {
            Log.app.error("SOS: petición fuera del hilo principal")
            return .failed(.notMainThread)
        }
        MainActor.assumeIsolated {
            WKApplication.shared().openSystemURL(url)
        }
        Log.app.info("SOS: llamada entregada al sistema")
        return .handedToSystem
    }
}
