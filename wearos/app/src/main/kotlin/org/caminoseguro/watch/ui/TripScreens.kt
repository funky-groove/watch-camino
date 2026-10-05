package org.caminoseguro.watch.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.wear.compose.foundation.lazy.ScalingLazyListScope
import androidx.wear.compose.foundation.lazy.ScalingLazyListState
import androidx.wear.compose.material.ListHeader
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.Formatters
import org.caminoseguro.watch.core.StorageIssue
import org.caminoseguro.watch.platform.Notifications

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

// ------------------------------------------------------------------ 2. Trayecto en curso

@Composable
fun TripActiveScreen(
    state: CaminoUiState,
    active: ActiveStageUi,
    listState: ScalingLazyListState,
    onSos: () -> Unit,
    onFinish: () -> Unit,
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
    val f = active.figures

    TripScaffold(listState = listState, onSos = onSos) {
        demoBadge(state.isDemo)
        item { CenteredText(active.stageName, style = MaterialTheme.typography.caption1) }

        // Cifras (orden de lectura: restante, recorrido, pasos, tiempo). Sin ceros falsos.
        item {
            val label = stringResource(R.string.trip_label_remaining)
            val meters = f.remainingMeters
            StatRow(
                label = label,
                value = meters?.let { Formatters.distance(it) } ?: stringResource(R.string.stat_unavailable),
                spoken = meters?.let { stringResource(R.string.active_remaining_a11y, Formatters.distanceSpoken(it)) }
                    ?: stringResource(R.string.stat_unavailable_a11y, label),
                hero = true,
            )
        }
        item {
            val label = stringResource(R.string.trip_label_walked)
            val meters = f.walkedMeters
            StatRow(
                label = label,
                value = meters?.let { Formatters.distance(it) } ?: stringResource(R.string.stat_unavailable),
                spoken = meters?.let { stringResource(R.string.active_walked_a11y, Formatters.distanceSpoken(it)) }
                    ?: stringResource(R.string.stat_unavailable_a11y, label),
            )
        }
        item {
            val label = stringResource(R.string.trip_label_steps)
            val steps = f.steps
            StatRow(
                label = label,
                value = steps?.let { Formatters.steps(it) } ?: stringResource(R.string.stat_unavailable),
                spoken = steps?.let { Formatters.stepsSpoken(it.toLong()) }
                    ?: stringResource(R.string.stat_unavailable_a11y, label),
            )
        }
        item {
            StatRow(
                label = stringResource(R.string.trip_label_time),
                value = Formatters.duration(f.elapsedSeconds),
                spoken = stringResource(R.string.active_time_a11y, Formatters.durationSpoken(f.elapsedSeconds)),
                divider = false,
            )
        }

        // Próximo POI (si hay fix).
        val next = active.nextPoi
        if (next != null) {
            item {
                val category = stringResource(Notifications.categoryLabel(next.poi.category))
                ValueText(
                    text = stringResource(R.string.active_next_poi, Formatters.poiAlertText(next.poi, next.distanceMeters)),
                    spoken = stringResource(
                        R.string.active_next_poi_a11y,
                        next.poi.name,
                        category,
                        Formatters.distanceSpoken(next.distanceMeters),
                    ),
                    style = MaterialTheme.typography.body2,
                )
            }
        } else if (!active.hasFix && state.permissions.location) {
            item { CenteredText(stringResource(R.string.active_no_fix), style = MaterialTheme.typography.caption1) }
        }
        if (alert != null) {
            item {
                CenteredText(
                    stringResource(R.string.active_last_alert, Formatters.poiAlertText(alert.poi, alert.distanceMeters)),
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
