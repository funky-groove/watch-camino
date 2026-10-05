package org.caminoseguro.watch.data

import org.caminoseguro.watch.core.CaminoJson
import org.caminoseguro.watch.core.DisplayPreferences
import org.caminoseguro.watch.core.FaceHintState
import java.io.File

/**
 * Unidades y ritmo/velocidad (V1.1 §G), junto a [FileThemeStore] y con la misma escritura atómica.
 * Sin fichero o ilegible → métrico + ritmo. El idioma NO se guarda aquí: lo guarda el sistema
 * (`LocaleManager`, API 33+), ver `platform/AppLocale.kt`.
 */
class FileDisplayPreferencesStore(file: File) {
    private val json = JsonFile(
        file = file,
        default = { DisplayPreferences() },
        encode = CaminoJson::encodeDisplayPreferences,
        decode = CaminoJson::decodeDisplayPreferences,
    )

    suspend fun load(): DisplayPreferences = json.read()

    suspend fun save(prefs: DisplayPreferences) {
        json.write(prefs)
    }
}

/** Aviso de primer uso «Accede desde tu esfera» (V1.1 §I). Sin fichero → no decidido. */
class FileFaceHintStore(file: File) {
    private val json = JsonFile(
        file = file,
        default = { FaceHintState.notDecided },
        encode = CaminoJson::encodeFaceHint,
        decode = CaminoJson::decodeFaceHint,
    )

    suspend fun load(): FaceHintState = json.read()

    suspend fun save(state: FaceHintState) {
        json.write(state)
    }
}
