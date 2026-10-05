package org.caminoseguro.watch.data

import android.util.AtomicFile
import android.util.Log
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import org.caminoseguro.watch.core.CaminoJson
import org.caminoseguro.watch.core.SessionSnapshot
import org.caminoseguro.watch.core.SessionStore
import org.caminoseguro.watch.core.StepCounterState
import org.caminoseguro.watch.core.SyncQueueState
import org.caminoseguro.watch.core.SyncQueueStore
import java.io.File
import java.io.FileOutputStream

/**
 * Fichero JSON en almacenamiento privado de la app, escrito de forma atómica ([AtomicFile]) y con
 * caché en memoria. Si el contenido está corrupto se aparta a `*.corrupt` y se empieza de cero.
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

    suspend fun read(): T = mutex.withLock {
        cache ?: withContext(Dispatchers.IO) { readFromDisk() }.also { cache = it }
    }

    suspend fun write(value: T) = mutex.withLock {
        withContext(Dispatchers.IO) { writeToDisk(value) }
        cache = value
    }

    suspend fun delete() = mutex.withLock {
        withContext(Dispatchers.IO) { atomic.delete() }
        cache = null
    }

    private fun readFromDisk(): T {
        if (!atomic.baseFile.exists()) return default()
        return try {
            decode(String(atomic.readFully(), Charsets.UTF_8))
        } catch (e: Exception) {
            Log.w(TAG, "Fichero ilegible (${file.name}): ${e.javaClass.simpleName}; se aparta")
            atomic.baseFile.renameTo(File(file.parentFile, file.name + ".corrupt"))
            default()
        }
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
    }
}

class FileSessionStore(file: File) : SessionStore {
    private val json = JsonFile(file, { SessionSnapshot() }, CaminoJson::encodeSession, CaminoJson::decodeSession)
    override suspend fun load(): SessionSnapshot = json.read()
    override suspend fun save(snapshot: SessionSnapshot) {
        json.write(snapshot)
    }
}

class FileSyncQueueStore(file: File) : SyncQueueStore {
    private val json = JsonFile(file, { SyncQueueState() }, CaminoJson::encodeSyncQueue, CaminoJson::decodeSyncQueue)
    override suspend fun load(): SyncQueueState = json.read()
    override suspend fun save(state: SyncQueueState) {
        json.write(state)
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
