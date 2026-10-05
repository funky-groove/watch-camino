package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/** V1.1: formato por preferencias (texto y TalkBack), aviso de esfera, lugares, perfil y complicación. */
class WatchPresentationTest {
    private val origin = GeoPoint(42.7808, -7.4141)
    private fun north(m: Double) = GeoPoint(origin.lat + m / Geo.EARTH_RADIUS_M * 180 / Math.PI, origin.lon)

    @Test
    fun spokenDistancesFollowUnitsAndLanguage() {
        assertEquals("4,2 kilómetros", Spoken.distance(4200.0, UnitSystem.metric, AppLanguage.es))
        assertEquals("4.2 kilometers", Spoken.distance(4200.0, UnitSystem.metric, AppLanguage.en))
        assertEquals("340 metros", Spoken.distance(340.0, UnitSystem.metric, AppLanguage.es))
        assertEquals("2.6 miles", Spoken.distance(4200.0, UnitSystem.imperial, AppLanguage.en))
        assertEquals("2,6 millas", Spoken.distance(4200.0, UnitSystem.imperial, AppLanguage.es))
        assertEquals("1.0 kilometers", Spoken.distance(1000.0, UnitSystem.metric, AppLanguage.en))
        assertTrue(Spoken.distance(50.0, UnitSystem.imperial, AppLanguage.en).endsWith(" feet"))
        assertEquals("412 metros", Spoken.elevation(412.4, UnitSystem.metric, AppLanguage.es))
        assertEquals("1352 feet", Spoken.elevation(412.0, UnitSystem.imperial, AppLanguage.en))
        assertEquals("1 meter", Spoken.elevation(1.0, UnitSystem.metric, AppLanguage.en))
    }

    @Test
    fun spokenPaceSpeedDurationSteps() {
        // 1 km en 750 s → 12:30 /km.
        assertEquals("12 minutos 30 segundos por kilómetro", Spoken.pace(1000.0, 750.0, UnitSystem.metric, AppLanguage.es))
        assertEquals("12 minutes 30 seconds per kilometer", Spoken.pace(1000.0, 750.0, UnitSystem.metric, AppLanguage.en))
        assertNull(Spoken.pace(50.0, 750.0, UnitSystem.metric, AppLanguage.es))
        assertEquals("4,8 kilómetros por hora", Spoken.speed(1000.0, 750.0, UnitSystem.metric, AppLanguage.es))
        assertEquals("3.0 miles per hour", Spoken.speed(1000.0, 750.0, UnitSystem.imperial, AppLanguage.en))
        assertEquals("1 hour 5 minutes", Spoken.duration(3900, AppLanguage.en))
        assertEquals("1 hora 5 minutos", Spoken.duration(3900, AppLanguage.es))
        assertEquals("1,234 steps", Spoken.steps(1234, AppLanguage.en))
        assertEquals("1.234 pasos", Spoken.steps(1234, AppLanguage.es))
        assertEquals("1 step", Spoken.steps(1, AppLanguage.en))
    }

    @Test
    fun displayFormatAppliesPreferences() {
        val en = DisplayFormat(UnitSystem.imperial, PaceMode.speed, AppLanguage.en)
        assertEquals("2.6 mi", en.distance(4200.0))
        assertEquals("1352 ft", en.elevation(412.0))
        assertEquals("3.0 mph", en.paceOrSpeed(1000.0, 750.0))
        assertNull(en.paceOrSpeed(1000.0, 30.0))
        val es = DisplayFormat()
        assertEquals("4,2 km", es.distance(4200.0))
        assertEquals("12:30 /km", es.paceOrSpeed(1000.0, 750.0))
        val poi = Poi("p", "s", "Fuente", PoiCategory.water, origin)
        assertEquals("💧 Fuente · 0.2 mi", en.poiAlertText(poi, 340.0))
        assertEquals(AppLanguage.en, DisplayFormat.languageOf("en-GB"))
        assertEquals(AppLanguage.es, DisplayFormat.languageOf("es-ES"))
        assertEquals(AppLanguage.es, DisplayFormat.languageOf("fr"))
        assertEquals(AppLanguage.es, DisplayFormat.languageOf(null))
    }

