import XCTest
@testable import CaminoCore

/// §K: validación, caché, política y tiempos de la bienvenida visual (paridad con Wear OS,
/// wearos/core/src/test/.../BrandAssetTest.kt).
final class BrandAssetTests: XCTestCase {

    // MARK: - PNG mínimo construido aquí

    private func be32(_ value: UInt32) -> [UInt8] {
        return [UInt8(truncatingIfNeeded: value >> 24), UInt8(truncatingIfNeeded: value >> 16),
                UInt8(truncatingIfNeeded: value >> 8), UInt8(truncatingIfNeeded: value)]
    }

    private func chunk(_ type: String, _ data: [UInt8]) -> [UInt8] {
        let typeBytes = Array(type.utf8)
        return be32(UInt32(data.count)) + typeBytes + data + be32(CRC32Checksum.checksum(typeBytes + data))
    }

    /// Flujo zlib con bloques «stored» (sin compresión) y Adler-32.
    private func zlibStored(_ raw: [UInt8]) -> [UInt8] {
        var out: [UInt8] = [0x78, 0x01]
        var offset = 0
        repeat {
            let n = min(65_535, raw.count - offset)
            let last: UInt8 = offset + n >= raw.count ? 1 : 0
            out.append(last)
            out += [UInt8(n & 0xFF), UInt8(n >> 8), UInt8(~n & 0xFF), UInt8((~n >> 8) & 0xFF)]
            out += raw[offset..<(offset + n)]
            offset += n
        } while offset < raw.count
        var a: UInt32 = 1
        var b: UInt32 = 0
        for byte in raw {
            a = (a + UInt32(byte)) % 65_521
            b = (b + a) % 65_521
        }
        return out + be32(b << 16 | a)
    }

    /// PNG gris de 8 bits de `w`×`h` px. Hasta 512 px los píxeles son reales (decodificable);
    /// por encima, IDAT simbólico (el validador del núcleo sólo lee la cabecera; decodificar es
    /// cosa de la plataforma, `decodable`). `padding` añade un fragmento tEXt de ese tamaño.
    private func png(_ w: Int, _ h: Int, padding: Int = 0) -> Data {
        var bytes = BrandAssetValidator.pngSignature
        bytes += chunk("IHDR", be32(UInt32(w)) + be32(UInt32(h)) + [8, 0, 0, 0, 0])
        let raw = (w <= 512 && h <= 512) ? [UInt8](repeating: 0, count: h * (w + 1)) : [0]
        bytes += chunk("IDAT", zlibStored(raw))
        if padding > 0 {
            bytes += chunk("tEXt", [UInt8](repeating: 0x61, count: padding))
        }
        bytes += chunk("IEND", [])
        return Data(bytes)
    }

    private func reason(_ v: BrandAssetValidation) -> BrandAssetRejection? {
        if case .invalid(let r) = v {
            return r
        }
        return nil
    }

    private func mutated(_ data: Data, at index: Int, _ value: UInt8) -> Data {
        var bytes = [UInt8](data)
        bytes[index] = value
        return Data(bytes)
    }

    // MARK: - SHA-256 / CRC-32

