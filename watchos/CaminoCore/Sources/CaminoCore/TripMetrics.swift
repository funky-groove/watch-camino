import Foundation

/// Qué aportó un fix a las métricas del trayecto.
public struct TripFixOutcome: Equatable, Sendable {
    /// Resultado del acumulador de distancia (§5). `.ignoredPaused` si el trayecto está en pausa.
    public let distance: DistanceStepOutcome
    /// Segundos sumados al tiempo en movimiento (§D).
    public let movingSecondsAdded: Double
    /// `true` si el fix aportó una altitud válida (§E).
    public let altitudeAccepted: Bool
    /// `true` si se añadió una muestra al perfil (§F).
    public let profileSampleAdded: Bool

    public init(
        distance: DistanceStepOutcome,
        movingSecondsAdded: Double = 0,
        altitudeAccepted: Bool = false,
        profileSampleAdded: Bool = false
    ) {
        self.distance = distance
        self.movingSecondsAdded = movingSecondsAdded
        self.altitudeAccepted = altitudeAccepted
        self.profileSampleAdded = profileSampleAdded
    }

    /// `true` si cambió algo del estado (conviene persistir).
    public var changedMetrics: Bool {
        return distance.movedAnchor || altitudeAccepted
    }
}

/// Métricas del trayecto — V1.1 §C (pausa), §D (tiempo en movimiento),
/// §E (altitud y desnivel) y §F (perfil registrado).
///
/// Pura y paso a paso: reproduce exactamente `trip_metrics` de
/// `shared/conformance/reference.py`. La usa `StageSessionMachine` a través de
/// `StageSession.metrics`.
public struct TripMetrics: Equatable, Sendable {
    public static let minMovingSpeedMetersPerSecond: Double = 0.5
    public static let maxVerticalAccuracyMeters: Double = 15.0
    public static let altitudeHysteresisMeters: Double = 3.0
    public static let profileSpacingMeters: Double = 50.0
    public static let profileGapMeters: Double = 200.0
    public static let defaultProfileCap: Int = 500
    /// Altitud "antigua" si `now − altitudeAt` supera esto (§E).
    public static let altitudeStaleSeconds: Double = 300.0

    public var distanceMeters: Double
    public var movingSeconds: Double
    public var pausedAt: Date?
    public var pausedSeconds: Double
    public var ascentMeters: Double
    public var descentMeters: Double
    public var altitudeRef: Double?
    public var altitude: Double?
    public var altitudeAt: Date?
    /// Ancla del acumulador de distancia.
    public var lastFix: LocationFix?
    public var profile: [ProfileSample]
    public var profileSpacing: Double
    /// Máximo de muestras del perfil antes de recortar a la mitad.
    public var profileCap: Int

    public init(
        distanceMeters: Double = 0,
        movingSeconds: Double = 0,
        pausedAt: Date? = nil,
        pausedSeconds: Double = 0,
        ascentMeters: Double = 0,
        descentMeters: Double = 0,
        altitudeRef: Double? = nil,
        altitude: Double? = nil,
        altitudeAt: Date? = nil,
        lastFix: LocationFix? = nil,
        profile: [ProfileSample] = [],
        profileSpacing: Double = TripMetrics.profileSpacingMeters,
        profileCap: Int = TripMetrics.defaultProfileCap
    ) {
        self.distanceMeters = distanceMeters
        self.movingSeconds = movingSeconds
        self.pausedAt = pausedAt
        self.pausedSeconds = pausedSeconds
        self.ascentMeters = ascentMeters
        self.descentMeters = descentMeters
        self.altitudeRef = altitudeRef
        self.altitude = altitude
        self.altitudeAt = altitudeAt
        self.lastFix = lastFix
        self.profile = profile
        self.profileSpacing = profileSpacing
        self.profileCap = profileCap
    }

    public var isPaused: Bool {
        return pausedAt != nil
    }

    /// En marcha → Pausado. `lastFix = nil` y `altitudeRef = nil` para que ni el tramo ni el
    /// desnivel recorridos en pausa se cuenten al reanudar (V1.1 §C).
    public mutating func pause(at now: Date) throws {
        if pausedAt != nil {
            throw SessionError.alreadyPaused
        }
        pausedAt = now
        lastFix = nil
        altitudeRef = nil
    }

