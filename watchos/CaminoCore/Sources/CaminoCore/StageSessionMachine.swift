import Foundation

/// Errores de la máquina de estados (§4).
public enum SessionError: String, Error, Equatable, Sendable {
    case alreadyActive
    case unknownStage
    case notActive
}

/// Resultado de `updateLocation`.
public struct LocationUpdateResult: Equatable, Sendable {
    public let distance: DistanceStepOutcome
    public let alert: PoiAlert?

    public init(distance: DistanceStepOutcome, alert: PoiAlert?) {
        self.distance = distance
        self.alert = alert
    }

    /// `true` si la sesión cambió y conviene persistir.
    public var changedSession: Bool {
        return distance.movedAnchor || alert != nil
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

    /// Acumulador de distancia (§5) + motor POI (§6).
    /// - Parameter pois: POIs; sólo se consideran los de la etapa activa.
    /// - Note: el "now" del límite de ritmo POI es `fix.timestamp`.
    public mutating func updateLocation(_ fix: LocationFix, pois: [Poi]) throws -> LocationUpdateResult {
        guard case .active(var session) = state else {
            throw SessionError.notActive
        }
        // Paso 1 de §5: un fix impreciso no hace nada (ni distancia ni POI).
        guard DistanceAccumulator.isAccurateEnough(fix) else {
            return LocationUpdateResult(distance: .rejectedAccuracy, alert: nil)
        }

        var accumulator = DistanceAccumulator(distanceMeters: session.distanceMeters, lastFix: session.lastFix)
        let outcome = accumulator.add(fix)
        session.distanceMeters = accumulator.distanceMeters
        session.lastFix = accumulator.lastFix

        let stagePois = pois.filter { $0.stageId == session.stageId }
        let alert = PoiEngine.evaluate(
            pois: stagePois,
            alerted: session.alertedPoiIds,
            lastAlertAt: session.lastAlertAt,
            now: fix.timestamp,
            position: fix.point,
            accuracyMeters: fix.accuracyMeters
        )
        if let alert = alert {
            session.alertedPoiIds.insert(alert.poi.id)
            session.lastAlertAt = fix.timestamp
        }
        state = .active(session)
        return LocationUpdateResult(distance: outcome, alert: alert)
    }

    /// Active → Idle. Añade el resumen al historial y encola `stage_finished`.
    public mutating func finish(now: Date) throws -> FinishResult {
        guard case .active(let session) = state else {
            throw SessionError.notActive
        }
        let elapsed = now.timeIntervalSince(session.startedAt)
        let activeSeconds: Int
        if elapsed.isFinite && elapsed > 0 {
            activeSeconds = Int(elapsed.rounded(.down))
        } else {
            activeSeconds = 0
        }
        let distance: Int
        if session.distanceMeters.isFinite && session.distanceMeters > 0 {
            distance = Int(session.distanceMeters.rounded())
        } else {
            distance = 0
        }
        let summary = SessionSummary(
            sessionId: session.sessionId,
            stageId: session.stageId,
            startedAt: session.startedAt,
            finishedAt: now,
            steps: max(0, session.steps),
            distanceMeters: distance,
            activeSeconds: activeSeconds
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
}
