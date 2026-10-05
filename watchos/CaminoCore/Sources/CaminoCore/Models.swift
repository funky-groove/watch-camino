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
    /// Teléfono del lugar (V1.1 §J), opcional. Sólo se ofrece «Llamar» si
    /// `PhoneNumber.isValid(phone)`; los datos actuales no traen teléfonos.
    public var phone: String?

    public init(
        id: String,
        stageId: String,
        name: String,
        category: PoiCategory,
        location: GeoPoint,
        phone: String? = nil
    ) {
        self.id = id
        self.stageId = stageId
        self.name = name
        self.category = category
        self.location = location
        self.phone = phone
    }

    private enum CodingKeys: String, CodingKey {
        case id, stageId, name, category, location, phone
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        stageId = try c.decode(String.self, forKey: .stageId)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(PoiCategory.self, forKey: .category)
        location = try c.decode(GeoPoint.self, forKey: .location)
        phone = try c.decodeIfPresent(String.self, forKey: .phone)
    }

    /// URL `tel:` si el teléfono del lugar es válido (§J); `nil` en otro caso.
    public var telURL: URL? {
        guard let phone = phone else {
            return nil
        }
        return PhoneNumber.telURL(phone)
    }
}

/// Posición medida por el GPS.
public struct LocationFix: Codable, Equatable, Sendable {
    public var point: GeoPoint
    public var accuracyMeters: Double
    public var timestamp: Date
    /// Altitud GPS en metros (V1.1 §E). `nil` si el sensor no la da.
    public var altitudeMeters: Double?
    /// Precisión vertical en metros; negativa o `nil` = altitud no válida.
    public var verticalAccuracyMeters: Double?

    public init(
        point: GeoPoint,
        accuracyMeters: Double,
        timestamp: Date,
        altitudeMeters: Double? = nil,
        verticalAccuracyMeters: Double? = nil
    ) {
        self.point = point
        self.accuracyMeters = accuracyMeters
        self.timestamp = timestamp
        self.altitudeMeters = altitudeMeters
        self.verticalAccuracyMeters = verticalAccuracyMeters
    }

    private enum CodingKeys: String, CodingKey {
        case point, accuracyMeters, timestamp, altitudeMeters, verticalAccuracyMeters
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        point = try c.decode(GeoPoint.self, forKey: .point)
        accuracyMeters = try c.decode(Double.self, forKey: .accuracyMeters)
        timestamp = try c.decode(Date.self, forKey: .timestamp)
        altitudeMeters = try c.decodeIfPresent(Double.self, forKey: .altitudeMeters)
        verticalAccuracyMeters = try c.decodeIfPresent(Double.self, forKey: .verticalAccuracyMeters)
    }
}

/// Muestra del perfil de altitud registrado (V1.1 §F).
public struct ProfileSample: Codable, Equatable, Sendable {
    /// Distancia recorrida (m) al tomar la muestra.
    public var d: Double
    /// Altitud (m).
    public var alt: Double
    /// `true` si hubo un hueco (> 200 m) antes de esta muestra: no se une con la anterior.
    public var gapBefore: Bool

    public init(d: Double, alt: Double, gapBefore: Bool = false) {
        self.d = d
        self.alt = alt
        self.gapBefore = gapBefore
    }
}

/// Sesión de etapa en curso.
///
/// V1.1 añade pausa, tiempo en movimiento, altitud/desnivel y perfil. Todos los campos
/// nuevos se decodifican con `decodeIfPresent`: un estado persistido de V1 se sigue leyendo.
public struct StageSession: Codable, Equatable, Sendable {
    /// UUID v4 generado en el reloj.
    public var sessionId: String
    public var stageId: String
    public var startedAt: Date
    /// Pasos acumulados desde `startedAt`. Nunca bajan (y no se pausan).
    public var steps: Int
    public var distanceMeters: Double
    /// Último fix aceptado por el acumulador de distancia (§5). `nil` tras pausar.
    public var lastFix: LocationFix?
    public var alertedPoiIds: Set<String>
    public var lastAlertAt: Date?

    // MARK: V1.1
    /// Inicio de la pausa en curso; `nil` = en marcha (§C).
    public var pausedAt: Date?
    /// Segundos de pausas ya cerradas.
    public var pausedSeconds: Double
    /// Tiempo en movimiento (§D).
    public var movingSeconds: Double
    /// Subida y bajada acumuladas con histéresis (§E).
    public var ascentMeters: Double
    public var descentMeters: Double
    /// Altitud de referencia de la histéresis.
    public var altitudeRef: Double?
    /// Última altitud válida y la hora (`fix.timestamp`) en que se midió.
    public var altitude: Double?
    public var altitudeAt: Date?
    /// Perfil de altitud registrado (§F).
    public var profile: [ProfileSample]
    /// Separación mínima actual entre muestras del perfil (se duplica al recortar).
    public var profileSpacing: Double

