package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant

/**
 * Presentación y controlador de la pantalla SOS con [FakeEmergencyDialer] (no abre nada):
 * entrega al sistema, sin marcador, fallo, y que la telefonía nunca bloquea el intento.
 */
class SosPresentationTest {
    private val now: Instant = Instant.ofEpochSecond(1_700_000_000)
    private val noLocation = EmergencyLocationSummary.of(null, now, EmergencyLocationPermission.GRANTED)
    private val lte = TelephonyCapability(hasTelephony = true, hasCallingFeature = true)
    private val bluetoothOnly = TelephonyCapability(hasTelephony = false, hasCallingFeature = false)

    @Test
    fun handedToSystemSaysDialerOpenedNeverCallPlaced() {
        val dialer = FakeEmergencyDialer(DialResult.HandedToSystem)
        val sos = SosController(dialer)
        assertNull(SosPresentation.outcome(sos.lastResult.value))
        assertEquals(DialResult.HandedToSystem, sos.dial())
        assertEquals(listOf(EmergencyNumber.SPAIN_EU), dialer.requests)
        assertEquals(SosOutcomeMessage.DIALER_OPENED, SosPresentation.outcome(sos.lastResult.value))
    }

    @Test
    fun noDialerGivesNativeSosInstructions() {
        val sos = SosController(FakeEmergencyDialer(DialResult.NoDialer))
        sos.dial()
        assertEquals(SosOutcomeMessage.NO_DIALER, SosPresentation.outcome(sos.lastResult.value))
    }

    @Test
    fun failureGivesNativeSosInstructions() {
        val sos = SosController(FakeEmergencyDialer(DialResult.Failed))
        sos.dial()
        assertEquals(SosOutcomeMessage.FAILED, SosPresentation.outcome(sos.lastResult.value))
    }

    @Test
    fun adapterExceptionBecomesFailed() {
        val sos = SosController(EmergencyDialer { throw IllegalStateException("boom") })
        assertEquals(DialResult.Failed, sos.dial())
        assertEquals(SosOutcomeMessage.FAILED, SosPresentation.outcome(sos.lastResult.value))
    }

    @Test
    fun resetClearsPreviousMessage() {
        val sos = SosController(FakeEmergencyDialer())
        sos.dial()
        sos.reset()
        assertNull(sos.lastResult.value)
    }

    @Test
    fun withoutTelephonyTheAttemptIsStillMade() {
        val dialer = FakeEmergencyDialer(DialResult.HandedToSystem)
        val sos = SosController(dialer)
        val before = SosPresentation.state(sos.number, bluetoothOnly, sos.lastResult.value, noLocation)
        assertTrue("nunca se bloquea el intento", before.actionEnabled)
        assertEquals(DialActionLabel.DIAL, before.actionLabel)
        assertTrue(before.showNoCallingNotice)
        sos.dial()
        assertEquals(1, dialer.requests.size)
        val after = SosPresentation.state(sos.number, bluetoothOnly, sos.lastResult.value, noLocation)
        assertTrue("tras un intento se puede repetir", after.actionEnabled)
        assertEquals(SosOutcomeMessage.DIALER_OPENED, after.outcome)
    }

    @Test
    fun labelFollowsDeclaredCalling() {
        assertEquals(DialActionLabel.CALL, SosPresentation.actionLabel(lte))
        assertFalse(SosPresentation.state(EmergencyNumber.SPAIN_EU, lte, null, noLocation).showNoCallingNotice)
        // API 30-32: sin FEATURE_TELEPHONY_CALLING se decide sólo por FEATURE_TELEPHONY.
        assertEquals(DialActionLabel.CALL, SosPresentation.actionLabel(TelephonyCapability(true, null)))
        // Radio sin servicio de llamadas (API 33+): texto honesto «Marcar 112».
        assertEquals(DialActionLabel.DIAL, SosPresentation.actionLabel(TelephonyCapability(true, false)))
        assertEquals(DialActionLabel.DIAL, SosPresentation.actionLabel(bluetoothOnly))
    }

    @Test
    fun outcomesNeverClaimHelpIsComing() {
        // Los mensajes posibles son exactamente estos tres; ninguno afirma que se haya llamado,
        // enviado una emergencia ni que llegue ayuda (los textos se comprueban en AppResourcesTest).
        assertEquals(
            setOf("DIALER_OPENED", "NO_DIALER", "FAILED"),
            SosOutcomeMessage.entries.map { it.name }.toSet(),
        )
        val results = listOf(DialResult.HandedToSystem, DialResult.NoDialer, DialResult.Failed)
        assertEquals(SosOutcomeMessage.entries.toSet(), results.mapNotNull { SosPresentation.outcome(it) }.toSet())
    }
}
