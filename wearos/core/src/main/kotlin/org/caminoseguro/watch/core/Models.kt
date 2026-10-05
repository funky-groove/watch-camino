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
import kotlin.math.max

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
    /** Teléfono del lugar (V1.1 §J). Sólo se ofrece «Llamar» si [PhoneNumber.isValid]. */
    val phone: String? = null,
) {
    /** `tel:` normalizado si [phone] es válido; null si no hay teléfono utilizable. */
    fun telUri(): String? = phone?.let(PhoneNumber::telUri)
}

@Serializable
data class LocationFix(
    val point: GeoPoint,
    val accuracyMeters: Double,
    val timestamp: SerializableInstant,
    /** Altitud GPS (m) — V1.1 §E. Null si el sistema no la da. */
    val altitudeMeters: Double? = null,
    /** Precisión vertical (m); la altitud sólo cuenta si `0 ≤ vacc ≤ 15`. */
    val verticalAccuracyMeters: Double? = null,
)

/** Muestra del perfil registrado (V1.1 §F): distancia recorrida, altitud y si hay hueco antes. */
@Serializable
data class ProfileSample(
    val d: Double,
    val alt: Double,
    val gapBefore: Boolean = false,
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
    // ---- V1.1 (valores por defecto: se lee el estado guardado por V1) ----
    /** Inicio de la pausa en curso; null = en marcha (§C). */
    val pausedAt: SerializableInstant? = null,
    /** Segundos en pausa ya cerrados (sin contar la pausa en curso). */
    val pausedSeconds: Double = 0.0,
    /** Tiempo en movimiento (§D). */
    val movingSeconds: Double = 0.0,
    val ascentMeters: Double = 0.0,
    val descentMeters: Double = 0.0,
    /** Referencia de la histéresis de desnivel (§E). */
    val altitudeRef: Double? = null,
    /** Última altitud válida y cuándo se obtuvo (antigua si `now − altitudeAt > 300 s`). */
    val altitude: Double? = null,
    val altitudeAt: SerializableInstant? = null,
    /** Perfil registrado (§F). Sólo local; nunca se envía. */
    val profile: List<ProfileSample> = emptyList(),
    val profileSpacing: Double = TripMetrics.PROFILE_SPACING_M,
) {
    val isPaused: Boolean get() = pausedAt != null

    /** Segundos en pausa incluyendo la pausa en curso hasta [now]. */
    fun pausedSecondsAt(now: Instant): Double =
        pausedSeconds + (pausedAt?.let { max(0.0, secondsBetween(it, now)) } ?: 0.0)

    /** ¿La altitud es antigua (o no hay)? — §E. */
    fun isAltitudeStale(now: Instant): Boolean =
        altitudeAt?.let { secondsBetween(it, now) > TripMetrics.ALTITUDE_STALE_S } ?: true
}

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
    // ---- V1.1 (enteros, half-up; por defecto 0 para el historial V1) ----
    val movingSeconds: Int = 0,
    val pausedSeconds: Int = 0,
    val ascentMeters: Int = 0,
    val descentMeters: Int = 0,
    /** Perfil registrado (sólo local; nunca va en el payload). */
    val profile: List<ProfileSample> = emptyList(),
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
