package org.caminoseguro.watch.core

import java.time.Duration
import java.time.Instant
import kotlin.math.asin
import kotlin.math.cos
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.sqrt

object Geo {
    /** Radio terrestre medio (m) — §5. */
    const val EARTH_RADIUS_M: Double = 6_371_008.8

    /** Distancia haversine en metros. */
    fun haversineMeters(a: GeoPoint, b: GeoPoint): Double {
        val p1 = Math.toRadians(a.lat)
        val p2 = Math.toRadians(b.lat)
        val dp = p2 - p1
        val dl = Math.toRadians(b.lon - a.lon)
        val sdp = sin(dp / 2)
        val sdl = sin(dl / 2)
        val h = sdp * sdp + cos(p1) * cos(p2) * sdl * sdl
        return 2 * EARTH_RADIUS_M * asin(min(1.0, sqrt(h)))
    }
}

/** Segundos (con fracción) de [from] a [to]; negativo si [to] es anterior. */
internal fun secondsBetween(from: Instant, to: Instant): Double {
    val d = Duration.between(from, to)
    return d.seconds + d.nano / 1_000_000_000.0
}