    /// Tiempo en movimiento para mostrar EN VIVO: `min(movingSeconds, now − startedAt)`, igual
    /// que el resumen acota con la duración (§D). Con el reloj hacia atrás (`now < startedAt`)
    /// devuelve 0: nunca «tiempo en movimiento > duración».
    public func liveMovingSeconds(at now: Date) -> Double {
        let elapsed = now.timeIntervalSince(startedAt)
        let bound = (elapsed.isFinite && elapsed > 0) ? elapsed : 0
        let moving = movingSeconds.isFinite ? max(0, movingSeconds) : 0
        return min(moving, bound)
    }

    public init(
        sessionId: String,
        stageId: String,
        startedAt: Date,
        steps: Int = 0,
        distanceMeters: Double = 0,
        lastFix: LocationFix? = nil,
        alertedPoiIds: Set<String> = [],
        lastAlertAt: Date? = nil,
        pausedAt: Date? = nil,
        pausedSeconds: Double = 0,
        movingSeconds: Double = 0,
        ascentMeters: Double = 0,
        descentMeters: Double = 0,
        altitudeRef: Double? = nil,
        altitude: Double? = nil,
        altitudeAt: Date? = nil,
        profile: [ProfileSample] = [],
        profileSpacing: Double = TripMetrics.profileSpacingMeters
    ) {
        self.sessionId = sessionId
        self.stageId = stageId
        self.startedAt = startedAt
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.lastFix = lastFix
        self.alertedPoiIds = alertedPoiIds
        self.lastAlertAt = lastAlertAt
        self.pausedAt = pausedAt
        self.pausedSeconds = pausedSeconds
        self.movingSeconds = movingSeconds
        self.ascentMeters = ascentMeters
        self.descentMeters = descentMeters
        self.altitudeRef = altitudeRef
        self.altitude = altitude
        self.altitudeAt = altitudeAt
        self.profile = profile
        self.profileSpacing = profileSpacing
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, stageId, startedAt, steps, distanceMeters, lastFix, alertedPoiIds, lastAlertAt
        case pausedAt, pausedSeconds, movingSeconds, ascentMeters, descentMeters
        case altitudeRef, altitude, altitudeAt, profile, profileSpacing
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        stageId = try c.decode(String.self, forKey: .stageId)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        steps = try c.decode(Int.self, forKey: .steps)
        distanceMeters = try c.decode(Double.self, forKey: .distanceMeters)
        lastFix = try c.decodeIfPresent(LocationFix.self, forKey: .lastFix)
        alertedPoiIds = try c.decode(Set<String>.self, forKey: .alertedPoiIds)
        lastAlertAt = try c.decodeIfPresent(Date.self, forKey: .lastAlertAt)
        pausedAt = try c.decodeIfPresent(Date.self, forKey: .pausedAt)
        pausedSeconds = try c.decodeIfPresent(Double.self, forKey: .pausedSeconds) ?? 0
        movingSeconds = try c.decodeIfPresent(Double.self, forKey: .movingSeconds) ?? 0
        ascentMeters = try c.decodeIfPresent(Double.self, forKey: .ascentMeters) ?? 0
        descentMeters = try c.decodeIfPresent(Double.self, forKey: .descentMeters) ?? 0
        altitudeRef = try c.decodeIfPresent(Double.self, forKey: .altitudeRef)
        altitude = try c.decodeIfPresent(Double.self, forKey: .altitude)
        altitudeAt = try c.decodeIfPresent(Date.self, forKey: .altitudeAt)
        profile = try c.decodeIfPresent([ProfileSample].self, forKey: .profile) ?? []
        profileSpacing = try c.decodeIfPresent(Double.self, forKey: .profileSpacing) ?? TripMetrics.profileSpacingMeters
    }

    /// `true` si hay una pausa en curso.
    public var isPaused: Bool {
        return pausedAt != nil
    }

    /// Segundos en pausa a `now`, incluida la pausa en curso.
    public func pausedSeconds(at now: Date) -> Double {
        guard let since = pausedAt else {
            return pausedSeconds
        }
        let open = now.timeIntervalSince(since)
        return pausedSeconds + ((open.isFinite && open > 0) ? open : 0)
    }

    /// Altitud "antigua" (§E): sin altitud o medida hace más de 300 s.
    public func isAltitudeStale(at now: Date) -> Bool {
        guard altitude != nil, let at = altitudeAt else {
            return true
        }
        return now.timeIntervalSince(at) > TripMetrics.altitudeStaleSeconds
    }

