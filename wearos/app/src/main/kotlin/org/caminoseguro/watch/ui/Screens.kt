package org.caminoseguro.watch.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextOverflow
import androidx.wear.compose.foundation.lazy.ScalingLazyListScope
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.ListHeader
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.RadioButton
import androidx.wear.compose.material.Switch
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.ToggleChip
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.Formatters
import org.caminoseguro.watch.core.PoiCategory
import org.caminoseguro.watch.core.StorageIssue
import org.caminoseguro.watch.core.ThemeId
import org.caminoseguro.watch.platform.Notifications

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

/** Errores de almacenamiento recuperables (V-01, V-03): la app sigue funcionando y lo dice. */
internal fun ScalingLazyListScope.storageWarnings(state: CaminoUiState, onDismiss: (StorageIssue) -> Unit) {
    if (StorageIssue.restoreFailed in state.storageIssues) {
        item { CenteredText(stringResource(R.string.storage_restore_failed), style = MaterialTheme.typography.caption2) }
        item {
            WideChip(
                text = stringResource(R.string.action_understood),
                onClick = { onDismiss(StorageIssue.restoreFailed) },
            )
        }
    }
    if (StorageIssue.saveFailed in state.storageIssues) {
        item { CenteredText(stringResource(R.string.storage_save_failed), style = MaterialTheme.typography.caption2) }
    }
}

/** Si se deniega un permiso, la etapa sigue con lo disponible y la UI lo dice (spec §11). */
internal fun ScalingLazyListScope.permissionWarnings(state: CaminoUiState) {
    val p = state.permissions
    if (!p.location) {
        item { CenteredText(stringResource(R.string.perm_no_location), style = MaterialTheme.typography.caption2) }
    } else if (state.sensors.foregroundServiceBlocked) {
        item { CenteredText(stringResource(R.string.fgs_blocked), style = MaterialTheme.typography.caption2) }
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
            item {
                // V-09: sin servidor real nunca se promete sincronizar.
                val saved = if (state.isDemo) R.string.summary_saved_demo else R.string.summary_saved
                CenteredText(stringResource(saved), style = MaterialTheme.typography.caption1)
            }
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
            val status = syncStatusText(sync, state.isDemo)
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
        } else if (state.isDemo) {
            item {
                CenteredText(stringResource(R.string.sync_demo_explain), style = MaterialTheme.typography.caption2)
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

// ------------------------------------------------------------------ 7. Ajustes: tema y avisos (V-08)

/**
 * Tema (Negro/Perla, persistido; Negro por defecto) y un ToggleChip por categoría de aviso. Las
 * categorías desactivadas no avisan ni consumen el límite de ritmo (§6).
 */
@Composable
fun SettingsScreen(
    state: CaminoUiState,
    theme: ThemeId,
    onTheme: (ThemeId) -> Unit,
    onToggle: (PoiCategory, Boolean) -> Unit,
) {
    CaminoScreen {
        demoBadge(state.isDemo)
        item { ListHeader { Text(stringResource(R.string.settings_screen_title)) } }
        item { SectionLabel(stringResource(R.string.settings_theme)) }
        items(ThemeId.entries.toList()) { option ->
            val selected = option == theme
            val label = stringResource(if (option == ThemeId.NEGRO) R.string.theme_negro else R.string.theme_perla)
            ToggleChip(
                checked = selected,
                onCheckedChange = { if (it) onTheme(option) },
                label = { Text(text = label, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                secondaryLabel = {
                    Text(stringResource(if (selected) R.string.theme_selected else R.string.theme_not_selected))
                },
                toggleControl = { RadioButton(selected = selected) },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item { SectionLabel(stringResource(R.string.settings_title)) }
        items(PoiCategory.entries.toList()) { category ->
            val checked = category in state.alertCategories
            val label = stringResource(Notifications.categoryLabel(category))
            ToggleChip(
                checked = checked,
                onCheckedChange = { onToggle(category, it) },
                label = { Text(text = "${category.icon} $label", maxLines = 2, overflow = TextOverflow.Ellipsis) },
                secondaryLabel = {
                    Text(stringResource(if (checked) R.string.settings_on else R.string.settings_off))
                },
                toggleControl = { Switch(checked = checked) },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        item {
            CenteredText(stringResource(R.string.settings_explain), style = MaterialTheme.typography.caption2)
        }
    }
}
