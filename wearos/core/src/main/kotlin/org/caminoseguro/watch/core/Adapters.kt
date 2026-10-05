package org.caminoseguro.watch.core

import kotlinx.coroutines.delay
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import java.time.Instant
import java.util.UUID
import java.util.concurrent.atomic.AtomicLong
import kotlin.random.Random

// ------------------------------------------------------------------ CaminoApi

/** Adaptador de Release: el contrato backend no existe, así que nunca se envía nada. */
class BlockedCaminoApi : CaminoApi {
    override suspend fun send(event: SyncEvent): SendResult = SendResult.Blocked
}

/** Sólo Debug. Acepta todo tras una latencia simulada. La UI debe mostrar `DEMO`. */
class MockCaminoApi(private val latencyMillis: Long = 600) : CaminoApi {
    override suspend fun send(event: SyncEvent): SendResult {
        if (latencyMillis > 0) delay(latencyMillis)
        return SendResult.Accepted
    }
}

// ------------------------------------------------------------------ Fixtures

@Serializable
private data class StagesFile(val stages: List<Stage>)

@Serializable
private data class PoisFile(val pois: List<Poi>)

/** Catálogo a partir del JSON con el formato de `shared/fixtures/stages.json`. DATOS DE DEMOSTRACIÓN. */
class FixtureStageCatalog(json: String) : StageCatalog {
    private val stages: List<Stage> = CaminoJson.json.decodeFromString(StagesFile.serializer(), json).stages

    override suspend fun stages(): List<Stage> = stages
}

/** POIs a partir del JSON con el formato de `shared/fixtures/pois.json`. DATOS DE DEMOSTRACIÓN. */
class FixturePoiSource(json: String) : PoiSource {
    private val all: List<Poi> = CaminoJson.json.decodeFromString(PoisFile.serializer(), json).pois

    fun allPois(): List<Poi> = all

    override suspend fun pois(stageId: String): List<Poi> = all.filter { it.stageId == stageId }
}

// ------------------------------------------------------------------ Stores en memoria (tests)

class InMemorySessionStore(initial: SessionSnapshot = SessionSnapshot()) : SessionStore {
    private val mutex = Mutex()
    private var value = initial
    var saveCount: Int = 0
        private set

    override suspend fun load(): SessionSnapshot = mutex.withLock { value }

    override suspend fun save(snapshot: SessionSnapshot) {
        mutex.withLock {
            value = snapshot
            saveCount++
        }
    }
}

class InMemorySyncQueueStore(initial: SyncQueueState = SyncQueueState()) : SyncQueueStore {
    private val mutex = Mutex()
    private var value = initial

    override suspend fun load(): SyncQueueState = mutex.withLock { value }

    override suspend fun save(state: SyncQueueState) {
        mutex.withLock { value = state }
    }
}

class InMemoryCredentialStore : CredentialStore {
    @Volatile private var token: String? = null
    override fun read(): String? = token
    override fun write(token: String) { this.token = token }
    override fun clear() { token = null }
}

// ------------------------------------------------------------------ Clock / Ids / Jitter

object WallClock : Clock {
    override fun now(): Instant = Instant.now()
}

/** Reloj controlable para tests. */
class MutableClock(var current: Instant = Instant.EPOCH) : Clock {
    override fun now(): Instant = current
    fun advanceSeconds(seconds: Long) { current = current.plusSeconds(seconds) }
}

object UuidGenerator : IdGenerator {
    override fun newId(): String = UUID.randomUUID().toString()
}

/** Ids deterministas para tests: `prefix1`, `prefix2`, … */
class SequentialIdGenerator(private val prefix: String = "id-") : IdGenerator {
    private val counter = AtomicLong(0)
    override fun newId(): String = prefix + counter.incrementAndGet()
}

object RandomJitter : JitterSource {
    override fun nextFraction(): Double = Random.nextDouble(0.0, Backoff.MAX_JITTER)
}

val NoJitter: JitterSource = JitterSource { 0.0 }
