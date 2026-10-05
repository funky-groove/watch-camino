import Foundation

/// Errores de la máquina de estados (§4).
public enum SessionError: String, Error, Equatable, Sendable {
    case alreadyActive
    case unknownStage
    case notActive
    /// V1.1 §C: `pause` con el trayecto ya en pausa.
    case alreadyPaused
    /// V1.1 §C: `resume` sin pausa en curso.
    case notPaused
}

/// Resultado de `updateLocation`.
public struct LocationUpdateResult: Equatable, Sendable {
    public let distance: DistanceStepOutcome
    public let alert: PoiAlert?
    /// Detalle de métricas del trayecto (V1.1). `nil` si el fix no pasó el paso 1 de §5.
    public let trip: TripFixOutcome?

    public init(distance: DistanceStepOutcome, alert: PoiAlert?, trip: TripFixOutcome? = nil) {
        self.distance = distance
        self.alert = alert
        self.trip = trip
    }

    /// `true` si la sesión cambió y conviene persistir.
    public var changedSession: Bool {
        return distance.movedAnchor || alert != nil || (trip?.changedMetrics ?? false)
    }
}

/// Resultado de `finish`.
public struct FinishResult: Equatable, Sendable {
    public let summary: SessionSummary
    public let events: [SyncEvent]
}

/// Máquina de estados de la etapa — docs/WATCH_V1_SPEC.md §4.
///
/// Es pura: no persiste ni envía nada. Cada comando que debe encolar eventos de
/// sincronización los devuelve; quien la usa (`CaminoController`) los mete en la
/// cola persistente y persiste el estado tras cada transición.
public struct StageSessionMachine {
    public private(set) var state: SessionState
    /// Más reciente primero.
    public private(set) var history: History

    private let knownStageIds: Set<String>
    private let ids: any IdGenerator

    public init(
        state: SessionState = .idle,
        history: History = [],
        knownStageIds: Set<String>,
        ids: any IdGenerator
    ) {
        self.state = state
        self.history = history
        self.knownStageIds = knownStageIds
        self.ids = ids
    }

    public var activeSession: StageSession? {
        return state.activeSession
    }

    /// Idle → Active. Encola `stage_started`.
    public mutating func start(stageId: String, sessionId: String, now: Date) throws -> [SyncEvent] {
        if state.isActive {
            throw SessionError.alreadyActive
        }
        guard knownStageIds.contains(stageId) else {
            throw SessionError.unknownStage
        }
        let session = StageSession(sessionId: sessionId, stageId: stageId, startedAt: now)
        state = .active(session)
        let event = SyncEvent(
            eventId: ids.newId(),
            type: .stageStarted,
            sessionId: sessionId,
            occurredAt: now,
            payload: SyncPayload.started(stageId: stageId, startedAt: now)
        )
        return [event]
    }

    /// `steps = max(steps, n)`: los pasos nunca bajan.
    /// - Returns: `true` si el valor cambió.
    @discardableResult
    public mutating func updateSteps(_ n: Int) throws -> Bool {
        guard case .active(var session) = state else {
            throw SessionError.notActive
        }
        let newValue = max(session.steps, n)
        if newValue == session.steps {
            return false
        }
        session.steps = newValue
        state = .active(session)
        return true
    }

    /// En marcha → Pausado (V1.1 §C): `pausedAt = now`, `lastFix = nil`.
    public mutating func pause(now: Date) throws {
        guard case .active(var session) = state else {
            throw SessionError.notActive
        }
        var metrics = session.metrics
        try metrics.pause(at: now)
        session.metrics = metrics
        state = .active(session)
    }

    /// Pausado → En marcha (V1.1 §C): `pausedSeconds += max(0, now − pausedAt)`.
    public mutating func resume(now: Date) throws {
        guard case .active(var session) = state else {
            throw SessionError.notActive
        }
        var metrics = session.metrics
        try metrics.resume(at: now)
        session.metrics = metrics
        state = .active(session)
    }

