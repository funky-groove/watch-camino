package org.caminoseguro.watch.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import java.io.File
import java.time.Instant
import kotlin.math.floor
import kotlin.math.roundToLong

/** Localiza `shared/` vía system property (Gradle) o subiendo desde el directorio actual. */
object Shared {
    private fun locate(property: String, relative: String): File {
        System.getProperty(property)?.let { return File(it) }
        var dir: File? = File("").absoluteFile
        while (dir != null) {
            val candidate = File(dir, "shared/$relative")
            if (candidate.isDirectory) return candidate
            dir = dir.parentFile
        }
        error("No se encuentra shared/$relative (define -D$property)")
    }

    val conformanceDir: File by lazy { locate("camino.conformanceDir", "conformance") }
    val fixturesDir: File by lazy { locate("camino.fixturesDir", "fixtures") }

    fun conformance(name: String): JsonObject =
        Json.parseToJsonElement(File(conformanceDir, name).readText()).jsonObject

    fun fixture(name: String): String = File(fixturesDir, name).readText()
}

fun epoch(seconds: Double): Instant {
    val whole = floor(seconds)
    val nanos = ((seconds - whole) * 1_000_000_000.0).roundToLong()
    return Instant.ofEpochSecond(whole.toLong(), nanos)
}

val JsonElement.obj: JsonObject get() = jsonObject
val JsonElement.arr: JsonArray get() = jsonArray
val JsonElement.d: Double get() = jsonPrimitive.double
val JsonElement.i: Int get() = jsonPrimitive.int
val JsonElement.s: String get() = jsonPrimitive.content
val JsonElement?.isNull: Boolean get() = this == null || this is JsonNull

fun JsonElement.point(): GeoPoint = GeoPoint(obj["lat"]!!.d, obj["lon"]!!.d)

fun JsonElement.poi(): Poi = CaminoJson.json.decodeFromJsonElement(Poi.serializer(), this)
