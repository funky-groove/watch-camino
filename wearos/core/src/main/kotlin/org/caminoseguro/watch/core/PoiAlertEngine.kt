package org.caminoseguro.watch.core

import java.time.Instant

data class PoiAlert(val poi: Poi, val distanceMeters: Double)

data class PoiDistance(val poi: Poi, val distanceMeters: Double)

/** Motor de avisos POI — §6. */
object PoiAlertEngine {
    const val RADIUS_M: Double = 300.0
    const val MIN_INTERVAL_S: Double = 60.0

    /**
     * Devuelve el POI a avisar o `null`. No muta nada: quien llama añade el id a
     * `alertedPoiIds` y fija `lastAlertAt = now`.
     */
    fun evaluate(
        pois: List<Poi>,
        alreadyAlerted: Set<String>,
        lastAlertAt: Instant?,
        now: Instant,
        position: GeoPoint,
        accuracyMeters: Double,
    ): PoiAlert? {
        if (accuracyMeters > DistanceAccumulator.MAX_ACCURACY_M) return null
        val candidates = pois.asSequence()
            .filter { it.id !in alreadyAlerted }
            .map { PoiDistance(it, Geo.haversineMeters(position, it.location)) }
            .filter { it.distanceMeters <= RADIUS_M }
            .toList()
        if (candidates.isEmpty()) return null
        if (lastAlertAt != null && secondsBetween(lastAlertAt, now) < MIN_INTERVAL_S) return null
        val best = candidates.minWith(nearestThenId)
        return PoiAlert(best.poi, best.distanceMeters)
    }

    /** POI no avisado más cercano (sin límite de radio), para la línea "Próximo POI". */
    fun nearestUnalerted(pois: List<Poi>, alreadyAlerted: Set<String>, position: GeoPoint): PoiDistance? =
        pois.asSequence()
            .filter { it.id !in alreadyAlerted }
            .map { PoiDistance(it, Geo.haversineMeters(position, it.location)) }
            .minWithOrNull(nearestThenId)

    private val nearestThenId: Comparator<PoiDistance> =
        compareBy<PoiDistance> { it.distanceMeters }.thenBy { it.poi.id }
}
