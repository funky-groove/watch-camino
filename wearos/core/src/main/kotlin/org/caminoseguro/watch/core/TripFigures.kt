package org.caminoseguro.watch.core

import java.time.Instant

/**
 * Cifras del trayecto en curso para la pantalla principal, SIN ceros falsos: una cifra que el reloj
 * no puede medir (sin permiso o sin sensor, y sin nada medido antes) es `null` y la UI dice
 * "sin datos" en vez de "0". Reutiliza [CaminoStats] y [StageMachine].
 */
data class TripFigures(
    /** `null` si no se conoce la etapa o no se puede medir la distancia. */
    val remainingMeters: Double?,
    /** `null` si no hay ubicación y no se ha medido nada todavía. */
    val walkedMeters: Double?,
    /** `null` si no hay sensor/permiso de pasos y no se ha contado nada todavía. */
    val steps: Int?,
    /** El tiempo siempre se conoce (reloj del sistema). */
    val elapsedSeconds: Long,
) {
    companion object {
        fun of(
            session: StageSession,
            stage: Stage?,
            now: Instant,
            locationAvailable: Boolean,
            stepsAvailable: Boolean,
        ): TripFigures {
            // Lo ya medido es real aunque luego se retire el permiso: se conserva.
            val walked = if (locationAvailable || session.distanceMeters > 0.0) session.distanceMeters else null
            val steps = if (stepsAvailable || session.steps > 0) session.steps else null
            val remaining = if (stage != null && walked != null) CaminoStats.remainingMeters(stage, session) else null
            return TripFigures(
                remainingMeters = remaining,
                walkedMeters = walked,
                steps = steps,
                elapsedSeconds = StageMachine.activeSeconds(session.startedAt, now).toLong(),
            )
        }
    }
}

/**
 * Evita el doble inicio de un flujo (p. ej. dos toques rápidos en «Iniciar trayecto»): el primer
 * [tryEnter] gana; los siguientes devuelven `false` hasta [reset].
 */
class ActionGate {
    @Volatile
    private var busy = false

    val isBusy: Boolean get() = busy

    @Synchronized
    fun tryEnter(): Boolean {
        if (busy) return false
        busy = true
        return true
    }

    @Synchronized
    fun reset() {
        busy = false
    }
}
