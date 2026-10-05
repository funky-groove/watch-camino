package org.caminoseguro.watch.core

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.Serializable
import java.io.File
import java.io.IOException
import java.nio.file.AtomicMoveNotSupportedException
import java.nio.file.Files
import java.nio.file.StandardCopyOption
import java.security.MessageDigest
import java.util.zip.CRC32

// Bienvenida visual con recurso de marca remoto (docs/WATCH_V1_SPEC.md §K). Núcleo puro y testado:
// validación, metadatos de caché, puerto del origen remoto (BLOQUEADO) y repositorio de caché.

// ------------------------------------------------------------------ Validación (§K.1)

/** Motivo de rechazo de un recurso de marca. */
enum class BrandAssetRejection {
    EMPTY,
    TOO_LARGE,
    BAD_SIGNATURE,
    BAD_IHDR,
    NOT_SQUARE,
    DIMENSIONS_OUT_OF_RANGE,
    SHA256_MISMATCH,
    UNDECODABLE,
}

sealed interface BrandAssetValidation {
    data class Valid(val width: Int, val height: Int, val bytes: Int, val sha256: String) : BrandAssetValidation
    data class Invalid(val reason: BrandAssetRejection) : BrandAssetValidation
}

/**
 * Reglas §K.1, todas obligatorias: 0 < bytes ≤ 512 KiB; firma PNG; cabecera IHDR legible (primer
 * fragmento, longitud 13, CRC correcto); cuadrada entre 256 y 2048 px; y, si el manifiesto trae
 * `sha256`, coincidencia exacta (hex en minúsculas). La decodificación de plataforma la añade
 * [BrandAssetRepository] con su `decodable`.
 */
object BrandAssetValidator {
    const val MAX_BYTES: Int = 512 * 1024
    const val MIN_SIDE_PX: Int = 256
    const val MAX_SIDE_PX: Int = 2048

    val PNG_SIGNATURE: ByteArray = byteArrayOf(
        0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    )

    private val IHDR = byteArrayOf(0x49, 0x48, 0x44, 0x52)
    private const val IHDR_LENGTH = 13
    /** Firma (8) + longitud (4) + tipo (4) + datos IHDR (13) + CRC (4). */
    private const val IHDR_END = 8 + 4 + 4 + IHDR_LENGTH + 4
    private val SHA256_HEX = Regex("^[0-9a-f]{64}$")

    fun validate(bytes: ByteArray, expectedSha256: String? = null): BrandAssetValidation {
        if (bytes.isEmpty()) return invalid(BrandAssetRejection.EMPTY)
        if (bytes.size > MAX_BYTES) return invalid(BrandAssetRejection.TOO_LARGE)
        if (bytes.size < PNG_SIGNATURE.size || !PNG_SIGNATURE.indices.all { bytes[it] == PNG_SIGNATURE[it] }) {
            return invalid(BrandAssetRejection.BAD_SIGNATURE)
        }
        if (bytes.size < IHDR_END) return invalid(BrandAssetRejection.BAD_IHDR)
        if (readInt(bytes, 8) != IHDR_LENGTH) return invalid(BrandAssetRejection.BAD_IHDR)
        if (!IHDR.indices.all { bytes[12 + it] == IHDR[it] }) return invalid(BrandAssetRejection.BAD_IHDR)
        val crc = CRC32().apply { update(bytes, 12, 4 + IHDR_LENGTH) }.value
        if (readInt(bytes, 12 + 4 + IHDR_LENGTH).toLong() and 0xFFFFFFFFL != crc) {
            return invalid(BrandAssetRejection.BAD_IHDR)
        }
        val width = readInt(bytes, 16)
        val height = readInt(bytes, 20)
        if (width <= 0 || height <= 0) return invalid(BrandAssetRejection.BAD_IHDR)
        if (width != height) return invalid(BrandAssetRejection.NOT_SQUARE)
        if (width < MIN_SIDE_PX || width > MAX_SIDE_PX) return invalid(BrandAssetRejection.DIMENSIONS_OUT_OF_RANGE)
        val sha = sha256Hex(bytes)
        if (expectedSha256 != null && (!SHA256_HEX.matches(expectedSha256) || expectedSha256 != sha)) {
            return invalid(BrandAssetRejection.SHA256_MISMATCH)
        }
        return BrandAssetValidation.Valid(width = width, height = height, bytes = bytes.size, sha256 = sha)
    }

    fun sha256Hex(bytes: ByteArray): String =
        MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun invalid(reason: BrandAssetRejection) = BrandAssetValidation.Invalid(reason)

    /** Entero de 32 bits big-endian (como en PNG); valores ≥ 2^31 salen negativos y se rechazan. */
    private fun readInt(b: ByteArray, at: Int): Int =
        ((b[at].toInt() and 0xFF) shl 24) or ((b[at + 1].toInt() and 0xFF) shl 16) or
            ((b[at + 2].toInt() and 0xFF) shl 8) or (b[at + 3].toInt() and 0xFF)
}