    func testSha256KnownVectors() {
        XCTAssertEqual(SHA256Digest.hex(Data("abc".utf8)),
                       "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
        XCTAssertEqual(SHA256Digest.hex(Data()),
                       "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        // Dos bloques (56 bytes: el relleno pasa al segundo bloque).
        XCTAssertEqual(SHA256Digest.hex(Data("abcdbcdecdefdefgefghfghighijhijkijkljklmklmnlmnomnopnopq".utf8)),
                       "248d6a61d20638b8e5c026930c3e6039a33ce45964ff2167f6ecedd419db06c1")
    }

    func testCrc32KnownVector() {
        XCTAssertEqual(CRC32Checksum.checksum(Array("123456789".utf8)), 0xCBF43926)
    }

    // MARK: - Validador

    func testValidMinimalPng() {
        let bytes = png(256, 256)
        XCTAssertEqual(
            BrandAssetValidator.validate(bytes),
            .valid(width: 256, height: 256, bytes: bytes.count, sha256: BrandAssetValidator.sha256Hex(bytes))
        )
        if case .valid(let w, _, _, _) = BrandAssetValidator.validate(png(2048, 2048)) {
            XCTAssertEqual(w, 2048)
        } else {
            XCTFail("2048 px debe ser válido")
        }
    }

    func testEmptyRejected() {
        XCTAssertEqual(reason(BrandAssetValidator.validate(Data())), .empty)
    }

    func testBadSignatureRejected() {
        XCTAssertEqual(reason(BrandAssetValidator.validate(mutated(png(256, 256), at: 1, 0x51))), .badSignature)
        XCTAssertEqual(reason(BrandAssetValidator.validate(Data("GIF89a".utf8))), .badSignature)
    }

    func testUnreadableIhdrRejected() {
        let good = png(256, 256)
        XCTAssertEqual(reason(BrandAssetValidator.validate(good.prefix(20))), .badIHDR)
        XCTAssertEqual(reason(BrandAssetValidator.validate(mutated(good, at: 29, good[29] &+ 1))), .badIHDR)
        XCTAssertEqual(reason(BrandAssetValidator.validate(mutated(good, at: 12, 0x58))), .badIHDR)
        XCTAssertEqual(reason(BrandAssetValidator.validate(png(0, 0))), .badIHDR)
    }

    func testNotSquareRejected() {
        XCTAssertEqual(reason(BrandAssetValidator.validate(png(512, 256))), .notSquare)
    }

    func testDimensionsOutOfRangeRejected() {
        XCTAssertEqual(reason(BrandAssetValidator.validate(png(255, 255))), .dimensionsOutOfRange)
        XCTAssertEqual(reason(BrandAssetValidator.validate(png(2049, 2049))), .dimensionsOutOfRange)
    }

    func testSizeLimits() {
        let big = png(256, 256, padding: BrandAssetValidator.maxBytes)
        XCTAssertGreaterThan(big.count, BrandAssetValidator.maxBytes)
        XCTAssertEqual(reason(BrandAssetValidator.validate(big)), .tooLarge)
        // Justo en el límite (512 KiB) sigue siendo válido; un byte más, no.
        let base = png(256, 256)
        let atLimit = png(256, 256, padding: BrandAssetValidator.maxBytes - base.count - 12)
        XCTAssertEqual(atLimit.count, BrandAssetValidator.maxBytes)
        XCTAssertNil(reason(BrandAssetValidator.validate(atLimit)))
        let overLimit = png(256, 256, padding: BrandAssetValidator.maxBytes - base.count - 11)
        XCTAssertEqual(reason(BrandAssetValidator.validate(overLimit)), .tooLarge)
    }

    func testSha256MustMatchLowercaseHex() {
        let bytes = png(256, 256)
        let sha = BrandAssetValidator.sha256Hex(bytes)
        XCTAssertNil(reason(BrandAssetValidator.validate(bytes, expectedSha256: sha)))
        XCTAssertEqual(reason(BrandAssetValidator.validate(bytes, expectedSha256: String(repeating: "0", count: 64))),
                       .sha256Mismatch)
        XCTAssertEqual(reason(BrandAssetValidator.validate(bytes, expectedSha256: sha.uppercased())), .sha256Mismatch)
        XCTAssertEqual(reason(BrandAssetValidator.validate(bytes, expectedSha256: "")), .sha256Mismatch)
    }

    // MARK: - Repositorio

    private final class FakeSource: BrandAssetSource {
        var next: BrandAssetFetch
        var error: Error?
        private(set) var calls = 0

        init(_ next: BrandAssetFetch) {
            self.next = next
        }

        func fetch() async throws -> BrandAssetFetch {
            calls += 1
            if let error = error {
                throw error
            }
            return next
        }
    }

    private struct Boom: Error {}

    private let clock = FixedClock(Date(timeIntervalSince1970: 1_791_194_400)) // 2026-10-05T10:00:00Z

    private func tempDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("brand-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }

    private func meta(of logo: BrandLogo) -> BrandAssetCacheMeta? {
        if case .cached(_, let meta) = logo {
            return meta
        }
        return nil
    }

    func testMissingCacheUsesBundledLogo() throws {
        let fileRepo = BrandAssetRepository(
            store: FileBrandAssetStore(directory: try tempDirectory().appendingPathComponent("nada")),
            source: BlockedBrandAssetSource(),
            clock: clock
        )
        XCTAssertEqual(fileRepo.current(), .bundled)
        let memoryRepo = BrandAssetRepository(store: InMemoryBrandAssetStore(), source: BlockedBrandAssetSource(), clock: clock)
        XCTAssertEqual(memoryRepo.current(), .bundled)
    }

    func testBlockedSourceDownloadsNothing() async throws {
        let dir = try tempDirectory()
        let repo = BrandAssetRepository(store: FileBrandAssetStore(directory: dir), source: BlockedBrandAssetSource(), clock: clock)
        let outcome = await repo.refresh()
        XCTAssertEqual(outcome, .unavailable)
        XCTAssertEqual(repo.current(), .bundled)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), [])
    }

    func testValidDownloadReplacesCacheAtomically() async throws {
        let dir = try tempDirectory()
        let bytes = png(512, 512)
        let sha = BrandAssetValidator.sha256Hex(bytes)
        let store = FileBrandAssetStore(directory: dir)
        let repo = BrandAssetRepository(store: store, source: FakeSource(.downloaded(bytes: bytes, expectedSha256: sha)), clock: clock)
        let outcome = await repo.refresh()
        XCTAssertEqual(outcome, .replaced)
        let expectedMeta = BrandAssetCacheMeta(sha256: sha, width: 512, height: 512, bytes: bytes.count,
                                               fetchedAt: "2026-10-05T10:00:00Z")
        XCTAssertEqual(repo.current(), .cached(bytes: bytes, meta: expectedMeta))
        // Sin temporal y sólo la imagen nueva + metadatos.
        let names = try FileManager.default.contentsOfDirectory(atPath: dir.path).sorted()
        XCTAssertEqual(names, ["brand-\(sha).png", "brand.json"])
        XCTAssertEqual(store.assetURL(for: expectedMeta)?.lastPathComponent, "brand-\(sha).png")
        // La misma imagen otra vez: sin cambios.
        let again = await repo.refresh()
        XCTAssertEqual(again, .unchanged)
        // Otra imagen válida: la sustituye y borra la huérfana.
        let second = png(256, 256)
        let repo2 = BrandAssetRepository(store: store, source: FakeSource(.downloaded(bytes: second, expectedSha256: nil)), clock: clock)
        let replaced = await repo2.refresh()
        XCTAssertEqual(replaced, .replaced)
        XCTAssertEqual(meta(of: repo2.current())?.width, 256)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path).count, 2)
    }

    func testInvalidDownloadNeverReplacesValidCache() async throws {
        let dir = try tempDirectory()
        let store = FileBrandAssetStore(directory: dir)
        let good = png(512, 512)
        let source = FakeSource(.downloaded(bytes: good, expectedSha256: nil))
        let repo = BrandAssetRepository(store: store, source: source, clock: clock)
        let first = await repo.refresh()
        XCTAssertEqual(first, .replaced)
        let before = repo.current()

        let invalid: [BrandAssetFetch] = [
            .downloaded(bytes: mutated(png(512, 512), at: 0, 0), expectedSha256: nil),      // firma
            .downloaded(bytes: png(512, 256), expectedSha256: nil),                         // no cuadrada
            .downloaded(bytes: png(128, 128), expectedSha256: nil),                         // pequeña
            .downloaded(bytes: png(256, 256), expectedSha256: String(repeating: "a", count: 64)), // sha
            .downloaded(bytes: Data(), expectedSha256: nil),                                // vacía
            .downloaded(bytes: png(256, 256, padding: BrandAssetValidator.maxBytes), expectedSha256: nil) // grande
        ]
        for fetch in invalid {
            source.next = fetch
            let outcome = await repo.refresh()
            XCTAssertEqual(outcome, .rejected)
            XCTAssertEqual(repo.current(), before)
            XCTAssertFalse(FileManager.default.fileExists(atPath: dir.appendingPathComponent(FileBrandAssetStore.tempName).path))
        }

        // La plataforma no la puede decodificar → inválida.
        let undecodable = BrandAssetRepository(store: store, source: FakeSource(.downloaded(bytes: png(256, 256), expectedSha256: nil)),
                                               clock: clock, decodable: { _ in false })
        let rejected = await undecodable.refresh()
        XCTAssertEqual(rejected, .rejected)
        XCTAssertEqual(repo.current(), before)

        // Fallo del origen o del disco: la caché sigue intacta.
        source.error = Boom()
        let failed = await repo.refresh()
        XCTAssertEqual(failed, .failed)
        XCTAssertEqual(repo.current(), before)
    }

    func testCommitFailureKeepsPreviousCache() async {
        let good = png(256, 256)
        let goodSha = BrandAssetValidator.sha256Hex(good)
        let goodMeta = BrandAssetCacheMeta(sha256: goodSha, width: 256, height: 256, bytes: good.count, fetchedAt: "x")
        let store = InMemoryBrandAssetStore(meta: goodMeta, asset: good)
        store.failCommit = true
        let repo = BrandAssetRepository(store: store, source: FakeSource(.downloaded(bytes: png(512, 512), expectedSha256: nil)), clock: clock)
        let outcome = await repo.refresh()
        XCTAssertEqual(outcome, .failed)
        XCTAssertEqual(repo.current(), .cached(bytes: good, meta: goodMeta))
        XCTAssertNil(store.temp)
    }

    func testCorruptOrMismatchedCacheFallsBackToBundled() throws {
        let good = png(256, 256)
        let sha = BrandAssetValidator.sha256Hex(good)
        // Bytes que no coinciden con el hash de los metadatos.
        let tampered = InMemoryBrandAssetStore(
            meta: BrandAssetCacheMeta(sha256: sha, width: 256, height: 256, bytes: good.count, fetchedAt: "x"),
            asset: mutated(good, at: good.count - 1, 0)
        )
        XCTAssertEqual(BrandAssetRepository(store: tampered, source: BlockedBrandAssetSource(), clock: clock).current(), .bundled)
        // Metadatos que no cuadran con la imagen.
        let wrongMeta = InMemoryBrandAssetStore(
            meta: BrandAssetCacheMeta(sha256: sha, width: 512, height: 512, bytes: good.count, fetchedAt: "x"),
            asset: good
        )
        XCTAssertEqual(BrandAssetRepository(store: wrongMeta, source: BlockedBrandAssetSource(), clock: clock).current(), .bundled)
        // brand.json ilegible en disco.
        let dir = try tempDirectory()
        try Data("{no".utf8).write(to: dir.appendingPathComponent(FileBrandAssetStore.metaName))
        XCTAssertEqual(BrandAssetRepository(store: FileBrandAssetStore(directory: dir), source: BlockedBrandAssetSource(), clock: clock).current(), .bundled)
    }

    func testCacheMetaCodableRoundTrip() throws {
        let meta = BrandAssetCacheMeta(sha256: String(repeating: "b", count: 64), width: 300, height: 300, bytes: 1234,
                                       fetchedAt: "2026-10-05T10:00:00Z")
        let data = try CaminoJSON.encoder().encode(meta)
        XCTAssertEqual(try CaminoJSON.decoder().decode(BrandAssetCacheMeta.self, from: data), meta)
        let keys = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys.sorted()
        XCTAssertEqual(keys, ["bytes", "fetchedAt", "height", "sha256", "width"])
    }

    // MARK: - Política (§K.2)

    func testWelcomePolicyAllBranches() {
        XCTAssertTrue(WelcomePolicy.shouldShow(coldStart: true, hasActiveOrRestoredTrip: false,
                                               launchedFromDeepLink: false, launchedForSos: false, alreadyShown: false))
        // Cada condición por separado la impide.
        XCTAssertFalse(WelcomePolicy.shouldShow(coldStart: false, hasActiveOrRestoredTrip: false,
                                                launchedFromDeepLink: false, launchedForSos: false, alreadyShown: false))
        XCTAssertFalse(WelcomePolicy.shouldShow(coldStart: true, hasActiveOrRestoredTrip: true,
                                                launchedFromDeepLink: false, launchedForSos: false, alreadyShown: false))
        XCTAssertFalse(WelcomePolicy.shouldShow(coldStart: true, hasActiveOrRestoredTrip: false,
                                                launchedFromDeepLink: true, launchedForSos: false, alreadyShown: false))
        XCTAssertFalse(WelcomePolicy.shouldShow(coldStart: true, hasActiveOrRestoredTrip: false,
                                                launchedFromDeepLink: false, launchedForSos: true, alreadyShown: false))
        XCTAssertFalse(WelcomePolicy.shouldShow(coldStart: true, hasActiveOrRestoredTrip: false,
                                                launchedFromDeepLink: false, launchedForSos: false, alreadyShown: true))
        // Exhaustivo: sólo una combinación de las 32 la muestra.
        var shown = 0
        for mask in 0..<32 {
            if WelcomePolicy.shouldShow(coldStart: mask & 1 != 0, hasActiveOrRestoredTrip: mask & 2 != 0,
                                        launchedFromDeepLink: mask & 4 != 0, launchedForSos: mask & 8 != 0,
                                        alreadyShown: mask & 16 != 0) {
                shown += 1
                XCTAssertEqual(mask, 1)
            }
        }
        XCTAssertEqual(shown, 1)
    }

    // MARK: - Tiempos (§K.3)

    func testWelcomeTiming() {
        XCTAssertEqual(WelcomeTiming.visibleMs, 600)
        XCTAssertEqual(WelcomeTiming.fadeMs, 400)
        XCTAssertLessThanOrEqual(WelcomeTiming.visibleMs + WelcomeTiming.fadeMs, WelcomeTiming.totalMaxMs)
        XCTAssertEqual(WelcomeTiming.totalMaxMs, 1_000)
        XCTAssertEqual(WelcomeTiming.reducedMotionTotalMs, WelcomeTiming.visibleMs)
        XCTAssertEqual(WelcomeTiming.visibleSeconds, 0.6, accuracy: 1e-9)
        XCTAssertEqual(WelcomeTiming.fadeSeconds, 0.4, accuracy: 1e-9)
    }
}
