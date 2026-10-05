package org.caminoseguro.watch.core

import kotlinx.serialization.json.Json

/** Codificación JSON de la persistencia local y de los fixtures. */
object CaminoJson {
    val json: Json = Json {
        ignoreUnknownKeys = true
        encodeDefaults = true
        prettyPrint = false
    }

    fun encodeSession(snapshot: SessionSnapshot): String =
        json.encodeToString(SessionSnapshot.serializer(), snapshot)

    fun decodeSession(text: String): SessionSnapshot =
        json.decodeFromString(SessionSnapshot.serializer(), text)

    fun encodeSyncQueue(state: SyncQueueState): String =
        json.encodeToString(SyncQueueState.serializer(), state)

    fun decodeSyncQueue(text: String): SyncQueueState =
        json.decodeFromString(SyncQueueState.serializer(), text)

    fun encodeStepCounter(state: StepCounterState): String =
        json.encodeToString(StepCounterState.serializer(), state)

    fun decodeStepCounter(text: String): StepCounterState =
        json.decodeFromString(StepCounterState.serializer(), text)

    fun encodeEvent(event: SyncEvent): String =
        json.encodeToString(SyncEvent.serializer(), event)
}
