package org.caminoseguro.watch.core

import java.util.Locale
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToLong

// Lógica pura de la pantalla SOS (docs/accessibility/SOS_CAPABILITY_MATRIX.md). Sin Android:
// la app conecta [EmergencyDialer] con el sistema (`Intent.ACTION_DIAL`, nunca `ACTION_CALL`).
// Paridad con watchOS (`watchos/CaminoCore/Sources/CaminoCore/EmergencyInfo.swift`): mismos
// umbrales (60 s / 5 min), mismo redondeo y mismo formato de coordenadas.

// ------------------------------------------------------------------ Número de emergencia

/**
 * Número de emergencia que ofrece la app.
 *
 * Alcance documentado: **112, número único de emergencia en España y en la UE**. NO es universal
 * (p. ej. EE. UU. usa 911) y la app NO lo deduce del idioma ni de la región del reloj: un peregrino
 * con el reloj en inglés sigue estando en España.
 */
data class EmergencyNumber(
    /** Sólo dígitos ASCII, sin espacios ni prefijos. */
    val digits: String,
) {
    /**
     * `tel:112`. `null` si el número está vacío o contiene algo que no sea un dígito ASCII (nunca
     * se entrega al sistema una URI construida con texto arbitrario).
     */
    val telUri: String?
        get() = if (digits.isNotEmpty() && digits.all { it in '0'..'9' }) "tel:$digits" else null

    companion object {
        /** 112: España y Unión Europea. Es el único que ofrece la app. */
        val SPAIN_EU = EmergencyNumber("112")
    }
}

// ------------------------------------------------------------------ Entrega al sistema

/**
 * Resultado de pedir al sistema que abra el marcador. Honesto a propósito: la app sólo puede saber
 * que entregó la petición; nunca que la llamada se haya hecho ni conectado.
 */
sealed interface DialResult {
    /** `startActivity(ACTION_DIAL tel:112)` no lanzó: el marcador debería mostrarse con el 112. */
    data object HandedToSystem : DialResult

    /** No hay app que maneje `ACTION_DIAL` + `tel:` (`ActivityNotFoundException`). */
    data object NoDialer : DialResult

    /** Cualquier otro fallo (p. ej. `SecurityException`, número inválido). */
    data object Failed : DialResult

    /**
     * Marcador simulado (escenarios DEMO de Debug): NO se ha abierto nada. La UI lo dice tal cual
     * («Simulado: no se ha abierto el marcador»); nunca «Marcador abierto».
     */
    data object Simulated : DialResult
}

/**
 * Puerto para pedir el marcador. La app usa `SystemEmergencyDialer` (`ACTION_DIAL`); los tests y
 * los escenarios de demostración usan [FakeEmergencyDialer], que no abre nada.
 */
fun interface EmergencyDialer {
    fun requestDial(number: EmergencyNumber): DialResult

    /** `true` si este marcador no abre nada (simulado): la pantalla SOS muestra la marca DEMO. */
    val isSimulated: Boolean get() = false
}

/**
 * Marcador simulado: registra las peticiones y NO abre nada. [isSimulated] es siempre `true`:
 * [SosController] convierte su `HandedToSystem` en [DialResult.Simulated] para que la pantalla no
 * diga nunca «Marcador abierto» cuando no se ha abierto.
 */
class FakeEmergencyDialer(
    /** Resultado que devolverá (por defecto, entregado al sistema). */
    var nextResult: DialResult = DialResult.HandedToSystem,
) : EmergencyDialer {
    override val isSimulated: Boolean get() = true

    private val _requests = mutableListOf<EmergencyNumber>()
    val requests: List<EmergencyNumber> get() = _requests.toList()

    override fun requestDial(number: EmergencyNumber): DialResult {
        _requests += number
        if (number.telUri == null) return DialResult.Failed
        return nextResult
    }
}

// ------------------------------------------------------------------ Ubicación en emergencia

/** Estado del permiso de ubicación tal como lo ve la pantalla SOS (que nunca lo pide). */
enum class EmergencyLocationPermission { NOT_DETERMINED, DENIED, GRANTED }

/** Hemisferio de una coordenada. La app pone la letra en el idioma: N/S/E/O o N/S/E/W. */
enum class Hemisphere { NORTH, SOUTH, EAST, WEST }

/**
 * Coordenada legible: valor absoluto con 5 decimales (≈ 1 m) y hemisferio.
 *
 * Siempre con **punto decimal** e independiente del idioma ("42.78080"), aunque el resto de cifras
 * de la app usen coma: así se dictan las coordenadas y se evita confundir la coma decimal con el
 * separador entre latitud y longitud ("42.78080° N, 7.41410° O").
 */
