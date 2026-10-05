package org.caminoseguro.watch.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyListScope
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Chip
import androidx.wear.compose.material.ChipDefaults
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.SyncSnapshot
import org.caminoseguro.watch.core.SyncStatus

/**
 * Pantalla estándar para reloj redondo: TimeText + ScalingLazyColumn + indicador de posición.
 * En Wear Compose 1.4 `ScalingLazyColumn` trae soporte de corona/rotary activado por defecto
 * (parámetro `rotaryScrollableBehavior`).
 */
@Composable
fun CaminoScreen(content: ScalingLazyListScope.() -> Unit) {
    val listState = rememberScalingLazyListState()
    Scaffold(
        // Fondo explícito del tema (la ventana es negra; Perla necesita su fondo claro).
        modifier = Modifier.background(LocalPalette.current.background.toColor()),
        timeText = { TimeText() },
        vignette = vignetteFor(LocalThemeId.current),
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScalingLazyColumn(
            modifier = Modifier.fillMaxSize(),
            state = listState,
            content = content,
        )
    }
}

/** Marca DEMO, visible siempre que el adaptador sea MockCaminoApi. */
fun ScalingLazyListScope.demoBadge(isDemo: Boolean) {
    if (!isDemo) return
    item {
        val description = stringResource(R.string.demo_badge_a11y)
        Text(
            text = stringResource(R.string.demo_badge),
            color = MaterialTheme.colors.secondary,
            style = MaterialTheme.typography.caption1,
            fontWeight = FontWeight.Bold,
            modifier = Modifier
                .border(1.dp, MaterialTheme.colors.secondary, RoundedCornerShape(50))
                .padding(horizontal = 10.dp, vertical = 2.dp)
                .clearAndSetSemantics { contentDescription = description },
        )
    }
}

/** Texto de valor centrado con etiqueta hablada (unidades en palabras). */
@Composable
fun ValueText(
    text: String,
    spoken: String,
    style: TextStyle = MaterialTheme.typography.body1,
) {
    Text(
        text = text,
        style = style,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = spoken },
    )
}

@Composable
fun CenteredText(text: String, style: TextStyle = MaterialTheme.typography.body2) {
    Text(
        text = text,
        style = style,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth(),
    )
}

/** Chip de ancho completo (altura por defecto 52 dp ≥ 48 dp). */
@Composable
fun WideChip(
    text: String,
    onClick: () -> Unit,
    primary: Boolean = false,
    secondaryText: String? = null,
    enabled: Boolean = true,
    spoken: String? = null,
) {
    Chip(
        onClick = onClick,
        // Hasta 3 líneas: con letra grande del sistema el texto se parte, no se corta.
        label = { Text(text = text, maxLines = 3, overflow = TextOverflow.Ellipsis) },
        secondaryLabel = if (secondaryText != null) {
            { Text(text = secondaryText, maxLines = 3, overflow = TextOverflow.Ellipsis) }
        } else {
            null
        },
        colors = if (primary) ChipDefaults.primaryChipColors() else ChipDefaults.secondaryChipColors(),
        enabled = enabled,
        modifier = Modifier
            .fillMaxWidth()
            .then(if (spoken != null) Modifier.semantics { contentDescription = spoken } else Modifier),
    )
}

/**
 * V-02: nunca "Sincronizado" sin servidor real. Con BlockedCaminoApi el estado es siempre `blocked`
 * (§7.4); con MockCaminoApi (DEMO) se dice que el envío es simulado.
 */
@Composable
fun syncStatusText(sync: SyncSnapshot, isDemo: Boolean): String = when (Presentation.syncLabel(sync.status)) {
    SyncLabel.SYNCED -> if (isDemo) stringResource(R.string.sync_synced_demo) else stringResource(R.string.sync_synced)
    SyncLabel.PENDING -> {
        val n = (sync.status as? SyncStatus.Pending)?.count ?: sync.queued
        if (n == 1) stringResource(R.string.sync_pending_one) else stringResource(R.string.sync_pending_many, n)
    }
    SyncLabel.OFFLINE -> stringResource(R.string.sync_offline)
    SyncLabel.BLOCKED ->
        if (sync.queued == 0) stringResource(R.string.sync_blocked_empty) else stringResource(R.string.sync_blocked)
    SyncLabel.NEEDS_LINK -> stringResource(R.string.sync_needs_link)
    SyncLabel.SYNCING -> stringResource(R.string.sync_syncing)
}

/** Fila de estado de sincronización (Inicio / Etapa). */
@Composable
fun SyncStatusChip(sync: SyncSnapshot, isDemo: Boolean, onClick: () -> Unit) {
    val status = syncStatusText(sync, isDemo)
    WideChip(
        text = stringResource(R.string.action_sync),
        secondaryText = status,
        onClick = onClick,
        spoken = stringResource(R.string.sync_status_a11y, status),
    )
}
