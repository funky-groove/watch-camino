import Foundation
import UserNotifications
import WatchKit

/// Avisos POI (§6): notificación local + háptica.
///
/// - El contenido sólo lleva categoría, nombre y distancia (nunca coordenadas).
/// - Un identificador por POI: si el sistema aún muestra un aviso del mismo POI, se sustituye
///   en lugar de duplicarse (además el núcleo avisa como máximo una vez por etapa).
/// - Con la app en primer plano no se muestra banner: la pantalla ya enseña el aviso y
///   suena la háptica; así no se duplica ni se roba el foco.
/// - Al tocar la notificación se abre la ficha del POI (`onOpenPoi`).
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let poiCategoryId = "camino.poi"
    static let poiIdKey = "poiId"

    /// Se llama en el hilo principal al tocar un aviso de POI.
    var onOpenPoi: ((String) -> Void)?

    private let center = UNUserNotificationCenter.current()

    override init() {
        super.init()
        center.delegate = self
        let category = UNNotificationCategory(
            identifier: Notifier.poiCategoryId,
            actions: [],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    /// Se llama al pulsar "Iniciar trayecto" (permiso en contexto, §11).
    /// `completion` (opcional) llega en el hilo principal cuando el usuario ha respondido.
    func requestPermissionIfNeeded(completion: (() -> Void)? = nil) {
        center.requestAuthorization(options: [.alert, .sound]) { _, error in
            if let error = error {
                Log.app.error("Notificaciones: error \(Log.describe(error), privacy: .public)")
            }
            if let completion = completion {
                DispatchQueue.main.async {
                    completion()
                }
            }
        }
    }

    /// Estado real del permiso de notificaciones. `completion` llega en el hilo principal.
    func currentPermission(completion: @escaping (LocationPermission) -> Void) {
        center.getNotificationSettings { settings in
            let status = settings.authorizationStatus
            let permission: LocationPermission
            if status == .notDetermined {
                permission = .notDetermined
            } else if status == .denied {
                permission = .denied
            } else {
                permission = .granted
            }
            DispatchQueue.main.async {
                completion(permission)
            }
        }
    }

    func notifyPoi(poiId: String, text: String) {
        let content = UNMutableNotificationContent()
        content.title = L10n.notificationPoiTitle
        content.body = text
        content.sound = UNNotificationSound.default
        content.categoryIdentifier = Notifier.poiCategoryId
        content.userInfo = [Notifier.poiIdKey: poiId]
        let request = UNNotificationRequest(identifier: "poi-\(poiId)", content: content, trigger: nil)
        center.add(request) { error in
            if let error = error {
                Log.app.error("Notificación POI: error \(Log.describe(error), privacy: .public)")
            }
        }
        WKInterfaceDevice.current().play(.notification)
    }

    // MARK: - UNUserNotificationCenterDelegate

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // En primer plano el aviso ya está en pantalla: sin banner duplicado.
        completionHandler([])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let info = response.notification.request.content.userInfo
        if response.actionIdentifier == UNNotificationDefaultActionIdentifier,
           let poiId = info[Notifier.poiIdKey] as? String {
            let handler = onOpenPoi
            DispatchQueue.main.async {
                handler?(poiId)
            }
        }
        completionHandler()
    }
}
