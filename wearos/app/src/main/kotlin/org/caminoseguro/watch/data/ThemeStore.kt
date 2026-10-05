package org.caminoseguro.watch.data

import org.caminoseguro.watch.core.ThemeId
import java.io.File

/**
 * Tema elegido en Ajustes (Negro/Perla), persistido en `filesDir/camino/theme.json` con la misma
 * escritura atómica que el resto. Sin fichero o ilegible → Negro (valor inicial).
 */
class FileThemeStore(file: File) {
    private val json = JsonFile(
        file = file,
        default = { ThemeId.INITIAL },
        encode = { theme -> "\"${theme.storageKey}\"" },
        decode = { text -> ThemeId.fromStorage(text.trim().removeSurrounding("\"")) },
    )

    suspend fun load(): ThemeId = json.read()

    suspend fun save(theme: ThemeId) {
        json.write(theme)
    }
}
