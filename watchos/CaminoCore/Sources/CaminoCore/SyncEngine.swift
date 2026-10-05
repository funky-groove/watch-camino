import Foundation

/// Backoff exponencial con tope — docs/WATCH_V1_SPEC.md §7.
/// `backoff(attempt) = min(30 · 2^(attempt−1), 1800)` s, más jitter en [0, 20 %].
public enum Backoff {
    public static let baseSeconds: Double = 30.0
    public static let capSeconds: Double = 1800.0
    public static let maxJitterFraction: Double = 0.2

    /// Backoff sin jitter (lo que fijan los vectores de `backoff.json`).
    public static func seconds(attempt: Int) -> Double {
        guard attempt >= 1 else {
            return 0
        }
        // 2^16 · 30 ya supera de sobra el tope; evita desbordar el desplazamiento.
        let exponent = min(attempt - 1, 16)
        let raw = baseSeconds * Double(1 << exponent)
        return min(raw, capSeconds)
    }

    /// Backoff con jitter. `jitterFraction` se recorta a [0, 0.2].
    public static func delaySeconds(attempt: Int, jitterFraction: Double) -> Double {
        var jitter = jitterFraction.isFinite ? jitterFraction : 0
        jitter = min(max(jitter, 0), maxJitterFraction)
        return seconds(attempt: attempt) * (1.0 + jitter)
    }

    /// Fuente de jitter de producción.
    public static func systemJitter() -> Double {
        return Double.random(in: 0...maxJitterFraction)
    }
}

/// Motor de sincronización offline-first — docs/WATCH_V1_SPEC.md §7.
///
/// Aislado al `MainActor` para que la cola no se toque desde dos hilos: el envío
/// (`CaminoApi.send`) es la única parte que sale del actor.
@MainActor
public final class SyncEngine {
    public private(set) var state: SyncQueueState
    public private(set) var status: SyncStatus
    public private(set) var isSyncing: Bool = false
    /// Error al cargar la cola persistida (si lo hubo). Se arranca con cola vacía.
    public private(set) var loadError: Error?

    public var onStatusChange: ((SyncStatus) -> Void)?
    public var onStorageError: ((Error) -> Void)?

    private let api: any CaminoApi
    private let store: any SyncQueueStore
    private let clock: any CaminoClock
    private let jitter: () -> Double

    public init(
        api: any CaminoApi,
        store: any SyncQueueStore,
        clock: any CaminoClock,
        jitter: @escaping () -> Double = Backoff.systemJitter
    ) {
        self.api = api
        self.store = store
        self.clock = clock
        self.jitter = jitter
        var loaded = SyncQueueState()
        var error: Error?
        do {
            if let persisted = try store.load() {
                loaded = persisted
            }
        } catch let caught {
            error = caught
        }
        self.state = loaded
        self.loadError = error
        self.status = SyncEngine.restingStatus(for: loaded)
    }

    public var isDemo: Bool {
        return api.isDemo
    }

    public var pendingCount: Int {
        return state.queue.count
    }

    public var deadLetterCount: Int {
        return state.deadLetters.count
    }

    /// Añade eventos al final de la cola (FIFO) y persiste.
    public func enqueue(_ events: [SyncEvent]) {
        guard !events.isEmpty else {
            return
        }
        state.queue.append(contentsOf: events)
        persist()
        if isSyncing {
            return
        }
        switch status {
        case .blocked, .needsLink:
            // Se mantiene: sigue siendo la explicación correcta de por qué no se envía.
            break
        default:
            setStatus(.pending(state.queue.count))
        }
    }

    /// Algoritmo `syncNow(now)` de §7. Un solo `syncNow` en vuelo a la vez:
    /// una llamada concurrente devuelve el estado actual sin enviar nada.
    @discardableResult
    public func syncNow(manual: Bool) async -> SyncStatus {
        if isSyncing {
            return status
        }
        let now = clock.now()

        // 1. Backoff activo y disparo no manual → no se envía nada.
        if !manual, let next = state.nextAttemptAt, now < next {
            let resting: SyncStatus = state.queue.isEmpty ? .synced : .pending(state.queue.count)
            setStatus(resting)
            return resting
        }

        isSyncing = true
        setStatus(.syncing)

        // 2. Recorrer la cola en orden.
        var stopOutcome: SyncOutcome?
        drain: while let event = state.queue.first {
            let result = await api.send(event)
            switch result {
            case .accepted:
                removeFromQueue(eventId: event.eventId)
                state.attempt = 0
                state.nextAttemptAt = nil
                persist()
            case .permanent:
                removeFromQueue(eventId: event.eventId)
                state.deadLetters.append(event)
                persist()
            case .retryable:
                state.attempt += 1
                let delay = Backoff.delaySeconds(attempt: state.attempt, jitterFraction: jitter())
                state.nextAttemptAt = now.addingTimeInterval(delay)
                stopOutcome = .pending
                break drain
            case .unauthorized:
                stopOutcome = .needsLink
                break drain
            case .blocked:
                stopOutcome = .blocked
                break drain
            }
        }

        // 3. Cola vacía → synced.
        let outcome: SyncOutcome
        if let stop = stopOutcome {
            outcome = stop
        } else {
            outcome = state.queue.isEmpty ? .synced : .pending
        }
        state.lastOutcome = outcome
        persist()
        isSyncing = false

        let finalStatus = SyncEngine.status(for: outcome, queueCount: state.queue.count)
        setStatus(finalStatus)
        return finalStatus
    }

    // MARK: - Privado

    private func removeFromQueue(eventId: String) {
        if let index = state.queue.firstIndex(where: { $0.eventId == eventId }) {
            state.queue.remove(at: index)
        }
    }

    private func persist() {
        do {
            try store.save(state)
        } catch {
            onStorageError?(error)
        }
    }

    private func setStatus(_ newStatus: SyncStatus) {
        status = newStatus
        onStatusChange?(newStatus)
    }

    private static func status(for outcome: SyncOutcome, queueCount: Int) -> SyncStatus {
        switch outcome {
        case .synced:
            return queueCount == 0 ? .synced : .pending(queueCount)
        case .pending:
            return .pending(queueCount)
        case .blocked:
            return .blocked
        case .needsLink:
            return .needsLink
        }
    }

    private static func restingStatus(for state: SyncQueueState) -> SyncStatus {
        if state.queue.isEmpty {
            return .synced
        }
        return status(for: state.lastOutcome ?? .pending, queueCount: state.queue.count)
    }
}
