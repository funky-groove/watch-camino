package org.caminoseguro.watch.core

import java.time.Instant

// Puertos — §9. Sensores (StepSource, LocationSource) y Notifier viven en la capa app.

interface StageCatalog {
    suspend fun stages(): List<Stage>
}

interface PoiSource {
    suspend fun pois(stageId: String): List<Poi>
}

interface SessionStore {
    suspend fun load(): SessionSnapshot
    suspend fun save(snapshot: SessionSnapshot)

    /**
     * `true` (una sola vez) si la última carga no pudo leer el fichero anterior: el almacén lo apartó
     * como copia y devolvió el estado vacío. La UI debe avisar al usuario (V-03).
     */
    fun takeUnreadableNotice(): Boolean = false
}

interface SyncQueueStore {
    suspend fun load(): SyncQueueState
    suspend fun save(state: SyncQueueState)

    /** Igual que [SessionStore.takeUnreadableNotice]. */
    fun takeUnreadableNotice(): Boolean = false
}

/** Única puerta remota. V1: `BlockedCaminoApi` (Release) y `MockCaminoApi` (Debug). */
interface CaminoApi {
    suspend fun send(event: SyncEvent): SendResult
}

/** Token opaco. Nada lo escribe en V1 (la vinculación está bloqueada por contrato). */
interface CredentialStore {
    fun read(): String?
    fun write(token: String)
    fun clear()
}

interface Clock {
    fun now(): Instant
}

interface IdGenerator {
    /** UUID v4 en texto. */
    fun newId(): String
}

/** Fuente del jitter del backoff: fracción en `[0, 0.20]`. Se inyecta para tests. */
fun interface JitterSource {
    fun nextFraction(): Double
}
