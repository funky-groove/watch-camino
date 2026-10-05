package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.Instant
import java.util.Locale

/**
 * Pantalla SOS: número, marcador simulado y resumen de ubicación. Mismos casos que
 * `watchos/CaminoCore/Tests/CaminoCoreTests/EmergencyInfoTests.swift` (paridad de umbrales y formato).
 * Sólo se usa [FakeEmergencyDialer]: ningún test abre ni simula abrir una llamada real.
 */
class EmergencyInfoTest {
    private val now: Instant = Instant.ofEpochSecond(1_700_000_000)

    private fun fix(
        lat: Double = 42.7808,
        lon: Double = -7.4141,
        accuracy: Double = 8.0,
        ageSeconds: Long,
    ) = LocationFix(GeoPoint(lat, lon), accuracy, now.minusSeconds(ageSeconds))

    private fun summary(f: LocationFix?, permission: EmergencyLocationPermission = EmergencyLocationPermission.GRANTED) =
        EmergencyLocationSummary.of(f, now, permission)

    // ------------------------------------------------ número

    @Test
    fun emergencyNumberIs112WithTelUri() {
        assertEquals("112", EmergencyNumber.SPAIN_EU.digits)
        assertEquals("tel:112", EmergencyNumber.SPAIN_EU.telUri)
    }

    @Test
    fun invalidNumbersHaveNoUri() {
        assertNull(EmergencyNumber("").telUri)
        assertNull(EmergencyNumber("11 2").telUri)
        assertNull(EmergencyNumber("112;x").telUri)
        assertNull("dígitos no ASCII", EmergencyNumber("١١٢").telUri)
    }

    @Test
    fun numberDoesNotDependOnLocale() {
        val saved = Locale.getDefault()
        try {
            for (locale in listOf(Locale.US, Locale.UK, Locale.forLanguageTag("es-ES"), Locale.GERMANY)) {
                Locale.setDefault(locale)
                assertEquals("tel:112", EmergencyNumber.SPAIN_EU.telUri)
                assertEquals("42.78080", EmergencyCoordinate.latitude(42.7808).degrees)
            }
        } finally {
            Locale.setDefault(saved)
        }
    }

    // ------------------------------------------------ marcador simulado

    @Test
    fun fakeRecordsRequestsAndHandsToSystem() {
        val dialer = FakeEmergencyDialer()
        assertEquals(DialResult.HandedToSystem, dialer.requestDial(EmergencyNumber.SPAIN_EU))
        assertEquals(DialResult.HandedToSystem, dialer.requestDial(EmergencyNumber.SPAIN_EU))
        assertEquals(listOf(EmergencyNumber.SPAIN_EU, EmergencyNumber.SPAIN_EU), dialer.requests)
    }

    @Test
    fun fakeFailsOnInvalidNumber() {
        val dialer = FakeEmergencyDialer()
        assertEquals(DialResult.Failed, dialer.requestDial(EmergencyNumber("")))
        assertEquals(1, dialer.requests.size)
    }

    // ------------------------------------------------ coordenadas

    @Test
    fun coordinatesFiveDecimalsWithHemispheres() {
        val s = summary(fix(lat = 42.780812, lon = -7.414096, ageSeconds = 10))
        assertEquals(EmergencyCoordinate("42.78081", Hemisphere.NORTH), s.latitude)
        assertEquals(EmergencyCoordinate("7.41410", Hemisphere.WEST), s.longitude)
        assertTrue(s.hasCoordinates)
    }

    @Test
    fun southernAndEasternHemispheres() {
        val s = summary(fix(lat = -33.8688, lon = 151.2093, ageSeconds = 0))
        assertEquals(EmergencyCoordinate("33.86880", Hemisphere.SOUTH), s.latitude)
        assertEquals(EmergencyCoordinate("151.20930", Hemisphere.EAST), s.longitude)
    }

    @Test
    fun valueRoundingToZeroIsNotSouthOrWest() {
        assertEquals(EmergencyCoordinate("0.00000", Hemisphere.NORTH), EmergencyCoordinate.latitude(-0.000001))
        assertEquals(EmergencyCoordinate("0.00000", Hemisphere.EAST), EmergencyCoordinate.longitude(-0.000001))
    }

    // ------------------------------------------------ antigüedad

    @Test
    fun currentUpTo60Seconds() {
        val at0 = summary(fix(ageSeconds = 0))
        assertEquals(EmergencyLocationSummary.Status.CURRENT, at0.status)
        assertEquals(0L, at0.ageSeconds)
        val at60 = summary(fix(ageSeconds = 60))
        assertEquals(EmergencyLocationSummary.Status.CURRENT, at60.status)
        assertEquals(60L, at60.ageSeconds)
    }