    /// Acumulador de distancia (§5) + métricas del trayecto (V1.1) + motor POI (§6).
    /// - Parameter pois: POIs; sólo se consideran los de la etapa activa.
    /// - Parameter now: hora del reloj del sistema al procesar el fix; es el "now" del
    ///   límite de ritmo POI (§6), no `fix.timestamp`, para que un lote de fixes atrasados
    ///   no produzca varios avisos seguidos.
    public mutating func updateLocation(_ fix: LocationFix, pois: [Poi], now: Date) throws -> LocationUpdateResult {
        guard case .active(var session) = state else {
            throw SessionError.notActive
        }
        // Paso 1 de §5: un fix impreciso no hace nada (ni distancia ni POI).
        guard DistanceAccumulator.isAccurateEnough(fix) else {
            return LocationUpdateResult(distance: .rejectedAccuracy, alert: nil)
        }

        // Métricas (§5, V1.1 §D–F). En pausa no cambian: sólo se evalúan avisos POI (§C).
        var metrics = session.metrics
        let trip = metrics.add(fix)
        session.metrics = metrics
        let outcome = trip.distance

        let stagePois = pois.filter { $0.stageId == session.stageId }
        let alert = PoiEngine.evaluate(
            pois: stagePois,
            alerted: session.alertedPoiIds,
            lastAlertAt: session.lastAlertAt,
            now: now,
            position: fix.point,
            accuracyMeters: fix.accuracyMeters
        )
        if let alert = alert {
            session.alertedPoiIds.insert(alert.poi.id)
            session.lastAlertAt = now
        }
        state = .active(session)
        return LocationUpdateResult(distance: outcome, alert: alert, trip: trip)
    }

    /// Active → Idle. Añade el resumen al historial y encola `stage_finished`.
    public mutating func finish(now: Date) throws -> FinishResult {
        guard case .active(var session) = state else {
            throw SessionError.notActive
        }
        // V1.1 §C: finalizar en pausa cierra la pausa en curso.
        var metrics = session.metrics
        metrics.closePause(at: now)
        session.metrics = metrics

        let elapsed = now.timeIntervalSince(session.startedAt)
        let activeSeconds: Int
        if elapsed.isFinite && elapsed > 0 {
            activeSeconds = Int(min(elapsed, Double(Int32.max)).rounded(.down))
        } else {
            activeSeconds = 0
        }
        let summary = SessionSummary(
            sessionId: session.sessionId,
            stageId: session.stageId,
            startedAt: session.startedAt,
            finishedAt: now,
            steps: max(0, session.steps),
            distanceMeters: StageSessionMachine.roundHalfUp(session.distanceMeters),
            activeSeconds: activeSeconds,
            // El tiempo en movimiento nunca supera la duración total (§D).
            movingSeconds: min(StageSessionMachine.roundHalfUp(session.movingSeconds), activeSeconds),
            pausedSeconds: StageSessionMachine.roundHalfUp(session.pausedSeconds),
            ascentMeters: StageSessionMachine.roundHalfUp(session.ascentMeters),
            descentMeters: StageSessionMachine.roundHalfUp(session.descentMeters),
            profile: session.profile
        )
        history.insert(summary, at: 0)
        state = .idle
        let event = SyncEvent(
            eventId: ids.newId(),
            type: .stageFinished,
            sessionId: session.sessionId,
            occurredAt: now,
            payload: SyncPayload.finished(summary)
        )
        return FinishResult(summary: summary, events: [event])
    }

    /// Entero no negativo con redondeo half-up (`floor(x + 0.5)`); NaN/negativo → 0.
    static func roundHalfUp(_ value: Double) -> Int {
        guard value.isFinite, value > 0 else {
            return 0
        }
        return Int(min(value, 1.0e15) + 0.5) // truncar tras +0.5 = floor para x ≥ 0
    }
}
