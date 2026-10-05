package org.caminoseguro.watch.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.wear.compose.foundation.lazy.ScalingLazyListScope
import androidx.wear.compose.foundation.lazy.ScalingLazyListState
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.ListHeader
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.StorageIssue

// Pantalla principal (ruta "home"): sin trayecto (Inicio) o con trayecto en curso. Ambas con la
// cabecera fija «SOS» arriba a la derecha, accesible sin recorrer las estadísticas.

// ------------------------------------------------------------------ Cargando

@Composable
fun TripLoadingScreen(listState: ScalingLazyListState, onSos: () -> Unit) {
    TripScaffold(listState = listState, onSos = onSos) {
        item { CenteredText(stringResource(R.string.loading)) }
    }
}

// ------------------------------------------------------------------ 1. Sin trayecto

@Composable
fun TripIdleScreen(
    state: CaminoUiState,
    listState: ScalingLazyListState,
    startBusy: Boolean,
    onStart: () -> Unit,
    onSos: () -> Unit,
    onPlaces: () -> Unit,
    onStats: () -> Unit,
    onSync: () -> Unit,
    onSettings: () -> Unit,
    onDismissIssue: (StorageIssue) -> Unit,
) {
    TripScaffold(listState = listState, onSos = onSos) {
        demoBadge(state.isDemo)
        item { ListHeader { Text(stringResource(R.string.home_title)) } }
        item {
            // Deshabilitado tras el primer toque (además del ActionGate del ViewModel): no hay doble inicio.
            WideChip(
                text = stringResource(R.string.action_start_trip),
                onClick = onStart,
                primary = true,
                enabled = !startBusy,
            )
        }
        permissionStatus(state)
        storageWarnings(state, onDismissIssue)
        // Lugares sin trayecto (spec V1.1 §A).
        item { WideChip(text = stringResource(R.string.places_title), onClick = onPlaces) }
        item { WideChip(text = stringResource(R.string.action_stats), onClick = onStats) }
        item { SyncStatusChip(state.sync, state.isDemo, onSync) }
        item { WideChip(text = stringResource(R.string.action_settings), onClick = onSettings) }
    }
}

/** Explicación breve de los permisos y su estado REAL (texto, no sólo color). */
private fun ScalingLazyListScope.permissionStatus(state: CaminoUiState) {
    val p = state.permissions
    item { CenteredText(stringResource(R.string.perm_explain), style = MaterialTheme.typography.caption2) }
    item {
        CenteredText(
            stringResource(if (p.location) R.string.perm_location_on else R.string.perm_location_off),
            style = MaterialTheme.typography.caption2,
        )
    }
    item {
        val res = when {
            !state.sensors.hasStepSensor -> R.string.no_step_sensor
            p.activityRecognition -> R.string.perm_activity_on
            else -> R.string.perm_activity_off
        }
        CenteredText(stringResource(res), style = MaterialTheme.typography.caption2)
    }
    item {
        CenteredText(
            stringResource(if (p.notifications) R.string.perm_notifications_on else R.string.perm_notifications_off),
            style = MaterialTheme.typography.caption2,
        )
    }
}

// ------------------------------------------------------------------ 2. Trayecto en curso (V1.1 §B)

/**
 * Orden del contenido (spec V1.1 §B): A estadísticas principales (visibles al abrir, sin desplazarse,
 * en un reloj redondo de ~192 dp), B altitud y desnivel, C perfil compacto (→ vista ampliada),
 * D lugares útiles (máx. 3, → ficha; «Ver todos» → Lugares), E «Pausar»/«Reanudar» y, al final y
 * separado, «Finalizar trayecto» (con confirmación). «SOS» sigue fijo en la cabecera.
 */
