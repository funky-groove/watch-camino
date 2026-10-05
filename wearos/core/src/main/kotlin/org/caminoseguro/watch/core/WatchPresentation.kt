package org.caminoseguro.watch.core

import kotlinx.serialization.Serializable
import java.time.Instant

// Presentación V1.1 compartida por la UI, las notificaciones y la complicación de Wear OS.
// Pura (sin Android): se prueba en JVM con `./gradlew -PcoreOnly=true :core:test`.

// ------------------------------------------------------------------ Preferencias (§G)

/** Preferencias de presentación persistidas en el reloj. Por defecto: métrico y ritmo. */
@Serializable
data class DisplayPreferences(
    val units: UnitSystem = UnitSystem.metric,
    val paceMode: PaceMode = PaceMode.pace,
)

/**
 * Formato de TODAS las cifras visibles y habladas según las preferencias y el idioma efectivo de la
 * app. Una única puerta para que pantalla, TalkBack, notificaciones y complicación digan lo mismo.
 */
data class DisplayFormat(
    val units: UnitSystem = UnitSystem.metric,
    val paceMode: PaceMode = PaceMode.pace,
    val lang: AppLanguage = AppLanguage.es,
) {
    fun distance(meters: Double): String = UnitFormatter.distance(meters, units, lang)
    fun distanceSpoken(meters: Double): String = Spoken.distance(meters, units, lang)
    fun elevation(meters: Double): String = UnitFormatter.elevation(meters, units)
    fun elevationSpoken(meters: Double): String = Spoken.elevation(meters, units, lang)
    fun steps(n: Long): String = UnitFormatter.steps(n, lang)
    fun stepsSpoken(n: Long): String = Spoken.steps(n, lang)
    fun duration(seconds: Long): String = Formatters.duration(seconds)
    fun durationSpoken(seconds: Long): String = Spoken.duration(seconds, lang)

    /** Ritmo o velocidad (preferencia); null = "sin datos" (nunca 0). */
    fun paceOrSpeed(distanceM: Double, movingS: Double): String? =
        UnitFormatter.paceOrSpeed(distanceM, movingS, units, paceMode, lang)

    fun paceOrSpeedSpoken(distanceM: Double, movingS: Double): String? =
        Spoken.paceOrSpeed(distanceM, movingS, units, paceMode, lang)

    /** `"<icono> <nombre> · <distancia>"` (§6) en las unidades del usuario. */
    fun poiAlertText(poi: Poi, distanceMeters: Double): String =
        "${poi.category.icon} ${poi.name} · ${distance(distanceMeters)}"

    companion object {
        fun of(prefs: DisplayPreferences, lang: AppLanguage): DisplayFormat = DisplayFormat(prefs.units, prefs.paceMode, lang)

        /**
         * Idioma efectivo a partir de la etiqueta del locale con el que se resolvieron los recursos:
         * `en*` → inglés; cualquier otro → español (los recursos por defecto son en español).
         */
        fun languageOf(languageTag: String?): AppLanguage =
            if (languageTag?.lowercase()?.startsWith("en") == true) AppLanguage.en else AppLanguage.es
    }
}

/** Versiones habladas (TalkBack): mismas cifras que [UnitFormatter], unidades en palabras. */
object Spoken {

    fun distance(meters: Double, units: UnitSystem, lang: AppLanguage): String =
        withUnitWords(UnitFormatter.distance(meters, units, lang), lang)

    fun elevation(meters: Double, units: UnitSystem, lang: AppLanguage): String =
        withUnitWords(UnitFormatter.elevation(meters, units), lang)

    fun steps(n: Long, lang: AppLanguage): String {
        val text = UnitFormatter.steps(n, lang)
        val one = text == "1"
        return when (lang) {
            AppLanguage.es -> if (one) "1 paso" else "$text pasos"
            AppLanguage.en -> if (one) "1 step" else "$text steps"
        }
    }

    /** "1 hora 5 minutos" / "1 hour 5 minutes". */
    fun duration(seconds: Long, lang: AppLanguage): String {
        if (lang == AppLanguage.es) return Formatters.durationSpoken(seconds)
        val s = maxOf(0L, seconds)
        val minutes = (s % 3600) / 60
        val hours = s / 3600
        val minText = if (minutes == 1L) "1 minute" else "$minutes minutes"
        if (hours == 0L) return minText
        val hourText = if (hours == 1L) "1 hour" else "$hours hours"
        return "$hourText $minText"
    }

    /** "12 minutos 30 segundos por kilómetro" / "20 minutes 7 seconds per mile"; null = sin datos. */
    fun pace(distanceM: Double, movingS: Double, units: UnitSystem, lang: AppLanguage): String? {
        val text = UnitFormatter.pace(distanceM, movingS, units) ?: return null
        val clock = text.substringBefore(' ')
        val minutes = clock.substringBefore(':').toLongOrNull() ?: return text
        val seconds = clock.substringAfter(':').toLongOrNull() ?: return text
        val metric = units == UnitSystem.metric
        return when (lang) {
            AppLanguage.es -> {
                val m = if (minutes == 1L) "1 minuto" else "$minutes minutos"
                val s = if (seconds == 1L) "1 segundo" else "$seconds segundos"
                "$m $s por ${if (metric) "kilómetro" else "milla"}"
            }
            AppLanguage.en -> {
                val m = if (minutes == 1L) "1 minute" else "$minutes minutes"
                val s = if (seconds == 1L) "1 second" else "$seconds seconds"
                "$m $s per ${if (metric) "kilometer" else "mile"}"
            }
        }
    }

