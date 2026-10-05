package org.caminoseguro.watch.core

import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.ByteArrayOutputStream
import java.io.DataOutputStream
import java.io.IOException
import java.time.Instant
import java.util.zip.CRC32
import java.util.zip.Deflater

/** §K: validación, caché y política de la bienvenida visual. */
class BrandAssetTest {

    @get:Rule val tmp = TemporaryFolder()

    // ------------------------------------------------------------------ PNG mínimo construido aquí

    private fun chunk(out: DataOutputStream, type: String, data: ByteArray) {
        val typeBytes = type.toByteArray(Charsets.US_ASCII)
        out.writeInt(data.size)
        out.write(typeBytes)
        out.write(data)
        val crc = CRC32().apply { update(typeBytes); update(data) }
        out.writeInt(crc.value.toInt())
    }

    /** PNG gris de 8 bits, válido y decodificable, de [w]×[h] px. */
    private fun png(w: Int, h: Int, padding: Int = 0): ByteArray {
        val bos = ByteArrayOutputStream()
        val out = DataOutputStream(bos)
        out.write(BrandAssetValidator.PNG_SIGNATURE)
        val ihdr = ByteArrayOutputStream().also { b ->
            DataOutputStream(b).apply {
                writeInt(w); writeInt(h)
                writeByte(8); writeByte(0); writeByte(0); writeByte(0); writeByte(0)
            }
        }.toByteArray()
        chunk(out, "IHDR", ihdr)
        val raw = ByteArray(h * (w + 1)) // filtro 0 + píxeles negros
        val deflater = Deflater().apply { setInput(raw); finish() }
        val buf = ByteArray(raw.size + 64)
        val n = deflater.deflate(buf)
        chunk(out, "IDAT", buf.copyOf(n))
        if (padding > 0) chunk(out, "tEXt", ByteArray(padding) { 'a'.code.toByte() })
        chunk(out, "IEND", ByteArray(0))
        return bos.toByteArray()
    }

    private fun reason(v: BrandAssetValidation) = (v as BrandAssetValidation.Invalid).reason

    // ------------------------------------------------------------------ Validador

    @Test fun validMinimalPng() {
        val bytes = png(256, 256)
        val v = BrandAssetValidator.validate(bytes) as BrandAssetValidation.Valid
        assertEquals(256, v.width)
        assertEquals(256, v.height)
        assertEquals(bytes.size, v.bytes)
        assertEquals(BrandAssetValidator.sha256Hex(bytes), v.sha256)
        assertTrue(BrandAssetValidator.validate(png(2048, 2048)) is BrandAssetValidation.Valid)
    }

    @Test fun emptyRejected() {
        assertEquals(BrandAssetRejection.EMPTY, reason(BrandAssetValidator.validate(ByteArray(0))))
    }

    @Test fun badSignatureRejected() {
        val bytes = png(256, 256).also { it[1] = 'Q'.code.toByte() }
        assertEquals(BrandAssetRejection.BAD_SIGNATURE, reason(BrandAssetValidator.validate(bytes)))
        assertEquals(BrandAssetRejection.BAD_SIGNATURE, reason(BrandAssetValidator.validate("GIF89a".toByteArray())))
    }

    @Test fun unreadableIhdrRejected() {
        val truncated = png(256, 256).copyOf(20)
        assertEquals(BrandAssetRejection.BAD_IHDR, reason(BrandAssetValidator.validate(truncated)))
        val badCrc = png(256, 256).also { it[29] = (it[29] + 1).toByte() }
        assertEquals(BrandAssetRejection.BAD_IHDR, reason(BrandAssetValidator.validate(badCrc)))
        val wrongType = png(256, 256).also { it[12] = 'X'.code.toByte() }
        assertEquals(BrandAssetRejection.BAD_IHDR, reason(BrandAssetValidator.validate(wrongType)))
    }

    @Test fun notSquareRejected() {
        assertEquals(BrandAssetRejection.NOT_SQUARE, reason(BrandAssetValidator.validate(png(512, 256))))
    }

