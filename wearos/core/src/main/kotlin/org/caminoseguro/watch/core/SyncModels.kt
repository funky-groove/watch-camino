package org.caminoseguro.watch.core

import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable

// Sincronización — §7. Privacidad: sólo agregados, nunca posiciones ni traza GPS.

@Serializable
enum class SyncEventType(val wireName: String) {
    @SerialName("stage_started")
    StageStarted("stage_started"),

    @SerialName("stage_finished")
    StageFinished("stage_finished"),
}

@Serializable
sealed interface SyncPayload {
    val stageId: String

    @Serializable
    @SerialName("stage_started")
    data class StageStarted(
        override val stageId: String,
        val startedAt: SerializableInstant,
    ) : SyncPayload

    @Serializable
    @SerialName("stage_finished")
    data class StageFinished(
        override val stageId: String,
        val startedAt: SerializableInstant,
        val finishedAt: SerializableInstant,
        val steps: Int,
        val distanceMeters: Int,
        val activeSeconds: Int,
    ) : SyncPayload
}

@Serializable
data class SyncEvent(
    /** UUID v4: clave de idempotencia. */
    val eventId: String,
    val type: SyncEventType,
    val sessionId: String,
    val occurredAt: SerializableInstant,
    val payload: SyncPayload,
)

sealed interface SendResult {
    data object Accepted : SendResult
    data class Retryable(val reason: String) : SendResult
    data class Permanent(val reason: String) : SendResult
    data object Unauthorized : SendResult
    data object Blocked : SendResult
}

/** Lo que persiste `SyncQueueStore`: cola FIFO, dead-letter y estado de backoff. */
@Serializable
data class SyncQueueState(
    val queue: List<SyncEvent> = emptyList(),
    val deadLetters: List<SyncEvent> = emptyList(),
    val attempt: Int = 0,
    val nextAttemptAt: SerializableInstant? = null,
)

/** Estado de sincronización para la UI. */
sealed interface SyncStatus {
    data object Synced : SyncStatus
    data class Pending(val count: Int) : SyncStatus
    /** Reservado: V1 no tiene monitor de red (no hay permiso INTERNET ni contrato). */
    data object Offline : SyncStatus
    /** `BlockedCaminoApi`: contrato backend pendiente. */
    data object Blocked : SyncStatus
    /** `Unauthorized`: el flujo de vinculación está BLOQUEADO por contrato. */
    data object NeedsLink : SyncStatus
    data object Syncing : SyncStatus
}

data class SyncSnapshot(
    val status: SyncStatus = SyncStatus.Synced,
    val queued: Int = 0,
    val deadLetters: Int = 0,
)
