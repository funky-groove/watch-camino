import Foundation

/// Servicio de aplicación del núcleo: orquesta máquina de estados + persistencia +
/// sincronización para que la capa app (SwiftUI + sensores) sea fina.
///
/// - Persiste en cada transición (§4) y cuando cambian pasos, distancia o avisos.
/// - Tras `start` y `finish` dispara `syncNow` (si `autoSync`), §7.
/// - Aislado al `MainActor`: la UI y los sensores entregan aquí sus datos en el hilo principal.
@MainActor
public final class CaminoController {
    public let catalog: any StageCatalog
    public let poiSource: any PoiSource
    public let sync: SyncEngine

    /// Errores al cargar el estado persistido en el arranque (se arranca en limpio).
    public private(set) var startupErrors: [Error] = []

    /// Se llama tras cualquier cambio observable (estado, historial, sync).
    public var onChange: (() -> Void)?
    /// Se llama si falla una escritura en disco. El estado en memoria sigue siendo válido.
    public var onStorageError: ((Error) -> Void)?

    /// Si es `true`, `start` y `finish` lanzan un `syncNow` no manual en segundo plano.
    public var autoSync: Bool

    /// Categorías de POI que generan aviso (preferencia del usuario). Por defecto, todas.
    /// Un POI de una categoría desactivada no se avisa ni consume el límite de ritmo.
    public var alertCategories: Set<PoiCategory> = Set(PoiCategory.allCases)

    private var machine: StageSessionMachine
    private let sessionStore: any SessionStore
    private let clock: any CaminoClock
    private let ids: any IdGenerator

    public init(
        catalog: any StageCatalog,
        poiSource: any PoiSource,
        sessionStore: any SessionStore,
        syncStore: any SyncQueueStore,
        api: any CaminoApi,
        clock: any CaminoClock,
        ids: any IdGenerator,
        jitter: @escaping () -> Double = Backoff.systemJitter,
        autoSync: Bool = true
    ) {
        self.catalog = catalog
        self.poiSource = poiSource
        self.sessionStore = sessionStore
        self.clock = clock
        self.ids = ids
        self.autoSync = autoSync

        var persisted = PersistedSession()
        var errors: [Error] = []
        do {
            if let loaded = try sessionStore.load() {
                persisted = loaded
            }
        } catch {
            errors.append(error)
        }

        let known = Set(catalog.allStages().map { $0.id })
        self.machine = StageSessionMachine(
            state: persisted.state,
            history: persisted.history,
            knownStageIds: known,
            ids: ids
        )
        self.sync = SyncEngine(api: api, store: syncStore, clock: clock, jitter: jitter)
        if let syncError = sync.loadError {
            errors.append(syncError)
        }
        self.startupErrors = errors

        sync.onStatusChange = { [weak self] _ in
            self?.onChange?()
        }
        sync.onStorageError = { [weak self] error in
            self?.onStorageError?(error)
        }
    }

    // MARK: - Lectura

    public var state: SessionState {
        return machine.state
    }

    /// Más reciente primero.
    public var history: History {
        return machine.history
    }

    public var activeSession: StageSession? {
        return machine.state.activeSession
    }

    public var stages: [Stage] {
        return catalog.allStages()
    }

    public var isDemo: Bool {
        return sync.isDemo
    }

    public func stage(id: String) -> Stage? {
        return catalog.stage(id: id)
    }

    public func pois(forStage stageId: String) -> [Poi] {
        return poiSource.pois(forStage: stageId)
    }

    public var activeStage: Stage? {
        guard let session = activeSession else {
            return nil
        }
        return stage(id: session.stageId)
    }

    /// Etapa sugerida (§10): la siguiente a la última terminada; la primera si no hay
    /// historial; `nil` si la última terminada era la final del catálogo.
    public var suggestedStage: Stage? {
        let all = stages
        guard let first = all.first else {
            return nil
        }
        guard let last = history.first else {
            return first
        }
        guard let index = all.firstIndex(where: { $0.id == last.stageId }) else {
            return first
        }
        let next = index + 1
        return next < all.count ? all[next] : nil
    }

    /// Lista para "Elegir etapa": la sugerida primero, el resto en orden de catálogo.
    public var stagesForPicker: [Stage] {
        let all = stages
        guard let suggested = suggestedStage else {
            return all
        }
        return [suggested] + all.filter { $0.id != suggested.id }
    }

    /// Metros que faltan de la etapa activa: `max(0, plan − recorridos)`.
    public var remainingMeters: Double? {
        guard let session = activeSession, let stage = activeStage else {
            return nil
        }
        return max(0, Double(stage.distanceMeters) - session.distanceMeters)
    }

    /// POI no avisado más cercano a `point` de la etapa activa.
    public func nextPoi(from point: GeoPoint) -> PoiAlert? {
        guard let session = activeSession else {
            return nil
        }
        return PoiEngine.nearestPending(
            pois: pois(forStage: session.stageId),
            alerted: session.alertedPoiIds,
            position: point
        )
    }

