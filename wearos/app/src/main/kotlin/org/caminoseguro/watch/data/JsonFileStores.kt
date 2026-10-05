package org.caminoseguro.watch.data

import android.util.AtomicFile
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.caminoseguro.watch.core.CaminoJson
import org.caminoseguro.watch.core.PoiCategory
import org.caminoseguro.watch.core.SessionSnapshot
import org.caminoseguro.watch.core.SessionStore
import org.caminoseguro.watch.core.StepCounterState
import org.caminoseguro.watch.core.SyncQueueState
import org.caminoseguro.watch.core.SyncQueueStore
import java.io.File
import java.io.FileOutputStream
import java.io.IOException

/**
 * Fichero JSON en almacenamiento privado de la app, escrito de forma atómica ([AtomicFile]) y con
 * caché en memoria. Si el fichero no se puede leer (error de E/S o contenido corrupto) se aparta a
 * `<nombre>.corrupt-<epochMillis>` ANTES de que nada pueda reescribirlo, se empieza de cero y se deja
 * un aviso ([takeUnreadableNotice]) para la UI (V-03). Si ni siquiera se puede apartar, se bloquean
 * las escrituras para no sobrescribir el original en silencio.
 * Los logs nunca incluyen el contenido (puede llevar coordenadas).
 */
internal class JsonFile<T>(
    private val file: File,
    private val default: () -> T,
    private val encode: (T) -> String,
    private val decode: (String) -> T,
) {
    private val atomic = AtomicFile(file)
    private val mutex = Mutex()
    private var cache: T? = null
    @Volatile private var unreadableNotice = false
    /** No se pudo apartar un fichero ilegible: no se escribe encima. */
    @Volatile private var writesBlocked = false

    /** `true` una sola vez tras una lectura fallida (el fichero se apartó). */
    fun takeUnreadableNotice(): Boolean = unreadableNotice.also { unreadableNotice = false }

    suspend fun read(): T = mutex.withLock {
        cache ?: withContext(Dispatchers.IO) { readFromDisk() }.also { cache = it }
    }

    suspend fun write(value: T) = mutex.withLock {
        if (writesBlocked) throw IOException("${file.name}: original ilegible sin apartar; no se sobrescribe")
        withContext(Dispatchers.IO) { writeToDisk(value) }
        cache = value
    }

    suspend fun delete() = mutex.withLock {
        withContext(Dispatchers.IO) { atomic.delete() }
        cache = null
    }

    private fun readFromDisk(): T {
        // AtomicFile.readFully() restaura un `.bak` pendiente, así que se comprueban ambos.
        if (!atomic.baseFile.exists() && !File(file.path + ".bak").exists()) return default()
        return try {
            decode(String(atomic.readFully(), Charsets.UTF_8))
        } catch (e: Exception) {
            Log.w(TAG, "Fichero ilegible (${file.name}): ${e.javaClass.simpleName}; se aparta")
            setAside()
            default()
        }
    }

    private fun setAside() {
        unreadableNotice = true
        val base = atomic.baseFile
        if (!base.exists()) return
        val target = File(file.parentFile, "${file.name}.corrupt-${System.currentTimeMillis()}")
        val moved = try {
            // Si no se puede renombrar, basta con una copia: el original ya puede reescribirse.
            base.renameTo(target) || run {
                base.copyTo(target, overwrite = false)
                true
            }
        } catch (e: Exception) {
            false
        }
        if (!moved) {
            Log.e(TAG, "No se pudo apartar ${file.name}; se bloquean las escrituras")
            writesBlocked = true
        }
        pruneCopies()
    }

    /** Conserva como mucho [MAX_CORRUPT_COPIES] copias apartadas (pueden llevar coordenadas). */
    private fun pruneCopies() {
        val copies = file.parentFile?.listFiles { f -> f.name.startsWith("${file.name}.corrupt") } ?: return
        copies.sortedByDescending { it.lastModified() }.drop(MAX_CORRUPT_COPIES).forEach { it.delete() }
    }

    private fun writeToDisk(value: T) {
        var out: FileOutputStream? = null
        try {
            out = atomic.startWrite()
            out.write(encode(value).toByteArray(Charsets.UTF_8))
            atomic.finishWrite(out)
        } catch (e: Exception) {
            if (out != null) atomic.failWrite(out)
            Log.e(TAG, "No se pudo guardar ${file.name}: ${e.javaClass.simpleName}")
            throw e
        }
    }

    private companion object {
        const val TAG = "CaminoStore"
        const val MAX_CORRUPT_COPIES = 3
    }
}

class FileSessionStore(file: File) : SessionStore {
    private val json = JsonFile(file, { SessionSnapshot() }, CaminoJson::encodeSession, CaminoJson::decodeSession)
    override suspend fun load(): SessionSnapshot = json.read()
    override suspend fun save(snapshot: SessionSnapshot) {
        json.write(snapshot)
    }
    override fun takeUnreadableNotice(): Boolean = json.takeUnreadableNotice()
}

class FileSyncQueueStore(file: File) : SyncQueueStore {
    private val json = JsonFile(file, { SyncQueueState() }, CaminoJson::encodeSyncQueue, CaminoJson::decodeSyncQueue)
    override suspend fun load(): SyncQueueState = json.read()
    override suspend fun save(state: SyncQueueState) {
        json.write(state)
    }
    override fun takeUnreadableNotice(): Boolean = json.takeUnreadableNotice()
}

/** Ajustes: categorías de POI que avisan (V-08). Por defecto, todas. */
class FileAlertPreferencesStore(file: File) {
    private val json = JsonFile(
        file = file,
        default = { PoiCategory.entries.toSet() },
        encode = CaminoJson::encodeCategories,
        decode = CaminoJson::decodeCategories,
    )

    suspend fun load(): Set<PoiCategory> = json.read()
    suspend fun save(categories: Set<PoiCategory>) {
        json.write(categories)
    }
}

/** Baseline/offset del contador de pasos de la sesión activa (spec §4). */
class FileStepCounterStore(file: File) {
    private val json = JsonFile<StepCounterState?>(
        file = file,
        default = { null },
        encode = { state -> if (state == null) "" else CaminoJson.encodeStepCounter(state) },
        decode = { text -> if (text.isBlank()) null else CaminoJson.decodeStepCounter(text) },
    )

    suspend fun load(): StepCounterState? = json.read()
    suspend fun save(state: StepCounterState) {
        json.write(state)
    }
    suspend fun clear() {
        json.delete()
    }
}