@Composable
fun TripActiveScreen(
    state: CaminoUiState,
    active: ActiveStageUi,
    listState: ScalingLazyListState,
    onSos: () -> Unit,
    onTogglePause: () -> Unit,
    onFinish: () -> Unit,
    onProfile: () -> Unit,
    onPlace: (String) -> Unit,
    onPlaces: () -> Unit,
    onStats: () -> Unit,
    onSync: () -> Unit,
    onSettings: () -> Unit,
    onDismissIssue: (StorageIssue) -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val alert = state.lastAlert
    LaunchedEffect(alert) {
        if (alert != null) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
    }
    val f = LocalFormat.current
    val figures = active.figures

    TripScaffold(listState = listState, onSos = onSos) {
        // A. Estadísticas principales (primer elemento: lo primero que se ve y que lee TalkBack).
        item { PrimaryStats(active, isDemo = state.isDemo) }

        // B. Altitud y desnivel.
        item { SectionLabel(stringResource(R.string.section_altitude)) }
        item { AltitudeBlock(active) }

        // C. Perfil registrado compacto.
        item { SectionLabel(stringResource(R.string.section_profile)) }
        item { ProfileCard(active.profile, onOpen = onProfile) }

        // D. Lugares útiles (máx. 3), distancia en línea recta.
        item { SectionLabel(stringResource(R.string.section_places)) }
        if (!active.hasFix) {
            item {
                CenteredText(
                    stringResource(if (state.permissions.location) R.string.active_no_fix else R.string.places_no_location),
                    style = MaterialTheme.typography.caption2,
                )
            }
        } else if (active.usefulPlaces.isEmpty()) {
            item { CenteredText(stringResource(R.string.places_none_stage), style = MaterialTheme.typography.caption2) }
        }
        items(active.usefulPlaces, key = { it.poi.id }) { place ->
            UsefulPlaceChip(place, onClick = { onPlace(place.poi.id) })
        }
        item { WideChip(text = stringResource(R.string.places_see_all), onClick = onPlaces) }

        // E. Pausar / Reanudar.
        item {
            WideChip(
                text = stringResource(if (active.paused) R.string.action_resume else R.string.action_pause),
                primary = active.paused,
                onClick = onTogglePause,
            )
        }
        if (active.paused) {
            item { CenteredText(stringResource(R.string.trip_paused_note), style = MaterialTheme.typography.caption2) }
        }

        // Más datos: etapa, restante, pasos y duración total (diferenciada del tiempo en movimiento).
        item {
            val remaining = figures.remainingMeters
            val text = remaining?.let { stringResource(R.string.trip_stage_line, active.stageName, f.distance(it)) }
                ?: active.stageName
            val spoken = remaining?.let { stringResource(R.string.trip_stage_line_a11y, active.stageName, f.distanceSpoken(it)) }
                ?: active.stageName
            ValueText(text, spoken, style = MaterialTheme.typography.caption1)
        }
        item {
            val label = stringResource(R.string.trip_label_steps)
            val steps = figures.steps
            StatRow(
                label = label,
                value = steps?.let { f.steps(it.toLong()) } ?: stringResource(R.string.stat_unavailable),
                spoken = steps?.let { f.stepsSpoken(it.toLong()) } ?: stringResource(R.string.stat_unavailable_a11y, label),
            )
        }
        item {
            val label = stringResource(R.string.trip_label_total_time)
            StatRow(
                label = label,
                value = f.duration(figures.elapsedSeconds),
                spoken = stringResource(R.string.label_value_a11y, label, f.durationSpoken(figures.elapsedSeconds)),
                divider = false,
            )
        }
        if (alert != null) {
            item {
                CenteredText(
                    stringResource(R.string.active_last_alert, f.poiAlertText(alert.poi, alert.distanceMeters)),
                    style = MaterialTheme.typography.caption1,
                )
            }
        }
        storageWarnings(state, onDismissIssue)
        permissionWarnings(state)

        item { WideChip(text = stringResource(R.string.action_stats), onClick = onStats) }
        item { SyncStatusChip(state.sync, state.isDemo, onSync) }
        item { WideChip(text = stringResource(R.string.action_settings), onClick = onSettings) }

        // Al FINAL del contenido desplazable, separado: «Finalizar trayecto» (con confirmación).
        item { EndSeparator() }
        item { WideChip(text = stringResource(R.string.action_finish_trip), onClick = onFinish) }
    }
}
