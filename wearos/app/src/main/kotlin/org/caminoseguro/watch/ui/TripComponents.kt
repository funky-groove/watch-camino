package org.caminoseguro.watch.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.sizeIn
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.zIndex
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyColumnDefaults
import androidx.wear.compose.foundation.lazy.ScalingLazyListAnchorType
import androidx.wear.compose.foundation.lazy.ScalingLazyListScope
import androidx.wear.compose.foundation.lazy.ScalingLazyListState
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.ThemeId

// Componentes de la pantalla principal del trayecto: cabecera fija con «SOS», lista con
// ScalingLazyColumn (scroll vertical nativo + corona/bisel por defecto en Wear Compose 1.4) y
// filas de cifras sobrias (estética Rams/Braun: líneas finas, cifras tabulares, color contenido).

/** Objetivo táctil mínimo (Wear OS / Material: 48 × 48 dp). */
val MinTouchTarget: Dp = 48.dp

/** Hueco para TimeText. En sp → dp para que crezca con el tamaño de letra del sistema. */
@Composable
fun timeTextSpace(): Dp = with(LocalDensity.current) { 20.sp.toDp() } + 4.dp

/**
 * Pantalla con la cabecera «SOS» FIJA (fuera de la lista, visible al desplazar) y la lista debajo.
 * La lista no se superpone a la cabecera: su `contentPadding` superior es la altura medida de la
 * cabecera, que además tiene fondo opaco por si el contenido pasa por debajo al desplazar.
 *
 * Usa la [listState] que se le pasa: la ruta de Inicio la crea con `rememberScalingLazyListState`
 * (guardada en el back stack), así que al volver de SOS se conserva la posición de scroll.
 */
@Composable
fun TripScaffold(
    listState: ScalingLazyListState,
    onSos: () -> Unit,
    content: ScalingLazyListScope.() -> Unit,
) {
    val palette = LocalPalette.current
    val density = LocalDensity.current
    var headerHeightPx by remember { mutableIntStateOf(0) }
    val headerHeight = if (headerHeightPx > 0) with(density) { headerHeightPx.toDp() } else timeTextSpace() + MinTouchTarget
    val side = listHorizontalPadding()
    Scaffold(
        modifier = Modifier.background(palette.background.toColor()),
        timeText = { TimeText() },
        vignette = vignetteFor(LocalThemeId.current, bottomOnly = true),
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        Box(modifier = Modifier.fillMaxSize()) {
            // Primero en el árbol (orden de foco: cabecera → cifras → finalizar) y encima (zIndex).
            SosHeader(
                onSos = onSos,
                modifier = Modifier
                    .zIndex(1f)
                    .onSizeChanged { headerHeightPx = it.height },
            )
            ScalingLazyColumn(
                modifier = Modifier.fillMaxSize(),
                state = listState,
                contentPadding = PaddingValues(
                    start = side,
                    end = side,
                    top = headerHeight + 4.dp,
                    bottom = 36.dp,
                ),
                // Contenido alineado arriba bajo la cabecera (no centrado en la pantalla).
                anchorType = ScalingLazyListAnchorType.ItemStart,
                autoCentering = null,
                scalingParams = ScalingLazyColumnDefaults.scalingParams(edgeAlpha = LIST_EDGE_ALPHA),
                content = content,
            )
        }
    }
}

/**
 * La viñeta de Wear es negra: sobre Perla (fondo claro) ensucia los bordes, así que sólo en Negro.
 * Con cabecera «SOS» fija ([bottomOnly]) sólo abajo, para no oscurecer el rojo del botón.
 */
fun vignetteFor(theme: ThemeId, bottomOnly: Boolean = false): (@Composable () -> Unit)? = when {
    theme != ThemeId.NEGRO -> null
    bottomOnly -> NegroVignetteBottom
    else -> NegroVignette
}

private val NegroVignette: @Composable () -> Unit = { Vignette(vignettePosition = VignettePosition.TopAndBottom) }
private val NegroVignetteBottom: @Composable () -> Unit = { Vignette(vignettePosition = VignettePosition.Bottom) }

/**
 * Fila fija superior con «SOS». En pantalla redonda va bajo TimeText, centrada y desplazada a la
 * derecha (dentro del círculo incluso en 192 dp con letra grande); en cuadrada, arriba a la derecha.
 */
