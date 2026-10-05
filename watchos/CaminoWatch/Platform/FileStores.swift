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

/// No se pudo apartar un fichero ilegible: no se escribe para no destruirlo.
struct UnreadableFileGuardError: Error {}

/// Lectura/escritura atómica de un valor `Codable` en un fichero JSON.
final class JSONFileStorage<Value: Codable> {
    let url: URL
    /// `true` si la lectura falló y el fichero no se pudo apartar: escribir lo destruiría.
    private var mustNotOverwrite = false

    init(url: URL) {
        self.url = url
    }

    /// `nil` si el fichero no existe. Si existe pero no se puede leer (permiso, protección
    /// de datos, E/S…) o está corrupto, se aparta (`.corrupt-<t>.json`) ANTES de cualquier
    /// escritura, para no sobrescribir el fichero bueno, y se propaga el error (V-03).
    func read() throws -> Value? {
        guard FileManager.default.fileExists(atPath: url.path) else {
            return nil
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            if JSONFileStorage.isNotFound(error) {
                return nil
            }
            quarantine()
            throw error
        }
        do {
            return try CaminoJSON.decoder().decode(Value.self, from: data)
        } catch {
            quarantine()
            throw error
        }
    }

    func write(_ value: Value) throws {
        if mustNotOverwrite {
            // Se reintenta apartarlo; si sigue sin poder, no se escribe.
            quarantine()
            if mustNotOverwrite {
                throw UnreadableFileGuardError()
            }
        }
        let data = try CaminoJSON.encoder().encode(value)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func quarantine() {
        guard FileManager.default.fileExists(atPath: url.path) else {
            mustNotOverwrite = false
            return
        }
        let stamp = Int(Date().timeIntervalSince1970)
        let base = url.deletingPathExtension().lastPathComponent
        let destination = url.deletingLastPathComponent()
            .appendingPathComponent("\(base).corrupt-\(stamp).json")
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            mustNotOverwrite = false
        } catch {
            mustNotOverwrite = true
        }
    }

    private static func isNotFound(_ error: Error) -> Bool {
        if let cocoa = error as? CocoaError, cocoa.code == .fileReadNoSuchFile || cocoa.code == .fileNoSuchFile {
            return true
        }
        let ns = error as NSError
        return ns.domain == NSPOSIXErrorDomain && ns.code == Int(ENOENT)
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
