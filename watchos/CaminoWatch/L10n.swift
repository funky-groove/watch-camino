import Foundation

/// Textos de la app, centralizados (§10). Base: español.
///
/// Cada clave está en `es.lproj/Localizable.strings`; el valor por defecto de aquí es
/// idéntico y sólo se usa si la tabla no se encontrase, para que nunca se vea una clave.
enum L10n {
    private static func tr(_ key: String, _ value: String) -> String {
        return NSLocalizedString(key, tableName: nil, bundle: .main, value: value, comment: "")
    }

    private static func format(_ key: String, _ value: String, _ argument: Int) -> String {
        return String(format: tr(key, value), locale: Locale(identifier: "es_ES"), argument)
    }

    // MARK: General

    static var appTitle: String { tr("app.title", "Camino Seguro") }
    static var cancel: String { tr("common.cancel", "Cancelar") }
    static var done: String { tr("common.done", "Hecho") }
    static var demoBadge: String { tr("demo.badge", "DEMO") }
    static var demoAccessibility: String { tr("demo.a11y", "Modo demostración. Los datos no se envían a ningún servidor.") }

    // MARK: Inicio

    static var startStage: String { tr("home.start", "Comenzar etapa") }
    static var startStageHint: String { tr("home.start.hint", "Elige la etapa y confírmala para empezar.") }

    // MARK: Elegir etapa

    static var pickerTitle: String { tr("picker.title", "Elegir etapa") }
    static var pickerSuggested: String { tr("picker.suggested", "Sugerida") }
    static var pickerConfirmTitle: String { tr("picker.confirm.title", "¿Comenzar esta etapa?") }
    static var pickerConfirmStart: String { tr("picker.confirm.start", "Comenzar") }
    static var fixturesNotice: String {
        tr("picker.notice", "Datos de demostración con coordenadas aproximadas. No sirven para orientarse en el Camino.")
    }

    // MARK: Etapa activa

    static var activeTitle: String { tr("active.title", "Etapa") }
    static var remaining: String { tr("active.remaining", "restantes") }
    static var walked: String { tr("active.walked", "Recorrido") }
    static var steps: String { tr("active.steps", "Pasos") }
    static var time: String { tr("active.time", "Tiempo") }
    static var nextPoi: String { tr("active.nextPoi", "Próximo POI") }
    static var nextPoiSearching: String { tr("active.nextPoi.searching", "Buscando ubicación…") }
    static var nextPoiNone: String { tr("active.nextPoi.none", "No quedan POI en esta etapa") }
    static var lastAlert: String { tr("active.lastAlert", "Aviso") }
    static var finish: String { tr("active.finish", "Finalizar") }
    static var finishConfirmTitle: String { tr("active.finish.confirm.title", "¿Finalizar la etapa?") }
    static var finishConfirmMessage: String {
        tr("active.finish.confirm.message", "Se guardará el resumen. Una etapa finalizada no se puede reanudar.")
    }
    static var finishConfirmAction: String { tr("active.finish.confirm.action", "Finalizar etapa") }
    static var finishConfirmCancel: String { tr("active.finish.confirm.cancel", "Seguir caminando") }
    static var locationDenied: String {
        tr("active.locationDenied", "Sin permiso de ubicación: no se mide la distancia ni hay avisos de POI.")
    }
    static var stepsUnavailable: String {
        tr("active.stepsUnavailable", "Sin acceso al movimiento: no se cuentan los pasos.")
    }

    // MARK: Estadísticas

    static var statsTitle: String { tr("stats.title", "Estadísticas") }
    static var statsToday: String { tr("stats.today", "Hoy") }
    static var statsTodayEmpty: String { tr("stats.today.empty", "Aún no has hecho ninguna etapa.") }
    static var statsTotal: String { tr("stats.total", "Acumulado del Camino") }
    static var statsStages: String { tr("stats.stages", "Etapas") }
    static var statsDistance: String { tr("stats.distance", "Distancia") }

    // MARK: Resumen

    static var summaryTitle: String { tr("summary.title", "Etapa terminada") }
    static var summarySaved: String { tr("summary.saved", "Guardado · se sincronizará") }

    // MARK: Sincronización

    static var syncTitle: String { tr("sync.title", "Sincronización") }
    static var syncSynced: String { tr("sync.synced", "Sincronizado") }
    static var syncOffline: String { tr("sync.offline", "Sin conexión") }
    static var syncBlocked: String { tr("sync.blocked", "Pendiente de backend") }
    static var syncNeedsLink: String { tr("sync.needsLink", "Necesita vincular") }
    static var syncSyncing: String { tr("sync.syncing", "Sincronizando…") }
    static var syncNow: String { tr("sync.now", "Sincronizar ahora") }
    static var syncBlockedExplain: String {
        tr("sync.blocked.explain", "El servidor aún no está disponible. Tus etapas están guardadas en el reloj y no se pierden.")
    }
    static var syncNeedsLinkExplain: String {
        tr("sync.needsLink.explain", "Hace falta vincular el reloj con tu cuenta. Esta función aún no está disponible.")
    }
    static var syncDemoExplain: String { tr("sync.demo.explain", "Modo demostración: el envío es simulado.") }

    static func syncPending(_ count: Int) -> String {
        if count == 1 {
            return tr("sync.pending.one", "1 pendiente")
        }
        return format("sync.pending.many", "%d pendientes", count)
    }

    static func syncSavedEvents(_ count: Int) -> String {
        if count == 1 {
            return tr("sync.saved.one", "1 evento guardado en el reloj")
        }
        return format("sync.saved.many", "%d eventos guardados en el reloj", count)
    }

    static func syncDeadLetters(_ count: Int) -> String {
        if count == 1 {
            return tr("sync.deadLetters.one", "1 evento rechazado")
        }
        return format("sync.deadLetters.many", "%d eventos rechazados", count)
    }

    // MARK: Errores

    static var errorStart: String { tr("error.start", "No se pudo comenzar la etapa.") }
    static var errorFinish: String { tr("error.finish", "No se pudo finalizar la etapa.") }
    static var errorStorage: String { tr("error.storage", "No se pudo guardar en el reloj. Los datos siguen en memoria.") }

    // MARK: Notificaciones

    static var notificationPoiTitle: String { tr("notification.poi.title", "Punto de interés cerca") }

    // MARK: Accesibilidad (lo que lee VoiceOver)

    static var spokenKilometers: String { tr("a11y.unit.km", "kilómetros") }
    static var spokenMeters: String { tr("a11y.unit.m", "metros") }
    static var spokenSteps: String { tr("a11y.unit.steps", "pasos") }

    static func spokenHours(_ count: Int) -> String {
        if count == 1 {
            return tr("a11y.hours.one", "1 hora")
        }
        return format("a11y.hours.many", "%d horas", count)
    }

    static func spokenMinutes(_ count: Int) -> String {
        if count == 1 {
            return tr("a11y.minutes.one", "1 minuto")
        }
        return format("a11y.minutes.many", "%d minutos", count)
    }
}