    @Test fun dimensionsOutOfRangeRejected() {
        assertEquals(BrandAssetRejection.DIMENSIONS_OUT_OF_RANGE, reason(BrandAssetValidator.validate(png(255, 255))))
        assertEquals(BrandAssetRejection.DIMENSIONS_OUT_OF_RANGE, reason(BrandAssetValidator.validate(png(2049, 2049))))
    }

    @Test fun tooLargeRejected() {
        val big = png(256, 256, padding = BrandAssetValidator.MAX_BYTES)
        assertTrue(big.size > BrandAssetValidator.MAX_BYTES)
        assertEquals(BrandAssetRejection.TOO_LARGE, reason(BrandAssetValidator.validate(big)))
        val base = png(256, 256)
        // Justo en el límite (512 KiB) sigue siendo válido.
        val atLimit = png(256, 256, padding = BrandAssetValidator.MAX_BYTES - base.size - 12)
        assertEquals(BrandAssetValidator.MAX_BYTES, atLimit.size)
        assertTrue(BrandAssetValidator.validate(atLimit) is BrandAssetValidation.Valid)
    }

    @Test fun sha256MustMatchLowercaseHex() {
        val bytes = png(256, 256)
        val sha = BrandAssetValidator.sha256Hex(bytes)
        assertTrue(BrandAssetValidator.validate(bytes, sha) is BrandAssetValidation.Valid)
        assertEquals(BrandAssetRejection.SHA256_MISMATCH, reason(BrandAssetValidator.validate(bytes, "0".repeat(64))))
        assertEquals(BrandAssetRejection.SHA256_MISMATCH, reason(BrandAssetValidator.validate(bytes, sha.uppercase())))
        assertEquals(BrandAssetRejection.SHA256_MISMATCH, reason(BrandAssetValidator.validate(bytes, "")))
    }

    // ------------------------------------------------------------------ Repositorio

    private class FakeSource(var next: BrandAssetFetch) : BrandAssetSource {
        var calls = 0
        override suspend fun fetch(): BrandAssetFetch {
            calls++
            return next
        }
    }

    private val clock = object : Clock {
        override fun now(): Instant = Instant.parse("2026-10-05T10:00:00Z")
    }

    private fun repo(source: BrandAssetSource, decodable: (ByteArray) -> Boolean = { true }) =
        BrandAssetRepository(FileBrandAssetStore(tmp.root), source, clock, decodable)

    @Test fun missingCacheUsesBundledLogo() {
        assertSame(BrandLogo.Bundled, repo(BlockedBrandAssetSource).current())
    }

    @Test fun blockedSourceDownloadsNothing() = runBlocking {
        val r = repo(BlockedBrandAssetSource)
        assertEquals(BrandRefreshOutcome.UNAVAILABLE, r.refresh())
        assertSame(BrandLogo.Bundled, r.current())
        assertTrue(tmp.root.listFiles()!!.isEmpty())
    }

    @Test fun validDownloadReplacesCacheAtomically() = runBlocking {
        val bytes = png(512, 512)
        val sha = BrandAssetValidator.sha256Hex(bytes)
        val r = repo(FakeSource(BrandAssetFetch.Downloaded(bytes, sha)))
        assertEquals(BrandRefreshOutcome.REPLACED, r.refresh())
        val cached = r.current() as BrandLogo.Cached
        assertArrayEquals(bytes, cached.bytes)
        assertEquals(BrandAssetCacheMeta(sha, 512, 512, bytes.size, "2026-10-05T10:00:00Z"), cached.meta)
        assertFalse("sin temporal tras confirmar", tmp.root.list()!!.any { it.endsWith(".tmp") })
        // Misma imagen otra vez: sin cambios.
        assertEquals(BrandRefreshOutcome.UNCHANGED, r.refresh())
    }

    @Test fun invalidDownloadNeverReplacesValidCache() = runBlocking {
        val good = png(512, 512)
        val source = FakeSource(BrandAssetFetch.Downloaded(good, null))
        val r = repo(source)
        assertEquals(BrandRefreshOutcome.REPLACED, r.refresh())

        val bad = listOf(
            BrandAssetFetch.Downloaded(png(512, 300), null),
            BrandAssetFetch.Downloaded(png(128, 128), null),
            BrandAssetFetch.Downloaded(png(256, 256).also { it[0] = 0 }, null),
            BrandAssetFetch.Downloaded(png(256, 256), "f".repeat(64)),
            BrandAssetFetch.Downloaded(png(256, 256, padding = BrandAssetValidator.MAX_BYTES), null),
            BrandAssetFetch.Downloaded(ByteArray(0), null),
        )
        for (fetch in bad) {
            source.next = fetch
            assertEquals(BrandRefreshOutcome.REJECTED, r.refresh())
            assertArrayEquals(good, (r.current() as BrandLogo.Cached).bytes)
            assertFalse(tmp.root.list()!!.any { it.endsWith(".tmp") })
        }
    }

