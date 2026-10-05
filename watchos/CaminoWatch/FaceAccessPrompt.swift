import Foundation

/// Aviso de primer uso «Accede desde tu esfera» (V1.1 §I): estado persistido y reglas.
///
/// Estado (UserDefaults, clave `faceAccess.prompt`): `notDecided` → `dismissed` («Ahora no»)
/// o `helpOpened` («Cómo añadirlo»). Sólo las dos acciones lo cambian: si se cierra la app con
/// el aviso abierto sigue `notDecided` y se volverá a ofrecer en otro arranque.
///
/// Heurística de "tras la configuración inicial": la pantalla principal tiene que haberse
/// mostrado ya en un arranque ANTERIOR (`faceAccess.homeSeen`, que se marca al aparecer la
/// pantalla principal). Así el primer arranque completo (permisos, primer trayecto…) nunca
/// lo muestra. Además se aplaza si:
/// - hay trayecto activo,
/// - este arranque ha restaurado un trayecto (se espera a un arranque posterior sin trayecto),
/// - ya se mostró en este arranque.
/// El aviso nunca afirma que la complicación esté instalada (no hay API pública para saberlo).
final class FaceAccessPrompt {
    enum State: String {
        case notDecided
        case dismissed
        case helpOpened
    }

    static let stateKey = "faceAccess.prompt"
    static let homeSeenKey = "faceAccess.homeSeen"

    private let defaults: UserDefaults?
    /// Sin persistencia (escenarios DEMO): estado sólo en memoria.
    private var memoryState: State = .notDecided
    private var memoryHomeSeen = false
    /// La pantalla principal ya se había mostrado en un arranque anterior.
    private let homeSeenBeforeThisLaunch: Bool
    /// Este arranque restauró un trayecto en curso: no se muestra hasta otro arranque.
    private let restoredTripThisLaunch: Bool
    private var shownThisLaunch = false

    /// - Parameter defaults: `nil` → no se guarda nada (escenarios DEMO).
    init(defaults: UserDefaults?, restoredTripThisLaunch: Bool) {
        self.defaults = defaults
        self.restoredTripThisLaunch = restoredTripThisLaunch
        self.homeSeenBeforeThisLaunch = defaults?.bool(forKey: FaceAccessPrompt.homeSeenKey) ?? false
    }

    var state: State {
        guard let defaults = defaults else {
            return memoryState
        }
        return defaults.string(forKey: FaceAccessPrompt.stateKey).flatMap(State.init(rawValue:)) ?? .notDecided
    }

    /// La pantalla principal se ha mostrado (cuenta para el próximo arranque).
    func markHomeSeen() {
        if let defaults = defaults {
            defaults.set(true, forKey: FaceAccessPrompt.homeSeenKey)
        } else {
            memoryHomeSeen = true
        }
    }

    /// `true` si ahora toca mostrar el aviso. Si devuelve `true` se considera mostrado en este arranque.
    func shouldPresent(hasActiveTrip: Bool) -> Bool {
        guard state == .notDecided,
              !shownThisLaunch,
              homeSeenBeforeThisLaunch,
              !restoredTripThisLaunch,
              !hasActiveTrip else {
            return false
        }
        shownThisLaunch = true
        return true
    }

    /// Escenario DEMO `face-prompt`: forzar la hoja sin condiciones.
    func forcePresentation() {
        shownThisLaunch = true
    }

    func dismiss() {
        save(.dismissed)
    }

    func helpOpened() {
        save(.helpOpened)
    }

    private func save(_ value: State) {
        if let defaults = defaults {
            defaults.set(value.rawValue, forKey: FaceAccessPrompt.stateKey)
        } else {
            memoryState = value
        }
    }
}
