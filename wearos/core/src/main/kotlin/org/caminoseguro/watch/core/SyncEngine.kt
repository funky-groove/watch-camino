package org.caminoseguro.watch.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Motor de sincronización offline-first — §7.
 *
 * - Cola FIFO persistida en [SyncQueueStore]; dead-letter y backoff también.
 * - Un solo `syncNow` en vuelo: las llamadas concurrentes se serializan ([syncMutex]).
 * - `enqueue` no espera a un sync en vuelo (usa otro mutex, [stateMutex], sólo para la cola).
 */
class SyncEngine(
    private val store: SyncQueueStore,
    private val api: CaminoApi,
    private val clock: Clock,
    private val jitter: JitterSource = RandomJitter,
) {
    private val syncMutex = Mutex()
    private val stateMutex = Mutex()

    private val _snapshot = MutableStateFlow(SyncSnapshot())
    val snapshot: StateFlow<SyncSnapshot> = _snapshot.asStateFlow()

    /** Lista de eventIds enviados en la última ejecución (diagnóstico y tests). */
    @Volatile
    var lastRunSent: List<String> = emptyList()
        private set

    /** Carga el estado persistido y publica el estado inicial. */
    suspend fun load() {
        val s = stateMutex.withLock { store.load() }
        publishIdle(s, keep = null)
    }

    suspend fun enqueue(events: List<SyncEvent>) {
        if (events.isEmpty()) return
        val s = stateMutex.withLock {
            val cur = store.load()
            val next = cur.copy(queue = cur.queue + events)
            store.save(next)
            next
        }
        val current = _snapshot.value.status
        val status = when (current) {
            SyncStatus.Synced, is SyncStatus.Pending -> SyncStatus.Pending(s.queue.size)
            else -> current
        }
        _snapshot.value = SyncSnapshot(status, s.queue.size, s.deadLetters.size)
    }

    suspend fun state(): SyncQueueState = stateMutex.withLock { store.load() }

    /**
     * Algoritmo `syncNow(now)` de §7. [manual] = botón "Sincronizar ahora" (ignora el backoff).
     */
    suspend fun syncNow(manual: Boolean): SyncStatus = syncMutex.withLock {
        val now = clock.now()
        val initial = stateMutex.withLock { store.load() }
        val nextAt = initial.nextAttemptAt
        if (!manual && nextAt != null && now < nextAt) {
            lastRunSent = emptyList()
            val status = if (initial.queue.isEmpty()) SyncStatus.Synced else SyncStatus.Pending(initial.queue.size)
            _snapshot.value = SyncSnapshot(status, initial.queue.size, initial.deadLetters.size)
            return@withLock status
        }

        val sent = mutableListOf<String>()
        var stop: SyncStatus? = null
        _snapshot.value = _snapshot.value.copy(status = SyncStatus.Syncing)
        try {
            while (true) {
                val head = stateMutex.withLock { store.load().queue.firstOrNull() } ?: break
                sent += head.eventId
                val result = try {
                    api.send(head)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    SendResult.Retryable(e.javaClass.simpleName)
                }
                stop = stateMutex.withLock {
                    val s = store.load()
                    val rest = s.queue.filterNot { it.eventId == head.eventId }
                    when (result) {
                        SendResult.Accepted -> {
                            store.save(s.copy(queue = rest, attempt = 0, nextAttemptAt = null))
                            null
                        }
                        is SendResult.Permanent -> {
                            store.save(s.copy(queue = rest, deadLetters = s.deadLetters + head))
                            null
                        }
                        is SendResult.Retryable -> {
                            val attempt = s.attempt + 1
                            val delayMs = Backoff.delayMillis(attempt, jitter.nextFraction())
                            store.save(s.copy(attempt = attempt, nextAttemptAt = now.plusMillis(delayMs)))
                            SyncStatus.Pending(s.queue.size)
                        }
                        SendResult.Unauthorized -> SyncStatus.NeedsLink
                        SendResult.Blocked -> SyncStatus.Blocked
                    }
                }
                if (stop != null) break
            }
        } finally {
            lastRunSent = sent.toList()
            val s = stateMutex.withLock { store.load() }
            publishIdle(s, keep = stop)
        }
        _snapshot.value.status
    }

    private fun publishIdle(s: SyncQueueState, keep: SyncStatus?) {
        val status = when (keep) {
            is SyncStatus.Pending -> SyncStatus.Pending(s.queue.size)
            null -> if (s.queue.isEmpty()) SyncStatus.Synced else SyncStatus.Pending(s.queue.size)
            else -> keep
        }
        _snapshot.value = SyncSnapshot(status, s.queue.size, s.deadLetters.size)
    }
}
