package org.caminoseguro.watch.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyListAnchorType
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.ListHeader
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.DialActionLabel
import org.caminoseguro.watch.core.EmergencyCoordinate
import org.caminoseguro.watch.core.EmergencyLocationSummary
import org.caminoseguro.watch.core.Hemisphere
import org.caminoseguro.watch.core.SosOutcomeMessage
import org.caminoseguro.watch.core.SosViewState

/**
 * Pantalla SOS (ruta "sos"). Se abre navegando desde la cabecera; se vuelve con el gesto/atrás del
 * sistema (SwipeDismissableNavHost) o con «Volver». Sin menús, formularios, cuenta atrás, pulsación
 * prolongada ni confirmación propia: la confirmación es la del marcador del sistema. No pausa ni
 * finaliza el trayecto, no pide permisos y funciona sin sesión ni backend.
 */
@Composable
fun SosScreen(state: SosViewState, onDial: () -> Unit, onBack: () -> Unit) {
    val palette = LocalPalette.current
    val listState = rememberScalingLazyListState(initialCenterItemIndex = 0)
    Scaffold(
        modifier = Modifier.background(palette.background.toColor()),
        timeText = { TimeText() },
        vignette = vignetteFor(LocalThemeId.current),
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            contentPadding = PaddingValues(start = 10.dp, end = 10.dp, top = timeTextSpace() + 2.dp, bottom = 36.dp),
            anchorType = ScalingLazyListAnchorType.ItemStart,
            autoCentering = null,
        ) {
            item { ListHeader { Text(stringResource(R.string.sos_title)) } }

            // Acción principal: «Llamar al 112» / «Marcar 112». Nunca deshabilitada.
            item {
                val label = when (state.actionLabel) {
                    DialActionLabel.CALL -> stringResource(R.string.sos_call, state.number.digits)
                    DialActionLabel.DIAL -> stringResource(R.string.sos_dial, state.number.digits)
                }
                val hint = stringResource(R.string.sos_call_hint)
                Chip(
                    onClick = onDial,
                    enabled = state.actionEnabled,
                    label = { Text(text = label, maxLines = 3) },
                    colors = ChipDefaults.chipColors(
                        backgroundColor = palette.critical.toColor(),
                        contentColor = palette.actionPrimaryText.toColor(),
                    ),
                    modifier = Modifier
                        .fillMaxWidth()
                        .semantics { contentDescription = "$label. $hint" },
                )
            }

            // Resultado del intento (honesto). TalkBack lo anuncia al aparecer.
            state.outcome?.let { outcome ->
                item {
                    val text = when (outcome) {
                        SosOutcomeMessage.DIALER_OPENED -> stringResource(R.string.sos_result_dialer_opened)
                        SosOutcomeMessage.NO_DIALER -> stringResource(R.string.sos_result_no_dialer)
                        SosOutcomeMessage.FAILED -> stringResource(R.string.sos_result_failed)
                    }
                    Text(
                        text = text,
                        style = MaterialTheme.typography.body2,
                        textAlign = TextAlign.Center,
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics { liveRegion = LiveRegionMode.Polite },
                    )
                }
            }
            if (state.showNoCallingNotice) {
                item { CenteredText(stringResource(R.string.sos_no_calling_notice), style = MaterialTheme.typography.caption2) }
            }

            // Ubicación breve (no se envía a ningún sitio).
            item { SectionLabel(stringResource(R.string.sos_location_section)) }
            emergencyLocationItems(state.location)

            item { CenteredText(stringResource(R.string.sos_scope), style = MaterialTheme.typography.caption1) }

            item { SectionLabel(stringResource(R.string.sos_native_section)) }
            item { CenteredText(stringResource(R.string.sos_native_help), style = MaterialTheme.typography.caption2) }
            item { CenteredText(stringResource(R.string.sos_satellite), style = MaterialTheme.typography.caption2) }

            item { WideChip(text = stringResource(R.string.action_back), onClick = onBack) }
        }
    }
}

