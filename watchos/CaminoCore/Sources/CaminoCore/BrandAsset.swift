import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#elseif canImport(Musl)
import Musl
#endif

// Bienvenida visual con recurso de marca remoto (docs/WATCH_V1_SPEC.md §K). Núcleo puro y testado:
// validación, metadatos de caché, puerto del origen remoto (BLOQUEADO), repositorio de caché,
// política y tiempos. Mismos nombres y reglas que Wear OS (wearos/core/.../BrandAsset.kt).

// MARK: - Validación (§K.1)

/// Motivo de rechazo de un recurso de marca.
public enum BrandAssetRejection: String, Equatable, Sendable {
    case empty
    case tooLarge
    case badSignature
    case badIHDR
    case notSquare
    case dimensionsOutOfRange
    case sha256Mismatch
    case undecodable
}

public enum BrandAssetValidation: Equatable, Sendable {
    case valid(width: Int, height: Int, bytes: Int, sha256: String)
    case invalid(BrandAssetRejection)
}

/// Reglas §K.1, todas obligatorias: 0 < bytes ≤ 512 KiB; firma PNG; cabecera IHDR legible (primer
/// fragmento, longitud 13, CRC correcto); cuadrada entre 256 y 2048 px; y, si el manifiesto trae
/// `sha256`, coincidencia exacta (hex en minúsculas). La decodificación de plataforma la añade
/// `BrandAssetRepository` con su `decodable`.
public enum BrandAssetValidator {
    public static let maxBytes = 512 * 1024
    public static let minSidePx = 256
    public static let maxSidePx = 2048

    public static let pngSignature: [UInt8] = [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]

    private static let ihdrType: [UInt8] = [0x49, 0x48, 0x44, 0x52]
    private static let ihdrLength = 13
    /// Firma (8) + longitud (4) + tipo (4) + datos IHDR (13) + CRC (4).
    private static let ihdrEnd = 8 + 4 + 4 + 13 + 4

    public static func validate(_ data: Data, expectedSha256: String? = nil) -> BrandAssetValidation {
        if data.isEmpty {
            return .invalid(.empty)
        }
        if data.count > maxBytes {
            return .invalid(.tooLarge)
        }
        let bytes = [UInt8](data)
        if bytes.count < pngSignature.count || Array(bytes[0..<pngSignature.count]) != pngSignature {
            return .invalid(.badSignature)
        }
        if bytes.count < ihdrEnd {
            return .invalid(.badIHDR)
        }
        if readUInt32(bytes, at: 8) != UInt32(ihdrLength) || Array(bytes[12..<16]) != ihdrType {
            return .invalid(.badIHDR)
        }
        let crc = CRC32Checksum.checksum(bytes[12..<(16 + ihdrLength)])
        if readUInt32(bytes, at: 16 + ihdrLength) != crc {
            return .invalid(.badIHDR)
        }
        let rawWidth = readUInt32(bytes, at: 16)
        let rawHeight = readUInt32(bytes, at: 20)
        // PNG limita las dimensiones a 2^31 - 1; 0 no es válido.
        if rawWidth == 0 || rawHeight == 0 || rawWidth > UInt32(Int32.max) || rawHeight > UInt32(Int32.max) {
            return .invalid(.badIHDR)
        }
        let width = Int(rawWidth)
        let height = Int(rawHeight)
        if width != height {
            return .invalid(.notSquare)
        }
        if width < minSidePx || width > maxSidePx {
            return .invalid(.dimensionsOutOfRange)
        }
        let sha = sha256Hex(data)
        if let expected = expectedSha256, !(isLowercaseSha256Hex(expected) && expected == sha) {
            return .invalid(.sha256Mismatch)
        }
        return .valid(width: width, height: height, bytes: data.count, sha256: sha)
    }

    public static func sha256Hex(_ data: Data) -> String {
        return SHA256Digest.hex(data)
    }

    /// 64 caracteres `[0-9a-f]`.
    public static func isLowercaseSha256Hex(_ text: String) -> Bool {
        let utf8 = Array(text.utf8)
        guard utf8.count == 64 else {
            return false
        }
        return utf8.allSatisfy { ($0 >= 0x30 && $0 <= 0x39) || ($0 >= 0x61 && $0 <= 0x66) }
    }

