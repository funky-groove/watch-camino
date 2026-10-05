package org.caminoseguro.watch.ui

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.DisplayFormat
import org.caminoseguro.watch.core.DisplayPreferences
import org.caminoseguro.watch.core.PaceMode
import org.caminoseguro.watch.core.PoiDistance
import org.caminoseguro.watch.core.ProfileGeometry
import org.caminoseguro.watch.core.ProfileSample
import org.caminoseguro.watch.platform.Notifications

// Componentes V1.1 del trayecto: estadísticas principales, altitud y desnivel, perfil (Canvas) y
// lugares útiles. Todas las cifras pasan por [LocalFormat] (unidades, ritmo/velocidad e idioma).

/** Formato de cifras de la pantalla (preferencias + idioma efectivo de los recursos). */
val LocalFormat = staticCompositionLocalOf { DisplayFormat() }

/** Proporciona [LocalFormat] con el idioma con el que se resolvieron los recursos de la actividad. */
@Composable
fun ProvideFormat(prefs: DisplayPreferences, content: @Composable () -> Unit) {
    val locales = LocalConfiguration.current.locales
    val lang = DisplayFormat.languageOf(if (locales.isEmpty) null else locales[0].toLanguageTag())
    CompositionLocalProvider(LocalFormat provides DisplayFormat.of(prefs, lang), content = content)
}

// ------------------------------------------------------------------ A. Estadísticas principales

/** «En marcha» / «Pausado»: símbolo + texto (el color nunca va solo). */
@Composable
fun TripStatusLabel(paused: Boolean, demo: Boolean = false) {
    val palette = LocalPalette.current
    val color = (if (paused) palette.warning else palette.positive).toColor()
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Icon(
            painter = painterResource(if (paused) R.drawable.ic_status_paused else R.drawable.ic_status_moving),
            contentDescription = null,
            tint = color,
            modifier = Modifier.size(14.dp),
        )
        Spacer(modifier = Modifier.width(4.dp))
        Text(
            text = stringResource(if (paused) R.string.trip_status_paused else R.string.trip_status_moving),
            style = MaterialTheme.typography.caption1,
            fontWeight = FontWeight.SemiBold,
            color = color,
        )
        if (demo) {
            // Marca DEMO (MockCaminoApi) visible en la primera vista, sin desplazar las cifras.
            Spacer(modifier = Modifier.width(6.dp))
            Text(
                text = stringResource(R.string.demo_badge),
                style = MaterialTheme.typography.caption2,
                fontWeight = FontWeight.Bold,
                color = palette.positive.toColor(),
                modifier = Modifier
                    .border(1.dp, palette.positive.toColor(), RoundedCornerShape(50))
                    .padding(horizontal = 6.dp),
            )
        }
    }
}

/**
 * Primera vista sin desplazarse (≈192 dp redondo): estado, distancia destacada, tiempo EN MOVIMIENTO
 * y ritmo o velocidad. TalkBack lo lee como un único elemento con las unidades en palabras.
 */
@Composable
fun PrimaryStats(active: ActiveStageUi, isDemo: Boolean) {
    val f = LocalFormat.current
    val palette = LocalPalette.current
    val walked = active.figures.walkedMeters
    val waiting = stringResource(R.string.trip_waiting_gps)
    val noData = stringResource(R.string.stat_unavailable)
    val moving = active.movingSeconds
    val paceLabel = stringResource(if (f.paceMode == PaceMode.pace) R.string.trip_label_pace else R.string.trip_label_speed)
    val paceText = walked?.let { f.paceOrSpeed(it, moving.toDouble()) } ?: noData
    val paceSpoken = walked?.let { f.paceOrSpeedSpoken(it, moving.toDouble()) } ?: noData
    val status = stringResource(if (active.paused) R.string.trip_status_paused else R.string.trip_status_moving)
    val demoSpoken = if (isDemo) stringResource(R.string.demo_badge_a11y) + ". " else ""
    val spoken = demoSpoken + stringResource(
        R.string.trip_primary_a11y,
        status,
        walked?.let { f.distanceSpoken(it) } ?: waiting,
        f.durationSpoken(moving),
        paceLabel,
        paceSpoken,
    )
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = spoken },
    ) {
        TripStatusLabel(active.paused, demo = isDemo)
        Text(
            text = walked?.let { f.distance(it) } ?: waiting,
            style = (if (walked != null) MaterialTheme.typography.display3 else MaterialTheme.typography.title3).tabular(),
            color = palette.textPrimary.toColor(),
            textAlign = TextAlign.Center,
        )
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            MiniStat(stringResource(R.string.trip_label_moving_time), f.duration(moving), Modifier.weight(1f))
            MiniStat(paceLabel, paceText, Modifier.weight(1f))
        }
    }
}