    /// Vista de las métricas del trayecto (§C–F) como `TripMetrics`; al asignar se copian de vuelta.
    public var metrics: TripMetrics {
        get {
            return TripMetrics(
                distanceMeters: distanceMeters,
                movingSeconds: movingSeconds,
                pausedAt: pausedAt,
                pausedSeconds: pausedSeconds,
                ascentMeters: ascentMeters,
                descentMeters: descentMeters,
                altitudeRef: altitudeRef,
                altitude: altitude,
                altitudeAt: altitudeAt,
                lastFix: lastFix,
                profile: profile,
                profileSpacing: profileSpacing
            )
        }
        set {
            distanceMeters = newValue.distanceMeters
            movingSeconds = newValue.movingSeconds
            pausedAt = newValue.pausedAt
            pausedSeconds = newValue.pausedSeconds
            ascentMeters = newValue.ascentMeters
            descentMeters = newValue.descentMeters
            altitudeRef = newValue.altitudeRef
            altitude = newValue.altitude
            altitudeAt = newValue.altitudeAt
            lastFix = newValue.lastFix
            profile = newValue.profile
            profileSpacing = newValue.profileSpacing
        }
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
    /// Duración total `finishedAt − startedAt` (incluye pausas).
    public var activeSeconds: Int
    // MARK: V1.1 (enteros, redondeo half-up)
    public var movingSeconds: Int
    public var pausedSeconds: Int
    public var ascentMeters: Int
    public var descentMeters: Int
    /// Perfil registrado. Sólo local: nunca se envía.
    public var profile: [ProfileSample]

    public var id: String { sessionId }

    public init(
        sessionId: String,
        stageId: String,
        startedAt: Date,
        finishedAt: Date,
        steps: Int,
        distanceMeters: Int,
        activeSeconds: Int,
        movingSeconds: Int = 0,
        pausedSeconds: Int = 0,
        ascentMeters: Int = 0,
        descentMeters: Int = 0,
        profile: [ProfileSample] = []
    ) {
        self.sessionId = sessionId
        self.stageId = stageId
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.steps = steps
        self.distanceMeters = distanceMeters
        self.activeSeconds = activeSeconds
        self.movingSeconds = movingSeconds
        self.pausedSeconds = pausedSeconds
        self.ascentMeters = ascentMeters
        self.descentMeters = descentMeters
        self.profile = profile
    }

    private enum CodingKeys: String, CodingKey {
        case sessionId, stageId, startedAt, finishedAt, steps, distanceMeters, activeSeconds
        case movingSeconds, pausedSeconds, ascentMeters, descentMeters, profile
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        sessionId = try c.decode(String.self, forKey: .sessionId)
        stageId = try c.decode(String.self, forKey: .stageId)
        startedAt = try c.decode(Date.self, forKey: .startedAt)
        finishedAt = try c.decode(Date.self, forKey: .finishedAt)
        steps = try c.decode(Int.self, forKey: .steps)
        distanceMeters = try c.decode(Int.self, forKey: .distanceMeters)
        activeSeconds = try c.decode(Int.self, forKey: .activeSeconds)
        movingSeconds = try c.decodeIfPresent(Int.self, forKey: .movingSeconds) ?? 0
        pausedSeconds = try c.decodeIfPresent(Int.self, forKey: .pausedSeconds) ?? 0
        ascentMeters = try c.decodeIfPresent(Int.self, forKey: .ascentMeters) ?? 0
        descentMeters = try c.decodeIfPresent(Int.self, forKey: .descentMeters) ?? 0
        profile = try c.decodeIfPresent([ProfileSample].self, forKey: .profile) ?? []
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

    /// `true` si hay sesión activa y está en pausa (V1.1 §C).
    public var isPaused: Bool {
        return activeSession?.isPaused ?? false
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
    public var movingSeconds: Int
    public var ascentMeters: Int
    public var descentMeters: Int

    public init(
        stages: Int = 0,
        distanceMeters: Int = 0,
        steps: Int = 0,
        activeSeconds: Int = 0,
        movingSeconds: Int = 0,
        ascentMeters: Int = 0,
        descentMeters: Int = 0
    ) {
        self.stages = stages
        self.distanceMeters = distanceMeters
        self.steps = steps
        self.activeSeconds = activeSeconds
        self.movingSeconds = movingSeconds
        self.ascentMeters = ascentMeters
        self.descentMeters = descentMeters
    }

    public static func of(_ history: History) -> CaminoTotals {
        var totals = CaminoTotals()
        for summary in history {
            totals.stages += 1
            totals.distanceMeters += summary.distanceMeters
            totals.steps += summary.steps
            totals.activeSeconds += summary.activeSeconds
            totals.movingSeconds += summary.movingSeconds
            totals.ascentMeters += summary.ascentMeters
            totals.descentMeters += summary.descentMeters
        }
        return totals
    }
}
