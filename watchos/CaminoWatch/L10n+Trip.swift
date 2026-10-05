import Foundation

// Textos V1.1: trayecto (pausa, tiempo en movimiento, ritmo/velocidad, altitud, perfil),
// lugares, preferencias, acceso desde la esfera y resumen.
// Títulos en minúsculas por contenido; `SectionLabel` pone las mayúsculas.

extension L10n {
    /// Sustituye cada `%@` por el siguiente argumento, en orden.
    static func fillAll(_ template: String, _ arguments: [String]) -> String {
        var result = ""
        var rest = Substring(template)
        var index = 0
        while let range = rest.range(of: "%@") {
            result += String(rest[rest.startIndex..<range.lowerBound])
            result += index < arguments.count ? arguments[index] : ""
            index += 1
            rest = rest[range.upperBound...]
        }
        return result + String(rest)
    }

    // MARK: Unidades habladas

    static var spokenMiles: String { tr("a11y.unit.mi", "millas") }
    static var spokenFeet: String { tr("a11y.unit.ft", "pies") }
    static var spokenKmh: String { tr("a11y.unit.kmh", "kilómetros por hora") }
    static var spokenMph: String { tr("a11y.unit.mph", "millas por hora") }
    static var spokenPerKilometer: String { tr("a11y.per.km", "por kilómetro") }
    static var spokenPerMile: String { tr("a11y.per.mi", "por milla") }

    static func spokenSeconds(_ count: Int) -> String {
        if count == 1 {
            return tr("a11y.seconds.one", "1 segundo")
        }
        return format("a11y.seconds.many", "%ld segundos", count)
    }

    // MARK: Cifras del trayecto

    static var metricPace: String { tr("metric.pace", "ritmo") }
    static var metricSpeed: String { tr("metric.speed", "velocidad") }
    static var metricPaceAverage: String { tr("metric.pace.average", "ritmo medio") }
    static var metricSpeedAverage: String { tr("metric.speed.average", "velocidad media") }
    static var tripMovingTime: String { tr("trip.movingTime", "tiempo en movimiento") }
    static var tripTotalTime: String { tr("trip.totalTime", "duración total") }
    /// Etiqueta corta del tiempo en movimiento en la pantalla Trayecto.
    static var tripMovingTimeShort: String { tr("trip.movingTime.short", "en movimiento") }

    // MARK: Estado y pausa

    static var tripRunning: String { tr("trip.running", "En marcha") }
    static var tripPaused: String { tr("trip.paused", "Pausado") }
    static var tripPausedNote: String {
        tr("trip.paused.note", "las cifras no avanzan; los avisos de lugares siguen activos")
    }
    static var tripPause: String { tr("trip.pause", "Pausar") }
    static var tripResume: String { tr("trip.resume", "Reanudar") }
    static var tripPauseHint: String {
        tr("trip.pause.hint", "Detiene la distancia y el tiempo en movimiento. Los avisos de lugares siguen activos.")
    }
    static var tripResumeHint: String {
        tr("trip.resume.hint", "Vuelve a medir la distancia y el tiempo en movimiento.")
    }
    static var errorPause: String { tr("error.pause", "No se pudo pausar el trayecto.") }
    static var errorResume: String { tr("error.resume", "No se pudo reanudar el trayecto.") }

    // MARK: Altitud y desnivel

    static var altitudeSection: String { tr("altitude.section", "altitud y desnivel") }
    static var altitudeCurrent: String { tr("altitude.current", "altitud actual · GPS") }
    static var altitudeAscent: String { tr("altitude.ascent", "subida") }
    static var altitudeDescent: String { tr("altitude.descent", "bajada") }
    static var altitudeNone: String { tr("altitude.none", "sin datos de altitud") }

    /// "altitud antigua · hace 7 min"
    static func altitudeStale(_ age: String) -> String {
        return stageFill(tr("altitude.stale", "altitud antigua · %@"), age)
    }

    // MARK: Perfil

    static var profileSection: String { tr("profile.section", "perfil registrado") }
    static var profileTitle: String { tr("profile.title", "perfil") }
    static var profileEmpty: String { tr("profile.empty", "aún no hay perfil") }
    static var profileNotRecorded: String { tr("profile.notRecorded", "no se registró perfil de altitud") }
    static var profileHint: String { tr("profile.hint", "Abre el perfil ampliado.") }
    static var profileNote: String {
        tr("profile.note", "Sólo lo recorrido, con altitud GPS. Los tramos sin datos no se unen.")
    }

    /// "perfil de 4,2 km, de 412 m a 448 m"
    static func profileSummary(distance: String, low: String, high: String) -> String {
        return fillAll(tr("profile.summary", "perfil de %@, de %@ a %@"), [distance, low, high])
    }

    // MARK: Lugares

