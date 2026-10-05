import Foundation

// Modelos de sincronización — docs/WATCH_V1_SPEC.md §7.
// Privacidad: los eventos sólo llevan agregados, nunca posiciones ni traza GPS.

public enum SyncEventType: String, Codable, Sendable {
    case stageStarted = "stage_started"
    case stageFinished = "stage_finished"
}

/// `stage_started.payload  = { stageId, startedAt }`
/// `stage_finished.payload = { stageId, startedAt, finishedAt, steps, distanceMeters, activeSeconds }`
public struct SyncPayload: Codable, Equatable, Sendable {
    public var stageId: String
    public var startedAt: Date
    public var finishedAt: Date?
    public var steps: Int?
    public var distanceMeters: Int?
    public var activeSeconds: Int?

    public init(
        stageId: String,
        startedAt: Date,
        finishedAt: Date? = nil,
        steps: Int? = nil,
        distanceMeters: Int? = nil,
        activeSeconds: Int? = nil
    ) {
        self.stageId = stageId
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.activeSeconds = activeSeconds
    }

    public static func started(stageId: String, startedAt: Date) -> SyncPayload {
        return SyncPayload(stageId: stageId, startedAt: startedAt)
    }

    public static func finished(_ summary: SessionSummary) -> SyncPayload {
        return SyncPayload(
            stageId: summary.stageId,
            startedAt: summary.startedAt,
            finishedAt: summary.finishedAt,
            steps: summary.steps,
            distanceMeters: summary.distanceMeters,
            activeSeconds: summary.activeSeconds
        )
    }
}

public struct SyncEvent: Codable, Equatable, Identifiable, Sendable {
    /// UUID v4; clave de idempotencia.
    public var eventId: String
    public var type: SyncEventType
    public var sessionId: String
    public var occurredAt: Date
    public var payload: SyncPayload

    public var id: String { eventId }

    public init(eventId: String, type: SyncEventType, sessionId: String, occurredAt: Date, payload: SyncPayload) {
        self.eventId = eventId
        self.type = type
        self.sessionId = sessionId
        self.occurredAt = occurredAt
        self.payload = payload
    }
}

/// `Accepted | Retryable(reason) | Permanent(reason) | Unauthorized | Blocked`
public enum SendResult: Equatable, Sendable {
    case accepted
    case retryable(reason: String)
    case permanent(reason: String)
    case unauthorized
    case blocked
}

/// Estado de sincronización para la UI.
/// `offline` existe por paridad con la spec, pero en V1 ningún adaptador lo produce
/// (no hay cliente HTTP real; ver README).
public enum SyncStatus: Equatable, Sendable {
    case synced
    case pending(Int)
    case offline
    case blocked
    case needsLink
    case syncing

    /// Nombre estable usado por los vectores de conformidad.
    public var code: String {
        switch self {
        case .synced: return "synced"
        case .pending: return "pending"
        case .offline: return "offline"
        case .blocked: return "blocked"
        case .needsLink: return "needsLink"
        case .syncing: return "syncing"
        }
    }
}

/// Resultado persistido de la última ejecución de `syncNow`, para que la UI
/// muestre el estado correcto tras relanzar la app.
public enum SyncOutcome: String, Codable, Sendable {
    case synced
    case pending
    case blocked
    case needsLink
}

/// Lo que persiste `SyncQueueStore`: cola FIFO, dead-letter y backoff.
public struct SyncQueueState: Codable, Equatable, Sendable {
    public var queue: [SyncEvent]
    public var deadLetters: [SyncEvent]
    public var attempt: Int
    public var nextAttemptAt: Date?
    public var lastOutcome: SyncOutcome?

    public init(
        queue: [SyncEvent] = [],
        deadLetters: [SyncEvent] = [],
        attempt: Int = 0,
        nextAttemptAt: Date? = nil,
        lastOutcome: SyncOutcome? = nil
    ) {
        self.queue = queue
        self.deadLetters = deadLetters
        self.attempt = attempt
        self.nextAttemptAt = nextAttemptAt
        self.lastOutcome = lastOutcome
    }
}
