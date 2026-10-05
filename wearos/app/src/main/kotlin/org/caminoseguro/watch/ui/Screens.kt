package org.caminoseguro.watch.ui

import androidx.annotation.StringRes
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.unit.dp
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
import org.caminoseguro.watch.core.AppLanguage
import org.caminoseguro.watch.core.DisplayFormat
import org.caminoseguro.watch.core.DisplayPreferences
import org.caminoseguro.watch.core.PaceMode
import org.caminoseguro.watch.core.PoiCategory
import org.caminoseguro.watch.core.StorageIssue
import org.caminoseguro.watch.core.ThemeId
import org.caminoseguro.watch.core.UnitSystem
import org.caminoseguro.watch.platform.Notifications

// ------------------------------------------------------------------ 2. Elegir etapa

@Composable
fun SelectStageScreen(state: CaminoUiState, onSelect: (String) -> Unit) {
    val f = LocalFormat.current
    CaminoScreen {
        demoBadge(state.isDemo)
        item { ListHeader { Text(stringResource(R.string.select_title)) } }
        items(state.choices) { choice ->
            val meters = choice.stage.distanceMeters.toDouble()
            val distance = f.distance(meters)
            val spokenDistance = f.distanceSpoken(meters)
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
    val f = LocalFormat.current
    CaminoScreen {
        item {
            CenteredText(stringResource(R.string.confirm_start_title), style = MaterialTheme.typography.title3)
        }
        if (stage != null) {
            item { CenteredText(stage.name, style = MaterialTheme.typography.body1) }
            item {
                val meters = stage.distanceMeters.toDouble()
                ValueText(f.distance(meters), f.distanceSpoken(meters))
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

// ------------------------------------------------------------------ 5. Resumen (V1.1)

/**
 * Resumen al finalizar: distancia, duración total y tiempo en movimiento DIFERENCIADOS, ritmo o
 * velocidad media (distancia / tiempo en movimiento), subida/bajada, mini perfil y pasos.
 * «Guardado en el reloj» sólo aparece porque el resumen existe únicamente tras guardar con éxito
 * (`FinishOutcome.Finished`). El envío se dice aparte y sin promesas (sin servidor → no disponible).
 */
@Composable
fun SummaryScreen(state: CaminoUiState, onDone: () -> Unit) {
    val summary = state.summary
    val f = LocalFormat.current
    val noData = stringResource(R.string.stat_unavailable)
    CaminoScreen {
        demoBadge(state.isDemo)
        item { ListHeader { Text(stringResource(R.string.summary_title)) } }
        if (summary != null) {
            val hasAltitude = summary.profile.isNotEmpty() || summary.ascentMeters > 0 || summary.descentMeters > 0
            item { CenteredText(summary.stageName, style = MaterialTheme.typography.caption1) }
            item {
                ValueText(
                    f.distance(summary.distanceMeters),
                    stringResource(R.string.label_value_a11y, stringResource(R.string.trip_label_distance), f.distanceSpoken(summary.distanceMeters)),
                    style = MaterialTheme.typography.title1.tabular(),
                )
            }
            labelValue(R.string.trip_label_total_time, f.duration(summary.activeSeconds), f.durationSpoken(summary.activeSeconds))
            labelValue(R.string.trip_label_moving_time, f.duration(summary.movingSeconds), f.durationSpoken(summary.movingSeconds))
            item {
                val label = stringResource(
                    if (f.paceMode == org.caminoseguro.watch.core.PaceMode.pace) R.string.summary_avg_pace else R.string.summary_avg_speed,
                )
                val moving = summary.movingSeconds.toDouble()
                ValueText(
                    stringResource(R.string.label_value, label, f.paceOrSpeed(summary.distanceMeters, moving) ?: noData),
                    stringResource(R.string.label_value_a11y, label, f.paceOrSpeedSpoken(summary.distanceMeters, moving) ?: noData),
                )
            }
            labelValue(
                R.string.trip_label_ascent,
                if (hasAltitude) f.elevation(summary.ascentMeters.toDouble()) else noData,
                if (hasAltitude) f.elevationSpoken(summary.ascentMeters.toDouble()) else noData,
            )
            labelValue(
                R.string.trip_label_descent,
                if (hasAltitude) f.elevation(summary.descentMeters.toDouble()) else noData,
                if (hasAltitude) f.elevationSpoken(summary.descentMeters.toDouble()) else noData,
            )
            labelValue(R.string.trip_label_steps, f.steps(summary.steps.toLong()), f.stepsSpoken(summary.steps.toLong()))
            item {
                val description = profileSummary(summary.profile, spoken = true)
                androidx.compose.foundation.layout.Box(
                    modifier = Modifier
                        .fillMaxWidth()
                        .clearAndSetSemantics { contentDescription = description },
                ) {
                    ProfileChart(summary.profile, height = 36.dp)
                }
            }
            item { CenteredText(stringResource(R.string.summary_saved_watch), style = MaterialTheme.typography.caption1) }
            item { CenteredText(summarySyncText(state), style = MaterialTheme.typography.caption2) }
        }
        item { WideChip(text = stringResource(R.string.action_done), onClick = onDone, primary = true) }
    }
}

/** Fila "Etiqueta: valor" con versión hablada. */
private fun ScalingLazyListScope.labelValue(@StringRes labelRes: Int, value: String, spoken: String) {
    item {
        val label = stringResource(labelRes)
        ValueText(
            stringResource(R.string.label_value, label, value),
            stringResource(R.string.label_value_a11y, label, spoken),
        )
    }
}

/** Envío, diferenciado del guardado: sin servidor nunca se promete sincronizar (V-09). */
@Composable
private fun summarySyncText(state: CaminoUiState): String = when (Presentation.syncLabel(state.sync.status)) {
    SyncLabel.BLOCKED -> stringResource(R.string.summary_sync_blocked)
    SyncLabel.SYNCED -> if (state.isDemo) stringResource(R.string.summary_sync_demo) else stringResource(R.string.sync_synced)
    SyncLabel.PENDING, SyncLabel.SYNCING -> stringResource(R.string.summary_sync_pending)
    SyncLabel.OFFLINE -> stringResource(R.string.sync_offline)
    SyncLabel.NEEDS_LINK -> stringResource(R.string.sync_needs_link)
}

// ------------------------------------------------------------------ 4. Estadísticas

@Composable
fun StatsScreen(state: CaminoUiState) {
    val stats = state.stats
    val f = LocalFormat.current
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
            statLines(f, today.distanceMeters, today.steps.toLong(), today.activeSeconds)
        }
        if (stats != null) {
            item { ListHeader { Text(stringResource(R.string.stats_total)) } }
            item {
                val n = stats.totals.stages
                CenteredText(
                    if (n == 1) stringResource(R.string.stats_stages_one) else stringResource(R.string.stats_stages_many, n),
                )
            }
            statLines(f, stats.totals.distanceMeters, stats.totals.steps, stats.totals.activeSeconds)
        }
    }
}

private fun ScalingLazyListScope.statLines(f: DisplayFormat, distanceMeters: Double, steps: Long, seconds: Long) {
    item {
        ValueText(
            stringResource(R.string.stats_distance, f.distance(distanceMeters)),
            stringResource(R.string.stats_distance_a11y, f.distanceSpoken(distanceMeters)),
        )
    }
    item {
        ValueText(
            stringResource(R.string.stats_steps, f.steps(steps)),
            f.stepsSpoken(steps),
        )
    }
    item {
        ValueText(
            stringResource(R.string.stats_time, f.duration(seconds)),
            stringResource(R.string.stats_time_a11y, f.durationSpoken(seconds)),
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

// ------------------------------------------------------------------ 7. Ajustes (V1.1 §A, §G)

/**
 * Ajustes, en este orden: acceso desde la esfera (→ ayuda), unidades, ritmo/velocidad, tema,
 * idioma (API 33+: selector; API 30–32: "sigue el idioma del reloj"), avisos por categoría y estado.
 */
@Composable
fun SettingsScreen(
    state: CaminoUiState,
    theme: ThemeId,
    prefs: DisplayPreferences,
    languageSelectable: Boolean,
    chosenLanguage: AppLanguage?,
    onTheme: (ThemeId) -> Unit,
    onUnits: (UnitSystem) -> Unit,
    onPaceMode: (PaceMode) -> Unit,
    onLanguage: (AppLanguage?) -> Unit,
    onFaceHelp: () -> Unit,
    onSync: () -> Unit,
    onToggle: (PoiCategory, Boolean) -> Unit,
) {
    CaminoScreen {
        demoBadge(state.isDemo)
        item { ListHeader { Text(stringResource(R.string.settings_screen_title)) } }

        // Acceso desde la esfera → instrucciones (no se afirma que esté añadida).
        item { SectionLabel(stringResource(R.string.settings_face_access)) }
        item { WideChip(text = stringResource(R.string.face_hint_how), onClick = onFaceHelp) }

        item { SectionLabel(stringResource(R.string.settings_units)) }
        items(UnitSystem.entries.toList()) { option ->
            RadioRow(
                label = stringResource(if (option == UnitSystem.metric) R.string.units_metric else R.string.units_imperial),
                selected = option == prefs.units,
                onSelect = { onUnits(option) },
            )
        }

        item { SectionLabel(stringResource(R.string.settings_pace_mode)) }
        items(PaceMode.entries.toList()) { option ->
            RadioRow(
                label = stringResource(if (option == PaceMode.pace) R.string.pace_mode_pace else R.string.pace_mode_speed),
                selected = option == prefs.paceMode,
                onSelect = { onPaceMode(option) },
            )
        }

        item { SectionLabel(stringResource(R.string.settings_theme)) }
        items(ThemeId.entries.toList()) { option ->
            RadioRow(
                label = stringResource(if (option == ThemeId.NEGRO) R.string.theme_negro else R.string.theme_perla),
                selected = option == theme,
                onSelect = { onTheme(option) },
            )
        }

        item { SectionLabel(stringResource(R.string.settings_language)) }
        if (languageSelectable) {
            val options: List<AppLanguage?> = listOf(null, AppLanguage.es, AppLanguage.en)
            items(options) { option ->
                RadioRow(
                    label = stringResource(
                        when (option) {
                            null -> R.string.language_system
                            AppLanguage.es -> R.string.language_es
                            AppLanguage.en -> R.string.language_en
                        },
                    ),
                    selected = option == chosenLanguage,
                    onSelect = { onLanguage(option) },
                )
            }
        } else {
            item { CenteredText(stringResource(R.string.language_follows_watch), style = MaterialTheme.typography.caption1) }
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

        item { SectionLabel(stringResource(R.string.settings_status)) }
        item { SyncStatusChip(state.sync, state.isDemo, onSync) }
        item { CenteredText(stringResource(R.string.settings_demo_data), style = MaterialTheme.typography.caption2) }
    }
}

/** Opción única (radio) con su estado en texto («Seleccionado»), objetivo ≥ 48 dp. */
@Composable
private fun RadioRow(label: String, selected: Boolean, onSelect: () -> Unit) {
    ToggleChip(
        checked = selected,
        onCheckedChange = { if (it) onSelect() },
        label = { Text(text = label, maxLines = 3, overflow = TextOverflow.Ellipsis) },
        secondaryLabel = {
            Text(stringResource(if (selected) R.string.theme_selected else R.string.theme_not_selected))
        },
        toggleControl = { RadioButton(selected = selected) },
        modifier = Modifier.fillMaxWidth(),
    )
}
