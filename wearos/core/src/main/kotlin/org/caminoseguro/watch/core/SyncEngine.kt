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

    /**
     * §7.4: con `BlockedCaminoApi` (Release sin contrato) el estado es siempre `blocked`, también con
     * la cola vacía: nunca se dice "sincronizado" si no existe servidor (V-02).
     */
    private val alwaysBlocked: Boolean = api is BlockedCaminoApi

    private val _snapshot = MutableStateFlow(SyncSnapshot(status = if (alwaysBlocked) SyncStatus.Blocked else SyncStatus.Synced))
    val snapshot: StateFlow<SyncSnapshot> = _snapshot.asStateFlow()

    /** Lista de eventIds enviados en la última ejecución (diagnóstico y tests). */
    @Volatile
    var lastRunSent: List<String> = emptyList()
        private set

    /**
     * Carga el estado persistido y publica el estado inicial. Devuelve `true` si el almacén no pudo
     * leer la cola anterior (se apartó una copia y se empieza vacía): la UI debe avisar (V-03).
     */
    suspend fun load(): Boolean {
        val (s, unreadable) = stateMutex.withLock { store.load() to store.takeUnreadableNotice() }
        publishIdle(s, keep = null)
        return unreadable
    }

    suspend fun enqueue(events: List<SyncEvent>) {
        if (events.isEmpty()) return
        val s = stateMutex.withLock {
            val cur = store.load()
            // V-04: un `stage_finished` por sesión. Si ya hay uno (p. ej. tras un fallo de guardado
            // y un reintento de "Finalizar"), no se encola otro con distinto eventId/finishedAt.
            val finished = (cur.queue + cur.deadLetters)
                .filter { it.type == SyncEventType.StageFinished }
                .mapTo(HashSet()) { it.sessionId }
            val fresh = events.filterNot { it.type == SyncEventType.StageFinished && it.sessionId in finished }
            if (fresh.isEmpty()) return@withLock cur
            val next = cur.copy(queue = cur.queue + fresh)
            store.save(next)
            next
        }
        val current = _snapshot.value.status
        val status = when {
            alwaysBlocked -> SyncStatus.Blocked
            current == SyncStatus.Synced || current is SyncStatus.Pending -> SyncStatus.Pending(s.queue.size)
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
            val status = restingStatus(initial)
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

    private fun restingStatus(s: SyncQueueState): SyncStatus = when {
        alwaysBlocked -> SyncStatus.Blocked
        s.queue.isEmpty() -> SyncStatus.Synced
        else -> SyncStatus.Pending(s.queue.size)
    }

    private fun publishIdle(s: SyncQueueState, keep: SyncStatus?) {
        val status = when (keep) {
            is SyncStatus.Pending -> SyncStatus.Pending(s.queue.size)
            null -> restingStatus(s)
            else -> keep
        }
        _snapshot.value = SyncSnapshot(status, s.queue.size, s.deadLetters.size)
    }
}
