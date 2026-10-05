import Foundation

// Adaptadores de `CaminoApi` — docs/WATCH_V1_SPEC.md §0.
// No hay cliente HTTP en V1: el contrato del backend está BLOQUEADO (contracts/README.md).

/// Adaptador de Release: nunca envía nada. Devuelve siempre `Blocked`,
/// de modo que los eventos se quedan en la cola sin perderse.
public final class BlockedCaminoApi: CaminoApi {
    public init() {}

    public var isDemo: Bool {
        return false
    }

    public func send(_ event: SyncEvent) async -> SendResult {
        return .blocked
    }
}

/// Adaptador de demostración (sólo Debug): acepta todo tras una latencia simulada.
/// La app lo selecciona únicamente con `#if DEBUG` y muestra la marca DEMO.
public final class MockCaminoApi: CaminoApi {
    private let latencyNanoseconds: UInt64
    /// Ids de los eventos "enviados" (sólo para depuración/tests).
    public private(set) var sentEventIds: [String] = []

    /// - Parameter latencySeconds: latencia simulada por evento.
    public init(latencySeconds: Double = 0.5) {
        let clamped = max(0, min(latencySeconds, 10))
        self.latencyNanoseconds = UInt64(clamped * 1_000_000_000)
    }

    public var isDemo: Bool {
        return true
    }

    public func send(_ event: SyncEvent) async -> SendResult {
        if latencyNanoseconds > 0 {
            try? await Task.sleep(nanoseconds: latencyNanoseconds)
        }
        sentEventIds.append(event.eventId)
        return .accepted
    }
}
