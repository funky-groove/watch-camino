import Foundation

// Adaptadores en memoria (tests y respaldo si falla el almacenamiento en disco).

public final class InMemorySessionStore: SessionStore {
    public private(set) var value: PersistedSession?
    public private(set) var saveCount: Int = 0

    public init(_ initial: PersistedSession? = nil) {
        self.value = initial
    }

    public func load() throws -> PersistedSession? {
        return value
    }

    public func save(_ value: PersistedSession) throws {
        self.value = value
        saveCount += 1
    }
}

public final class InMemorySyncQueueStore: SyncQueueStore {
    public private(set) var value: SyncQueueState?
    public private(set) var saveCount: Int = 0

    public init(_ initial: SyncQueueState? = nil) {
        self.value = initial
    }

    public func load() throws -> SyncQueueState? {
        return value
    }

    public func save(_ value: SyncQueueState) throws {
        self.value = value
        saveCount += 1
    }
}

public final class InMemoryCredentialStore: CredentialStore {
    private var token: String?

    public init(token: String? = nil) {
        self.token = token
    }

    public func read() -> String? {
        return token
    }

    public func write(_ token: String) throws {
        self.token = token
    }

    public func clear() throws {
        token = nil
    }
}

// MARK: - Reloj

public final class SystemClock: CaminoClock {
    public init() {}

    public func now() -> Date {
        return Date()
    }
}

/// Reloj fijo y ajustable para tests.
public final class FixedClock: CaminoClock {
    public var current: Date

    public init(_ current: Date) {
        self.current = current
    }

    public convenience init(secondsSince1970: Double) {
        self.init(Date(timeIntervalSince1970: secondsSince1970))
    }

    public func now() -> Date {
        return current
    }

    public func advance(by seconds: TimeInterval) {
        current = current.addingTimeInterval(seconds)
    }
}

// MARK: - Identificadores

/// UUID v4 en minúsculas.
public final class SystemIdGenerator: IdGenerator {
    public init() {}

    public func newId() -> String {
        return UUID().uuidString.lowercased()
    }
}

/// Identificadores secuenciales deterministas para tests: `prefix1`, `prefix2`, …
public final class SequentialIdGenerator: IdGenerator {
    private let prefix: String
    private var counter: Int = 0

    public init(prefix: String = "id-") {
        self.prefix = prefix
    }

    public func newId() -> String {
        counter += 1
        return "\(prefix)\(counter)"
    }
}
