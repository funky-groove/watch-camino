package org.caminoseguro.watch.demo

import org.caminoseguro.watch.core.Clock
import org.caminoseguro.watch.core.Geo
import org.caminoseguro.watch.core.GeoPoint
import org.caminoseguro.watch.core.LocationFix
import java.time.Instant
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.sin

/**
 * DATOS DE DEMOSTRACIÓN para capturas (SÓLO Debug). Mismas cifras que el escenario watchOS
 * (`watchos/CaminoWatch/DemoScenario.swift`), derivadas de `shared/fixtures`:
 *
 * - Trayecto activo: Sarria → hacia p01 (Fuente de Barbadelo), 65 min, 5 230 pasos. Interpolado
 *   cada ≤ 50 m da ≈ 4 165 m acumulados con el acumulador de §5 y termina a ≈ 330 m de p01 (fuera
 *   del radio de aviso de 300 m). Altitud sintética 445 → ≈ 535 m (subida a Barbadelo).
 * - Finalizado: etapa Sarria – Portomarín completa (≈ 19,6 km interpolando cada ≤ 100 m),
 *   29 840 pasos, empezó hace 26 h y duró 5 h 30 min.
 * - Cerca: Palas de Rei → Melide (etapa cf-palas-arzua), 3 h, ≈ 12,6 km; termina a ≈ 200 m de p07.
 *
 * Las altitudes son SINTÉTICAS (aproximadas, suaves) para que el perfil y el desnivel no salgan vacíos.
 */
internal object DemoData {
    const val ACTIVE_STAGE_ID = "cf-sarria-portomarin"
    const val NEARBY_STAGE_ID = "cf-palas-arzua"

    const val ACTIVE_STEPS = 5_230
    const val ACTIVE_ELAPSED_SECONDS = 65L * 60
    /** El escenario «paused» entra en pausa 30 s antes de «ahora» (tras el último fix). */
    const val PAUSED_SINCE_SECONDS = 30L

    const val FINISHED_STEPS = 29_840
    const val FINISHED_START_OFFSET_SECONDS = -26L * 3600
    const val FINISHED_DURATION_SECONDS = 5L * 3600 + 30 * 60

    const val NEARBY_STEPS = 16_420
    const val NEARBY_ELAPSED_SECONDS = 3L * 3600

    /** Precisión horizontal de todos los fixes (≤ 50 m: pasa el paso 1 de §5). */
    const val ACCURACY_M = 8.0
    /** Precisión vertical (≤ 15 m: la altitud cuenta, V1.1 §E). */
    const val VERTICAL_ACCURACY_M = 6.0

    val activeWaypoints = listOf(
        GeoPoint(42.7808, -7.4141), // Sarria (inicio de etapa)
        GeoPoint(42.7850, -7.4255),
        GeoPoint(42.7750, -7.4335),
        GeoPoint(42.7775, -7.4440),
        GeoPoint(42.77109, -7.45139), // ≈ 330 m de p01
    )

    val finishedWaypoints = listOf(
        GeoPoint(42.7808, -7.4141),
        GeoPoint(42.7850, -7.4255),
        GeoPoint(42.7750, -7.4335),
        GeoPoint(42.7701, -7.4552), // p01
        GeoPoint(42.7640, -7.4800),
        GeoPoint(42.7790, -7.5050),
        GeoPoint(42.7720, -7.5300),
        GeoPoint(42.7835, -7.5536), // p02
        GeoPoint(42.7880, -7.5800),
        GeoPoint(42.7990, -7.5850),
        GeoPoint(42.8070, -7.6150), // p03
        GeoPoint(42.8075, -7.6156), // Portomarín (fin)
    )

    val nearbyWaypoints = listOf(
        GeoPoint(42.8733, -7.8686), // Palas de Rei (inicio de etapa)
        GeoPoint(42.8800, -7.9200),
        GeoPoint(42.9000, -7.9700),
        GeoPoint(42.9100, -8.0000),
        GeoPoint(42.9132, -8.0118), // Melide, ≈ 200 m de p07
    )

    /** Altitud sintética según la fracción recorrida [0, 1]. */
    fun activeAltitude(f: Double): Double = 445.0 + 90.0 * f + 6.0 * sin(6 * PI * f)

    fun finishedAltitude(f: Double): Double {
        val base = if (f < 0.55) 450.0 + 210.0 * (f / 0.55) else 660.0 - 270.0 * ((f - 0.55) / 0.45)
        return base + 8.0 * sin(10 * PI * f)
    }

    fun nearbyAltitude(f: Double): Double = 565.0 - 110.0 * f + 10.0 * sin(5 * PI * f)

    /** Puntos equiespaciados por tramo, con ≤ [maxStepMeters] entre vecinos (incluye todos los waypoints). */
    fun interpolate(waypoints: List<GeoPoint>, maxStepMeters: Double): List<GeoPoint> {
        if (waypoints.isEmpty()) return emptyList()
        val points = ArrayList<GeoPoint>()
        points += waypoints.first()
        for (i in 1 until waypoints.size) {
            val a = waypoints[i - 1]
            val b = waypoints[i]
            val parts = max(1, ceil(Geo.haversineMeters(a, b) / maxStepMeters).toInt())
            for (part in 1..parts) {
                val t = part.toDouble() / parts
                points += GeoPoint(a.lat + (b.lat - a.lat) * t, a.lon + (b.lon - a.lon) * t)
            }
        }
        return points
    }

    /** Fixes con marcas de tiempo repartidas uniformemente entre [first] y [last], con altitud. */
    fun fixes(
        points: List<GeoPoint>,
        first: Instant,
        last: Instant,
        altitude: (Double) -> Double,
    ): List<LocationFix> {
        val count = points.size
        val spanMillis = last.toEpochMilli() - first.toEpochMilli()
        return points.mapIndexed { index, point ->
            val fraction = if (count > 1) index.toDouble() / (count - 1) else 1.0
            LocationFix(
                point = point,
                accuracyMeters = ACCURACY_M,
                timestamp = first.plusMillis((spanMillis * fraction).toLong()),
                altitudeMeters = altitude(fraction),
                verticalAccuracyMeters = VERTICAL_ACCURACY_M,
            )
        }
    }
}

/** Reloj de pared desplazable: permite «empezar» la etapa en el pasado sin tocar el reloj del sistema. */
internal class DemoOffsetClock : Clock {
    @Volatile var offsetSeconds: Long = 0

    override fun now(): Instant = Instant.now().plusSeconds(offsetSeconds)
}