@Composable
fun SosHeader(onSos: () -> Unit, modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    val round = LocalConfiguration.current.isScreenRound
    // El objetivo táctil (48 dp) puede invadir 8 dp la franja de TimeText, que no es un control;
    // el contorno visible del botón queda por debajo de la hora.
    val top = (timeTextSpace() - 8.dp).coerceAtLeast(0.dp)
    Box(
        contentAlignment = if (round) Alignment.TopCenter else Alignment.TopEnd,
        modifier = modifier
            .fillMaxWidth()
            .background(palette.background.toColor())
            .windowInsetsPadding(WindowInsets.safeDrawing)
            .padding(top = top),
    ) {
        SosButton(
            onClick = onSos,
            modifier = if (round) Modifier.offset(x = 18.dp) else Modifier.padding(end = 6.dp),
        )
    }
}

/**
 * Botón «SOS»: texto (no sólo icono), rojo sobrio `critical` (≥ 4,5:1 sobre el fondo en ambos
 * temas, ver DesignTokensTest), contorno fino. Visual compacto; objetivo táctil ≥ 48 × 48 dp.
 * TalkBack: "SOS, botón, … abrir la pantalla de emergencia". Sin gestos propios.
 */
@Composable
fun SosButton(onClick: () -> Unit, modifier: Modifier = Modifier) {
    val red = LocalPalette.current.critical.toColor()
    val description = stringResource(R.string.sos_button_a11y)
    val actionLabel = stringResource(R.string.sos_button_action)
    Box(
        contentAlignment = Alignment.Center,
        modifier = modifier
            .sizeIn(minWidth = MinTouchTarget, minHeight = MinTouchTarget)
            .clip(RoundedCornerShape(50))
            .clickable(onClickLabel = actionLabel, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
    ) {
        Text(
            text = stringResource(R.string.sos_button),
            color = red,
            style = MaterialTheme.typography.button,
            fontWeight = FontWeight.SemiBold,
            textAlign = TextAlign.Center,
            modifier = Modifier
                .clearAndSetSemantics { }
                .border(1.5.dp, red, RoundedCornerShape(50))
                .padding(horizontal = 12.dp, vertical = 5.dp),
        )
    }
}

/**
 * Cifra con etiqueta: etiqueta pequeña en texto secundario, valor con dígitos tabulares y línea
 * fina debajo. TalkBack lee [spoken] (unidades en palabras) como un único elemento.
 */
@Composable
fun StatRow(label: String, value: String, spoken: String, hero: Boolean = false, divider: Boolean = true) {
    val palette = LocalPalette.current
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = roundTextInset())
            .clearAndSetSemantics { contentDescription = spoken },
    ) {
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.caption2,
            color = palette.textSecondary.toColor(),
            letterSpacing = 0.6.sp,
            textAlign = TextAlign.Center,
        )
        Text(
            text = value,
            style = (if (hero) MaterialTheme.typography.display3 else MaterialTheme.typography.title2).tabular(),
            color = palette.textPrimary.toColor(),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(bottom = 4.dp),
        )
        if (divider) Hairline()
    }
}

/** Línea fina decorativa (`hairline`). */
@Composable
fun Hairline(modifier: Modifier = Modifier) {
    Box(
        modifier = modifier
            .fillMaxWidth(0.7f)
            .height(1.dp)
            .background(LocalPalette.current.hairline.toColor()),
    )
}

/** Separación clara antes de «Finalizar trayecto»: línea fina + espacio. */
@Composable
fun EndSeparator() {
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = Modifier.fillMaxWidth()) {
        Spacer(modifier = Modifier.height(10.dp))
        Hairline()
        Spacer(modifier = Modifier.height(14.dp))
    }
}

/** Etiqueta de sección en mayúsculas, marcada como encabezado para TalkBack. */
@Composable
fun SectionLabel(text: String) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.caption2,
        fontWeight = FontWeight.SemiBold,
        letterSpacing = 0.6.sp,
        color = LocalPalette.current.textSecondary.toColor(),
        textAlign = TextAlign.Center,
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = 6.dp)
            .semantics { heading() },
    )
}
