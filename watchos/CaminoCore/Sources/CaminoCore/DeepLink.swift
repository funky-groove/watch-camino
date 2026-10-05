import Foundation

/// Enlaces directos `caminoseguro://…` desde complicaciones, widgets y notificaciones.
///
/// Seguridad: sólo se acepta el esquema propio, rutas conocidas y un identificador de POI
/// con juego de caracteres y longitud acotados. Cualquier otra cosa se descarta (`nil`);
/// un enlace nunca ejecuta acciones (no empieza ni termina etapas), sólo abre pantallas.
public enum DeepLink: Equatable, Sendable {
    /// Mi etapa (pantalla inicial).
    case stage
    /// Estadísticas.
    case stats
    /// Lista "Cerca"; `waterOnly` abre filtrada por agua.
    case nearby(waterOnly: Bool)
    /// Ficha de un POI.
    case poi(id: String)
    /// Ajustes.
    case settings

    public static let scheme = "caminoseguro"

    public static func parse(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == scheme else {
            return nil
        }
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return nil
        }
        // caminoseguro://nearby?c=water → host "nearby".
        let host = (components.host ?? "").lowercased()
        let query = components.queryItems ?? []
        switch host {
        case "stage", "":
            return .stage
        case "stats":
            return .stats
        case "nearby":
            let category = query.first(where: { $0.name == "c" })?.value
            return .nearby(waterOnly: category == "water")
        case "poi":
            guard let id = query.first(where: { $0.name == "id" })?.value, isValidId(id) else {
                return nil
            }
            return .poi(id: id)
        case "settings":
            return .settings
        default:
            return nil
        }
    }

    public var url: URL {
        let text: String
        switch self {
        case .stage:
            text = "stage"
        case .stats:
            text = "stats"
        case .nearby(let waterOnly):
            text = waterOnly ? "nearby?c=water" : "nearby"
        case .poi(let id):
            text = "poi?id=" + id
        case .settings:
            text = "settings"
        }
        // Los ids válidos sólo contienen [A-Za-z0-9_-]: la URL siempre es construible.
        return URL(string: DeepLink.scheme + "://" + text) ?? URL(string: DeepLink.scheme + "://stage")!
    }

    static func isValidId(_ id: String) -> Bool {
        guard !id.isEmpty, id.count <= 64 else {
            return false
        }
        return id.unicodeScalars.allSatisfy { scalar in
            switch scalar {
            case "a"..."z", "A"..."Z", "0"..."9", "-", "_":
                return true
            default:
                return false
            }
        }
    }
}
