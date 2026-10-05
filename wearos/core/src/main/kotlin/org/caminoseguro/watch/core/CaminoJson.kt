package org.caminoseguro.watch.core

import kotlinx.serialization.builtins.SetSerializer
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

    /** Ajustes: categorías de POI que avisan (V-08). */
    fun encodeCategories(categories: Set<PoiCategory>): String =
        json.encodeToString(SetSerializer(PoiCategory.serializer()), categories)

    fun decodeCategories(text: String): Set<PoiCategory> =
        json.decodeFromString(SetSerializer(PoiCategory.serializer()), text)

    /** Preferencias de presentación (V1.1 §G). */
    fun encodeDisplayPreferences(prefs: DisplayPreferences): String =
        json.encodeToString(DisplayPreferences.serializer(), prefs)

    fun decodeDisplayPreferences(text: String): DisplayPreferences =
        json.decodeFromString(DisplayPreferences.serializer(), text)

    /** Aviso «Accede desde tu esfera» (V1.1 §I). */
    fun encodeFaceHint(state: FaceHintState): String =
        json.encodeToString(FaceHintState.serializer(), state)

    fun decodeFaceHint(text: String): FaceHintState =
        json.decodeFromString(FaceHintState.serializer(), text)

    fun encodeEvent(event: SyncEvent): String =
        json.encodeToString(SyncEvent.serializer(), event)
}
