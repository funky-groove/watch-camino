import Foundation
import WidgetKit

/// Publica una instantánea para complicaciones y widgets (target `CaminoWidgets`).
///
/// Se llama en cada `refresh()` del modelo, que es frecuente (cada fix, cada lote de pasos).
/// Por eso:
/// - Sólo ESCRIBE el fichero si cambió algo visible (`WidgetSnapshot.isEquivalent`).
/// - Sólo pide RECARGAR los timelines (`WidgetCenter.reloadAllTimelines()`), que gasta del
///   presupuesto diario de WidgetKit, al empezar o terminar una etapa y, durante la etapa,
///   como mucho cada 15 min o cuando la distancia cambia ≥ 0,5 km desde la última recarga.
///
/// NO hay actualización continua garantizada: WidgetKit decide cuándo se redibuja la
/// esfera. El tiempo sí avanza solo (`Text(_, style: .timer)` en el widget).
/// Ver CaminoWidgets/README.md.
enum WidgetBridge {
    /// Intervalo mínimo entre recargas durante una etapa.
    static let minReloadInterval: TimeInterval = 15 * 60
    /// Cambio de distancia que justifica una recarga anticipada.
    static let reloadDistanceStep: Double = 500
    /// Suelo entre recargas por distancia (a pie, 0,5 km son ~6 min; evita ráfagas con GPS ruidoso).
    static let minDistanceReloadInterval: TimeInterval = 5 * 60

    @MainActor private static var lastWritten: WidgetSnapshot?
    @MainActor private static var didLoadFromDisk = false
    @MainActor private static var lastReloadAt: Date?
    @MainActor private static var lastReloadMeters: Double = 0

    @MainActor
    static func update(from model: AppModel) {
        let now = Date()
        let snapshot = makeSnapshot(from: model, now: now)
        guard WidgetSnapshotStore.fileURL != nil else {
            // Sin App Group (sin firma): degradación honesta, el widget dice "Abre Camino Seguro".
            return
        }
        if !didLoadFromDisk {
            didLoadFromDisk = true
            lastWritten = WidgetSnapshotStore.load()
        }
        let previous = lastWritten
        if let previous = previous, previous.isEquivalent(to: snapshot) {
            return
        }
        do {
            guard try WidgetSnapshotStore.save(snapshot) else {
                return
            }
        } catch {
            Log.app.error("No se pudo escribir la instantánea del widget: \(Log.describe(error), privacy: .public)")
            return
        }
        lastWritten = snapshot
        if shouldReload(previous: previous, current: snapshot, now: now) {
            lastReloadAt = now
            lastReloadMeters = snapshot.walkedMeters
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @MainActor
    private static func makeSnapshot(from model: AppModel, now: Date) -> WidgetSnapshot {
        let last = model.latestSummary
        let lastName = last.map { model.stageName(id: $0.stageId) }
        guard let session = model.activeSession else {
            return WidgetSnapshot(
                stageName: nil,
                startedAt: nil,
                walkedMeters: 0,
                plannedMeters: 0,
                hasFix: false,
                isDemo: model.isDemo,
                updatedAt: now,
                lastStageName: lastName,
                lastStageMeters: last?.distanceMeters,
                lastStageSeconds: last?.activeSeconds
            )
        }
        let planned = model.stage(id: session.stageId).map { Double($0.distanceMeters) } ?? 0
        return WidgetSnapshot(
            stageName: model.stageName(id: session.stageId),
            startedAt: session.startedAt,
            walkedMeters: session.distanceMeters,
            plannedMeters: planned,
            hasFix: session.lastFix != nil,
            isDemo: model.isDemo,
            updatedAt: now,
            lastStageName: lastName,
            lastStageMeters: last?.distanceMeters,
            lastStageSeconds: last?.activeSeconds
        )
    }

    @MainActor
    private static func shouldReload(previous: WidgetSnapshot?, current: WidgetSnapshot, now: Date) -> Bool {
        guard let previous = previous else {
            // Primer dato publicado (o fichero ilegible): una recarga.
            return true
        }
        // Empezar / terminar / cambiar de etapa, o pasar a/desde demostración.
        if previous.startedAt != current.startedAt || previous.isDemo != current.isDemo {
            return true
        }
        guard current.isActive else {
            // Sin etapa: los cambios restantes (p. ej. historial sincronizado) esperan
            // a la siguiente recarga natural; el resumen final ya recargó al terminar.
            return false
        }
        guard let last = lastReloadAt else {
            return true
        }
        let sinceLast = now.timeIntervalSince(last)
        if sinceLast >= minReloadInterval {
            return true
        }
        // Recarga anticipada por distancia, con un suelo para no agotar el presupuesto.
        return abs(current.walkedMeters - lastReloadMeters) >= reloadDistanceStep
            && sinceLast >= minDistanceReloadInterval
    }
}
