package org.caminoseguro.watch.complication

import android.content.ComponentName
import android.content.Context
import android.util.Log
import androidx.wear.watchface.complications.datasource.ComplicationDataSourceUpdateRequester
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.launch
import org.caminoseguro.watch.core.ComplicationRefreshPolicy
import org.caminoseguro.watch.core.DisplayFormat
import org.caminoseguro.watch.core.SessionSnapshot
import java.time.Instant

/**
 * Pide al sistema que vuelva a consultar la complicación ([CaminoComplicationService]) cuando
 * cambia lo que muestra: al empezar, pausar, reanudar o finalizar el trayecto y al cambiar las
 * unidades (enseguida), y por distancia como mucho una vez cada 5 min ([ComplicationRefreshPolicy]).
 * `requestUpdateAll()` sólo es una petición: el sistema decide cuándo consulta y repinta.
 */
class ComplicationUpdates(context: Context, private val scope: CoroutineScope) {
    private val appContext = context.applicationContext
    private val requester: ComplicationDataSourceUpdateRequester by lazy {
        ComplicationDataSourceUpdateRequester.create(
            appContext,
            ComponentName(appContext, CaminoComplicationService::class.java),
        )
    }

    private var lastKey: ComplicationRefreshPolicy.Key? = null
    private var lastRequestAt: Instant? = null
    private var observing = false

    /** Observa el estado del controlador y el formato; llamar una vez tras restaurar. */
    fun observe(snapshot: StateFlow<SessionSnapshot>, format: Flow<DisplayFormat>) {
        if (observing) return
        observing = true
        scope.launch {
            combine(snapshot, format) { snap, f -> ComplicationRefreshPolicy.Key.of(snap, f) }
                .collect { key ->
                    val now = Instant.now()
                    if (ComplicationRefreshPolicy.shouldRequest(lastKey, key, lastRequestAt, now)) {
                        lastKey = key
                        lastRequestAt = now
                        requestNow()
                    }
                }
        }
    }

    /** Petición inmediata (p. ej. tras cambiar el idioma). Nunca lanza. */
    fun requestNow() {
        try {
            requester.requestUpdateAll()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "Actualización de complicación no pedida: ${e.javaClass.simpleName}")
        }
    }

    private companion object {
        const val TAG = "CaminoComplication"
    }
}
