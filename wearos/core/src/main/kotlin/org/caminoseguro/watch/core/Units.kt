package org.caminoseguro.watch.core

import kotlinx.serialization.Serializable
import kotlin.math.floor
import kotlin.math.max

// Unidades e idioma — V1.1 §G. Reglas exactas de `reference.py` (fmt_distance_u, fmt_elevation,
// fmt_steps_l, pace_text, speed_text). Implementadas a mano: nada de formateadores del sistema.

@Suppress("EnumEntryName")
@Serializable
enum class UnitSystem { metric, imperial }

@Suppress("EnumEntryName")
@Serializable
enum class PaceMode { pace, speed }

@Suppress("EnumEntryName")
@Serializable
enum class AppLanguage {
    es, en;

    /** Separador decimal (es `,`, en `.`). */
    val decimalSeparator: Char get() = if (this == es) ',' else '.'

    /** Separador de miles (es `.`, en `,`). */
    val groupingSeparator: Char get() = if (this == es) '.' else ','
}

object UnitFormatter {
    const val METERS_PER_MILE: Double = 1609.344
    const val FEET_PER_METER: Double = 3.28084
    const val MPS_TO_KMH: Double = 3.6
    const val MPS_TO_MPH: Double = 2.2369362920544

    /** Sin dato por debajo de esto (§G): nunca se muestra 0. */
    const val MIN_DISTANCE_M: Double = 100.0
    const val MIN_MOVING_S: Double = 60.0
    private const val MAX_PACE_S: Long = 99 * 60 + 59

    /** "4,2 km" / "4.2 km" / "2.6 mi" / "530 ft". */
    fun distance(meters: Double, units: UnitSystem, lang: AppLanguage): String {
        val m = if (meters.isNaN()) 0.0 else max(0.0, meters)
        if (units == UnitSystem.metric) return Formatters.distance(m).replace(',', lang.decimalSeparator)
        val mi = m / METERS_PER_MILE
        if (mi < 0.1) return "${floor(m * FEET_PER_METER / 10 + 0.5).toLong() * 10} ft"
        val tenths = floor(mi * 10 + 0.5).toLong()
        if (tenths < 100) return "${tenths / 10}${lang.decimalSeparator}${tenths % 10} mi"
        return "${floor(mi + 0.5).toLong()} mi"
    }

    /** Altitud o desnivel: entero, redondeo half-away-from-zero, sin separador de miles. */
    fun elevation(meters: Double, units: UnitSystem): String {
        val v = if (units == UnitSystem.metric) meters else meters * FEET_PER_METER
        val n = if (v >= 0) floor(v + 0.5).toLong() else -floor(-v + 0.5).toLong()
        return "$n ${if (units == UnitSystem.metric) "m" else "ft"}"
    }

    fun steps(n: Long, lang: AppLanguage): String = group(max(0L, n), lang.groupingSeparator)

    fun steps(n: Int, lang: AppLanguage): String = steps(n.toLong(), lang)

    /** "12:30 /km" / "20:07 /mi"; null = sin datos (< 100 m, < 60 s o > 99:59). */
    fun pace(distanceM: Double, movingS: Double, units: UnitSystem): String? {
        if (!hasData(distanceM, movingS)) return null
        val unitM = if (units == UnitSystem.metric) 1000.0 else METERS_PER_MILE
        val total = floor(movingS / (distanceM / unitM) + 0.5)
        if (!total.isFinite() || total > MAX_PACE_S) return null
        val t = total.toLong()
        val ss = t % 60
        return "${t / 60}:${if (ss < 10) "0$ss" else "$ss"} /${if (units == UnitSystem.metric) "km" else "mi"}"
    }

    /** "4,8 km/h" / "3.0 mph"; null = sin datos (< 100 m o < 60 s). */
    fun speed(distanceM: Double, movingS: Double, units: UnitSystem, lang: AppLanguage): String? {
        if (!hasData(distanceM, movingS)) return null
        val v = distanceM / movingS * (if (units == UnitSystem.metric) MPS_TO_KMH else MPS_TO_MPH)
        val tenths = floor(v * 10 + 0.5).toLong()
        return "${tenths / 10}${lang.decimalSeparator}${tenths % 10} ${if (units == UnitSystem.metric) "km/h" else "mph"}"
    }

    /** Ritmo o velocidad según la preferencia. */
    fun paceOrSpeed(distanceM: Double, movingS: Double, units: UnitSystem, mode: PaceMode, lang: AppLanguage): String? =
        if (mode == PaceMode.pace) pace(distanceM, movingS, units) else speed(distanceM, movingS, units, lang)

    private fun hasData(distanceM: Double, movingS: Double): Boolean =
        distanceM.isFinite() && movingS.isFinite() && distanceM >= MIN_DISTANCE_M && movingS >= MIN_MOVING_S

    private fun group(n: Long, sep: Char): String {
        val digits = n.toString()
        val sb = StringBuilder()
        val firstGroup = digits.length % 3
        for ((i, c) in digits.withIndex()) {
            if (i != 0 && (i - firstGroup) % 3 == 0) sb.append(sep)
            sb.append(c)
        }
        return sb.toString()
    }
}