    @Test fun undecodableOnPlatformIsRejected() = runBlocking {
        val good = png(512, 512)
        val source = FakeSource(BrandAssetFetch.Downloaded(good, null))
        var decodes = true
        val r = repo(source) { decodes }
        r.refresh()
        decodes = false
        source.next = BrandAssetFetch.Downloaded(png(1024, 1024), null)
        assertEquals(BrandRefreshOutcome.REJECTED, r.refresh())
        assertArrayEquals(good, (r.current() as BrandLogo.Cached).bytes)
        // Un decodificador que lanza también rechaza.
        val r2 = repo(source) { throw IllegalStateException("x") }
        assertEquals(BrandRefreshOutcome.REJECTED, r2.refresh())
    }

    @Test fun storageFailureKeepsPreviousCache() = runBlocking {
        val good = png(512, 512)
        val store = FileBrandAssetStore(tmp.root)
        BrandAssetRepository(store, FakeSource(BrandAssetFetch.Downloaded(good, null)), clock).refresh()
        val failing = object : BrandAssetStore by store {
            override fun commitTemp(meta: BrandAssetCacheMeta) = throw IOException("disco lleno")
        }
        val r = BrandAssetRepository(failing, FakeSource(BrandAssetFetch.Downloaded(png(1024, 1024), null)), clock)
        assertEquals(BrandRefreshOutcome.FAILED, r.refresh())
        assertArrayEquals(good, (r.current() as BrandLogo.Cached).bytes)
    }

    @Test fun corruptedCacheFallsBackToBundled() = runBlocking {
        val good = png(512, 512)
        val r = repo(FakeSource(BrandAssetFetch.Downloaded(good, null)))
        r.refresh()
        val sha = BrandAssetValidator.sha256Hex(good)
        tmp.root.resolve("brand-$sha.png").writeBytes(good.copyOf(good.size - 1) + byteArrayOf(1))
        assertSame(BrandLogo.Bundled, r.current())
        tmp.root.resolve("brand.json").writeText("{no json")
        assertSame(BrandLogo.Bundled, r.current())
    }

    // ------------------------------------------------------------------ Política y tiempos

    @Test fun welcomePolicyAllBranches() {
        assertTrue(WelcomePolicy.shouldShow(true, false, false, false, false))
        assertFalse("no es arranque en frío", WelcomePolicy.shouldShow(false, false, false, false, false))
        assertFalse("trayecto activo/restaurado", WelcomePolicy.shouldShow(true, true, false, false, false))
        assertFalse("enlace directo", WelcomePolicy.shouldShow(true, false, true, false, false))
        assertFalse("SOS", WelcomePolicy.shouldShow(true, false, false, true, false))
        assertFalse("ya mostrada", WelcomePolicy.shouldShow(true, false, false, false, true))
        // Sólo la combinación con todo favorable la muestra.
        var shown = 0
        for (mask in 0 until 32) {
            val b = BooleanArray(5) { (mask shr it) and 1 == 1 }
            if (WelcomePolicy.shouldShow(b[0], b[1], b[2], b[3], b[4])) shown++
        }
        assertEquals(1, shown)
    }

    @Test fun welcomeTiming() {
        assertEquals(600L, WelcomeTiming.VISIBLE_MS)
        assertEquals(400L, WelcomeTiming.FADE_MS)
        assertTrue(WelcomeTiming.VISIBLE_MS + WelcomeTiming.FADE_MS <= WelcomeTiming.TOTAL_MAX_MS)
        assertEquals(WelcomeTiming.VISIBLE_MS, WelcomeTiming.REDUCED_MOTION_TOTAL_MS)
    }
}
