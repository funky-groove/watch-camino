package org.caminoseguro.watch.core

import kotlin.math.max

/** Acumulador de distancia GPS — §5. Puro y determinista. */
object DistanceAccumulator {
    const val MAX_ACCURACY_M: Double = 50.0
    const val MIN_STEP_M: Double = 10.0
    const val MAX_SPEED_MPS: Double = 4.0

    /**
     * [addedMeters]/[addedSeconds] > 0 sólo cuando el tramo se suma (paso 6); los usa el tiempo en
     * movimiento (V1.1 §D).
     */
    data class Result(
        val distanceMeters: Double,
        val lastFix: LocationFix?,
        val addedMeters: Double = 0.0,
        val addedSeconds: Double = 0.0,
    )

    /**
     * ¿Supera el fix el paso 1 de §5? (también es la puerta del motor POI, §6).
     * Además rechaza fixes inválidos (V-05): coordenadas no finitas o fuera de rango y precisión
     * no finita o negativa. Un NaN envenenaría la distancia y rompería la serialización.
     */
    fun isAccurateEnough(fix: LocationFix): Boolean = isUsable(fix.point, fix.accuracyMeters)

    fun isUsable(point: GeoPoint, accuracyMeters: Double): Boolean =
        isValidPoint(point) && accuracyMeters.isFinite() && accuracyMeters >= 0.0 && accuracyMeters <= MAX_ACCURACY_M

    fun isValidPoint(point: GeoPoint): Boolean =
        point.lat.isFinite() && point.lon.isFinite() && point.lat in -90.0..90.0 && point.lon in -180.0..180.0

    fun apply(distanceMeters: Double, lastFix: LocationFix?, fix: LocationFix): Result {
        // 1. Precisión insuficiente → descartar.
        if (!isAccurateEnough(fix)) return Result(distanceMeters, lastFix)
        // 2. Primer fix → ancla.
        if (lastFix == null) return Result(distanceMeters, fix)
        // 3.
        val d = Geo.haversineMeters(lastFix.point, fix.point)
        val dt = secondsBetween(lastFix.timestamp, fix.timestamp)
        // 4. Ruido: lastFix NO cambia.
        if (d < max(MIN_STEP_M, fix.accuracyMeters)) return Result(distanceMeters, lastFix)
        // 5. Salto / vehículo: reancla sin sumar.
        if (dt <= 0.0 || d / dt > MAX_SPEED_MPS) return Result(distanceMeters, fix)
        // 6.
        return Result(distanceMeters + d, fix, addedMeters = d, addedSeconds = dt)
    }
}
