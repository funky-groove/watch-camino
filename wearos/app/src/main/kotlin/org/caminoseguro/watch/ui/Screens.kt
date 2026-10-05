package org.caminoseguro.watch.ui

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.style.TextAlign
import androidx.wear.compose.foundation.lazy.ScalingLazyListScope
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.ListHeader
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.Formatters
import org.caminoseguro.watch.platform.Notifications

// ------------------------------------------------------------------ Cargando

@Composable
fun LoadingScreen() {
    CaminoScreen {
        item { CenteredText(stringResource(R.string.loading)) }
    }
}

// ------------------------------------------------------------------ 1. Inicio (Idle)

@Composable
fun HomeScreen(
    state: CaminoUiState,
    onStart: () -> Unit,
    onStats: () -> Unit,
    onSync: () -> Unit,
) {
    CaminoScreen {
        demoBadge(state.isDemo)
        item { ListHeader { Text(stringResource(R.string.home_title)) } }
        item { WideChip(text = stringResource(R.string.action_start_stage), onClick = onStart, primary = true) }
        item { SyncStatusChip(state.sync, onSync) }
        item { WideChip(text = stringResource(R.string.action_stats), onClick = onStats) }
    }
}

// ------------------------------------------------------------------ 2. Elegir etapa

@Composable
fun SelectStageScreen(state: CaminoUiState, onSelect: (String) -> Unit) {
    CaminoScreen {
        demoBadge(state.isDemo)
        item { ListHeader { Text(stringResource(R.string.select_title)) } }
        items(state.choices) { choice ->
            val meters = choice.stage.distanceMeters.toDouble()
            val distance = Formatters.distance(meters)
            val spokenDistance = Formatters.distanceSpoken(meters)
            val secondary = if (choice.suggested) stringResource(R.string.select_suggested, distance) else distance
            val spokenSecondary =
                if (choice.suggested) stringResource(R.string.select_suggested_a11y, spokenDistance) else spokenDistance
            WideChip(
                text = choice.stage.name,
                secondaryText = secondary,
                primary = choice.suggested,
                onClick = { onSelect(choice.stage.id) },
                spoken = "${choice.stage.name}, $spokenSecondary",
            )
        }
        item {
            CenteredText(stringResource(R.string.demo_data_notice), style = MaterialTheme.typography.caption2)
        }
    }
}

@Composable
fun ConfirmStartScreen(state: CaminoUiState, onConfirm: () -> Unit, onCancel: () -> Unit) {
    val stage = state.selected
    var submitted by rememberSaveable { mutableStateOf(false) }
    CaminoScreen {
        item {
            CenteredText(stringResource(R.string.confirm_start_title), style = MaterialTheme.typography.title3)
        }
        if (stage != null) {
            item { CenteredText(stage.name, style = MaterialTheme.typography.body1) }
            item {
                val meters = stage.distanceMeters.toDouble()
                ValueText(Formatters.distance(meters), Formatters.distanceSpoken(meters))
            }
        }
        item {
            WideChip(
                text = stringResource(R.string.confirm_start_yes),
                primary = true,
                enabled = stage != null && !submitted,
                onClick = {
                    submitted = true
                    onConfirm()
                },
            )
        }
        item { WideChip(text = stringResource(R.string.action_cancel), onClick = onCancel) }
    }
}

// ------------------------------------------------------------------ 3. Etapa activa

