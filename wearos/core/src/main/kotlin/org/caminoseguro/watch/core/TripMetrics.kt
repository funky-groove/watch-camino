package org.caminoseguro.watch.core

import java.time.Instant
import kotlin.math.floor

/**
 * Métricas del trayecto — V1.1 §C (pausa), §D (tiempo en movimiento), §E (altitud y desnivel) y
 * §F (perfil registrado). Pura y determinista; idéntica a `reference.py::trip_metrics`.
 * Opera sobre [StageSession]; la máquina de estados ([StageMachine]) la usa.
 */
object TripMetrics {
    const val MIN_MOVING_SPEED_MPS: Double = 0.5
    const val MAX_VERTICAL_ACCURACY_M: Double = 15.0
    const val ALTITUDE_HYSTERESIS_M: Double = 3.0
    const val PROFILE_SPACING_M: Double = 50.0
    const val PROFILE_GAP_M: Double = 200.0
    const val PROFILE_CAP: Int = 500

    /** Altitud "antigua" si `now − altitudeAt > 300 s`. */
    const val ALTITUDE_STALE_S: Double = 300.0

    /**
     * → Pausado (`pausedAt = now`, `lastFix = null`, `altitudeRef = null`): ni el tramo ni el desnivel
     * recorridos en pausa se cuentan al reanudar. Null si ya estaba en pausa (`alreadyPaused`).
     */
    fun pause(session: StageSession, now: Instant): StageSession? {
        if (session.isPaused) return null
        return session.copy(pausedAt = now, lastFix = null, altitudeRef = null)
    }

    /** → En marcha (`pausedSeconds += max(0, now − pausedAt)`). Null si no estaba en pausa (`notPaused`). */
    fun resume(session: StageSession, now: Instant): StageSession? {
        if (!session.isPaused) return null
        return closePause(session, now)
    }

    /** Cierra la pausa en curso, si la hay (también al finalizar). */
    fun closePause(session: StageSession, now: Instant): StageSession {
        if (session.pausedAt == null) return session
        return session.copy(pausedAt = null, pausedSeconds = session.pausedSecondsAt(now))
    }

    /** ¿Aporta altitud el fix? (`0 ≤ vacc ≤ 15`, valores finitos). No comprueba §5 paso 1. */
    fun hasUsableAltitude(fix: LocationFix): Boolean {
        val alt = fix.altitudeMeters ?: return false
        val vacc = fix.verticalAccuracyMeters ?: return false
        return alt.isFinite() && vacc.isFinite() && vacc >= 0.0 && vacc <= MAX_VERTICAL_ACCURACY_M
    }

    /**
     * Aplica un fix: distancia (§5), tiempo en movimiento, altitud/desnivel y perfil.
     * En pausa o con precisión insuficiente no cambia nada.
     */
    fun applyFix(session: StageSession, fix: LocationFix, profileCap: Int = PROFILE_CAP): StageSession {
        if (session.isPaused || !DistanceAccumulator.isAccurateEnough(fix)) return session
        val acc = DistanceAccumulator.apply(session.distanceMeters, session.lastFix, fix)
        var moving = session.movingSeconds
        if (acc.addedSeconds > 0.0 && acc.addedMeters / acc.addedSeconds >= MIN_MOVING_SPEED_MPS) {
            moving += acc.addedSeconds
        }
        var next = session.copy(distanceMeters = acc.distanceMeters, lastFix = acc.lastFix, movingSeconds = moving)
        if (!hasUsableAltitude(fix)) return next

        // §E: histéresis de 3 m.
        val alt = fix.altitudeMeters!!
        var ref = next.altitudeRef
        var ascent = next.ascentMeters
        var descent = next.descentMeters
        if (ref == null) {
            ref = alt
        } else {
            val diff = alt - ref
            if (diff >= ALTITUDE_HYSTERESIS_M) {
                ascent += diff
                ref = alt
            } else if (diff <= -ALTITUDE_HYSTERESIS_M) {
                descent += -diff
                ref = alt
            }
        }
        next = next.copy(
            altitude = alt,
            altitudeAt = fix.timestamp,
            altitudeRef = ref,
            ascentMeters = ascent,
            descentMeters = descent,
        )

        // §F: perfil.
        val (profile, spacing) = appendProfile(next.profile, next.profileSpacing, next.distanceMeters, alt, profileCap)
        return next.copy(profile = profile, profileSpacing = spacing)
    }

    /**
     * Añade `{d, alt}` si el perfil está vacío o `d − último.d ≥ spacing`. Si supera [cap] muestras
     * conserva las de índice par (el `gapBefore` de una descartada pasa a la siguiente conservada) y
     * duplica el espaciado.
     */
    fun appendProfile(
        profile: List<ProfileSample>,
        spacing: Double,
        distance: Double,
        alt: Double,
        cap: Int = PROFILE_CAP,
    ): Pair<List<ProfileSample>, Double> {
        val last = profile.lastOrNull()
        if (last != null && distance - last.d < spacing) return profile to spacing
        // El umbral crece con el espaciado: tras recortar, dos muestras seguidas pueden distar
        // `spacing` sin que falten datos (§F: `> max(200 m, 2·spacing)`).
        val gap = last != null && distance - last.d > maxOf(PROFILE_GAP_M, 2 * spacing)
        val grown = profile + ProfileSample(d = distance, alt = alt, gapBefore = gap)
        if (grown.size <= cap) return grown to spacing
        val kept = ArrayList<ProfileSample>(grown.size / 2 + 1)
        var pendingGap = false
        for ((j, s) in grown.withIndex()) {
            if (j % 2 == 0) {
                kept += s.copy(gapBefore = s.gapBefore || pendingGap)
                pendingGap = false
            } else {
                pendingGap = pendingGap || s.gapBefore
            }
        }
        return kept to spacing * 2
    }
}

/** Redondeo half-up a entero (los valores son ≥ 0 en la práctica; negativos → 0). */
internal fun halfUp(x: Double): Int {
    if (!x.isFinite() || x <= 0.0) return 0
    return floor(x + 0.5).coerceAtMost(Int.MAX_VALUE.toDouble()).toInt()
}