    /// Lista "Cerca": POIs de la etapa activa (o de todas las etapas si no hay etapa
    /// en curso) ordenados por distancia a `point`.
    public func nearby(from point: GeoPoint, categories: Set<PoiCategory>, limit: Int = 20) -> [PoiAlert] {
        let source: [Poi]
        if let session = activeSession {
            source = pois(forStage: session.stageId)
        } else {
            source = stages.flatMap { pois(forStage: $0.id) }
        }
        return Nearby.list(pois: source, from: point, categories: categories, limit: limit)
    }

    /// POI por id, en cualquier etapa.
    public func poi(id: String) -> Poi? {
        for stage in stages {
            if let match = pois(forStage: stage.id).first(where: { $0.id == id }) {
                return match
            }
        }
        return nil
    }

    /// Suma del historial (no incluye la sesión activa).
    public var totals: CaminoTotals {
        return CaminoTotals.of(history)
    }

    /// Segundos transcurridos de la sesión activa a `now`.
    public func elapsedSeconds(at now: Date) -> Int {
        guard let session = activeSession else {
            return 0
        }
        let elapsed = now.timeIntervalSince(session.startedAt)
        guard elapsed.isFinite, elapsed > 0 else {
            return 0
        }
        return Int(min(elapsed, Double(Int32.max)).rounded(.down))
    }

    public func now() -> Date {
        return clock.now()
    }

    // MARK: - Comandos

    /// Idle → Active. Persiste, encola `stage_started` y dispara sincronización.
    @discardableResult
    public func start(stageId: String) throws -> StageSession {
        let now = clock.now()
        let events = try machine.start(stageId: stageId, sessionId: ids.newId(), now: now)
        persistSession()
        sync.enqueue(events)
        notifyChange()
        triggerAutoSync()
        guard let session = machine.state.activeSession else {
            throw SessionError.notActive
        }
        return session
    }

    /// Pasos acumulados desde `startedAt`. En Idle se ignora sin error (§4).
    public func updateSteps(_ steps: Int) {
        guard machine.state.isActive else {
            return
        }
        let changed = (try? machine.updateSteps(steps)) ?? false
        if changed {
            persistSession()
            notifyChange()
        }
    }

    /// Fix de ubicación. En Idle se ignora sin error (§4).
    /// El límite de ritmo POI usa `clock.now()` (reloj del sistema), no `fix.timestamp` (§6).
    @discardableResult
    public func updateLocation(_ fix: LocationFix) -> LocationUpdateResult? {
        guard let session = machine.state.activeSession else {
            return nil
        }
        let stagePois = pois(forStage: session.stageId).filter { alertCategories.contains($0.category) }
        guard let result = try? machine.updateLocation(fix, pois: stagePois, now: clock.now()) else {
            return nil
        }
        if result.changedSession {
            persistSession()
            notifyChange()
        }
        return result
    }

    /// En marcha → Pausado (V1.1 §C). Persiste y notifica; no encola eventos ni sincroniza.
    /// - Throws: `SessionError.notActive` o `.alreadyPaused`.
    public func pause() throws {
        try machine.pause(now: clock.now())
        persistSession()
        notifyChange()
    }

    /// Pausado → En marcha (V1.1 §C). Persiste y notifica; no encola eventos ni sincroniza.
    /// - Throws: `SessionError.notActive` o `.notPaused`.
    public func resume() throws {
        try machine.resume(now: clock.now())
        persistSession()
        notifyChange()
    }

    /// `true` si hay trayecto activo en pausa.
    public var isPaused: Bool {
        return machine.state.isPaused
    }

    /// Active → Idle (cierra la pausa en curso si la hay). Persiste, encola `stage_finished`
    /// y dispara sincronización.
    @discardableResult
    public func finish() throws -> SessionSummary {
        let result = try machine.finish(now: clock.now())
        persistSession()
        sync.enqueue(result.events)
        notifyChange()
        triggerAutoSync()
        return result.summary
    }

    /// Disparadores de §7: primer plano, botón manual (`manual = true`), etc.
    @discardableResult
    public func syncNow(manual: Bool) async -> SyncStatus {
        let status = await sync.syncNow(manual: manual)
        notifyChange()
        return status
    }

    // MARK: - Privado

    private func persistSession() {
        let value = PersistedSession(state: machine.state, history: machine.history)
        do {
            try sessionStore.save(value)
        } catch {
            onStorageError?(error)
        }
    }

    private func notifyChange() {
        onChange?()
    }

    private func triggerAutoSync() {
        guard autoSync else {
            return
        }
        Task { [weak self] in
            guard let self = self else {
                return
            }
            _ = await self.syncNow(manual: false)
        }
    }
}