// ------------------------------------------------------------------ Caché

/** Metadatos de la caché (§K.1). Sin datos personales. `fetchedAt` en ISO-8601 (UTC). */
@Serializable
data class BrandAssetCacheMeta(
    val sha256: String,
    val width: Int,
    val height: Int,
    val bytes: Int,
    val fetchedAt: String,
)

/**
 * Almacén de la caché del recurso de marca (inyectable en tests). Contrato:
 * - [writeTemp] escribe la descarga en un fichero temporal; nunca toca la caché vigente;
 * - [commitTemp] sustituye la caché por el temporal de forma ATÓMICA: tras volver, [readMeta]
 *   devuelve `meta` y [readAsset] los bytes del temporal; si falla, la caché anterior sigue intacta;
 * - las lecturas devuelven null si no hay caché (o no se puede leer).
 */
interface BrandAssetStore {
    fun readMeta(): BrandAssetCacheMeta?
    fun readAsset(meta: BrandAssetCacheMeta): ByteArray?
    fun writeTemp(bytes: ByteArray)
    fun readTemp(): ByteArray?
    fun commitTemp(meta: BrandAssetCacheMeta)
    fun discardTemp()
}

/**
 * [BrandAssetStore] sobre ficheros (JVM puro). La imagen se guarda con su hash en el nombre
 * (`brand-<sha256>.png`) y el punto de confirmación es el reemplazo atómico de `brand.json`
 * (rename): o se ve la caché anterior completa o la nueva completa. Después se borran las
 * imágenes huérfanas.
 */
class FileBrandAssetStore(private val dir: File) : BrandAssetStore {
    private val metaFile get() = File(dir, META)
    private val tempFile get() = File(dir, TEMP)

    override fun readMeta(): BrandAssetCacheMeta? = try {
        if (metaFile.isFile) CaminoJson.json.decodeFromString(BrandAssetCacheMeta.serializer(), metaFile.readText()) else null
    } catch (e: Exception) {
        null
    }

    override fun readAsset(meta: BrandAssetCacheMeta): ByteArray? {
        val f = assetFile(meta.sha256) ?: return null
        return try {
            if (f.isFile && f.length() <= BrandAssetValidator.MAX_BYTES) f.readBytes() else null
        } catch (e: IOException) {
            null
        }
    }

    override fun writeTemp(bytes: ByteArray) {
        dir.mkdirs()
        tempFile.writeBytes(bytes)
    }

    override fun readTemp(): ByteArray? = try {
        if (tempFile.isFile && tempFile.length() <= BrandAssetValidator.MAX_BYTES) tempFile.readBytes() else null
    } catch (e: IOException) {
        null
    }

    override fun commitTemp(meta: BrandAssetCacheMeta) {
        val target = assetFile(meta.sha256) ?: throw IOException("sha256 no válido")
        move(tempFile, target)
        val metaTemp = File(dir, "$META.tmp")
        metaTemp.writeText(CaminoJson.json.encodeToString(BrandAssetCacheMeta.serializer(), meta))
        move(metaTemp, metaFile) // punto de confirmación
        dir.listFiles()?.forEach { f ->
            if (f.name.startsWith(ASSET_PREFIX) && f.name.endsWith(".png") && f.name != target.name) f.delete()
        }
    }

    override fun discardTemp() {
        tempFile.delete()
    }

    private fun assetFile(sha: String): File? =
        if (sha.matches(Regex("^[0-9a-f]{64}$"))) File(dir, "$ASSET_PREFIX$sha.png") else null

    private fun move(from: File, to: File) {
        try {
            Files.move(from.toPath(), to.toPath(), StandardCopyOption.ATOMIC_MOVE, StandardCopyOption.REPLACE_EXISTING)
        } catch (e: AtomicMoveNotSupportedException) {
            Files.move(from.toPath(), to.toPath(), StandardCopyOption.REPLACE_EXISTING)
        }
    }

    private companion object {
        const val META = "brand.json"
        const val TEMP = "brand.download.tmp"
        const val ASSET_PREFIX = "brand-"
    }
}

// ------------------------------------------------------------------ Origen remoto (puerto)

sealed interface BrandAssetFetch {
    /** No hay origen (contrato BLOQUEADO) o no se pudo consultar. */
    data object Unavailable : BrandAssetFetch

    /** Imagen descargada y `sha256` del manifiesto del backoffice (si lo trae). */
    class Downloaded(val bytes: ByteArray, val expectedSha256: String?) : BrandAssetFetch
}

/** Puerto del recurso de marca remoto. Sólo se llama en segundo plano (nunca al abrir). */
interface BrandAssetSource {
    suspend fun fetch(): BrandAssetFetch
}