    /** "4,8 kilómetros por hora" / "3.0 miles per hour"; null = sin datos. */
    fun speed(distanceM: Double, movingS: Double, units: UnitSystem, lang: AppLanguage): String? {
        val text = UnitFormatter.speed(distanceM, movingS, units, lang) ?: return null
        val number = text.substringBefore(' ')
        val metric = units == UnitSystem.metric
        val unit = when (lang) {
            AppLanguage.es -> if (metric) "kilómetros por hora" else "millas por hora"
            AppLanguage.en -> if (metric) "kilometers per hour" else "miles per hour"
        }
        return "$number $unit"
    }

    fun paceOrSpeed(distanceM: Double, movingS: Double, units: UnitSystem, mode: PaceMode, lang: AppLanguage): String? =
        if (mode == PaceMode.pace) pace(distanceM, movingS, units, lang) else speed(distanceM, movingS, units, lang)

    private fun withUnitWords(text: String, lang: AppLanguage): String {
        val number = text.substringBefore(' ')
        val unit = text.substringAfter(' ', "")
        val one = number == "1" || number == "-1"
        val word = when (lang) {
            AppLanguage.es -> when (unit) {
                "km" -> if (one) "kilómetro" else "kilómetros"
                "m" -> if (one) "metro" else "metros"
                "mi" -> if (one) "milla" else "millas"
                "ft" -> if (one) "pie" else "pies"
                else -> unit
            }
            AppLanguage.en -> when (unit) {
                "km" -> if (one) "kilometer" else "kilometers"
                "m" -> if (one) "meter" else "meters"
                "mi" -> if (one) "mile" else "miles"
                "ft" -> if (one) "foot" else "feet"
                else -> unit
            }
        }
        return "$number $word"
    }
}

// ------------------------------------------------------------------ Aviso de primer uso (§I)

/** Estado persistido del aviso «Accede desde tu esfera». */
@Suppress("EnumEntryName")
@Serializable
enum class FaceHintState { notDecided, dismissed, helpOpened }

object FaceHintPolicy {
    /**
     * Se ofrece una vez, sin trayecto activo y tras la carga inicial. Se aplaza si hay trayecto o si
     * en este arranque se restauró uno (recuperación). Cerrar la app con el aviso abierto no decide
     * nada: se volverá a ofrecer en otro arranque ([offeredThisLaunch] evita repetirlo en éste).
     */
    fun shouldOffer(
        state: FaceHintState,
        ready: Boolean,
        hasActiveTrip: Boolean,
        restoredActiveThisLaunch: Boolean,
        offeredThisLaunch: Boolean,
    ): Boolean = ready &&
        state == FaceHintState.notDecided &&
        !hasActiveTrip &&
        !restoredActiveThisLaunch &&
        !offeredThisLaunch
}

// ------------------------------------------------------------------ Lugares (§B.D y §J)

/** Filtros mínimos de Lugares. */
@Suppress("EnumEntryName")
enum class PlacesFilter { all, water, shelter }

/** Fila de Lugares: distancia en línea recta, o null si no hay ubicación. */
data class PlaceRow(val poi: Poi, val distanceMeters: Double?)

object Places {
    /** Lugares útiles en Trayecto: como máximo 3. */
    const val USEFUL_MAX: Int = 3

    /**
     * Lugares útiles: el agua más cercana, el alojamiento más cercano y el resto por distancia
     * (en línea recta), hasta [USEFUL_MAX]. Sin posición no hay orden posible → lista vacía.
     */
    fun useful(pois: List<Poi>, position: GeoPoint?, max: Int = USEFUL_MAX): List<PoiDistance> {
        if (position == null || max <= 0) return emptyList()
        val sorted = byDistance(pois, position)
        val picked = ArrayList<PoiDistance>(max)
        sorted.firstOrNull { it.poi.category == PoiCategory.water }?.let { picked += it }
        sorted.firstOrNull { it.poi.category == PoiCategory.shelter }?.let { if (picked.size < max) picked += it }
        for (p in sorted) {
            if (picked.size >= max) break
            if (picked.none { it.poi.id == p.poi.id }) picked += p
        }
        return picked
    }

    /** Lista de Lugares: filtrada; por distancia si hay posición, si no por nombre. */
    fun list(pois: List<Poi>, position: GeoPoint?, filter: PlacesFilter): List<PlaceRow> {
        val filtered = pois.filter { matches(it, filter) }
        if (position == null) return filtered.sortedWith(compareBy<Poi> { it.name }.thenBy { it.id }).map { PlaceRow(it, null) }
        return byDistance(filtered, position).map { PlaceRow(it.poi, it.distanceMeters) }
    }