/** Etiqueta pequeña + valor (sin semántica propia: la da el contenedor). */
@Composable
fun MiniStat(label: String, value: String, modifier: Modifier = Modifier) {
    val palette = LocalPalette.current
    Column(horizontalAlignment = Alignment.CenterHorizontally, modifier = modifier) {
        Text(
            text = label.uppercase(),
            style = MaterialTheme.typography.caption2,
            letterSpacing = 0.4.sp,
            color = palette.textSecondary.toColor(),
            textAlign = TextAlign.Center,
            maxLines = 2,
        )
        Text(
            text = value,
            style = MaterialTheme.typography.title3.tabular(),
            color = palette.textPrimary.toColor(),
            textAlign = TextAlign.Center,
        )
    }
}

// ------------------------------------------------------------------ B. Altitud y desnivel

/** Altitud actual (GPS), subida y bajada; ausente o antigua se dice en texto. */
@Composable
fun AltitudeBlock(active: ActiveStageUi) {
    val f = LocalFormat.current
    val palette = LocalPalette.current
    val noData = stringResource(R.string.stat_unavailable)
    val altitude = active.altitude
    val altitudeLabel = stringResource(R.string.trip_label_altitude)
    val ascentLabel = stringResource(R.string.trip_label_ascent)
    val descentLabel = stringResource(R.string.trip_label_descent)
    val ascent = if (active.hasAltitudeData) f.elevation(active.ascentMeters) else noData
    val descent = if (active.hasAltitudeData) f.elevation(active.descentMeters) else noData
    val altitudeSpoken = when {
        altitude == null -> stringResource(R.string.trip_altitude_none)
        active.altitudeStale -> stringResource(R.string.trip_altitude_stale_a11y, f.elevationSpoken(altitude))
        else -> stringResource(R.string.trip_altitude_a11y, f.elevationSpoken(altitude))
    }
    val spoken = listOf(
        altitudeSpoken,
        stringResource(R.string.label_value_a11y, ascentLabel, if (active.hasAltitudeData) f.elevationSpoken(active.ascentMeters) else noData),
        stringResource(R.string.label_value_a11y, descentLabel, if (active.hasAltitudeData) f.elevationSpoken(active.descentMeters) else noData),
    ).joinToString(". ")
    Column(
        horizontalAlignment = Alignment.CenterHorizontally,
        modifier = Modifier
            .fillMaxWidth()
            .clearAndSetSemantics { contentDescription = spoken },
    ) {
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceEvenly) {
            MiniStat(altitudeLabel, altitude?.let { f.elevation(it) } ?: noData, Modifier.weight(1f))
            MiniStat(ascentLabel, ascent, Modifier.weight(1f))
            MiniStat(descentLabel, descent, Modifier.weight(1f))
        }
        val note = when {
            altitude == null -> stringResource(R.string.trip_altitude_none)
            active.altitudeStale -> stringResource(R.string.trip_altitude_stale)
            else -> stringResource(R.string.trip_altitude_source)
        }
        Text(
            text = note,
            style = MaterialTheme.typography.caption2,
            color = (if (altitude != null && active.altitudeStale) palette.warning else palette.textSecondary).toColor(),
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(top = 2.dp),
        )
    }
}

// ------------------------------------------------------------------ C. Perfil de altitud

/**
 * Resumen hablado del perfil: "Perfil de altitud de 4,2 kilómetros, de 412 a 448 metros", o
 * "Aún no hay perfil" con menos de 2 muestras.
 */
@Composable
fun profileSummary(profile: List<ProfileSample>, spoken: Boolean): String {
    val f = LocalFormat.current
    val stats = ProfileGeometry.stats(profile) ?: return stringResource(R.string.profile_none)
    return if (spoken) {
        stringResource(
            R.string.profile_a11y,
            f.distanceSpoken(stats.spanMeters),
            f.elevationSpoken(stats.minAltitude),
            f.elevationSpoken(stats.maxAltitude),
        )
    } else {
        stringResource(
            R.string.profile_a11y,
            f.distance(stats.spanMeters),
            f.elevation(stats.minAltitude),
            f.elevation(stats.maxAltitude),
        )
    }
}

/**
 * Perfil registrado (distancia × altitud) con Canvas: una polilínea por tramo, sin unir los huecos
 * `gapBefore`; un tramo de una sola muestra es un punto. Ejes mínimos: línea base y eje vertical,
 * con etiquetas de texto (unidades del usuario) fuera del Canvas para que crezcan con la letra.
 * El Canvas no tiene semántica: el contenedor da el resumen hablado.
 */