@Composable
fun ActiveStageScreen(
    state: CaminoUiState,
    active: ActiveStageUi,
    onFinish: () -> Unit,
    onStats: () -> Unit,
    onSync: () -> Unit,
) {
    val haptics = LocalHapticFeedback.current
    val alert = state.lastAlert
    LaunchedEffect(alert) {
        if (alert != null) haptics.performHapticFeedback(HapticFeedbackType.LongPress)
    }

    CaminoScreen {
        demoBadge(state.isDemo)
        item {
            CenteredText(active.stageName, style = MaterialTheme.typography.caption1)
        }
        // Grande: km restantes.
        item {
            val remainingSpoken = stringResource(
                R.string.active_remaining_a11y,
                Formatters.distanceSpoken(active.remainingMeters),
            )
            Column(
                horizontalAlignment = Alignment.CenterHorizontally,
                modifier = Modifier
                    .fillMaxWidth()
                    .clearAndSetSemantics { contentDescription = remainingSpoken },
            ) {
                Text(
                    text = Formatters.distance(active.remainingMeters),
                    style = MaterialTheme.typography.display2,
                    textAlign = TextAlign.Center,
                )
                Text(
                    text = stringResource(R.string.active_remaining),
                    style = MaterialTheme.typography.caption1,
                    textAlign = TextAlign.Center,
                )
            }
        }
        // Secundario: recorrido, pasos, tiempo.
        item {
            ValueText(
                text = stringResource(R.string.active_walked, Formatters.distance(active.walkedMeters)),
                spoken = stringResource(R.string.active_walked_a11y, Formatters.distanceSpoken(active.walkedMeters)),
            )
        }
        item {
            ValueText(
                text = stringResource(R.string.active_steps, Formatters.steps(active.steps)),
                spoken = Formatters.stepsSpoken(active.steps.toLong()),
            )
        }
        item {
            ValueText(
                text = stringResource(R.string.active_time, Formatters.duration(active.elapsedSeconds)),
                spoken = stringResource(R.string.active_time_a11y, Formatters.durationSpoken(active.elapsedSeconds)),
            )
        }
        // Próximo POI (si hay fix).
        val next = active.nextPoi
        if (next != null) {
            item {
                val category = stringResource(Notifications.categoryLabel(next.poi.category))
                ValueText(
                    text = stringResource(
                        R.string.active_next_poi,
                        Formatters.poiAlertText(next.poi, next.distanceMeters),
                    ),
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
        permissionWarnings(state)
        item { WideChip(text = stringResource(R.string.action_finish), onClick = onFinish, primary = true) }
        item { WideChip(text = stringResource(R.string.action_stats), onClick = onStats) }
        item { SyncStatusChip(state.sync, onSync) }
    }
}

/** Si se deniega un permiso, la etapa sigue con lo disponible y la UI lo dice (spec §11). */
private fun ScalingLazyListScope.permissionWarnings(state: CaminoUiState) {
    val p = state.permissions
    if (!p.location) {
        item { CenteredText(stringResource(R.string.perm_no_location), style = MaterialTheme.typography.caption2) }
    }
    if (!state.sensors.hasStepSensor) {
        item { CenteredText(stringResource(R.string.no_step_sensor), style = MaterialTheme.typography.caption2) }
    } else if (!p.activityRecognition) {
        item { CenteredText(stringResource(R.string.perm_no_activity), style = MaterialTheme.typography.caption2) }
    }
    if (!p.notifications) {
        item { CenteredText(stringResource(R.string.perm_no_notifications), style = MaterialTheme.typography.caption2) }
    }
}

// ------------------------------------------------------------------ Finalizar (confirmación explícita)

@Composable
fun ConfirmFinishScreen(state: CaminoUiState, onConfirm: () -> Unit, onCancel: () -> Unit) {
    var submitted by rememberSaveable { mutableStateOf(false) }
    CaminoScreen {
        item {
            CenteredText(stringResource(R.string.confirm_finish_title), style = MaterialTheme.typography.title3)
        }
        state.active?.let { a -> item { CenteredText(a.stageName, style = MaterialTheme.typography.body2) } }
        item {
            WideChip(
                text = stringResource(R.string.confirm_finish_yes),
                primary = true,
                enabled = state.active != null && !submitted,
                onClick = {
                    submitted = true
                    onConfirm()
                },
            )
        }
        item { WideChip(text = stringResource(R.string.confirm_finish_no), onClick = onCancel) }
    }
}

// ------------------------------------------------------------------ 5. Resumen

@Composable
fun SummaryScreen(state: CaminoUiState, onDone: () -> Unit) {
    val summary = state.summary
    CaminoScreen {
        demoBadge(state.isDemo)
        item { ListHeader { Text(stringResource(R.string.summary_title)) } }
        if (summary != null) {
            item { CenteredText(summary.stageName, style = MaterialTheme.typography.caption1) }
            item {
                ValueText(
                    Formatters.distance(summary.distanceMeters),
                    Formatters.distanceSpoken(summary.distanceMeters),
                    style = MaterialTheme.typography.title1,
                )
            }
            item {
                ValueText(
                    stringResource(R.string.stats_steps, Formatters.steps(summary.steps)),
                    Formatters.stepsSpoken(summary.steps.toLong()),
                )
            }
            item {
                ValueText(
                    stringResource(R.string.stats_time, Formatters.duration(summary.activeSeconds)),
                    stringResource(R.string.stats_time_a11y, Formatters.durationSpoken(summary.activeSeconds)),
                )
            }
            item { CenteredText(stringResource(R.string.summary_saved), style = MaterialTheme.typography.caption1) }
        }
        item { WideChip(text = stringResource(R.string.action_done), onClick = onDone, primary = true) }
    }
}

// ------------------------------------------------------------------ 4. Estadísticas

@Composable
fun StatsScreen(state: CaminoUiState) {
    val stats = state.stats
    CaminoScreen {
        demoBadge(state.isDemo)
        item { ListHeader { Text(stringResource(R.string.stats_title)) } }
        val today = stats?.today
        if (today == null) {
            item { CenteredText(stringResource(R.string.stats_today_none)) }
        } else {
            item {
                val title = if (today.isActive) R.string.stats_today_active else R.string.stats_today
                CenteredText(stringResource(title), style = MaterialTheme.typography.title3)
            }
            stats?.todayStageName?.let { name ->
                item { CenteredText(name, style = MaterialTheme.typography.caption1) }
            }
            statLines(today.distanceMeters, today.steps.toLong(), today.activeSeconds)
        }
        if (stats != null) {
            item { ListHeader { Text(stringResource(R.string.stats_total)) } }
            item {
                val n = stats.totals.stages
                CenteredText(
                    if (n == 1) stringResource(R.string.stats_stages_one) else stringResource(R.string.stats_stages_many, n),
                )
            }
            statLines(stats.totals.distanceMeters, stats.totals.steps, stats.totals.activeSeconds)
        }
    }
}

private fun ScalingLazyListScope.statLines(distanceMeters: Double, steps: Long, seconds: Long) {
    item {
        ValueText(
            stringResource(R.string.stats_distance, Formatters.distance(distanceMeters)),
            stringResource(R.string.stats_distance_a11y, Formatters.distanceSpoken(distanceMeters)),
        )
    }
    item {
        ValueText(
            stringResource(R.string.stats_steps, Formatters.steps(steps)),
            Formatters.stepsSpoken(steps),
        )
    }
    item {
        ValueText(
            stringResource(R.string.stats_time, Formatters.duration(seconds)),
            stringResource(R.string.stats_time_a11y, Formatters.durationSpoken(seconds)),
        )
    }
}

// ------------------------------------------------------------------ 6. Sincronizar

@Composable
fun SyncScreen(state: CaminoUiState, onSyncNow: () -> Unit) {
    val sync = state.sync
    CaminoScreen {
        demoBadge(state.isDemo)
        item { ListHeader { Text(stringResource(R.string.sync_title)) } }
        item {
            val status = syncStatusText(sync)
            ValueText(status, stringResource(R.string.sync_status_a11y, status), style = MaterialTheme.typography.title3)
        }
        if (sync.queued > 0) {
            item {
                CenteredText(
                    if (sync.queued == 1) {
                        stringResource(R.string.sync_queued_one)
                    } else {
                        stringResource(R.string.sync_queued_many, sync.queued)
                    },
                    style = MaterialTheme.typography.caption1,
                )
            }
        }
        if (sync.deadLetters > 0) {
            item {
                CenteredText(
                    stringResource(R.string.sync_dead_letters, sync.deadLetters),
                    style = MaterialTheme.typography.caption1,
                )
            }
        }
        if (Presentation.syncLabel(sync.status) == SyncLabel.BLOCKED) {
            item {
                CenteredText(stringResource(R.string.sync_blocked_explain), style = MaterialTheme.typography.caption2)
            }
        }
        item {
            WideChip(
                text = stringResource(R.string.action_sync_now),
                primary = true,
                enabled = Presentation.syncLabel(sync.status) != SyncLabel.SYNCING,
                onClick = onSyncNow,
            )
        }
    }
}
