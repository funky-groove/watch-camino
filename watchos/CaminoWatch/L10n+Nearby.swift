import Foundation

// Textos de "Cerca", ficha de lugar, ajustes y sincronización (bloque UI-B).
// Claves con prefijo nearby. / poi. / settings. / sync2. para no chocar con L10n.swift.
// Títulos en minúsculas por contenido; las etiquetas de sección se ponen en mayúsculas
// con `SectionLabel` (textCase), no aquí.

extension L10n {
    // MARK: Cerca

    static var nearbyTitleWater: String { tr("nearby.title.water", "agua cerca") }
    static var nearbyTitleAll: String { tr("nearby.title.all", "cerca") }
    static var nearbySeeAll: String { tr("nearby.seeAll", "ver todo") }
    static var nearbyRetry: String { tr("nearby.retry", "buscar de nuevo") }
    static var nearbyNoLocation: String {
        tr("nearby.noLocation", "sin ubicación: no se pueden calcular distancias.")
    }
    static var nearbyNoLocationDenied: String {
        tr("nearby.noLocation.denied", "sin permiso de ubicación no se pueden calcular distancias.")
    }
    static var nearbyEmptyWaterStage: String {
        tr("nearby.empty.water.stage", "no hay puntos de agua en los datos de esta etapa")
    }
    static var nearbyEmptyAllStage: String {
        tr("nearby.empty.all.stage", "no hay lugares en los datos de esta etapa")
    }
    static var nearbyEmptyWaterAny: String {
        tr("nearby.empty.water.any", "no hay puntos de agua en los datos disponibles")
    }
    static var nearbyEmptyAllAny: String {
        tr("nearby.empty.all.any", "no hay lugares en los datos disponibles")
    }
    static var nearbyDemoNote: String {
        tr("nearby.demoNote", "datos de demostración · coordenadas aproximadas")
    }

    // Calidad de la ubicación (cabecera de "Cerca" y ficha).

    static var nearbyLocationSearching: String { tr("nearby.location.searching", "buscando ubicación…") }
    static var nearbyLocationDenied: String {
        tr("nearby.location.denied", "permiso de ubicación denegado — actívalo en Ajustes del reloj")
    }
    static var nearbyLocationStale: String { tr("nearby.location.stale", "ubicación antigua") }

    static func nearbyLocationAccuracy(_ meters: Int) -> String {
        return format("nearby.location.accuracy", "ubicación ±%ld m", meters)
    }

    static func nearbyLocationImprecise(_ meters: Int) -> String {
        return format("nearby.location.imprecise", "ubicación imprecisa ±%ld m", meters)
    }

    static var nearbyAgeNow: String { tr("nearby.age.now", "hace menos de 1 min") }

    static func nearbyAgeMinutes(_ minutes: Int) -> String {
        return format("nearby.age.minutes", "hace %ld min", minutes)
    }

    static func nearbyAgeHours(_ hours: Int) -> String {
        return format("nearby.age.hours", "hace %ld h", hours)
    }

    // Variantes habladas (VoiceOver no lee "±" ni "min" de forma natural).

    static func nearbySpokenAccuracy(_ meters: Int) -> String {
        return format("nearby.a11y.accuracy", "ubicación con precisión de %ld metros", meters)
    }

    static func nearbySpokenImprecise(_ meters: Int) -> String {
        return format("nearby.a11y.imprecise", "ubicación imprecisa, precisión de %ld metros", meters)
    }

    static var nearbySpokenAgeNow: String { tr("nearby.a11y.age.now", "hace menos de un minuto") }
    /// "hace 3 minutos" (el orden cambia con el idioma: "3 minutes ago").
    static func nearbySpokenAgo(_ duration: String) -> String {
        return stageFill(tr("nearby.a11y.ago", "hace %@"), duration)
    }

    // MARK: Ficha de lugar

    static var poiTitle: String { tr("poi.title", "lugar") }
    static var poiDistance: String { tr("poi.distance", "distancia") }
    static var poiNoLocation: String { tr("poi.noLocation", "sin ubicación") }
    static var poiAlerted: String { tr("poi.alerted", "avisado en esta etapa") }
    static var poiNotFound: String { tr("poi.notFound", "lugar no encontrado") }
    static var poiNotFoundExplain: String {
        tr("poi.notFound.explain", "el enlace puede ser antiguo o el lugar ya no está en los datos.")
    }

    // MARK: Ajustes

    static var settingsTitle: String { tr("settings.title", "ajustes") }
    static var settingsSectionTheme: String { tr("settings.section.theme", "tema") }
    static var settingsSectionAlerts: String { tr("settings.section.alerts", "avisos") }
    static var settingsSectionStatus: String { tr("settings.section.status", "estado") }
    static var settingsThemeNegro: String { tr("settings.theme.negro", "negro") }
    static var settingsThemePerla: String { tr("settings.theme.perla", "perla") }
    static var settingsAlertsRule: String {
        tr("settings.alerts.rule", "un aviso por lugar y etapa, como máximo uno por minuto")
    }
    static var settingsSyncRow: String { tr("settings.sync", "sincronización") }
    static var settingsSosInfo: String {
        tr("settings.sos", "en una emergencia: botón SOS de la pantalla principal, o SOS del reloj manteniendo pulsado el botón lateral")
    }

    // MARK: Sincronización (pantalla)

    static var sync2Title: String { tr("sync2.title", "sincronización") }
    static var sync2Now: String { tr("sync2.now", "sincronizar ahora") }
    static var sync2Synced: String { tr("sync2.synced.explain", "registros enviados al servidor") }
    static var sync2Demo: String { tr("sync2.demo.explain", "servidor de demostración: no se envía nada") }
    static var sync2Blocked: String {
        tr("sync2.blocked.explain", "guardado en el reloj · envío pendiente de backend: todavía no hay servidor, no se envía nada")
    }
    static var sync2NeedsLink: String {
        tr("sync2.needsLink.explain", "hay que vincular el reloj con tu cuenta (próximamente)")
    }
    static var sync2Offline: String {
        tr("sync2.offline.explain", "sin conexión: tus etapas se guardan en el reloj y se enviarán al recuperarla")
    }
    static var sync2Syncing: String { tr("sync2.syncing.explain", "enviando los registros guardados en el reloj") }
    static var sync2DeadLettersExplain: String {
        tr("sync2.deadLetters.explain", "el servidor no los aceptó: se conservan en el reloj y no se vuelven a enviar")
    }

    static func sync2Pending(_ count: Int) -> String {
        if count == 1 {
            return tr("sync2.pending.one", "1 registro guardado en el reloj")
        }
        return format("sync2.pending.many", "%ld registros guardados en el reloj", count)
    }

    static func sync2DeadLetters(_ count: Int) -> String {
        if count == 1 {
            return tr("sync2.deadLetters.one", "1 registro rechazado")
        }
        return format("sync2.deadLetters.many", "%ld registros rechazados", count)
    }
}
