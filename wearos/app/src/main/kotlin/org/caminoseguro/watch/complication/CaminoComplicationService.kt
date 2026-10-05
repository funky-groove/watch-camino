package org.caminoseguro.watch.complication

import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.drawable.Icon
import android.util.Log
import androidx.wear.watchface.complications.data.ComplicationData
import androidx.wear.watchface.complications.data.ComplicationText
import androidx.wear.watchface.complications.data.ComplicationType
import androidx.wear.watchface.complications.data.LongTextComplicationData
import androidx.wear.watchface.complications.data.MonochromaticImage
import androidx.wear.watchface.complications.data.MonochromaticImageComplicationData
import androidx.wear.watchface.complications.data.PlainComplicationText
import androidx.wear.watchface.complications.data.RangedValueComplicationData
import androidx.wear.watchface.complications.data.ShortTextComplicationData
import androidx.wear.watchface.complications.datasource.ComplicationRequest
import androidx.wear.watchface.complications.datasource.SuspendingComplicationDataSourceService
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import org.caminoseguro.watch.CaminoApplication
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.ComplicationContent
import org.caminoseguro.watch.core.DisplayFormat
import org.caminoseguro.watch.platform.AppLocale
import org.caminoseguro.watch.ui.MainActivity

/**
 * Complicación de esfera (V1.1 §H) — `ComplicationDataSourceService` de
 * `androidx.wear.watchface.complications.datasource`.
 *
 * - Tipos: SHORT_TEXT, LONG_TEXT, MONOCHROMATIC_IMAGE y RANGED_VALUE (progreso de la etapa).
 * - Sin trayecto: icono + «Iniciar trayecto» (LONG_TEXT) / icono + "Camino" (SHORT_TEXT).
 *   Con trayecto: distancia en las unidades del usuario + «en marcha» / «pausado»; «sin GPS» si la
 *   sesión aún no tiene ningún fix válido, y marca «DEMO» con el adaptador simulado (Debug).
 * - Datos: estado local persistido del controlador (fichero privado de la app), sin red.
 * - Tocar: `PendingIntent` INMUTABLE que abre [MainActivity] en Trayecto. Nunca inicia un trayecto
 *   ni una llamada.
 * - Actualización: `UPDATE_PERIOD_SECONDS = 0` (sin sondeo). La app pide actualizar por eventos
 *   ([ComplicationUpdates]); **el sistema decide cuándo consulta y cuándo repinta la esfera** (puede
 *   agrupar o retrasar las peticiones, y en modo ambiente o con ahorro de batería tardar más).
 */
class CaminoComplicationService : SuspendingComplicationDataSourceService() {

    override suspend fun onComplicationRequest(request: ComplicationRequest): ComplicationData? {
        return try {
            val container = (application as CaminoApplication).container
            val controller = container.controller
            // Lectura local: se espera a que el controlador haya cargado el fichero (sin red).
            withTimeoutOrNull(LOAD_TIMEOUT_MS) { controller.ready.first { it } } ?: return null
            val snapshot = controller.snapshot.value
            val stage = snapshot.activeSession?.let { controller.stage(it.stageId) }
            val format = DisplayFormat.of(container.displayPreferences.value, AppLocale.effective(this))
            build(this, request.complicationType, ComplicationContent.of(snapshot, stage, format, demo = container.isDemo))
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w(TAG, "Complicación sin datos: ${e.javaClass.simpleName}")
            null
        }
    }

    /** Vista previa del selector de complicaciones: un trayecto de ejemplo en marcha. */
    override fun getPreviewData(type: ComplicationType): ComplicationData? {
        val prefs = (application as CaminoApplication).container.displayPreferences.value
        val format = DisplayFormat.of(prefs, AppLocale.effective(this))
        val sample = ComplicationContent.Trip(
            distanceText = format.distance(PREVIEW_METERS),
            distanceSpoken = format.distanceSpoken(PREVIEW_METERS),
            paused = false,
            progress = PREVIEW_PROGRESS,
        )
        return build(this, type, sample, tapAction = null)
    }

