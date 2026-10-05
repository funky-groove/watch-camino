import Foundation
import CaminoCore

/// Destinos de navegación. Contrato compartido por todas las pantallas.
enum Route: Hashable {
    case pickStage
    case stats
    case statDetail(StatMetric)
    /// Destino «Lugares» (V1.1 §A, §J). `waterOnly` abre con el filtro de agua.
    case nearby(waterOnly: Bool)
    case poi(id: String)
    case settings
    case sync
    /// Perfil de altitud registrado, ampliado (V1.1 §B-C).
    case profile
    /// Instrucciones para añadir la complicación a la esfera (V1.1 §I).
    case watchFaceHelp
    /// Pantalla de emergencia (botón «SOS» de la cabecera). Se apila sobre la pantalla
    /// principal: al volver, esa pantalla sigue viva con su posición de desplazamiento.
    case sos
}

/// Filtro mínimo de «Lugares» (V1.1 §J).
enum PlaceFilter: String, Hashable, CaseIterable {
    case all
    case water
    case shelter

    var categories: Set<PoiCategory> {
        switch self {
        case .all:
            return Set(PoiCategory.allCases)
        case .water:
            return [.water]
        case .shelter:
            return [.shelter]
        }
    }
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