    static var placesTitle: String { tr("places.title", "lugares") }
    static var placesSection: String { tr("places.section", "lugares útiles") }
    static var placesSeeAll: String { tr("places.seeAll", "Ver todos") }
    static var placesFilterAll: String { tr("places.filter.all", "todos") }
    static var placesFilterWater: String { tr("places.filter.water", "agua") }
    static var placesFilterShelter: String { tr("places.filter.shelter", "alojamiento") }
    static var placesFilterLabel: String { tr("places.filter.label", "mostrar") }
    static var placesEmptyShelterStage: String {
        tr("places.empty.shelter.stage", "no hay alojamientos en los datos de esta etapa")
    }
    static var placesEmptyShelterAny: String {
        tr("places.empty.shelter.any", "no hay alojamientos en los datos disponibles")
    }

    /// "340 m en línea recta"
    static func placesStraightLine(_ distance: String) -> String {
        return stageFill(tr("places.straightLine", "%@ en línea recta"), distance)
    }

    static var poiDistanceStraight: String { tr("poi.distance.straight", "distancia en línea recta") }
    static var poiCall: String { tr("poi.call", "Llamar") }
    static var poiCallHint: String { tr("poi.call.hint", "El reloj pedirá confirmación antes de llamar.") }

    // MARK: Ajustes

    static var settingsSectionFace: String { tr("settings.section.face", "acceso desde la esfera") }
    static var settingsFaceRow: String { tr("settings.face.row", "Cómo añadirlo") }
    static var settingsSectionUnits: String { tr("settings.section.units", "unidades") }
    static var settingsUnitsMetric: String { tr("settings.units.metric", "métrico (km, m)") }
    static var settingsUnitsImperial: String { tr("settings.units.imperial", "imperial (mi, ft)") }
    static var settingsSectionPace: String { tr("settings.section.pace", "ritmo o velocidad") }
    static var settingsPacePace: String { tr("settings.pace.pace", "ritmo (minutos por km o mi)") }
    static var settingsPaceSpeed: String { tr("settings.pace.speed", "velocidad (km/h o mph)") }
    static var settingsSectionLanguage: String { tr("settings.section.language", "idioma") }
    static var settingsLanguageInfo: String {
        tr("settings.language.info", "Idioma: sigue el del reloj (español o inglés)")
    }

    // MARK: Aviso de primer uso y ayuda de la esfera

    static var faceTitle: String { tr("face.prompt.title", "Accede desde tu esfera") }
    static var faceBody: String { tr("face.prompt.body", "Abre Camino Seguro con un toque.") }
    static var faceHowTo: String { tr("face.prompt.how", "Cómo añadirlo") }
    static var faceNotNow: String { tr("face.prompt.notNow", "Ahora no") }

    static var faceHelpTitle: String { tr("face.help.title", "acceso desde la esfera") }
    static var faceHelpIntro: String {
        tr("face.help.intro", "Añade Camino Seguro a tu esfera como complicación:")
    }
    static var faceHelpStep1: String { tr("face.help.step1", "Mantén pulsada la esfera y toca Editar.") }
    static var faceHelpStep2: String { tr("face.help.step2", "Desliza hasta Complicaciones.") }
    static var faceHelpStep3: String {
        tr("face.help.step3", "Toca un hueco y elige Camino Seguro con la Digital Crown.")
    }
    static var faceHelpStep4: String { tr("face.help.step4", "Pulsa la Digital Crown para guardar.") }
    static var faceHelpNoSlot: String {
        tr("face.help.noSlot", "Si no hay hueco libre, sustituye otra complicación o elige otra esfera.")
    }
    static var faceHelpIPhone: String {
        tr("face.help.iphone", "También puedes hacerlo desde la app Watch del iPhone.")
    }
    static var faceHelpTapOnly: String {
        tr("face.help.tapOnly", "Al tocarla se abre la app; nunca inicia un trayecto.")
    }

    /// "paso 1" (VoiceOver)
    static func faceHelpStepLabel(_ number: Int) -> String {
        return format("face.help.step.a11y", "paso %ld", number)
    }

    // MARK: Resumen

    static var summarySaved: String { tr("summary.saved", "Guardado en el reloj") }
    static var summarySaveFailed: String {
        tr("summary.saveFailed", "No se pudo guardar en el reloj: los datos sólo siguen en memoria.")
    }
    static var summaryMemoryOnlyDemo: String {
        tr("summary.memoryOnly.demo", "Demostración: sólo en memoria, no se guarda en el reloj.")
    }
    static var summaryMemoryOnly: String {
        tr("summary.memoryOnly", "Almacenamiento no disponible: sólo en memoria, no se guarda en el reloj.")
    }
    static var summarySyncPending: String { tr("summary.sync.pending", "Pendiente de enviar") }
    static var summarySyncBlocked: String { tr("summary.sync.blocked", "Envío no disponible (sin servidor)") }
    static var summarySyncSynced: String { tr("summary.sync.synced", "Sincronizado") }
    static var summarySyncDemo: String { tr("summary.sync.demo", "Envío simulado (servidor de demostración)") }
    static var summarySyncNeedsLink: String {
        tr("summary.sync.needsLink", "Pendiente de enviar · falta vincular la cuenta")
    }
    static var summaryAverageNote: String {
        tr("summary.average.note", "media = distancia ÷ tiempo en movimiento")
    }
}