    companion object {
        private const val TAG = "CaminoComplication"
        private const val LOAD_TIMEOUT_MS = 3_000L
        private const val PREVIEW_METERS = 4_200.0
        private const val PREVIEW_PROGRESS = 0.19f
        private const val REQUEST_OPEN_TRIP = 7_001

        /** Acción del intent de la complicación: sólo abre Trayecto. */
        const val ACTION_OPEN_TRIP = "org.caminoseguro.watch.action.OPEN_TRIP"

        /** `PendingIntent` inmutable que abre la app en Trayecto (nunca inicia nada). */
        fun openTripIntent(context: Context): PendingIntent {
            val intent = Intent(context, MainActivity::class.java)
                .setAction(ACTION_OPEN_TRIP)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP)
            return PendingIntent.getActivity(
                context,
                REQUEST_OPEN_TRIP,
                intent,
                PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
            )
        }

        internal fun build(
            context: Context,
            type: ComplicationType,
            content: ComplicationContent,
            tapAction: PendingIntent? = openTripIntent(context),
        ): ComplicationData? {
            val icon = MonochromaticImage.Builder(Icon.createWithResource(context, R.drawable.ic_complication)).build()
            val trip = content as? ComplicationContent.Trip
            val status = trip?.let {
                context.getString(if (it.paused) R.string.complication_paused else R.string.complication_moving)
            }
            // F-08: sin ningún fix válido «sin GPS» (no «0 km»); con datos DEMO, marca «DEMO».
            val distance = trip?.let { if (it.noGps) context.getString(R.string.complication_no_gps) else it.distanceText }
            val distanceSpoken = trip?.let {
                if (it.noGps) context.getString(R.string.complication_no_gps_a11y) else it.distanceSpoken
            }
            val demo = trip?.demo == true
            val demoLabel = context.getString(R.string.demo_badge)
            val description = text(
                if (trip == null) {
                    context.getString(R.string.complication_idle_a11y)
                } else {
                    val spoken = context.getString(R.string.complication_trip_a11y, distanceSpoken, status)
                    if (demo) "$demoLabel. $spoken" else spoken
                },
            )
            return when (type) {
                ComplicationType.SHORT_TEXT -> {
                    val main = distance ?: context.getString(R.string.complication_short_idle)
                    // El título es corto: con DEMO, la marca tiene prioridad sobre el estado.
                    val title = if (demo) demoLabel else status
                    ShortTextComplicationData.Builder(text(main), description)
                        .setMonochromaticImage(icon)
                        .apply { if (title != null) setTitle(text(title)) }
                        .setTapAction(tapAction)
                        .build()
                }
                ComplicationType.LONG_TEXT -> {
                    val main = if (trip == null) {
                        context.getString(R.string.action_start_trip)
                    } else {
                        context.getString(R.string.complication_long_trip, distance, status)
                    }
                    val appName = context.getString(R.string.app_name)
                    LongTextComplicationData.Builder(text(main), description)
                        .setMonochromaticImage(icon)
                        .setTitle(text(if (demo) "$demoLabel · $appName" else appName))
                        .setTapAction(tapAction)
                        .build()
                }
                ComplicationType.MONOCHROMATIC_IMAGE ->
                    MonochromaticImageComplicationData.Builder(icon, description)
                        .setTapAction(tapAction)
                        .build()
                ComplicationType.RANGED_VALUE -> {
                    val value = trip?.progress ?: 0f
                    RangedValueComplicationData.Builder(value, 0f, 1f, description)
                        .setMonochromaticImage(icon)
                        .setText(text(distance ?: context.getString(R.string.complication_short_idle)))
                        .apply { if (demo) setTitle(text(demoLabel)) }
                        .setTapAction(tapAction)
                        .build()
                }
                else -> null
            }
        }

        private fun text(value: String): ComplicationText = PlainComplicationText.Builder(value).build()
    }
}