    /// Pausado → En marcha. `pausedSeconds += max(0, now − pausedAt)`.
    public mutating func resume(at now: Date) throws {
        guard pausedAt != nil else {
            throw SessionError.notPaused
        }
        closePause(at: now)
    }

    /// Cierra la pausa en curso (si la hay) sumando su duración. Usado por `resume` y `finish`.
    public mutating func closePause(at now: Date) {
        guard let since = pausedAt else {
            return
        }
        let elapsed = now.timeIntervalSince(since)
        if elapsed.isFinite && elapsed > 0 {
            pausedSeconds += elapsed
        }
        pausedAt = nil
    }

    /// Procesa un fix: distancia (§5), tiempo en movimiento (§D), altitud (§E) y perfil (§F).
    /// En pausa o con precisión > 50 m no cambia nada.
    @discardableResult
    public mutating func add(_ fix: LocationFix) -> TripFixOutcome {
        if pausedAt != nil {
            return TripFixOutcome(distance: .ignoredPaused)
        }
        guard DistanceAccumulator.isAccurateEnough(fix) else {
            return TripFixOutcome(distance: .rejectedAccuracy)
        }

        // Distancia y tiempo en movimiento.
        let previous = lastFix
        var accumulator = DistanceAccumulator(distanceMeters: distanceMeters, lastFix: lastFix)
        let outcome = accumulator.add(fix)
        distanceMeters = accumulator.distanceMeters
        lastFix = accumulator.lastFix
        var movingAdded: Double = 0
        if case .added(let d) = outcome, let previous = previous {
            let dt = fix.timestamp.timeIntervalSince(previous.timestamp)
            if d / dt >= TripMetrics.minMovingSpeedMetersPerSecond {
                movingAdded = dt
                movingSeconds += dt
            }
        }

        // Altitud.
        guard let alt = fix.altitudeMeters, alt.isFinite,
              let vacc = fix.verticalAccuracyMeters,
              vacc >= 0, vacc <= TripMetrics.maxVerticalAccuracyMeters else {
            return TripFixOutcome(distance: outcome, movingSecondsAdded: movingAdded)
        }
        altitude = alt
        altitudeAt = fix.timestamp
        if let ref = altitudeRef {
            let diff = alt - ref
            if diff >= TripMetrics.altitudeHysteresisMeters {
                ascentMeters += diff
                altitudeRef = alt
            } else if diff <= -TripMetrics.altitudeHysteresisMeters {
                descentMeters += -diff
                altitudeRef = alt
            }
        } else {
            altitudeRef = alt
        }

        // Perfil.
        let added = appendProfileSample(alt: alt)
        return TripFixOutcome(
            distance: outcome,
            movingSecondsAdded: movingAdded,
            altitudeAccepted: true,
            profileSampleAdded: added
        )
    }

    private mutating func appendProfileSample(alt: Double) -> Bool {
        let dist = distanceMeters
        if let last = profile.last, dist - last.d < profileSpacing {
            return false
        }
        let gap: Bool
        if let last = profile.last {
            // El umbral crece con el espaciado (§F): tras recortar, dos muestras seguidas pueden
            // estar a `spacing` sin que falten datos.
            gap = dist - last.d > max(TripMetrics.profileGapMeters, 2 * profileSpacing)
        } else {
            gap = false
        }
        profile.append(ProfileSample(d: dist, alt: alt, gapBefore: gap))
        if profile.count > max(1, profileCap) {
            var kept: [ProfileSample] = []
            kept.reserveCapacity(profile.count / 2 + 1)
            var pendingGap = false
            for (index, sample) in profile.enumerated() {
                if index % 2 == 0 {
                    var copy = sample
                    copy.gapBefore = copy.gapBefore || pendingGap
                    pendingGap = false
                    kept.append(copy)
                } else {
                    pendingGap = pendingGap || sample.gapBefore
                }
            }
            profile = kept
            profileSpacing *= 2
        }
        return true
    }
}
