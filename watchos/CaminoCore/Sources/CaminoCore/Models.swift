import Foundation

// Modelo de dominio — docs/WATCH_V1_SPEC.md §3.
// Los nombres coinciden con los del núcleo Kotlin (wearos/core).

/// Punto geográfico en grados decimales (WGS84).
public struct GeoPoint: Codable, Equatable, Hashable, Sendable {
    public var lat: Double
    public var lon: Double

    public init(lat: Double, lon: Double) {
        self.lat = lat
        self.lon = lon
    }
}

/// Categoría de punto de interés.
public enum PoiCategory: String, Codable, CaseIterable, Sendable {
    case water
    case shelter
    case pharmacy
    case health
    case food
    case landmark

    /// Icono de §8. Siempre se muestra acompañado de texto, nunca solo.
    public var icon: String {
        switch self {
        case .water: return "💧"
        case .shelter: return "🛏"
        case .pharmacy: return "➕"
        case .health: return "🏥"
        case .food: return "🍽"
        case .landmark: return "⛪"
        }
    }
}

/// Etapa del Camino.
public struct Stage: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var from: String
    public var to: String
    public var distanceMeters: Int
    public var start: GeoPoint
    public var end: GeoPoint

    public init(
        id: String,
        name: String,
        from: String,
        to: String,
        distanceMeters: Int,
        start: GeoPoint,
        end: GeoPoint
    ) {
        self.id = id
        self.name = name
        self.from = from
        self.to = to
        self.distanceMeters = distanceMeters
        self.start = start
        self.end = end
    }
}

/// Punto de interés asociado a una etapa.
public struct Poi: Codable, Equatable, Identifiable, Sendable {
    public var id: String
    public var stageId: String
    public var name: String
    public var category: PoiCategory
    public var location: GeoPoint

    public init(id: String, stageId: String, name: String, category: PoiCategory, location: GeoPoint) {
        self.id = id
        self.stageId = stageId
        self.name = name
        self.category = category
        self.location = location
    }
}

/// Posición medida por el GPS.
public struct LocationFix: Codable, Equatable, Sendable {
    public var point: GeoPoint
    public var accuracyMeters: Double
    public var timestamp: Date

    public init(point: GeoPoint, accuracyMeters: Double, timestamp: Date) {
        self.point = point
        self.accuracyMeters = accuracyMeters
        self.timestamp = timestamp
    }
}

/// Sesión de etapa en curso.
public struct StageSession: Codable, Equatable, Sendable {
    /// UUID v4 generado en el reloj.
    public var sessionId: String
    public var stageId: String
    public var startedAt: Date
    /// Pasos acumulados desde `startedAt`. Nunca bajan.
    public var steps: Int
    public var distanceMeters: Double
    /// Último fix aceptado por el acumulador de distancia (§5).
    public var lastFix: LocationFix?
    public var alertedPoiIds: Set<String>
    public var lastAlertAt: Date?

    public init(
        sessionId: String,
        stageId: String,
        startedAt: Date,
        steps: Int = 0,
        distanceMeters: Double = 0,
        lastFix: LocationFix? = nil,
        alertedPoiIds: Set<String> = [],
        lastAlertAt: Date? = nil
    ) {
        self.sessionId = sessionId
        self.stageId = stageId
        self.startedAt = startedAt
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.lastFix = lastFix
        self.alertedPoiIds = alertedPoiIds
        self.lastAlertAt = lastAlertAt
    }
}

/// Resumen de una etapa terminada.
public struct SessionSummary: Codable, Equatable, Identifiable, Sendable {
    public var sessionId: String
    public var stageId: String
    public var startedAt: Date
    public var finishedAt: Date
    public var steps: Int
    /// Metros redondeados al entero más cercano.
    public var distanceMeters: Int
    public var activeSeconds: Int

    public var id: String { sessionId }

    public init(
        sessionId: String,
        stageId: String,
        startedAt: Date,
        finishedAt: Date,
        steps: Int,
        distanceMeters: Int,
        activeSeconds: Int
    ) {
        self.sessionId = sessionId
        self.stageId = stageId
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.activeSeconds = activeSeconds
    }
}

/// `Idle | Active(StageSession)`.
public enum SessionState: Equatable, Sendable {
    case idle
    case active(StageSession)

    public var activeSession: StageSession? {
        if case .active(let session) = self {
            return session
        }
        return nil
    }

    public var isActive: Bool {
        return activeSession != nil
    }
}

extension SessionState: Codable {
    private enum CodingKeys: String, CodingKey {
        case kind
        case session
    }

    private enum Kind: String, Codable {
        case idle
        case active
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let kind = try container.decode(Kind.self, forKey: .kind)
        switch kind {
        case .idle:
            self = .idle
        case .active:
            let session = try container.decode(StageSession.self, forKey: .session)
            self = .active(session)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .idle:
            try container.encode(Kind.idle, forKey: .kind)
        case .active(let session):
            try container.encode(Kind.active, forKey: .kind)
            try container.encode(session, forKey: .session)
        }
    }
}

/// Historial de etapas terminadas, más reciente primero.
public typealias History = [SessionSummary]

/// Lo que persiste `SessionStore`: estado + historial.
public struct PersistedSession: Codable, Equatable, Sendable {
    public var state: SessionState
    public var history: History

    public init(state: SessionState = .idle, history: History = []) {
        self.state = state
        self.history = history
    }
}

/// Totales acumulados del Camino (suma del historial).
public struct CaminoTotals: Equatable, Sendable {
    public var stages: Int
    public var distanceMeters: Int
    public var steps: Int
    public var activeSeconds: Int

    public init(stages: Int = 0, distanceMeters: Int = 0, steps: Int = 0, activeSeconds: Int = 0) {
        self.stages = stages
        self.distanceMeters = distanceMeters
        self.steps = steps
        self.activeSeconds = activeSeconds
    }

    public static func of(_ history: History) -> CaminoTotals {
        var totals = CaminoTotals()
        for summary in history {
            totals.stages += 1
            totals.distanceMeters += summary.distanceMeters
            totals.steps += summary.steps
            totals.activeSeconds += summary.activeSeconds
        }
        return totals
    }
}
