import Foundation

/// Textos de la extensión de widgets. Base: español. Cada clave está en
/// `CaminoWidgets/es.lproj/Localizable.strings`; el valor por defecto es idéntico.
enum WidgetStrings {
    static func tr(_ key: String, _ value: String) -> String {
        return NSLocalizedString(key, tableName: nil, bundle: .main, value: value, comment: "")
    }

    static var appTitle: String { tr("widget.app", "Camino Seguro") }
    static var displayName: String { tr("widget.name", "Trayecto") }
    static var description: String { tr("widget.description", "Distancia y estado del trayecto en curso. Tocar abre la app.") }
    static var demo: String { tr("widget.demo", "DEMO") }
    static var demoA11y: String { tr("widget.demo.a11y", "Datos de demostración.") }
    static var unitKm: String { tr("widget.unit.km", "km") }
    static var noStage: String { tr("widget.nostage", "Sin etapa") }
    static var noStageLong: String { tr("widget.nostage.long", "Sin etapa en curso") }
    static var last: String { tr("widget.last", "Última") }
    static var openApp: String { tr("widget.open", "Abre Camino Seguro") }
    static var open: String { tr("widget.open.short", "Abrir") }
    static var noGps: String { tr("widget.nogps", "Sin GPS") }
    /// Rótulo corto bajo el icono en la complicación circular sin fix.
    static var gpsShort: String { tr("widget.gps.short", "GPS") }
    static var elapsedA11y: String { tr("widget.elapsed.a11y", "Tiempo") }
    // V1.1 §H
    static var start: String { tr("widget.start", "Iniciar trayecto") }
    static var startShort: String { tr("widget.start.short", "Iniciar") }
    static var running: String { tr("widget.running", "en marcha") }
    static var paused: String { tr("widget.paused", "pausado") }

    /// "hace 20 min": datos antiguos, sin prometer frescura.
    static func ago(_ minutes: Int) -> String {
        return String(format: tr("widget.ago", "hace %ld min"), minutes)
    }

    /// "Datos de hace 20 minutos."
    static func staleA11y(_ minutes: Int) -> String {
        return String(format: tr("widget.stale.a11y", "Datos de hace %ld minutos."), minutes)
    }

    /// "de 22 km"
    static func ofPlanned(_ planned: String) -> String {
        return String(format: tr("widget.of", "de %@"), planned)
    }

    /// "Etapa: 4,2 km de 22 km"
    static func progressA11y(walked: String, planned: String) -> String {
        return String(format: tr("widget.progress.a11y", "Etapa: %@ de %@"), walked, planned)
    }
}
