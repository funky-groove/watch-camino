import Foundation
import CaminoCore

/// Ficheros JSON privados en Application Support, con
/// `FileProtectionType.completeUntilFirstUserAuthentication` (§11).
enum StorageLocation {
    static func directory() throws -> URL {
        let fileManager = FileManager.default
        let base = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = base.appendingPathComponent("CaminoSeguro", isDirectory: true)
        if !fileManager.fileExists(atPath: directory.path) {
            try fileManager.createDirectory(
                at: directory,
                withIntermediateDirectories: true,
                attributes: [FileAttributeKey.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
            )
        }
        return directory
    }
}

/// Lectura/escritura atómica de un valor `Codable` en un fichero JSON.
final class JSONFileStorage<Value: Codable> {
    let url: URL

    init(url: URL) {
        self.url = url
    }

    /// `nil` si el fichero no existe. Si está corrupto, se aparta (`.corrupt-<t>.json`)
    /// para no sobrescribirlo a ciegas, y se propaga el error.
    func read() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data = try Data(contentsOf: url)
        do {
            return try CaminoJSON.decoder().decode(Value.self, from: data)
        } catch {
            quarantine()
            throw error
        }
    }

    func write(_ value: Value) throws {
        let data = try CaminoJSON.encoder().encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func quarantine() {
        let stamp = Int(Date().timeIntervalSince1970)
        let base = url.deletingPathExtension().lastPathComponent
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent("\(base).corrupt-\(stamp).json")
        try? FileManager.default.moveItem(at: url, to: destination)
    }
}

/// `SessionStore` en `session.json`.
final class FileSessionStore: SessionStore {
    private let storage: JSONFileStorage<PersistedSession>

    init(directory: URL) {
        storage = JSONFileStorage<PersistedSession>(url: directory.appendingPathComponent("session.json"))
    }

    func load() throws -> PersistedSession? {
        return try storage.read()
    }

    func save(_ value: PersistedSession) throws {
        try storage.write(value)
    }
}

/// `SyncQueueStore` en `sync-queue.json`.
final class FileSyncQueueStore: SyncQueueStore {
    private let storage: JSONFileStorage<SyncQueueState>

    init(directory: URL) {
        storage = JSONFileStorage<SyncQueueState>(url: directory.appendingPathComponent("sync-queue.json"))
    }

    func load() throws -> SyncQueueState? {
        return try storage.read()
    }

    func save(_ value: SyncQueueState) throws {
        try storage.write(value)
    }
}