    @Test
    fun lastKnownFrom61SecondsTo5Minutes() {
        assertEquals(EmergencyLocationSummary.Status.LAST_KNOWN, summary(fix(ageSeconds = 61)).status)
        val at120 = summary(fix(ageSeconds = 120))
        assertEquals(EmergencyLocationSummary.Status.LAST_KNOWN, at120.status)
        assertEquals(120L, at120.ageSeconds)
        assertEquals(EmergencyLocationSummary.Status.LAST_KNOWN, summary(fix(ageSeconds = 300)).status)
    }

    @Test
    fun staleAfter5Minutes() {
        val s = summary(fix(ageSeconds = 301))
        assertEquals(EmergencyLocationSummary.Status.STALE, s.status)
        assertEquals(301L, s.ageSeconds)
        assertTrue("una posición antigua se muestra, marcada como antigua", s.hasCoordinates)
    }

    @Test
    fun futureTimestampHasZeroAge() {
        val s = summary(fix(ageSeconds = -30))
        assertEquals(EmergencyLocationSummary.Status.CURRENT, s.status)
        assertEquals(0L, s.ageSeconds)
    }

    @Test
    fun subSecondAgeIsFloored() {
        val f = LocationFix(GeoPoint(42.0, -7.0), 5.0, now.minusMillis(60_999))
        val s = summary(f)
        assertEquals(60L, s.ageSeconds)
        assertEquals(EmergencyLocationSummary.Status.CURRENT, s.status)
    }

    // ------------------------------------------------ precisión

    @Test
    fun accuracyRounded() {
        assertEquals(13L, summary(fix(accuracy = 12.6, ageSeconds = 5)).accuracyMeters)
    }

    @Test
    fun unknownAccuracyIsNull() {
        val zero = summary(fix(accuracy = 0.0, ageSeconds = 5))
        assertNull(zero.accuracyMeters)
        assertTrue(zero.hasCoordinates)
        assertNull(summary(fix(accuracy = Double.POSITIVE_INFINITY, ageSeconds = 5)).accuracyMeters)
    }

    // ------------------------------------------------ sin posición / sin permiso

    @Test
    fun noFixIsNoSignal() {
        for (permission in listOf(EmergencyLocationPermission.GRANTED, EmergencyLocationPermission.NOT_DETERMINED)) {
            val s = summary(null, permission)
            assertEquals(EmergencyLocationSummary.Status.NO_SIGNAL, s.status)
            assertFalse(s.hasCoordinates)
            assertNull(s.ageSeconds)
            assertNull(s.accuracyMeters)
            assertFalse(s.permissionDenied)
        }
    }

    @Test
    fun deniedWithoutFixIsPermissionDenied() {
        val s = summary(null, EmergencyLocationPermission.DENIED)
        assertEquals(EmergencyLocationSummary.Status.PERMISSION_DENIED, s.status)
        assertTrue(s.permissionDenied)
        assertFalse(s.hasCoordinates)
    }

    @Test
    fun deniedKeepsPreviousFixFlagged() {
        val s = summary(fix(ageSeconds = 600), EmergencyLocationPermission.DENIED)
        assertEquals(EmergencyLocationSummary.Status.STALE, s.status)
        assertTrue(s.permissionDenied)
        assertTrue(s.hasCoordinates)
    }

    @Test
    fun invalidFixesAreNoSignal() {
        val invalid = listOf(
            fix(accuracy = -1.0, ageSeconds = 5),
            fix(accuracy = Double.NaN, ageSeconds = 5),
            fix(lat = Double.NaN, ageSeconds = 5),
            fix(lat = 91.0, ageSeconds = 5),
            fix(lon = -181.0, ageSeconds = 5),
            fix(lon = Double.POSITIVE_INFINITY, ageSeconds = 5),
        )
        for (item in invalid) {
            val s = summary(item)
            assertEquals("$item", EmergencyLocationSummary.Status.NO_SIGNAL, s.status)
            assertFalse(s.hasCoordinates)
        }
    }

    @Test
    fun newestPicksMostRecentValidFix() {
        val old = fix(ageSeconds = 200)
        val recent = fix(ageSeconds = 5)
        val invalid = fix(lat = 95.0, ageSeconds = 0)
        assertEquals(recent, EmergencyLocationSummary.newest(old, null, recent, invalid))
        assertNull(EmergencyLocationSummary.newest(null, invalid))
    }
}