/** Adaptador mientras no haya contrato (§K, contracts/README.md): no descarga nada. */
object BlockedBrandAssetSource : BrandAssetSource {
    override suspend fun fetch(): BrandAssetFetch = BrandAssetFetch.Unavailable
}

// ------------------------------------------------------------------ Repositorio

/** Logo que se muestra en la bienvenida. */
sealed interface BrandLogo {
    /** Logo incluido en la app (caché ausente o inválida). */
    data object Bundled : BrandLogo

    class Cached(val bytes: ByteArray, val meta: BrandAssetCacheMeta) : BrandLogo
}

enum class BrandRefreshOutcome { UNAVAILABLE, UNCHANGED, REPLACED, REJECTED, FAILED }

/**
 * Caché del recurso de marca (§K.1).
 * - [current]: lee SÓLO la caché local (sin red); si falta o no supera la validación → [BrandLogo.Bundled].
 * - [refresh]: para segundo plano. Descarga → temporal → validación (+ [decodable] de la plataforma)
 *   → sustitución atómica. Un recurso inválido nunca sustituye a uno válido (se descarta el temporal).
 */
class BrandAssetRepository(
    private val store: BrandAssetStore,
    private val source: BrandAssetSource,
    private val clock: Clock,
    private val decodable: (ByteArray) -> Boolean = { true },
) {
    private val mutex = Mutex()

    fun current(): BrandLogo {
        val meta = try {
            store.readMeta()
        } catch (e: Exception) {
            null
        } ?: return BrandLogo.Bundled
        val bytes = try {
            store.readAsset(meta)
        } catch (e: Exception) {
            null
        } ?: return BrandLogo.Bundled
        val v = BrandAssetValidator.validate(bytes, meta.sha256)
        if (v !is BrandAssetValidation.Valid || v.width != meta.width || v.height != meta.height || v.bytes != meta.bytes) {
            return BrandLogo.Bundled
        }
        return BrandLogo.Cached(bytes, meta)
    }

    suspend fun refresh(): BrandRefreshOutcome = mutex.withLock {
        try {
            when (val fetched = source.fetch()) {
                BrandAssetFetch.Unavailable -> BrandRefreshOutcome.UNAVAILABLE
                is BrandAssetFetch.Downloaded -> install(fetched)
            }
        } catch (e: CancellationException) {
            discardQuietly()
            throw e
        } catch (e: Exception) {
            discardQuietly()
            BrandRefreshOutcome.FAILED
        }
    }

    private fun install(fetched: BrandAssetFetch.Downloaded): BrandRefreshOutcome {
        // Rechazo previo barato (tamaño) antes de escribir nada.
        if (fetched.bytes.isEmpty() || fetched.bytes.size > BrandAssetValidator.MAX_BYTES) {
            return BrandRefreshOutcome.REJECTED
        }
        val existing = current()
        if (existing is BrandLogo.Cached && existing.meta.sha256 == BrandAssetValidator.sha256Hex(fetched.bytes)) {
            return BrandRefreshOutcome.UNCHANGED
        }
        store.writeTemp(fetched.bytes)
        val onDisk = store.readTemp()
        val v = onDisk?.let { BrandAssetValidator.validate(it, fetched.expectedSha256) }
        if (onDisk == null || v !is BrandAssetValidation.Valid || !decodableSafe(onDisk)) {
            store.discardTemp()
            return BrandRefreshOutcome.REJECTED
        }
        store.commitTemp(
            BrandAssetCacheMeta(
                sha256 = v.sha256,
                width = v.width,
                height = v.height,
                bytes = v.bytes,
                fetchedAt = clock.now().toString(),
            ),
        )
        return BrandRefreshOutcome.REPLACED
    }

    private fun decodableSafe(bytes: ByteArray): Boolean = try {
        decodable(bytes)
    } catch (e: Exception) {
        false
    }

    private fun discardQuietly() {
        try {
            store.discardTemp()
        } catch (e: Exception) {
            // nada: el temporal nunca se lee como caché
        }
    }
}

// ------------------------------------------------------------------ Cuándo y cuánto (§K.2, §K.3)

/** §K.2: se muestra sólo si TODO se cumple. */
object WelcomePolicy {
    fun shouldShow(
        coldStart: Boolean,
        hasActiveOrRestoredTrip: Boolean,
        launchedFromDeepLink: Boolean,
        launchedForSos: Boolean,
        alreadyShown: Boolean,
    ): Boolean = coldStart && !hasActiveOrRestoredTrip && !launchedFromDeepLink && !launchedForSos && !alreadyShown
}

/** §K.3: duraciones fijadas en código (el backoffice sólo controla la imagen). */
object WelcomeTiming {
    const val VISIBLE_MS: Long = 600
    const val FADE_MS: Long = 400
    const val TOTAL_MAX_MS: Long = 1_000

    /** Con reducción de movimiento: sin animación, retirada de golpe al terminar la parte visible. */
    const val REDUCED_MOTION_TOTAL_MS: Long = VISIBLE_MS
}
