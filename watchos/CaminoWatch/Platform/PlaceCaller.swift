import Foundation
import WatchKit

/// «Llamar» de la ficha de un lugar (V1.1 §J). Mismo mecanismo que `SystemEmergencyDialer`
/// (`WKApplication.shared().openSystemURL`, el sistema pide confirmación), pero NO es una
/// llamada de emergencia: no usa el número 112 ni el flujo SOS.
///
/// La API no devuelve resultado: la app no sabe si la llamada se hizo, así que no muestra
/// ningún mensaje de éxito.
enum PlaceCaller {
    @MainActor
    static func open(_ url: URL) {
        guard url.scheme?.lowercased() == "tel" else {
            Log.app.error("Llamada a lugar: URL no válida")
            return
        }
        WKApplication.shared().openSystemURL(url)
        Log.app.info("Llamada a lugar entregada al sistema")
    }
}
