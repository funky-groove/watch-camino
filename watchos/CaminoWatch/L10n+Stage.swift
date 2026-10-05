import Foundation

// Textos de "Mi etapa", elegir etapa, estadísticas, ficha de métrica y resumen.
// Títulos en minúsculas por contenido; las etiquetas de sección se ponen en mayúsculas
// con `SectionLabel` (transformación visual), no aquí.

extension L10n {
    /// Sustituye `%@` por un texto ya formateado (cifras con `Formatters`).
    static func stageFill(_ template: String, _ argument: String) -> String {
        return template.replacingOccurrences(of: "%@", with: argument)
    }

    // MARK: Mi etapa

    static var myStageTitle: String { tr("mystage.title", "mi etapa") }
    static var myStageIdle: String { tr("mystage.idle", "sin etapa en curso") }
    static var myStageWalked: String { tr("mystage.walked", "recorrido") }
    static var myStageTime: String { tr("mystage.time", "tiempo") }
    static var myStageWaitingGps: String { tr("mystage.waitingGps", "esperando GPS") }
    static var myStageStage: String { tr("mystage.stage", "etapa") }
    static var myStageOpenDetailHint: String { tr("mystage.detail.hint", "Abre el detalle de esta cifra.") }
    static var myStageLastAlert: String { tr("mystage.lastAlert", "último aviso") }
    static var myStageWater: String { tr("mystage.water", "agua cercana") }
    static var myStageNoLocation: String { tr("mystage.noLocation", "sin ubicación") }
    static var myStageNoWater: String { tr("mystage.noWater", "sin puntos de agua en la lista") }
    static var myStageStats: String { tr("mystage.stats", "estadísticas") }
    static var myStageStart: String { tr("mystage.start", "comenzar etapa") }
    static var myStageStartHint: String { tr("mystage.start.hint", "Elige la etapa y confírmala para empezar.") }
    static var myStageFinish: String { tr("mystage.finish", "finalizar etapa") }
    static var myStageFinishConfirmTitle: String { tr("mystage.finish.title", "¿finalizar la etapa?") }
    static var myStageFinishConfirmMessage: String {
        tr("mystage.finish.message", "Se guardará el resumen. Una etapa finalizada no se puede reanudar.")
    }
    static var myStageFinishConfirmAction: String { tr("mystage.finish.action", "finalizar etapa") }
    static var myStageFinishConfirmCancel: String { tr("mystage.finish.cancel", "seguir caminando") }
    static var myStageSettings: String { tr("mystage.settings", "ajustes") }
    static var myStageWaterButton: String { tr("mystage.waterButton", "agua cercana") }
    static var myStageSyncHint: String { tr("mystage.sync.hint", "Abre el estado de sincronización.") }
    static var myStageSyncLabel: String { tr("mystage.sync.label", "sincronización") }

    /// "quedan 8,3 km"
    static func myStageRemaining(_ distance: String) -> String {
        return stageFill(tr("mystage.remaining", "quedan %@"), distance)
    }

    /// "agua · 340 m"
    static func myStageWaterAt(_ distance: String) -> String {
        return stageFill(tr("mystage.waterAt", "agua · %@"), distance)
    }

    /// "última: Sarria – Portomarín · 22 km"
    static func myStageLastFinished(_ text: String) -> String {
        return stageFill(tr("mystage.lastFinished", "última: %@"), text)
    }

    /// "300 m al avisar"
    static func myStageAtAlert(_ distance: String) -> String {
        return stageFill(tr("mystage.atAlert", "%@ al avisar"), distance)
    }

    // MARK: Elegir etapa

    static var pickStageTitle: String { tr("pickstage.title", "elegir etapa") }
    static var pickStageSuggested: String { tr("pickstage.suggested", "sugerida") }
    static var pickStageOthers: String { tr("pickstage.others", "etapas") }
    static var pickStageEmpty: String { tr("pickstage.empty", "No hay etapas disponibles.") }
    static var pickStageConfirmTitle: String { tr("pickstage.confirm.title", "¿comenzar esta etapa?") }
    static var pickStageConfirmStart: String { tr("pickstage.confirm.start", "comenzar") }
    static var pickStageCancel: String { tr("pickstage.cancel", "cancelar") }
    static var pickStageNotice: String {
        tr("pickstage.notice", "Datos de demostración: coordenadas aproximadas. No sirven para orientarse en el Camino.")
    }

    // MARK: Estadísticas

    static var statsListTitle: String { tr("statlist.title", "estadísticas") }
    static var statsThisStage: String { tr("statlist.thisStage", "esta etapa") }
    static var statsCumulative: String { tr("statlist.cumulative", "acumulado") }
    static var statsNoStages: String { tr("statlist.noStages", "aún no hay etapas terminadas") }
    static var statsMetricDistance: String { tr("statlist.distance", "distancia") }
    static var statsMetricTime: String { tr("statlist.time", "tiempo") }
    static var statsMetricSteps: String { tr("statlist.steps", "pasos") }
    static var statsNoSteps: String { tr("statlist.noSteps", "sin datos de pasos") }
    static var statsFinishedStages: String { tr("statlist.finishedStages", "etapas terminadas") }

    /// "en curso: Sarria – Portomarín"
    static func statsInProgress(_ name: String) -> String {
        return stageFill(tr("statlist.inProgress", "en curso: %@"), name)
    }

    /// "última terminada: Sarria – Portomarín"
    static func statsLastFinished(_ name: String) -> String {
        return stageFill(tr("statlist.lastFinished", "última terminada: %@"), name)
    }

    // MARK: Ficha de métrica

    static var statDetailSource: String { tr("statdetail.source", "de dónde sale") }
    static var statDetailDistanceSource: String {
        tr("statdetail.distance.source", "Medida con GPS; se descartan posiciones con precisión peor de 50 m.")
    }
    static var statDetailTimeSource: String {
        tr("statdetail.time.source", "Desde que empezaste la etapa; no se pausa.")
    }
    static var statDetailStepsSource: String {
        tr("statdetail.steps.source", "Sensor de movimiento del reloj.")
    }
    static var statDetailLocationNone: String { tr("statdetail.location.none", "ubicación: aún ninguna") }

    /// "ubicación buena · ±12 m"
    static func statDetailLocationGood(_ accuracy: String) -> String {
        return stageFill(tr("statdetail.location.good", "ubicación buena · ±%@"), accuracy)
    }

    /// "ubicación imprecisa · ±80 m"
    static func statDetailLocationImprecise(_ accuracy: String) -> String {
        return stageFill(tr("statdetail.location.imprecise", "ubicación imprecisa · ±%@"), accuracy)
    }

    /// "ubicación antigua · hace 7 min"
    static func statDetailLocationStale(_ age: String) -> String {
        return stageFill(tr("statdetail.location.stale", "ubicación antigua · hace %@"), age)
    }

    // MARK: Resumen

    static var finishedTitle: String { tr("finished.title", "etapa terminada") }
    static var finishedDone: String { tr("finished.done", "hecho") }
    static var finishedSynced: String { tr("finished.synced", "guardado · sincronizado") }
    static var finishedWillSync: String { tr("finished.willSync", "guardado · se sincronizará") }
    static var finishedOffline: String { tr("finished.offline", "guardado en el reloj · se sincronizará con conexión") }
    static var finishedBlocked: String { tr("finished.blocked", "guardado en el reloj · pendiente de backend") }
    static var finishedNeedsLink: String { tr("finished.needsLink", "guardado en el reloj · falta vincular la cuenta") }
}
