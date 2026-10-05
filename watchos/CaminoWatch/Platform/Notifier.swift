import Foundation
import UserNotifications
import WatchKit

/// Avisos POI (§6): notificación local + háptica. El texto en pantalla lo pinta la UI.
/// El contenido de la notificación sólo lleva icono, nombre y distancia (nunca coordenadas).
final class Notifier {
    private let center = UNUserNotificationCenter.current()

    /// Se llama al pulsar "Comenzar etapa" (permiso en contexto, §11).
    func requestPermissionIfNeeded() {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error {
                Log.app.error("Notificaciones: error \(Log.describe(error), privacy: .public)")
            }
        }
    }

    func notifyPoi(poiId: String, text: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.notificationPoiTitle
        content.body = text
        content.sound = UNNotificationSound.default
        let request = UNNotificationRequest(identifier: "poi-\(poiId)", content: content, trigger: nil)
        center.add(request) { error in
            if let error = error {
                Log.app.error("Notificación POI: error \(Log.describe(error), privacy: .public)")
            }
        }
        WKInterfaceDevice.current().play(.notification)
    }
}
