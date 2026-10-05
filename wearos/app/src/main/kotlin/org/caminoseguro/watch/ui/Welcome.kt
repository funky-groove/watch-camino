package org.caminoseguro.watch.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameMillis
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.WelcomeTiming

/**
 * Datos de una bienvenida decidida en `MainActivity.onCreate` (§K.2).
 * - [reducedMotion]: sin fundido; se retira de golpe a los 0,6 s.
 * - [holdUntilTap]: SÓLO escenarios DEMO con `demo.welcome=show` (capturas): no se retira sola.
 * - [tripActive]: si al terminar de restaurar aparece un trayecto activo, se retira al instante.
 * - [cachedLogo]: lo rellena en IO la decodificación de la caché; sólo se usa si está listo al
 *   componer el primer fotograma (nunca se espera: si no, logo incluido).
 */
class WelcomeLaunch(
    val reducedMotion: Boolean,
    val holdUntilTap: Boolean,
    val tripActive: Flow<Boolean>,
    val tripActiveInitial: Boolean,
) {
    @Volatile var cachedLogo: ImageBitmap? = null
}

/**
 * Bienvenida visual (§K.3): capa sobre la interfaz YA construida ([content] se compone siempre,
 * debajo). La capa no tiene manejadores de toque, así que los toques llegan a la interfaz; el
 * contenedor observa el toque en la pasada inicial SIN consumirlo y retira la capa. Es decorativa:
 * sin semántica (TalkBack no la anuncia ni recibe foco).
 */
@Composable
fun WelcomeHost(welcome: WelcomeLaunch?, content: @Composable () -> Unit) {
    var showing by remember { mutableStateOf(welcome != null) }
    val dismissOnTouch = if (showing) {
        Modifier.pointerInput(Unit) {
            awaitPointerEventScope {
                while (true) {
                    val event = awaitPointerEvent(PointerEventPass.Initial)
                    if (event.type == PointerEventType.Press) showing = false
                }
            }
        }
    } else {
        Modifier
    }
    Box(Modifier.fillMaxSize().then(dismissOnTouch)) {
        content()
        if (showing && welcome != null) WelcomeOverlay(welcome, onDone = { showing = false })
    }
}

@Composable
private fun WelcomeOverlay(welcome: WelcomeLaunch, onDone: () -> Unit) {
    // Se lee una sola vez, en la primera composición: o la caché ya está decodificada, o logo incluido.
    val cachedPainter = remember { welcome.cachedLogo?.let { BitmapPainter(it) } }
    var alpha by remember { mutableFloatStateOf(1f) }
    val tripActive by welcome.tripActive.collectAsState(initial = welcome.tripActiveInitial)

    LaunchedEffect(tripActive) {
        if (tripActive && !welcome.holdUntilTap) onDone()
    }
    LaunchedEffect(Unit) {
        if (welcome.holdUntilTap) return@LaunchedEffect
        delay(WelcomeTiming.VISIBLE_MS)
        if (!welcome.reducedMotion) {
            // Fundido por fotogramas con reloj real: no lo alarga la escala de animaciones.
            val fade = WelcomeTiming.FADE_MS.toFloat()
            val start = withFrameMillis { it }
            while (true) {
                val elapsed = withFrameMillis { it } - start
                alpha = (1f - elapsed / fade).coerceIn(0f, 1f)
                if (elapsed >= WelcomeTiming.FADE_MS) break
            }
        }
        onDone()
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .graphicsLayer { this.alpha = alpha }
            .background(Color.Black)
            .clearAndSetSemantics { },
        contentAlignment = Alignment.Center,
    ) {
        Image(
            painter = cachedPainter ?: painterResource(R.drawable.brand_logo),
            contentDescription = null,
            modifier = Modifier.fillMaxSize(LOGO_FRACTION),
        )
    }
}

/** Fracción de la pantalla que ocupa el logo (cabe en la zona útil de una esfera redonda). */
private const val LOGO_FRACTION = 0.62f