private fun androidx.wear.compose.foundation.lazy.ScalingLazyListScope.emergencyLocationItems(
    location: EmergencyLocationSummary,
) {
    item {
        val status = when (location.status) {
            EmergencyLocationSummary.Status.CURRENT -> R.string.sos_location_current
            EmergencyLocationSummary.Status.LAST_KNOWN -> R.string.sos_location_last_known
            EmergencyLocationSummary.Status.STALE -> R.string.sos_location_stale
            EmergencyLocationSummary.Status.NO_SIGNAL -> R.string.sos_location_no_signal
            EmergencyLocationSummary.Status.PERMISSION_DENIED -> R.string.sos_location_denied
        }
        CenteredText(stringResource(status), style = MaterialTheme.typography.caption1)
    }
    val lat = location.latitude
    val lon = location.longitude
    if (lat != null && lon != null) {
        item {
            val shown = stringResource(R.string.sos_coordinates, coordinateText(lat), coordinateText(lon))
            val spoken = stringResource(
                R.string.sos_coordinates_a11y,
                lat.degrees,
                hemisphereSpoken(lat.hemisphere),
                lon.degrees,
                hemisphereSpoken(lon.hemisphere),
            )
            Text(
                text = shown,
                style = MaterialTheme.typography.body1.tabular(),
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .fillMaxWidth()
                    .clearAndSetSemantics { contentDescription = spoken },
            )
        }
        item {
            val age = location.ageSeconds?.let { ageText(it) }
            val ageSpoken = location.ageSeconds?.let { ageSpoken(it) }
            val accuracy = location.accuracyMeters
            val shown = listOfNotNull(
                accuracy?.let { stringResource(R.string.sos_accuracy, it) },
                age,
            ).joinToString(" · ")
            val spoken = listOfNotNull(
                accuracy?.let { stringResource(R.string.sos_accuracy_a11y, it) },
                ageSpoken,
            ).joinToString(", ")
            if (shown.isNotEmpty()) {
                Text(
                    text = shown,
                    style = MaterialTheme.typography.caption1.tabular(),
                    textAlign = TextAlign.Center,
                    modifier = Modifier
                        .fillMaxWidth()
                        .clearAndSetSemantics { contentDescription = spoken },
                )
            }
        }
        if (location.permissionDenied) {
            item { CenteredText(stringResource(R.string.sos_location_denied), style = MaterialTheme.typography.caption2) }
        }
        item { CenteredText(stringResource(R.string.sos_location_not_sent), style = MaterialTheme.typography.caption2) }
    }
}

/** "42.78080° N" (punto decimal siempre; la letra según el idioma: N/S/E/O o N/S/E/W). */
@Composable
private fun coordinateText(c: EmergencyCoordinate): String =
    stringResource(R.string.sos_coordinate, c.degrees, hemisphereLetter(c.hemisphere))

@Composable
private fun hemisphereLetter(h: Hemisphere): String = stringResource(
    when (h) {
        Hemisphere.NORTH -> R.string.sos_hemisphere_n
        Hemisphere.SOUTH -> R.string.sos_hemisphere_s
        Hemisphere.EAST -> R.string.sos_hemisphere_e
        Hemisphere.WEST -> R.string.sos_hemisphere_w
    },
)

@Composable
private fun hemisphereSpoken(h: Hemisphere): String = stringResource(
    when (h) {
        Hemisphere.NORTH -> R.string.sos_hemisphere_n_a11y
        Hemisphere.SOUTH -> R.string.sos_hemisphere_s_a11y
        Hemisphere.EAST -> R.string.sos_hemisphere_e_a11y
        Hemisphere.WEST -> R.string.sos_hemisphere_w_a11y
    },
)

/** "hace 40 s" / "hace 3 min" / "hace 2 h". */
@Composable
private fun ageText(seconds: Long): String = when {
    seconds < 60 -> stringResource(R.string.sos_age_seconds, seconds)
    seconds < 3600 -> stringResource(R.string.sos_age_minutes, seconds / 60)
    else -> stringResource(R.string.sos_age_hours, seconds / 3600)
}

/** "hace 40 segundos" / "hace 1 minuto" (unidades en palabras para TalkBack). */
@Composable
private fun ageSpoken(seconds: Long): String = when {
    seconds < 60 ->
        if (seconds == 1L) stringResource(R.string.sos_age_second_one_a11y) else stringResource(R.string.sos_age_seconds_a11y, seconds)
    seconds < 3600 -> {
        val m = seconds / 60
        if (m == 1L) stringResource(R.string.sos_age_minute_one_a11y) else stringResource(R.string.sos_age_minutes_a11y, m)
    }
    else -> {
        val h = seconds / 3600
        if (h == 1L) stringResource(R.string.sos_age_hour_one_a11y) else stringResource(R.string.sos_age_hours_a11y, h)
    }
}
