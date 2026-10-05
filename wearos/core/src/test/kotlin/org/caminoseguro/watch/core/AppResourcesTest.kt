package org.caminoseguro.watch.core

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import javax.xml.parsers.DocumentBuilderFactory

/**
 * Guardas de los recursos de `:app` que se pueden comprobar SIN Android SDK (se ejecutan con
 * `-PcoreOnly=true`): mismas claves y mismos marcadores en español e inglés (lint MissingTranslation
 * / StringFormat*), apóstrofos escapados (aapt2), toda `R.string.x` usada existe, textos SOS
 * honestos y manifest sin `CALL_PHONE`.
 */
class AppResourcesTest {
    private val appDir: File = File(Shared.conformanceDir.parentFile.parentFile, "wearos/app")
    private val esFile = File(appDir, "src/main/res/values/strings.xml")
    private val enFile = File(appDir, "src/main/res/values-en/strings.xml")

    private fun strings(file: File): Map<String, String> {
        val doc = DocumentBuilderFactory.newInstance().newDocumentBuilder().parse(file)
        val nodes = doc.getElementsByTagName("string")
        return (0 until nodes.length).associate { i ->
            val el = nodes.item(i) as org.w3c.dom.Element
            el.getAttribute("name") to el.textContent
        }
    }

    private fun placeholders(text: String): List<String> =
        Regex("""%(\d+\$)?[sdf]""").findAll(text).map { it.value }.sorted().toList()

    @Test
    fun spanishAndEnglishHaveTheSameKeysAndPlaceholders() {
        assumeTrue(esFile.isFile)
        val es = strings(esFile)
        val en = strings(enFile)
        assertEquals("Claves es/en", es.keys.sorted(), en.keys.sorted())
        for ((key, value) in es) {
            assertEquals("Marcadores de $key", placeholders(value), placeholders(en.getValue(key)))
        }
    }

    @Test
    fun noUnescapedApostrophes() {
        assumeTrue(esFile.isFile)
        for (file in listOf(esFile, enFile)) {
            val raw = file.readText()
            val bad = Regex("""(?<!\\)'""").findAll(raw).count()
            assertEquals("Apóstrofo sin escapar en ${file.path}", 0, bad)
        }
    }

    @Test
    fun everyReferencedStringExists() {
        assumeTrue(esFile.isFile)
        val defined = strings(esFile).keys
        val used = File(appDir, "src").walkTopDown()
            .filter { it.isFile && it.extension == "kt" }
            .flatMap { Regex("""R\.string\.([a-z0-9_]+)""").findAll(it.readText()).map { m -> m.groupValues[1] } }
            .toSet()
        val missing = used - defined
        assertTrue("R.string sin definir: $missing", missing.isEmpty())
    }

    @Test
    fun sosTextsAreHonest() {
        assumeTrue(esFile.isFile)
        val forbidden = listOf(
            "emergencia enviada", "ayuda en camino", "llamada realizada", "llamando al", "ayuda está en camino",
            "emergency sent", "help is on the way", "help on the way", "call placed", "calling 112",
        )
        for (file in listOf(esFile, enFile)) {
            for ((key, value) in strings(file)) {
                val lower = value.lowercase()
                for (phrase in forbidden) assertFalse("$key contiene «$phrase»", lower.contains(phrase))
            }
        }
        val es = strings(esFile)
        assertEquals("Marcador abierto con el 112. Pulsa llamar si es seguro.", es["sos_result_dialer_opened"])
        assertEquals("112: España y UE", es["sos_scope"])
        assertEquals("Estas coordenadas no se envían al 112 automáticamente.", es["sos_location_not_sent"])
        assertTrue(es.getValue("sos_native_help").contains("Varía según el fabricante"))
        assertTrue(es.getValue("sos_satellite").contains("esta app no lo controla"))
        assertEquals("SOS", es["sos_button"])
        val en = strings(enFile)
        assertEquals("W", en["sos_hemisphere_w"])
        assertEquals("O", es["sos_hemisphere_w"])
    }

    @Test
    fun uiUsesTrayectoWording() {
        assumeTrue(esFile.isFile)
        val es = strings(esFile)
        assertEquals("Iniciar trayecto", es["action_start_trip"])
        assertEquals("Finalizar trayecto", es["action_finish_trip"])
    }

    @Test
    fun manifestDialsWithoutCallPhone() {
        val manifest = File(appDir, "src/main/AndroidManifest.xml")
        assumeTrue(manifest.isFile)
        val text = manifest.readText()
        assertFalse("No se declara CALL_PHONE", text.contains("android.permission.CALL_PHONE"))
        assertFalse("No se declara CALL_PRIVILEGED", text.contains("CALL_PRIVILEGED"))
        assertTrue(text.contains("<action android:name=\"android.intent.action.DIAL\" />"))
        assertTrue(text.contains("<data android:scheme=\"tel\" />"))
        val sources = File(appDir, "src").walkTopDown().filter { it.isFile && it.extension == "kt" }.map { it.readText() }
        assertFalse("Nunca ACTION_CALL", sources.any { Regex("""Intent\.ACTION_CALL\b""").containsMatchIn(it) })
    }
}