    /// Entero de 32 bits big-endian (como en PNG).
    private static func readUInt32(_ b: [UInt8], at i: Int) -> UInt32 {
        return UInt32(b[i]) << 24 | UInt32(b[i + 1]) << 16 | UInt32(b[i + 2]) << 8 | UInt32(b[i + 3])
    }
}

// MARK: - Caché

/// Metadatos de la caché (§K.1). Sin datos personales. `fetchedAt` en ISO-8601 (UTC).
public struct BrandAssetCacheMeta: Codable, Equatable, Sendable {
    public let sha256: String
    public let width: Int
    public let height: Int
    public let bytes: Int
    public let fetchedAt: String

    public init(sha256: String, width: Int, height: Int, bytes: Int, fetchedAt: String) {
        self.sha256 = sha256
        self.width = width
        self.height = height
        self.bytes = bytes
        self.fetchedAt = fetchedAt
    }
}

/// Almacén de la caché del recurso de marca (inyectable en tests). Contrato:
/// - `writeTemp` escribe la descarga en un fichero temporal; nunca toca la caché vigente;
/// - `commitTemp` sustituye la caché por el temporal de forma ATÓMICA: tras volver, `readMeta`
///   devuelve `meta` y `readAsset` los bytes del temporal; si falla, la caché anterior sigue intacta;
/// - las lecturas devuelven `nil` si no hay caché (o no se puede leer).
public protocol BrandAssetStore: AnyObject {
    func readMeta() -> BrandAssetCacheMeta?
    func readAsset(_ meta: BrandAssetCacheMeta) -> Data?
    func writeTemp(_ data: Data) throws
    func readTemp() -> Data?
    func commitTemp(_ meta: BrandAssetCacheMeta) throws
    func discardTemp()
}

public struct BrandAssetStoreError: Error, Equatable {
    public let reason: String
}

/// `BrandAssetStore` sobre ficheros (sólo Foundation). La imagen se guarda con su hash en el
/// nombre (`brand-<sha256>.png`) y el punto de confirmación es el reemplazo atómico de
/// `brand.json` (`rename(2)`): o se ve la caché anterior completa o la nueva completa. Después
/// se borran las imágenes huérfanas.
public final class FileBrandAssetStore: BrandAssetStore {
    public static let metaName = "brand.json"
    public static let tempName = "brand.download.tmp"
    public static let assetPrefix = "brand-"

    public let directory: URL
    private let fileManager = FileManager.default

    public init(directory: URL) {
        self.directory = directory
    }

    private var metaURL: URL {
        return directory.appendingPathComponent(FileBrandAssetStore.metaName)
    }

    private var tempURL: URL {
        return directory.appendingPathComponent(FileBrandAssetStore.tempName)
    }

    /// Fichero de la imagen de `meta` (para que la plataforma lo decodifique directamente).
    /// `nil` si el hash no tiene el formato esperado.
    public func assetURL(for meta: BrandAssetCacheMeta) -> URL? {
        guard BrandAssetValidator.isLowercaseSha256Hex(meta.sha256) else {
            return nil
        }
        return directory.appendingPathComponent(FileBrandAssetStore.assetPrefix + meta.sha256 + ".png")
    }

    public func readMeta() -> BrandAssetCacheMeta? {
        guard let data = readSmallFile(metaURL, limit: 4096) else {
            return nil
        }
        return try? CaminoJSON.decoder().decode(BrandAssetCacheMeta.self, from: data)
    }

    public func readAsset(_ meta: BrandAssetCacheMeta) -> Data? {
        guard let url = assetURL(for: meta) else {
            return nil
        }
        return readSmallFile(url, limit: BrandAssetValidator.maxBytes)
    }

