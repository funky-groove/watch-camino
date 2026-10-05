package org.caminoseguro.watch.core

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.yield
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

/** API con respuestas guionizadas, consumidas en orden (una por envío). */
class ScriptedCaminoApi(responses: List<SendResult>) : CaminoApi {
    private val pending = ArrayDeque(responses)
    val sent = mutableListOf<String>()
    override suspend fun send(event: SyncEvent): SendResult {
        sent += event.eventId
        return pending.removeFirstOrNull() ?: error("respuesta no guionizada para ${event.eventId}")
    }
}

fun fakeEvent(id: String): SyncEvent = SyncEvent(
    eventId = id,
    type = SyncEventType.StageStarted,
    sessionId = "S",
    occurredAt = epoch(0.0),
    payload = SyncPayload.StageStarted("s", epoch(0.0)),
)

fun response(name: String): SendResult = when (name) {
    "accepted" -> SendResult.Accepted
    "retryable" -> SendResult.Retryable("test")
    "permanent" -> SendResult.Permanent("test")
    "unauthorized" -> SendResult.Unauthorized
    "blocked" -> SendResult.Blocked
    else -> error(name)
}

fun statusName(s: SyncStatus): String = when (s) {
    SyncStatus.Synced -> "synced"
    is SyncStatus.Pending -> "pending"
    SyncStatus.Offline -> "offline"
    SyncStatus.Blocked -> "blocked"
    SyncStatus.NeedsLink -> "needsLink"
    SyncStatus.Syncing -> "syncing"
}

class SyncEngineConformanceTest {
    private val data = Shared.conformance("sync_engine.json")

    @Test
    fun allCases() = runTest {
        val cases = data["cases"]!!.arr
        assertEquals(10, cases.size)
        for (c in cases) {
            val o = c.obj
            val name = o["name"]!!.s
            val backoff = o["backoff"]!!.obj
            val store = InMemorySyncQueueStore(
                SyncQueueState(
                    queue = o["queue"]!!.arr.map { fakeEvent(it.s) },
                    attempt = backoff["attempt"]!!.i,
                    nextAttemptAt = backoff["nextAttemptAt"].let { if (it.isNull) null else epoch(it!!.d) },
                ),
            )
            val api = ScriptedCaminoApi(o["responses"]!!.arr.map { response(it.s) })
            val engine = SyncEngine(store, api, MutableClock(epoch(o["now"]!!.d)), NoJitter)
            engine.load()
            val status = engine.syncNow(manual = o["manual"]!!.jsonPrimitiveBoolean())

            val e = o["expected"]!!.obj
            val st = store.load()
            assertEquals(name, e["status"]!!.s, statusName(status))
            assertEquals(name, e["sent"]!!.arr.map { it.s }, api.sent)
            assertEquals(name, e["sent"]!!.arr.map { it.s }, engine.lastRunSent)
            assertEquals(name, e["remaining"]!!.arr.map { it.s }, st.queue.map { it.eventId })
            assertEquals(name, e["deadLetters"]!!.arr.map { it.s }, st.deadLetters.map { it.eventId })
            assertEquals(name, e["attempt"]!!.i, st.attempt)
            val nextAt = e["nextAttemptAt"]
            assertEquals(name, if (nextAt.isNull) null else epoch(nextAt!!.d), st.nextAttemptAt)
            // El snapshot publicado para la UI coincide.
            assertEquals(name, statusName(status), statusName(engine.snapshot.value.status))
            assertEquals(name, st.queue.size, engine.snapshot.value.queued)
            assertEquals(name, st.deadLetters.size, engine.snapshot.value.deadLetters)
            if (status is SyncStatus.Pending) assertEquals(name, st.queue.size, status.count)
        }
    }

    @Test
    fun jitterIsAppliedWithinTwentyPercent() = runTest {
        val store = InMemorySyncQueueStore(SyncQueueState(queue = listOf(fakeEvent("e1"))))
        val engine = SyncEngine(store, ScriptedCaminoApi(listOf(SendResult.Retryable("x"))), MutableClock(epoch(1000.0))) { 0.2 }
        engine.syncNow(manual = false)
        assertEquals(epoch(1036.0), store.load().nextAttemptAt)
    }

    @Test
    fun onlyOneSyncInFlight() = runTest {
        val gate = CompletableDeferred<Unit>()
        val inFlight = AtomicInteger(0)
        var maxInFlight = 0
        val api = object : CaminoApi {
            override suspend fun send(event: SyncEvent): SendResult {
                maxInFlight = maxOf(maxInFlight, inFlight.incrementAndGet())
                gate.await()
                yield()
                inFlight.decrementAndGet()
                return SendResult.Accepted
            }
        }
        val store = InMemorySyncQueueStore(SyncQueueState(queue = listOf(fakeEvent("e1"), fakeEvent("e2"))))
        val engine = SyncEngine(store, api, MutableClock(epoch(0.0)), NoJitter)
        val a = async { engine.syncNow(manual = false) }
        val b = async { engine.syncNow(manual = true) }
        yield()
        assertEquals(SyncStatus.Syncing, engine.snapshot.value.status)
        gate.complete(Unit)
        a.await(); b.await()
        assertEquals(1, maxInFlight)
        assertEquals(SyncStatus.Synced, engine.snapshot.value.status)
        assertTrue(store.load().queue.isEmpty())
    }

    @Test
    fun enqueueDuringBlockedKeepsBlockedAndLosesNothing() = runTest {
        val store = InMemorySyncQueueStore()
        val engine = SyncEngine(store, BlockedCaminoApi(), MutableClock(epoch(0.0)), NoJitter)
        engine.enqueue(listOf(fakeEvent("e1")))
        assertEquals(SyncStatus.Pending(1), engine.snapshot.value.status)
        assertEquals(SyncStatus.Blocked, engine.syncNow(manual = true))
        engine.enqueue(listOf(fakeEvent("e2")))
        assertEquals(SyncStatus.Blocked, engine.snapshot.value.status)
        assertEquals(listOf("e1", "e2"), store.load().queue.map { it.eventId })
    }

    @Test
    fun apiExceptionIsRetryable() = runTest {
        val store = InMemorySyncQueueStore(SyncQueueState(queue = listOf(fakeEvent("e1"))))
        val api = object : CaminoApi {
            override suspend fun send(event: SyncEvent): SendResult = throw IllegalStateException("boom")
        }
        val engine = SyncEngine(store, api, MutableClock(epoch(0.0)), NoJitter)
        assertEquals(SyncStatus.Pending(1), engine.syncNow(manual = false))
        assertEquals(1, store.load().attempt)
        assertEquals(epoch(30.0), store.load().nextAttemptAt)
    }

    @Test
    fun mockApiAcceptsEverything() = runTest {
        val store = InMemorySyncQueueStore(SyncQueueState(queue = listOf(fakeEvent("e1"), fakeEvent("e2"))))
        val engine = SyncEngine(store, MockCaminoApi(latencyMillis = 10), MutableClock(epoch(0.0)), NoJitter)
        assertEquals(SyncStatus.Synced, engine.syncNow(manual = false))
    }
}

private fun kotlinx.serialization.json.JsonElement.jsonPrimitiveBoolean(): Boolean =
    this.s.toBooleanStrict()
