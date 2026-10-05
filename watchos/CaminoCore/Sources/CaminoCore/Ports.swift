import Foundation

// Puertos del núcleo — docs/WATCH_V1_SPEC.md §9.
// Los sensores (StepSource, LocationSource) y el Notifier viven en la capa app.

/// Lista de etapas.
public protocol StageCatalog: AnyObject {
    func allStages() -> [Stage]
}

extension StageCatalog {
    public func stage(id: String) -> Stage? {
        return allStages().first(where: { $0.id == id })
    }
}

/// POIs por etapa.
public protocol PoiSource: AnyObject {
    func pois(forStage stageId: String) -> [Poi]
}

/// Persiste `SessionState` + `History`. `load()` devuelve `nil` si nunca se guardó nada.
public protocol SessionStore: AnyObject {
    func load() throws -> PersistedSession?
    func save(_ value: PersistedSession) throws
}

/// Persiste cola, dead-letter y backoff. `load()` devuelve `nil` si nunca se guardó nada.
public protocol SyncQueueStore: AnyObject {
    func load() throws -> SyncQueueState?
    func save(_ value: SyncQueueState) throws
}

/// Única puerta hacia el backend. En V1 sólo existen `BlockedCaminoApi` (Release)
/// y `MockCaminoApi` (Debug); el contrato real está BLOQUEADO (contracts/README.md).
public protocol CaminoApi: AnyObject {
    /// `true` si el adaptador es de demostración (la UI muestra la marca DEMO).
    var isDemo: Bool { get }
    func send(_ event: SyncEvent) async -> SendResult
}

/// Token opaco. Nada lo escribe en V1.
public protocol CredentialStore: AnyObject {
    func read() -> String?
    func write(_ token: String) throws
    func clear() throws
}

/// Puerto `Clock` de la spec. Se llama `CaminoClock` para no chocar con el
/// protocolo `Clock` de la biblioteca estándar de Swift (5.7+).
public protocol CaminoClock: AnyObject {
    func now() -> Date
}

/// Generador de identificadores (UUID v4 en producción).
public protocol IdGenerator: AnyObject {
    func newId() -> String
}