    public func writeTemp(_ data: Data) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        try data.write(to: tempURL)
    }

    public func readTemp() -> Data? {
        return readSmallFile(tempURL, limit: BrandAssetValidator.maxBytes)
    }

    public func commitTemp(_ meta: BrandAssetCacheMeta) throws {
        guard let target = assetURL(for: meta) else {
            throw BrandAssetStoreError(reason: "sha256 no válido")
        }
        try move(tempURL, to: target)
        let metaTemp = directory.appendingPathComponent(FileBrandAssetStore.metaName + ".tmp")
        try CaminoJSON.encoder().encode(meta).write(to: metaTemp)
        try move(metaTemp, to: metaURL) // punto de confirmación
        let names = (try? fileManager.contentsOfDirectory(atPath: directory.path)) ?? []
        for name in names where name.hasPrefix(FileBrandAssetStore.assetPrefix)
            && name.hasSuffix(".png") && name != target.lastPathComponent {
            try? fileManager.removeItem(at: directory.appendingPathComponent(name))
        }
    }

    public func discardTemp() {
        try? fileManager.removeItem(at: tempURL)
    }

    /// Lectura acotada: no carga ficheros mayores que `limit` (ni directorios).
    private func readSmallFile(_ url: URL, limit: Int) -> Data? {
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey]),
              values.isRegularFile == true,
              let size = values.fileSize,
              size <= limit else {
            return nil
        }
        return try? Data(contentsOf: url)
    }

    /// Sustitución atómica (`rename(2)` reemplaza el destino si existe).
    private func move(_ from: URL, to: URL) throws {
        let result = from.withUnsafeFileSystemRepresentation { source -> Int32 in
            to.withUnsafeFileSystemRepresentation { destination -> Int32 in
                guard let source = source, let destination = destination else {
                    return -1
                }
                return rename(source, destination)
            }
        }
        if result != 0 {
            throw BrandAssetStoreError(reason: "rename falló (\(errno))")
        }
    }
}

/// Almacén en memoria (tests y escenarios). `failCommit` simula un fallo de disco al confirmar.
public final class InMemoryBrandAssetStore: BrandAssetStore {
    public private(set) var meta: BrandAssetCacheMeta?
    public private(set) var asset: Data?
    public private(set) var temp: Data?
    public var failCommit = false

    public init(meta: BrandAssetCacheMeta? = nil, asset: Data? = nil) {
        self.meta = meta
        self.asset = asset
    }

    public func readMeta() -> BrandAssetCacheMeta? {
        return meta
    }

    public func readAsset(_ meta: BrandAssetCacheMeta) -> Data? {
        return asset
    }

    public func writeTemp(_ data: Data) throws {
        temp = data
    }

    public func readTemp() -> Data? {
        return temp
    }

    public func commitTemp(_ meta: BrandAssetCacheMeta) throws {
        if failCommit {
            throw BrandAssetStoreError(reason: "fallo simulado")
        }
        guard let data = temp else {
            throw BrandAssetStoreError(reason: "sin temporal")
        }
        asset = data
        self.meta = meta
        temp = nil
    }

    public func discardTemp() {
        temp = nil
    }
}

// MARK: - Origen remoto (puerto)

public enum BrandAssetFetch: Equatable, Sendable {
    /// No hay origen (contrato BLOQUEADO) o no se pudo consultar.
    case unavailable
    /// Imagen descargada y `sha256` del manifiesto del backoffice (si lo trae).
    case downloaded(bytes: Data, expectedSha256: String?)
}

/// Puerto del recurso de marca remoto. Sólo se llama en segundo plano (nunca al abrir).
public protocol BrandAssetSource: AnyObject {
    func fetch() async throws -> BrandAssetFetch
}

/// Adaptador mientras no haya contrato (§K, contracts/README.md): no descarga nada.
public final class BlockedBrandAssetSource: BrandAssetSource {
    public init() {}

    public func fetch() async throws -> BrandAssetFetch {
        return .unavailable
    }
}

// MARK: - Repositorio

/// Logo que se muestra en la bienvenida.
public enum BrandLogo: Equatable {
    /// Logo incluido en la app (caché ausente o inválida).
    case bundled
    case cached(bytes: Data, meta: BrandAssetCacheMeta)
}

public enum BrandRefreshOutcome: Equatable, Sendable {
    case unavailable
    case unchanged
    case replaced
    case rejected
    case failed
}

