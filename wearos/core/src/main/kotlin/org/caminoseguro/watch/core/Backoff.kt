package org.caminoseguro.watch.core

import kotlin.math.min

/** Backoff exponencial — §7. */
object Backoff {
    const val BASE_SECONDS: Long = 30
    const val MAX_SECONDS: Long = 1800
    const val MAX_JITTER: Double = 0.20

    /** `min(30 · 2^(attempt−1), 1800)` segundos, sin jitter. `attempt >= 1`. */
    fun baseSeconds(attempt: Int): Long {
        require(attempt >= 1) { "attempt debe ser >= 1" }
        // Evita desbordamiento: a partir de 2^7 ya se supera el tope.
        val exp = min(attempt - 1, 16)
        return min(BASE_SECONDS shl exp, MAX_SECONDS)
    }

    /** Con jitter en `[0, 0.20]` (fracción del valor base), en milisegundos. */
    fun delayMillis(attempt: Int, jitterFraction: Double): Long {
        val j = jitterFraction.coerceIn(0.0, MAX_JITTER)
        return Math.round(baseSeconds(attempt) * 1000.0 * (1.0 + j))
    }
}
