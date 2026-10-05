package org.caminoseguro.watch.core

import kotlin.math.floor
import kotlin.math.max

/**
 * Formato de presentación es-ES — §8. Implementa la regla a mano (no usa formateadores del
 * sistema, que divergen entre plataformas y locales).
 */
object Formatters {

    fun distance(meters: Double): String {
        val m = max(0.0, meters)
        val r = floor(m / 10 + 0.5).toLong() * 10
        if (r < 1000) return "$r m"
        val tenths = floor(m / 100 + 0.5).toLong()
        if (tenths < 100) return "${tenths / 10},${tenths % 10} km"
        return "${floor(m / 1000 + 0.5).toLong()} km"
    }

    fun duration(seconds: Long): String {
        val s = max(0L, seconds)
        if (s < 3600) return "${s / 60} min"
        val h = s / 3600
        val mm = (s % 3600) / 60
        return "$h h ${twoDigits(mm)} min"
    }

    fun steps(steps: Long): String = groupThousands(max(0L, steps))

    fun steps(steps: Int): String = steps(steps.toLong())

    /** `"<icono> <nombre> · <distancia>"` — §6. */
    fun poiAlertText(poi: Poi, distanceMeters: Double): String =
        "${poi.category.icon} ${poi.name} · ${distance(distanceMeters)}"

    // ------------------------------------------------ versiones habladas (TalkBack)

    /** "4,2 kilómetros", "340 metros" — mismas cifras que [distance], unidades en palabras. */
    fun distanceSpoken(meters: Double): String {
        val text = distance(meters)
        return when {
            text.endsWith(" km") -> {
                val n = text.removeSuffix(" km")
                if (n == "1") "1 kilómetro" else "$n kilómetros"
            }
            else -> {
                val n = text.removeSuffix(" m")
                if (n == "1") "1 metro" else "$n metros"
            }
        }
    }

    /** "45 minutos", "1 hora 5 minutos". */
    fun durationSpoken(seconds: Long): String {
        val s = max(0L, seconds)
        val minutes = (s % 3600) / 60
        val hours = s / 3600
        val minText = if (minutes == 1L) "1 minuto" else "$minutes minutos"
        if (hours == 0L) return minText
        val hourText = if (hours == 1L) "1 hora" else "$hours horas"
        return "$hourText $minText"
    }

    /** "1.234 pasos". */
    fun stepsSpoken(steps: Long): String {
        val n = max(0L, steps)
        return if (n == 1L) "1 paso" else "${groupThousands(n)} pasos"
    }

    private fun twoDigits(n: Long): String = if (n < 10) "0$n" else n.toString()

    private fun groupThousands(n: Long): String {
        val digits = n.toString()
        val sb = StringBuilder()
        val firstGroup = digits.length % 3
        for ((i, c) in digits.withIndex()) {
            if (i != 0 && (i - firstGroup) % 3 == 0) sb.append('.')
            sb.append(c)
        }
        return sb.toString()
    }
}
