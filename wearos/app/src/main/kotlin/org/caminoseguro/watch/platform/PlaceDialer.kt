package org.caminoseguro.watch.platform

import android.content.ActivityNotFoundException
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log

/**
 * «Llamar» de la ficha de un lugar (V1.1 §J): abre el marcador del sistema con `ACTION_DIAL`
 * (sin `CALL_PHONE`; el usuario confirma). Devuelve `false` si no hay marcador o el sistema lo
 * impide. `true` sólo significa que se entregó la petición: la app nunca dice que se haya llamado.
 */
object PlaceDialer {
    fun dial(context: Context, telUri: String): Boolean {
        val intent = Intent(Intent.ACTION_DIAL, Uri.parse(telUri)).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        return try {
            context.startActivity(intent)
            true
        } catch (e: ActivityNotFoundException) {
            Log.w(TAG, "Sin marcador para ACTION_DIAL")
            false
        } catch (e: SecurityException) {
            Log.w(TAG, "Marcador denegado: ${e.javaClass.simpleName}")
            false
        }
    }

    private const val TAG = "CaminoPlaces"
}
