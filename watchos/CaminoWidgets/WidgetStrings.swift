import Foundation

/// Textos de la extensión de widgets. Base: español. Cada clave está en
/// `CaminoWidgets/es.lproj/Localizable.strings`; el valor por defecto es idéntico.
enum WidgetStrings {
    static func tr(_ key: String, _ value: String) -> String {
        return NSLocalizedString(key, tableName: nil, bundle: .main, value: value, comment: "")
    }

    static var appTitle: String { tr("widget.app", "Camino Seguro") }
    static var displayName: String { tr("widget.name", "Mi etapa") }
    static var description: String { tr("widget.description", "Distancia y tiempo de la etapa en curso.") }
    static var demo: String { tr("widget.demo", "DEMO") }
    static var demoA11y: String { tr("widget.demo.a11y", "Datos de demostración.") }
    static var unitKm: String { tr("widget.unit.km", "km") }
    static var noStage: String { tr("widget.nostage", "Sin etapa") }
    static var noStageLong: String { tr("widget.nostage.long", "Sin etapa en curso") }
    static var last: String { tr("widget.last", "Última") }
    static var openApp: String { tr("widget.open", "Abre Camino Seguro") }
    static var open: String { tr("widget.open.short", "Abrir") }
    static var noGps: String { tr("widget.nogps", "Sin GPS") }
    static var elapsedA11y: String { tr("widget.elapsed.a11y", "Tiempo") }

    /// "de 22 km"
    static func ofPlanned(_ planned: String) -> String {
        return String(format: tr("widget.of", "de %@"), planned)
    }

    /// "Etapa: 4,2 km de 22 km"
    static func progressA11y(walked: String, planned: String) -> String {
        return String(format: tr("widget.progress.a11y", "Etapa: %@ de %@"), walked, planned)
    }
}