data class EmergencyCoordinate(val degrees: String, val hemisphere: Hemisphere) {
    companion object {
        fun latitude(value: Double): EmergencyCoordinate {
            val text = format(value)
            val negative = value < 0 && !isZero(text)
            return EmergencyCoordinate(text, if (negative) Hemisphere.SOUTH else Hemisphere.NORTH)
        }

        fun longitude(value: Double): EmergencyCoordinate {
            val text = format(value)
            val negative = value < 0 && !isZero(text)
            return EmergencyCoordinate(text, if (negative) Hemisphere.WEST else Hemisphere.EAST)
        }

        /** Formato independiente del idioma del reloj (ROOT: punto decimal, sin miles). */
        internal fun format(value: Double): String = String.format(Locale.ROOT, "%.5f", abs(value))

        private fun isZero(text: String): Boolean = text.all { it == '0' || it == '.' }
    }
}

/**
 * Resumen de la ubicación para la pantalla SOS. No pide permiso ni espera al GPS: clasifica lo que
 * ya hay. No se envía a ningún sitio.
 */
data class EmergencyLocationSummary(
    val status: Status,
    val latitude: EmergencyCoordinate?,
    val longitude: EmergencyCoordinate?,
    /** Antigüedad en segundos (0 si la hora del fix es futura). */
    val ageSeconds: Long?,
    /** Precisión redondeada (±m); `null` si el sistema no la da. */
    val accuracyMeters: Long?,
    /** El permiso está denegado (puede quedar una posición anterior a la denegación). */
    val permissionDenied: Boolean,
) {
    enum class Status {
        /** Posición de hace ≤ [CURRENT_MAX_AGE_SECONDS]. */
        CURRENT,

        /** Última conocida: más antigua que CURRENT, hasta [STALE_AFTER_SECONDS]. */
        LAST_KNOWN,

        /** Más antigua que [STALE_AFTER_SECONDS]: puede no ser donde estás. */
        STALE,

        /** Sin ninguna posición válida (con permiso concedido o sin decidir). */
        NO_SIGNAL,

        /** Sin permiso de ubicación y sin ninguna posición anterior. */
        PERMISSION_DENIED,
    }

    val hasCoordinates: Boolean get() = latitude != null && longitude != null

    companion object {
        /** Hasta 60 s se considera la posición actual. */
        const val CURRENT_MAX_AGE_SECONDS = 60L

        /** Más de 5 min: antigua. */
        const val STALE_AFTER_SECONDS = 300L

        fun of(
            fix: LocationFix?,
            now: java.time.Instant,
            permission: EmergencyLocationPermission,
        ): EmergencyLocationSummary {
            val denied = permission == EmergencyLocationPermission.DENIED
            if (fix == null || !isValid(fix)) {
                return EmergencyLocationSummary(
                    status = if (denied) Status.PERMISSION_DENIED else Status.NO_SIGNAL,
                    latitude = null,
                    longitude = null,
                    ageSeconds = null,
                    accuracyMeters = null,
                    permissionDenied = denied,
                )
            }
            val ageMs = now.toEpochMilli() - fix.timestamp.toEpochMilli()
            val age = max(0L, Math.floorDiv(ageMs, 1000L))
            val status = when {
                age <= CURRENT_MAX_AGE_SECONDS -> Status.CURRENT
                age <= STALE_AFTER_SECONDS -> Status.LAST_KNOWN
                else -> Status.STALE
            }
            val accuracy = fix.accuracyMeters
            val roundedAccuracy = if (accuracy.isFinite() && accuracy > 0) min(accuracy, 1.0e6).roundToLong() else null
            return EmergencyLocationSummary(
                status = status,
                latitude = EmergencyCoordinate.latitude(fix.point.lat),
                longitude = EmergencyCoordinate.longitude(fix.point.lon),
                ageSeconds = age,
                accuracyMeters = roundedAccuracy,
                permissionDenied = denied,
            )
        }

        /** La más reciente de varias posiciones (las inválidas se ignoran). */
        fun newest(vararg fixes: LocationFix?): LocationFix? =
            fixes.filterNotNull().filter { isValid(it) }.maxByOrNull { it.timestamp }

        /** Coordenadas finitas y en rango; precisión negativa o NaN = posición inválida. */
        private fun isValid(fix: LocationFix): Boolean {
            val lat = fix.point.lat
            val lon = fix.point.lon
            if (!lat.isFinite() || !lon.isFinite() || abs(lat) > 90 || abs(lon) > 180) return false
            if (fix.accuracyMeters.isNaN() || fix.accuracyMeters < 0) return false
            return true
        }
    }
}
