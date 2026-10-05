import Foundation
import CaminoCore

/// Destinos de navegación. Contrato compartido por todas las pantallas.
enum Route: Hashable {
    case pickStage
    case stats
    case statDetail(StatMetric)
    case nearby(waterOnly: Bool)
    case poi(id: String)
    case settings
    case sync
    /// Pantalla de emergencia (botón «SOS» de la cabecera). Se apila sobre la pantalla
    /// principal: al volver, esa pantalla sigue viva con su posición de desplazamiento.
    case sos
}

/// Métricas con ficha de detalle.
enum StatMetric: String, Hashable, CaseIterable {
    case distance
    case time
    case steps
}

extension DeepLink {
    /// Pila de navegación que abre este enlace, partiendo de "Mi etapa".
    var routes: [Route] {
        switch self {
        case .stage:
            return []
        case .stats:
            return [.stats]
        case .nearby(let waterOnly):
            return [.nearby(waterOnly: waterOnly)]
        case .poi(let id):
            return [.poi(id: id)]
        case .settings:
            return [.settings]
        }
    }
}
