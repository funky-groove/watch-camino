package org.caminoseguro.watch.platform

import android.app.LocaleManager
import android.content.Context
import android.os.Build
import android.os.LocaleList
import android.util.Log
import androidx.annotation.RequiresApi
import org.caminoseguro.watch.core.AppLanguage
import org.caminoseguro.watch.core.DisplayFormat

/**
 * Idioma de la app (V1.1 §G). En API 33+ hay idioma por app con `LocaleManager` (del framework;
 * no se añade AppCompat): el sistema lo guarda, lo aplica a todo el proceso (actividades, servicio
 * de la complicación, notificaciones) y recrea la actividad. Los idiomas ofrecidos están en
 * `res/xml/locales_config.xml` (`android:localeConfig`). En API 30–32 la app sigue el idioma del reloj.
 */
object AppLocale {

    /** ¿Se puede elegir idioma desde la app? */
    val isSelectable: Boolean get() = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU

    /**
     * Idioma efectivo con el que se resolvieron los recursos de [context] (lo que se ve en pantalla):
     * es el que debe usarse para separadores decimales y textos hablados.
     */
    fun effective(context: Context): AppLanguage {
        val locales = context.resources.configuration.locales
        return DisplayFormat.languageOf(if (locales.isEmpty) null else locales[0].toLanguageTag())
    }

    /** Idioma elegido en la app, o null si sigue al reloj (siempre null en API < 33). */
    fun chosen(context: Context): AppLanguage? {
        if (!isSelectable) return null
        return chosenApi33(context)
    }

    /** Fija el idioma de la app (null = idioma del reloj). Sin efecto en API < 33. */
    fun choose(context: Context, language: AppLanguage?) {
        if (!isSelectable) return
        chooseApi33(context, language)
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun chosenApi33(context: Context): AppLanguage? {
        val manager = context.getSystemService(LocaleManager::class.java) ?: return null
        val locales = manager.applicationLocales
        if (locales.isEmpty) return null
        return DisplayFormat.languageOf(locales[0].toLanguageTag())
    }

    @RequiresApi(Build.VERSION_CODES.TIRAMISU)
    private fun chooseApi33(context: Context, language: AppLanguage?) {
        val manager = context.getSystemService(LocaleManager::class.java) ?: return
        try {
            manager.applicationLocales =
                if (language == null) LocaleList.getEmptyLocaleList() else LocaleList.forLanguageTags(language.name)
        } catch (e: RuntimeException) {
            Log.w("CaminoLocale", "Idioma no aplicado: ${e.javaClass.simpleName}")
        }
    }
}
