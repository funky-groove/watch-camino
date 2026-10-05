package org.caminoseguro.watch.demo

import android.app.Activity
import android.app.Application
import android.content.ContentProvider
import android.content.ContentValues
import android.content.pm.ApplicationInfo
import android.database.Cursor
import android.net.Uri
import android.os.Bundle
import org.caminoseguro.watch.BuildConfig
import org.caminoseguro.watch.CaminoApplication
import org.caminoseguro.watch.DemoHooks

/**
 * Arranque de los escenarios de demostración (SÓLO Debug: declarado en
 * `src/debug/AndroidManifest.xml` con `android:exported="false"`; no expone datos).
 *
 * Un ContentProvider se crea antes de `Application.onCreate`, sin que `src/main` lo conozca. Aquí:
 * 1. registra `DemoHooks.apply` (objeto de `src/main`, null en Release);
 * 2. registra un `ActivityLifecycleCallbacks` que, en `onActivityPreCreated` (antes de
 *    `MainActivity.onCreate` y, por tanto, antes del ViewModel), lee los extras `demo.*`, aplica
 *    idioma/ruta e instala el escenario en el contenedor.
 * Sin extras `demo.scenario` no se hace nada: la app Debug funciona igual que siempre.
 */
class DemoBootstrapProvider : ContentProvider() {

    override fun onCreate(): Boolean {
        val app = context?.applicationContext as? Application ?: return true
        // F-01: doble cerrojo además de existir sólo en src/debug: build Debug y proceso depurable.
        // (No se puede saber con certeza si el lanzamiento viene de adb/shell; por eso la pantalla
        // SOS marca DEMO y «Simulado» siempre que el marcador sea el simulado.)
        val debuggable = (app.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE) != 0
        if (!BuildConfig.DEBUG || !debuggable) return true
        registerHook(app)
        app.registerActivityLifecycleCallbacks(Callbacks(app))
        return true
    }

    private class Callbacks(private val app: Application) : Application.ActivityLifecycleCallbacks {
        override fun onActivityPreCreated(activity: Activity, savedInstanceState: Bundle?) {
            DemoScenarioInstaller.onActivityPreCreated(activity, firstCreate = savedInstanceState == null)
            val container = (activity.application as? CaminoApplication)?.container ?: return
            DemoScenarioInstaller.install(app, container)
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
        override fun onActivityStarted(activity: Activity) = Unit
        override fun onActivityResumed(activity: Activity) = Unit
        override fun onActivityPaused(activity: Activity) = Unit
        override fun onActivityStopped(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) = Unit
    }

    /**
     * `DemoHooks.apply` (src/main) lo invoca `MainActivity.onCreate` antes de `setContent`. La
     * instalación es idempotente: normalmente ya se hizo en `onActivityPreCreated` y esta llamada
     * no hace nada; queda como segunda vía por si el contenedor no estaba disponible entonces.
     */
    private fun registerHook(app: Application) {
        DemoHooks.apply = { container -> DemoScenarioInstaller.install(app, container) }
    }

    // ContentProvider sin datos.
    override fun query(uri: Uri, projection: Array<out String>?, selection: String?, selectionArgs: Array<out String>?, sortOrder: String?): Cursor? = null
    override fun getType(uri: Uri): String? = null
    override fun insert(uri: Uri, values: ContentValues?): Uri? = null
    override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0
    override fun update(uri: Uri, values: ContentValues?, selection: String?, selectionArgs: Array<out String>?): Int = 0

}
