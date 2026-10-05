package org.caminoseguro.watch.core

import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// Presentación de la pantalla SOS, sin Android (testeable en JVM con FakeEmergencyDialer).

/**
 * Lo que el reloj declara de telefonía (`PackageManager.hasSystemFeature`). Sólo sirve para elegir
 * el TEXTO del botón y un aviso: NUNCA para bloquear el intento de marcar ni para deducir la
 * capacidad de llamar por tener Internet.
 */
data class TelephonyCapability(
    /** `FEATURE_TELEPHONY` ("android.hardware.telephony"). */
    val hasTelephony: Boolean,
    /** `FEATURE_TELEPHONY_CALLING` (API 33+); `null` si el sistema es anterior a API 33. */
    val hasCallingFeature: Boolean?,
) {
    /** El reloj declara radio y (si el sistema lo expone) servicio de llamadas. No garantiza SIM ni cobertura. */
    val declaresCalling: Boolean get() = hasTelephony && hasCallingFeature != false
}

/** Texto honesto de la acción principal. */
enum class DialActionLabel {
    /** "Llamar al 112": el reloj declara telefonía con llamadas. */
    CALL,

    /** "Marcar 112": el reloj no declara llamadas propias; el intento se hace igual. */
    DIAL,
}

/** Mensaje tras el intento. Nunca "llamada realizada", "emergencia enviada" ni "ayuda en camino". */
enum class SosOutcomeMessage {
    /** "Marcador abierto con el 112. Pulsa llamar si es seguro." */
    DIALER_OPENED,

    /** Sin marcador: instrucciones del SOS del reloj y del móvil. */
    NO_DIALER,

    /** Fallo: las mismas instrucciones. */
    FAILED,

    /** "Simulado: no se ha abierto el marcador." (marcador simulado de los escenarios DEMO). */
    SIMULATED,
}

data class SosViewState(
    val number: EmergencyNumber,
    val actionLabel: DialActionLabel,
    /** "Este reloj puede no tener llamadas propias; si no se abre el marcador…". */
    val showNoCallingNotice: Boolean,
    /** La acción principal nunca se deshabilita (ni por falta de telefonía ni tras un intento). */
    val actionEnabled: Boolean,
    val outcome: SosOutcomeMessage?,
    val location: EmergencyLocationSummary,
    /** El marcador es simulado (escenario DEMO): marca DEMO visible y aviso de que no se abre nada. */
    val simulated: Boolean = false,
)

object SosPresentation {

    fun actionLabel(capability: TelephonyCapability): DialActionLabel =
        if (capability.declaresCalling) DialActionLabel.CALL else DialActionLabel.DIAL

    fun outcome(result: DialResult?): SosOutcomeMessage? = when (result) {
        null -> null
        DialResult.HandedToSystem -> SosOutcomeMessage.DIALER_OPENED
        DialResult.NoDialer -> SosOutcomeMessage.NO_DIALER
        DialResult.Failed -> SosOutcomeMessage.FAILED
        DialResult.Simulated -> SosOutcomeMessage.SIMULATED
    }

    fun state(
        number: EmergencyNumber,
        capability: TelephonyCapability,
        lastResult: DialResult?,
        location: EmergencyLocationSummary,
        simulated: Boolean = false,
    ): SosViewState = SosViewState(
        number = number,
        actionLabel = actionLabel(capability),
        showNoCallingNotice = !capability.declaresCalling,
        actionEnabled = true,
        // Con marcador simulado nunca se afirma que se abrió el marcador.
        outcome = outcome(if (simulated && lastResult == DialResult.HandedToSystem) DialResult.Simulated else lastResult),
        location = location,
        simulated = simulated,
    )
}

/**
 * Estado de la acción "Llamar al 112". No conoce el trayecto: abrir el SOS o marcar no pausa ni
 * finaliza nada, y funciona sin sesión ni backend.
 */
class SosController(
    private val dialer: EmergencyDialer,
    val number: EmergencyNumber = EmergencyNumber.SPAIN_EU,
) {
    private val _lastResult = MutableStateFlow<DialResult?>(null)
    val lastResult: StateFlow<DialResult?> = _lastResult.asStateFlow()

    /** El marcador no abre nada (escenario DEMO): la pantalla muestra la marca DEMO. */
    val isSimulated: Boolean get() = dialer.isSimulated

    /**
     * Pide el marcador. Un fallo inesperado del adaptador se convierte en [DialResult.Failed]; un
     * «entregado» de un marcador simulado, en [DialResult.Simulated] (no se abrió nada).
     */
    fun dial(): DialResult {
        val raw = try {
            dialer.requestDial(number)
        } catch (e: RuntimeException) {
            DialResult.Failed
        }
        val result = if (dialer.isSimulated && raw == DialResult.HandedToSystem) DialResult.Simulated else raw
        _lastResult.value = result
        return result
    }

    /** Al abrir la pantalla SOS: sin mensajes de un intento anterior. */
    fun reset() {
        _lastResult.value = null
    }
}