@Composable
fun ProfileChart(profile: List<ProfileSample>, height: Dp, modifier: Modifier = Modifier) {
    val f = LocalFormat.current
    val palette = LocalPalette.current
    val stats = ProfileGeometry.stats(profile)
    if (stats == null) {
        Text(
            text = stringResource(R.string.profile_none),
            style = MaterialTheme.typography.caption1,
            color = palette.textSecondary.toColor(),
            textAlign = TextAlign.Center,
            modifier = modifier.fillMaxWidth(),
        )
        return
    }
    val lineColor = palette.textPrimary.toColor()
    val axisColor = palette.controlOutline.toColor()
    // Rango vertical mínimo de 10 m para que el ruido no parezca una montaña.
    val mid = (stats.maxAltitude + stats.minAltitude) / 2
    val half = maxOf((stats.maxAltitude - stats.minAltitude) / 2, MIN_ALTITUDE_RANGE_M / 2)
    val low = mid - half
    val high = mid + half
    val span = stats.spanMeters.takeIf { it > 0.0 } ?: 1.0
    Column(modifier = modifier.fillMaxWidth()) {
        Text(
            text = f.elevation(stats.maxAltitude),
            style = MaterialTheme.typography.caption2.tabular(),
            color = palette.textSecondary.toColor(),
        )
        Canvas(
            modifier = Modifier
                .fillMaxWidth()
                .height(height),
        ) {
            val w = size.width
            val h = size.height
            val strokePx = 2.dp.toPx()
            val axisPx = 1.dp.toPx()
            fun x(d: Double): Float = ((d - stats.startMeters) / span * w).toFloat()
            fun y(alt: Double): Float = (h - (alt - low) / (high - low) * h).toFloat()
            // Ejes mínimos: base y vertical izquierda.
            drawLine(axisColor, Offset(0f, h), Offset(w, h), strokeWidth = axisPx)
            drawLine(axisColor, Offset(0f, 0f), Offset(0f, h), strokeWidth = axisPx)
            for (segment in stats.segments) {
                if (segment.size == 1) {
                    drawCircle(lineColor, radius = strokePx, center = Offset(x(segment[0].d), y(segment[0].alt)))
                    continue
                }
                val path = Path()
                segment.forEachIndexed { i, s ->
                    if (i == 0) path.moveTo(x(s.d), y(s.alt)) else path.lineTo(x(s.d), y(s.alt))
                }
                drawPath(path, lineColor, style = Stroke(width = strokePx, cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
        }
        Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
            Text(
                text = f.elevation(stats.minAltitude),
                style = MaterialTheme.typography.caption2.tabular(),
                color = palette.textSecondary.toColor(),
            )
            Text(
                text = f.distance(stats.spanMeters),
                style = MaterialTheme.typography.caption2.tabular(),
                color = palette.textSecondary.toColor(),
            )
        }
    }
}

/** Perfil compacto pulsable (≥ 48 dp): abre la vista ampliada. */
@Composable
fun ProfileCard(profile: List<ProfileSample>, onOpen: () -> Unit) {
    val summary = profileSummary(profile, spoken = true)
    val action = stringResource(R.string.profile_open_action)
    Box(
        modifier = Modifier
            .fillMaxWidth()
            .heightIn(min = MinTouchTarget)
            .clip(RoundedCornerShape(14.dp))
            .clickable(onClickLabel = action, role = Role.Button, onClick = onOpen)
            .clearAndSetSemantics { contentDescription = summary }
            .padding(horizontal = 12.dp, vertical = 4.dp),
        contentAlignment = Alignment.Center,
    ) {
        ProfileChart(profile, height = 40.dp)
    }
}

private const val MIN_ALTITUDE_RANGE_M = 10.0

// ------------------------------------------------------------------ D. Lugares útiles

/** Fila de lugar: icono+categoría en texto, nombre y distancia "en línea recta". */
@Composable
fun PlaceChip(poi: org.caminoseguro.watch.core.Poi, distanceMeters: Double?, onClick: () -> Unit) {
    val f = LocalFormat.current
    val category = stringResource(Notifications.categoryLabel(poi.category))
    val distance = distanceMeters?.let { stringResource(R.string.places_straight_line, f.distance(it)) }
        ?: stringResource(R.string.place_distance_unknown_short)
    val spokenDistance = distanceMeters?.let { stringResource(R.string.places_straight_line, f.distanceSpoken(it)) }
        ?: stringResource(R.string.place_distance_unknown_short)
    WideChip(
        text = "${poi.category.icon} ${poi.name}",
        secondaryText = "$category · $distance",
        onClick = onClick,
        spoken = stringResource(R.string.place_row_a11y, poi.name, category, spokenDistance),
    )
}

/** Lugares útiles en Trayecto (máx. 3) desde una lista ya elegida por el núcleo. */
@Composable
fun UsefulPlaceChip(place: PoiDistance, onClick: () -> Unit) {
    PlaceChip(place.poi, place.distanceMeters, onClick)
}