    @Test
    fun preferencesRoundTripAndDefaults() {
        assertEquals(DisplayPreferences(UnitSystem.metric, PaceMode.pace), CaminoJson.decodeDisplayPreferences("{}"))
        val prefs = DisplayPreferences(UnitSystem.imperial, PaceMode.speed)
        assertEquals(prefs, CaminoJson.decodeDisplayPreferences(CaminoJson.encodeDisplayPreferences(prefs)))
        for (state in FaceHintState.entries) {
            assertEquals(state, CaminoJson.decodeFaceHint(CaminoJson.encodeFaceHint(state)))
        }
    }

    @Test
    fun faceHintIsOfferedOnceWithoutTrip() {
        assertTrue(FaceHintPolicy.shouldOffer(FaceHintState.notDecided, true, false, false, false))
        assertFalse("sin cargar", FaceHintPolicy.shouldOffer(FaceHintState.notDecided, false, false, false, false))
        assertFalse("trayecto activo", FaceHintPolicy.shouldOffer(FaceHintState.notDecided, true, true, false, false))
        assertFalse("recuperado en este arranque", FaceHintPolicy.shouldOffer(FaceHintState.notDecided, true, false, true, false))
        assertFalse("ya ofrecido", FaceHintPolicy.shouldOffer(FaceHintState.notDecided, true, false, false, true))
        assertFalse(FaceHintPolicy.shouldOffer(FaceHintState.dismissed, true, false, false, false))
        assertFalse(FaceHintPolicy.shouldOffer(FaceHintState.helpOpened, true, false, false, false))
    }

    @Test
    fun usefulPlacesPrioritiseWaterAndShelter() {
        val pois = listOf(
            Poi("l1", "s", "Iglesia", PoiCategory.landmark, north(50.0)),
            Poi("f1", "s", "Bar", PoiCategory.food, north(80.0)),
            Poi("w1", "s", "Fuente lejana", PoiCategory.water, north(900.0)),
            Poi("w2", "s", "Fuente", PoiCategory.water, north(500.0)),
            Poi("h1", "s", "Albergue", PoiCategory.shelter, north(2000.0)),
        )
        val useful = Places.useful(pois, origin)
        assertEquals(listOf("w2", "h1", "l1"), useful.map { it.poi.id })
        assertTrue(Places.useful(pois, null).isEmpty())
        // Sin alojamiento: agua y después el resto por distancia.
        assertEquals(listOf("w2", "l1", "f1"), Places.useful(pois.filter { it.category != PoiCategory.shelter }, origin).map { it.poi.id })
        assertEquals(3, Places.useful(pois, origin).size)
    }

    @Test
    fun placesListFiltersAndSorts() {
        val pois = listOf(
            Poi("b", "s", "Bravo", PoiCategory.water, north(500.0)),
            Poi("a", "s", "Alfa", PoiCategory.shelter, north(100.0)),
            Poi("c", "s", "Charlie", PoiCategory.water, north(50.0)),
        )
        assertEquals(listOf("c", "a", "b"), Places.list(pois, origin, PlacesFilter.all).map { it.poi.id })
        assertEquals(listOf("c", "b"), Places.list(pois, origin, PlacesFilter.water).map { it.poi.id })
        assertEquals(listOf("a"), Places.list(pois, origin, PlacesFilter.shelter).map { it.poi.id })
        val noPosition = Places.list(pois, null, PlacesFilter.all)
        assertEquals(listOf("a", "b", "c"), noPosition.map { it.poi.id })
        assertTrue(noPosition.all { it.distanceMeters == null })
        assertTrue(Places.list(pois, origin, PlacesFilter.all).all { it.distanceMeters != null })
    }