    fun matches(poi: Poi, filter: PlacesFilter): Boolean = when (filter) {
        PlacesFilter.all -> true
        PlacesFilter.water -> poi.category == PoiCategory.water
        PlacesFilter.shelter -> poi.category == PoiCategory.shelter
    }

    private fun byDistance(pois: List<Poi>, position: GeoPoint): List<PoiDistance> =
        pois.map { PoiDistance(it, Geo.haversineMeters(position, it.location)) }
            .sortedWith(compareBy<PoiDistance> { it.distanceMeters }.thenBy { it.poi.id })
}

// ------------------------------------------------------------------ Perfil registrado (§F)

/** Datos para dibujar el perfil: tramos (sin unir huecos `gapBefore`) y límites de los ejes. */
data class ProfileStats(
    val startMeters: Double,
    val endMeters: Double,
    val minAltitude: Double,
    val maxAltitude: Double,
    val segments: List<List<ProfileSample>>,
) {
    /** Distancia que abarca el perfil. */
    val spanMeters: Double get() = endMeters - startMeters
}

object ProfileGeometry {
    /** Mínimo de muestras para dibujar un perfil; con menos → "aún no hay perfil". */
    const val MIN_SAMPLES: Int = 2

    fun stats(profile: List<ProfileSample>): ProfileStats? {
        if (profile.size < MIN_SAMPLES) return null
        return ProfileStats(
            startMeters = profile.first().d,
            endMeters = profile.last().d,
            minAltitude = profile.minOf { it.alt },
            maxAltitude = profile.maxOf { it.alt },
            segments = segments(profile),
        )
    }

    /** Parte el perfil en tramos: una muestra con `gapBefore` empieza un tramo nuevo (no se une). */
    fun segments(profile: List<ProfileSample>): List<List<ProfileSample>> {
        val out = ArrayList<List<ProfileSample>>()
        var current = ArrayList<ProfileSample>()
        for (s in profile) {
            if (s.gapBefore && current.isNotEmpty()) {
                out += current
                current = ArrayList()
            }
            current += s
        }
        if (current.isNotEmpty()) out += current
        return out
    }
}

// ------------------------------------------------------------------ Complicación (§H)

/** Lo que muestra la complicación. Los textos fijos («Iniciar trayecto», «en marcha»…) son recursos. */
sealed interface ComplicationContent {
    /** Sin trayecto: icono + «Iniciar trayecto» / "Camino". */
    data object NoTrip : ComplicationContent

    data class Trip(
        val distanceText: String,
        val distanceSpoken: String,
        val paused: Boolean,
        /** Recorrido / plan de la etapa en [0, 1]; null si no se conoce el plan. */
        val progress: Float?,
    ) : ComplicationContent

    companion object {
        fun of(snapshot: SessionSnapshot, stage: Stage?, format: DisplayFormat): ComplicationContent {
            val s = snapshot.activeSession ?: return NoTrip
            val plan = stage?.takeIf { it.id == s.stageId }?.distanceMeters?.takeIf { it > 0 }
            val progress = plan?.let { (s.distanceMeters / it).coerceIn(0.0, 1.0).toFloat() }
            return Trip(format.distance(s.distanceMeters), format.distanceSpoken(s.distanceMeters), s.isPaused, progress)
        }
    }
}

/**
 * Cuándo pedir al sistema que vuelva a consultar la complicación. Al empezar, pausar, reanudar o
 * finalizar (o al cambiar unidades/idioma) se pide enseguida; por cambio de distancia, como mucho
 * una vez cada [DISTANCE_INTERVAL_S]. Aun así es el SISTEMA quien decide cuándo repinta la esfera.
 */
object ComplicationRefreshPolicy {
    const val DISTANCE_INTERVAL_S: Long = 300

    data class Key(
        val sessionId: String?,
        val paused: Boolean,
        val distanceText: String?,
        val format: DisplayFormat,
    ) {
        companion object {
            fun of(snapshot: SessionSnapshot, format: DisplayFormat): Key {
                val s = snapshot.activeSession
                return Key(s?.sessionId, s?.isPaused ?: false, s?.let { format.distance(it.distanceMeters) }, format)
            }
        }
    }

    /** [lastRequested] es la última clave por la que se pidió actualizar (null = nunca en este proceso). */
    fun shouldRequest(lastRequested: Key?, next: Key, lastRequestAt: Instant?, now: Instant): Boolean {
        if (lastRequested == null || lastRequestAt == null) return true
        if (lastRequested.sessionId != next.sessionId || lastRequested.paused != next.paused) return true
        if (lastRequested.format != next.format) return true
        if (lastRequested.distanceText != next.distanceText) {
            val elapsed = secondsBetween(lastRequestAt, now)
            return elapsed < 0 || elapsed >= DISTANCE_INTERVAL_S
        }
        return false
    }
}
