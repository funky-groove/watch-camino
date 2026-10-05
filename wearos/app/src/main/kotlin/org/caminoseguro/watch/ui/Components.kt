package org.caminoseguro.watch.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyColumnDefaults
import androidx.wear.compose.foundation.lazy.ScalingLazyListAnchorType
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

/** Margen lateral de los elementos de lista (guía Wear: ≈5,2 % del ancho de pantalla a cada lado). */
@Composable
fun listHorizontalPadding(): Dp = (LocalConfiguration.current.screenWidthDp * EDGE_MARGIN_FRACTION).dp

/**
 * Margen lateral EXTRA para filas de texto a ancho completo en pantalla redonda: cerca de arriba y
 * abajo el círculo se estrecha y el texto tocaría el borde. Con el de la lista suma ≈10,4 % por lado.
 * El texto se parte en más líneas; nunca se reduce la letra.
 */
@Composable
fun roundTextInset(): Dp {
    val cfg = LocalConfiguration.current
    return if (cfg.isScreenRound) (cfg.screenWidthDp * EDGE_MARGIN_FRACTION).dp else 0.dp
}

/** Reloj pequeño (≈192 dp): se compacta lo superior para que la acción principal quepa sin desplazar. */
@Composable
fun isSmallScreen(): Boolean = LocalConfiguration.current.screenHeightDp < SMALL_SCREEN_DP

private const val EDGE_MARGIN_FRACTION = 0.052f

/**
 * Opacidad de los elementos en el borde de la lista. La de Wear por defecto (0,5) dejaba el texto
 * secundario (etiquetas de sección, notas) por debajo del contraste verificado en DesignTokensTest
 * cuando queda cerca del borde en la primera vista; 0,8 conserva el efecto sin volverlo ilegible.
 */
const val LIST_EDGE_ALPHA = 0.8f
private const val SMALL_SCREEN_DP = 210

/**
 * Pantalla estándar para reloj redondo: TimeText + ScalingLazyColumn + indicador de posición.
 * En Wear Compose 1.4 `ScalingLazyColumn` trae soporte de corona/rotary activado por defecto
 * (parámetro `rotaryScrollableBehavior`).
 *
 * [topAligned]: el contenido empieza bajo la hora (como Trayecto/SOS) en lugar de centrar el
 * segundo elemento; para pantallas cuyo primer bloque es alto (p. ej. el perfil), que si no
 * empujaría el título encima de TimeText.
 */
@Composable
fun CaminoScreen(topAligned: Boolean = false, content: ScalingLazyListScope.() -> Unit) {
    val listState = rememberScalingLazyListState()
    val side = listHorizontalPadding()
    Scaffold(
        // Fondo explícito del tema (la ventana es negra; Perla necesita su fondo claro).
        modifier = Modifier.background(LocalPalette.current.background.toColor()),
        timeText = { TimeText() },
        vignette = vignetteFor(LocalThemeId.current),
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        if (topAligned) {
            ScalingLazyColumn(
                modifier = Modifier.fillMaxSize(),
                state = listState,
                contentPadding = PaddingValues(start = side, end = side, top = timeTextSpace() + 4.dp, bottom = 40.dp),
                anchorType = ScalingLazyListAnchorType.ItemStart,
                autoCentering = null,
                scalingParams = ScalingLazyColumnDefaults.scalingParams(edgeAlpha = LIST_EDGE_ALPHA),
                content = content,
            )
        } else {
            ScalingLazyColumn(
                modifier = Modifier.fillMaxSize(),
                state = listState,
                contentPadding = PaddingValues(horizontal = side),
                scalingParams = ScalingLazyColumnDefaults.scalingParams(edgeAlpha = LIST_EDGE_ALPHA),
                content = content,
            )
        }
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
            .padding(horizontal = roundTextInset())
            .clearAndSetSemantics { contentDescription = spoken },
    )
}

@Composable
fun CenteredText(text: String, style: TextStyle = MaterialTheme.typography.body2) {
    Text(
        text = text,
        style = style,
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = roundTextInset()),
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