    @Test
    fun profileSegmentsDoNotJoinGaps() {
        assertNull(ProfileGeometry.stats(emptyList()))
        assertNull(ProfileGeometry.stats(listOf(ProfileSample(0.0, 400.0))))
        val profile = listOf(
            ProfileSample(0.0, 412.0),
            ProfileSample(60.0, 420.0),
            ProfileSample(400.0, 448.0, gapBefore = true),
            ProfileSample(460.0, 430.0),
        )
        val stats = ProfileGeometry.stats(profile)!!
        assertEquals(2, stats.segments.size)
        assertEquals(listOf(0.0, 60.0), stats.segments[0].map { it.d })
        assertEquals(listOf(400.0, 460.0), stats.segments[1].map { it.d })
        assertEquals(412.0, stats.minAltitude, 0.0)
        assertEquals(448.0, stats.maxAltitude, 0.0)
        assertEquals(460.0, stats.spanMeters, 0.0)
    }

    @Test
    fun complicationContent() {
        val format = DisplayFormat()
        val stage = Stage("s", "S", "A", "B", 10_000, origin, north(10_000.0))
        assertEquals(ComplicationContent.NoTrip, ComplicationContent.of(SessionSnapshot(), stage, format))
        val session = StageSession("S", "s", epoch(0.0), distanceMeters = 4200.0)
        val trip = ComplicationContent.of(SessionSnapshot(SessionState.Active(session)), stage, format) as ComplicationContent.Trip
        assertEquals("4,2 km", trip.distanceText)
        assertEquals("4,2 kilómetros", trip.distanceSpoken)
        assertFalse(trip.paused)
        assertEquals(0.42f, trip.progress!!, 1e-6f)
        val paused = session.copy(pausedAt = epoch(10.0))
        val imperial = DisplayFormat(UnitSystem.imperial, PaceMode.pace, AppLanguage.en)
        val p = ComplicationContent.of(SessionSnapshot(SessionState.Active(paused)), null, imperial) as ComplicationContent.Trip
        assertEquals("2.6 mi", p.distanceText)
        assertTrue(p.paused)
        assertNull(p.progress)
    }

    @Test
    fun complicationRefreshIsEventDrivenAndRateLimitedByDistance() {
        val f = DisplayFormat()
        val idle = ComplicationRefreshPolicy.Key.of(SessionSnapshot(), f)
        val s = StageSession("S", "s", epoch(0.0), distanceMeters = 1000.0)
        val active = ComplicationRefreshPolicy.Key.of(SessionSnapshot(SessionState.Active(s)), f)
        val t0 = epoch(0.0)
        assertTrue("primera vez", ComplicationRefreshPolicy.shouldRequest(null, idle, null, t0))
        assertTrue("empezar", ComplicationRefreshPolicy.shouldRequest(idle, active, t0, epoch(1.0)))
        val paused = ComplicationRefreshPolicy.Key.of(SessionSnapshot(SessionState.Active(s.copy(pausedAt = t0))), f)
        assertTrue("pausar", ComplicationRefreshPolicy.shouldRequest(active, paused, t0, epoch(1.0)))
        assertTrue("finalizar", ComplicationRefreshPolicy.shouldRequest(active, idle, t0, epoch(1.0)))
        val further = ComplicationRefreshPolicy.Key.of(SessionSnapshot(SessionState.Active(s.copy(distanceMeters = 1500.0))), f)
        assertFalse("distancia < 5 min", ComplicationRefreshPolicy.shouldRequest(active, further, t0, epoch(299.0)))
        assertTrue("distancia ≥ 5 min", ComplicationRefreshPolicy.shouldRequest(active, further, t0, epoch(300.0)))
        assertFalse("sin cambios", ComplicationRefreshPolicy.shouldRequest(active, active, t0, epoch(900.0)))
        val imperial = ComplicationRefreshPolicy.Key.of(SessionSnapshot(SessionState.Active(s)), f.copy(units = UnitSystem.imperial))
        assertTrue("unidades", ComplicationRefreshPolicy.shouldRequest(active, imperial, t0, epoch(1.0)))
    }
}
