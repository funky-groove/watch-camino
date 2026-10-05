package org.caminoseguro.watch.core

import kotlin.math.max

/** Acumulador de distancia GPS — §5. Puro y determinista. */
object DistanceAccumulator {
    const val MAX_ACCURACY_M: Double = 50.0
    const val MIN_STEP_M: Double = 10.0
    const val MAX_SPEED_MPS: Double = 4.0

    data class Result(val distanceMeters: Double, val lastFix: LocationFix?)

    /** ¿Supera el fix el paso 1 de §5? (también es la puerta del motor POI, §6). */
    fun isAccurateEnough(fix: LocationFix): Boolean = fix.accuracyMeters <= MAX_ACCURACY_M

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
        return Result(distanceMeters + d, fix)
    }
}