/// Caché del recurso de marca (§K.1).
/// - `current()`: lee SÓLO la caché local (sin red); si falta o no supera la validación → `.bundled`.
/// - `refresh()`: para segundo plano. Descarga → temporal → validación (+ `decodable` de la
///   plataforma) → sustitución atómica. Un recurso inválido nunca sustituye a uno válido (se
///   descarta el temporal).
public final class BrandAssetRepository: @unchecked Sendable {
    private let store: any BrandAssetStore
    private let source: any BrandAssetSource
    private let clock: any CaminoClock
    private let decodable: (Data) -> Bool
    /// Serializa el acceso al almacén (lecturas y la instalación de una descarga).
    private let lock = NSLock()

    public init(
        store: any BrandAssetStore,
        source: any BrandAssetSource,
        clock: any CaminoClock,
        decodable: @escaping (Data) -> Bool = { _ in true }
    ) {
        self.store = store
        self.source = source
        self.clock = clock
        self.decodable = decodable
    }

    public func current() -> BrandLogo {
        lock.lock()
        defer { lock.unlock() }
        return currentLocked()
    }

    public func refresh() async -> BrandRefreshOutcome {
        let fetched: BrandAssetFetch
        do {
            fetched = try await source.fetch()
        } catch {
            return .failed
        }
        switch fetched {
        case .unavailable:
            return .unavailable
        case .downloaded(let bytes, let expectedSha256):
            return installSerialized(bytes, expectedSha256: expectedSha256)
        }
    }

    /// Síncrono a propósito: el cerrojo nunca se mantiene a través de un `await`.
    private func installSerialized(_ bytes: Data, expectedSha256: String?) -> BrandRefreshOutcome {
        lock.lock()
        defer { lock.unlock() }
        do {
            return try install(bytes, expectedSha256: expectedSha256)
        } catch {
            store.discardTemp()
            return .failed
        }
    }

    private func currentLocked() -> BrandLogo {
        guard let meta = store.readMeta(), let bytes = store.readAsset(meta) else {
            return .bundled
        }
        guard case .valid(let width, let height, let size, _) =
                BrandAssetValidator.validate(bytes, expectedSha256: meta.sha256),
              width == meta.width, height == meta.height, size == meta.bytes else {
            return .bundled
        }
        return .cached(bytes: bytes, meta: meta)
    }

    private func install(_ bytes: Data, expectedSha256: String?) throws -> BrandRefreshOutcome {
        // Rechazo previo barato (tamaño) antes de escribir nada.
        if bytes.isEmpty || bytes.count > BrandAssetValidator.maxBytes {
            return .rejected
        }
        if case .cached(_, let meta) = currentLocked(), meta.sha256 == BrandAssetValidator.sha256Hex(bytes) {
            return .unchanged
        }
        try store.writeTemp(bytes)
        guard let onDisk = store.readTemp(),
              case .valid(let width, let height, let size, let sha) =
                BrandAssetValidator.validate(onDisk, expectedSha256: expectedSha256),
              decodable(onDisk) else {
            store.discardTemp()
            return .rejected
        }
        try store.commitTemp(BrandAssetCacheMeta(
            sha256: sha,
            width: width,
            height: height,
            bytes: size,
            fetchedAt: BrandAssetRepository.iso8601(clock.now())
        ))
        return .replaced
    }

    static func iso8601(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

// MARK: - Cuándo y cuánto (§K.2, §K.3)

/// §K.2: se muestra sólo si TODO se cumple.
public enum WelcomePolicy {
    public static func shouldShow(
        coldStart: Bool,
        hasActiveOrRestoredTrip: Bool,
        launchedFromDeepLink: Bool,
        launchedForSos: Bool,
        alreadyShown: Bool
    ) -> Bool {
        return coldStart && !hasActiveOrRestoredTrip && !launchedFromDeepLink && !launchedForSos && !alreadyShown
    }
}

/// §K.3: duraciones fijadas en código (el backoffice sólo controla la imagen).
public enum WelcomeTiming {
    public static let visibleMs = 600
    public static let fadeMs = 400
    public static let totalMaxMs = 1_000
    /// Con reducción de movimiento: sin animación, retirada de golpe al terminar la parte visible.
    public static let reducedMotionTotalMs = visibleMs

    public static var visibleSeconds: TimeInterval {
        return TimeInterval(visibleMs) / 1000
    }

    public static var fadeSeconds: TimeInterval {
        return TimeInterval(fadeMs) / 1000
    }
}
