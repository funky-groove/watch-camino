package org.caminoseguro.watch.core

import kotlinx.serialization.KSerializer
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.descriptors.PrimitiveKind
import kotlinx.serialization.descriptors.PrimitiveSerialDescriptor
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.encoding.Decoder
import kotlinx.serialization.encoding.Encoder
import java.time.Instant

// Modelo de dominio — docs/WATCH_V1_SPEC.md §3. Los nombres coinciden con el núcleo Swift.

/** Serializa [Instant] como texto ISO-8601 (sin pérdida de precisión). */
object InstantIso8601Serializer : KSerializer<Instant> {
    override val descriptor: SerialDescriptor =
        PrimitiveSerialDescriptor("org.caminoseguro.watch.core.Instant", PrimitiveKind.STRING)

    override fun serialize(encoder: Encoder, value: Instant) = encoder.encodeString(value.toString())

    override fun deserialize(decoder: Decoder): Instant = Instant.parse(decoder.decodeString())
}

typealias SerializableInstant = @Serializable(with = InstantIso8601Serializer::class) Instant

@Serializable
data class GeoPoint(val lat: Double, val lon: Double)

@Serializable
data class Stage(
    val id: String,
    val name: String,
    val from: String,
    val to: String,
    val distanceMeters: Int,
    val start: GeoPoint,
    val end: GeoPoint,
)

/** Categorías de POI. Los nombres de las constantes son los de la spec (y los del JSON). */
@Suppress("EnumEntryName")
@Serializable
enum class PoiCategory(val icon: String) {
    water("💧"),
    shelter("🛏"),
    pharmacy("➕"),
    health("🏥"),
    food("🍽"),
    landmark("⛪"),
}

@Serializable
data class Poi(
    val id: String,
    val stageId: String,
    val name: String,
    val category: PoiCategory,
    val location: GeoPoint,
)

@Serializable
data class LocationFix(
    val point: GeoPoint,
    val accuracyMeters: Double,
    val timestamp: SerializableInstant,
)

@Serializable
data class StageSession(
    /** UUID v4 generado en el reloj. */
    val sessionId: String,
    val stageId: String,
    val startedAt: SerializableInstant,
    val steps: Int = 0,
    val distanceMeters: Double = 0.0,
    /** Ancla del acumulador de distancia (§5). Sólo se persiste en local; nunca se envía. */
    val lastFix: LocationFix? = null,
    val alertedPoiIds: Set<String> = emptySet(),
    val lastAlertAt: SerializableInstant? = null,
)

@Serializable
data class SessionSummary(
    val sessionId: String,
    val stageId: String,
    val startedAt: SerializableInstant,
    val finishedAt: SerializableInstant,
    val steps: Int,
    /** Redondeado al metro. */
    val distanceMeters: Int,
    val activeSeconds: Int,
)

@Serializable
sealed interface SessionState {
    @Serializable
    @SerialName("idle")
    data object Idle : SessionState

    @Serializable
    @SerialName("active")
    data class Active(val session: StageSession) : SessionState
}

/**
 * Lo que persiste `SessionStore`: estado + historial.
 * [history] va ordenado del más reciente al más antiguo.
 */
@Serializable
data class SessionSnapshot(
    val state: SessionState = SessionState.Idle,
    val history: List<SessionSummary> = emptyList(),
) {
    val activeSession: StageSession? get() = (state as? SessionState.Active)?.session
}
