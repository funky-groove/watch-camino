package org.caminoseguro.watch.ui

import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.material.ListHeader
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.RadioButton
import androidx.wear.compose.material.Text
import androidx.wear.compose.material.ToggleChip
import org.caminoseguro.watch.R
import org.caminoseguro.watch.core.Places
import org.caminoseguro.watch.core.PlacesFilter
import org.caminoseguro.watch.core.Poi
import org.caminoseguro.watch.core.ProfileSample
import org.caminoseguro.watch.platform.Notifications
import java.time.Duration
import java.time.Instant

// Pantallas V1.1: perfil ampliado, Lugares + ficha, aviso «Accede desde tu esfera» y su ayuda.

// ------------------------------------------------------------------ Perfil ampliado

@Composable
fun ProfileScreen(profile: List<ProfileSample>, hasAltitudeData: Boolean, ascentMeters: Double, descentMeters: Double) {
    val f = LocalFormat.current
    // Arriba, bajo la hora: el gráfico es alto y, centrado, empujaba el título encima de TimeText.
    CaminoScreen(topAligned = true) {
        item { ListHeader { Text(stringResource(R.string.profile_title), textAlign = TextAlign.Center) } }
        item {
            val summary = profileSummary(profile, spoken = true)
            androidx.compose.foundation.layout.Box(
                modifier = Modifier
                    .fillMaxWidth()
                    // Las etiquetas de los ejes quedan en las esquinas: margen de pantalla redonda.
                    .padding(horizontal = roundTextInset())
                    .clearAndSetSemantics { contentDescription = summary },
            ) {
                ProfileChart(profile, height = 84.dp)
            }
        }
        item { CenteredText(profileSummary(profile, spoken = false), style = MaterialTheme.typography.caption1) }
        if (hasAltitudeData) {
            item {
                val ascentLabel = stringResource(R.string.trip_label_ascent)
                ValueText(
                    stringResource(R.string.label_value, ascentLabel, f.elevation(ascentMeters)),
                    stringResource(R.string.label_value_a11y, ascentLabel, f.elevationSpoken(ascentMeters)),
                )
            }
            item {
                val descentLabel = stringResource(R.string.trip_label_descent)
                ValueText(
                    stringResource(R.string.label_value, descentLabel, f.elevation(descentMeters)),
                    stringResource(R.string.label_value_a11y, descentLabel, f.elevationSpoken(descentMeters)),
                )
            }
        }
        item { CenteredText(stringResource(R.string.profile_recorded_note), style = MaterialTheme.typography.caption2) }
        item { CenteredText(stringResource(R.string.trip_altitude_source), style = MaterialTheme.typography.caption2) }
    }
}

// ------------------------------------------------------------------ Lugares (§J)

/**
 * Lista de lugares con filtros mínimos (todos / agua / alojamiento) y estados: sin ubicación (orden
 * por nombre, sin distancias), ubicación antigua, sin resultados y datos de demostración.
 */
@Composable
fun PlacesScreen(source: PlacesSource, now: Instant, onPlace: (String) -> Unit) {
    var filter by rememberSaveable { mutableStateOf(PlacesFilter.all) }
    val position = source.position
    val rows = Places.list(source.pois, position?.point, filter)
    CaminoScreen {
        item { ListHeader { Text(stringResource(R.string.places_title)) } }
        items(PlacesFilter.entries.toList()) { option ->
            val selected = option == filter
            val label = stringResource(
                when (option) {
                    PlacesFilter.all -> R.string.places_filter_all
                    PlacesFilter.water -> R.string.places_filter_water
                    PlacesFilter.shelter -> R.string.places_filter_shelter
                },
            )
            ToggleChip(
                checked = selected,
                onCheckedChange = { if (it) filter = option },
                label = { Text(text = label, maxLines = 2, overflow = TextOverflow.Ellipsis) },
                toggleControl = { RadioButton(selected = selected) },
                modifier = Modifier.fillMaxWidth(),
            )
        }
        if (position == null) {
            item { CenteredText(stringResource(R.string.places_no_location), style = MaterialTheme.typography.caption2) }
        } else if (Duration.between(position.timestamp, now).seconds > STALE_POSITION_S) {
            item { CenteredText(stringResource(R.string.places_location_stale), style = MaterialTheme.typography.caption2) }
        }
        if (rows.isEmpty()) {
            item { CenteredText(stringResource(R.string.places_empty_filter)) }
        }
        items(rows, key = { it.poi.id }) { row ->
            PlaceChip(row.poi, row.distanceMeters, onClick = { onPlace(row.poi.id) })
        }
        if (source.demoData) {
            item { CenteredText(stringResource(R.string.places_demo_notice), style = MaterialTheme.typography.caption2) }
        }
    }
}

/** Ubicación de más de 5 min: las distancias se marcan como posiblemente inexactas. */
private const val STALE_POSITION_S = 300L

/**
 * Ficha: nombre, categoría, distancia "en línea recta" y, sólo si el lugar tiene teléfono válido
 * (`poi.telUri() != null`), «Llamar», que abre el marcador (`ACTION_DIAL`, sin `CALL_PHONE`). Si no
 * hay marcador se dice; nunca se muestra un mensaje de éxito (la app no sabe si se llamó).
 */
@Composable
fun PlaceDetailScreen(poi: Poi?, source: PlacesSource, onCall: (String) -> Boolean) {
    val f = LocalFormat.current
    var callFailed by rememberSaveable { mutableStateOf(false) }
    // Fuera del contenido de la lista (que no es @Composable).
    val category = poi?.let { stringResource(Notifications.categoryLabel(it.category)) }.orEmpty()
    CaminoScreen {
        if (poi == null) {
            item { CenteredText(stringResource(R.string.place_not_found)) }
            return@CaminoScreen
        }
        item {
            ListHeader {
                Text(text = poi.name, maxLines = 3, overflow = TextOverflow.Ellipsis, textAlign = TextAlign.Center)
            }
        }
        item { CenteredText("${poi.category.icon} $category", style = MaterialTheme.typography.body2) }
        item {
            val position = source.position
            if (position == null) {
                CenteredText(stringResource(R.string.place_distance_unknown), style = MaterialTheme.typography.caption1)
            } else {
                val d = org.caminoseguro.watch.core.Geo.haversineMeters(position.point, poi.location)
                ValueText(
                    stringResource(R.string.places_straight_line, f.distance(d)),
                    stringResource(R.string.places_straight_line, f.distanceSpoken(d)),
                    style = MaterialTheme.typography.title3,
                )
            }
        }
        val tel = poi.telUri()
        if (tel != null) {
            item {
                WideChip(
                    text = stringResource(R.string.action_call),
                    secondaryText = stringResource(R.string.place_call_hint),
                    primary = true,
                    onClick = { callFailed = !onCall(tel) },
                )
            }
            if (callFailed) {
                item {
                    Text(
                        text = stringResource(R.string.place_call_failed),
                        style = MaterialTheme.typography.caption1,
                        modifier = Modifier
                            .fillMaxWidth()
                            .semantics { liveRegion = LiveRegionMode.Polite },
                    )
                }
            }
        }
        if (source.demoData) {
            item { CenteredText(stringResource(R.string.places_demo_notice), style = MaterialTheme.typography.caption2) }
        }
    }
}

// ------------------------------------------------------------------ Aviso «Accede desde tu esfera» (§I)

/**
 * Aviso de primer uso. No afirma que la complicación esté instalada. «Cómo añadirlo» abre la ayuda
 * (y se guarda `helpOpened`); «Ahora no» se guarda como `dismissed`. Volver con el gesto del sistema
 * no decide nada: se volverá a ofrecer en otro arranque.
 */
@Composable
fun FaceHintScreen(onHow: () -> Unit, onNotNow: () -> Unit) {
    CaminoScreen {
        item {
            CenteredText(stringResource(R.string.face_hint_title), style = MaterialTheme.typography.title3)
        }
        item { CenteredText(stringResource(R.string.face_hint_text), style = MaterialTheme.typography.body2) }
        item { WideChip(text = stringResource(R.string.face_hint_how), onClick = onHow, primary = true) }
        item { WideChip(text = stringResource(R.string.face_hint_not_now), onClick = onNotNow) }
    }
}

/**
 * Cómo añadir la complicación: pasos MANUALES. No se abre ningún configurador: no hay una API pública
 * verificada para abrir el editor de esfera desde una app de terceros.
 */
@Composable
fun FaceHelpScreen() {
    CaminoScreen {
        item { ListHeader { Text(stringResource(R.string.face_help_title)) } }
        item { CenteredText(stringResource(R.string.face_help_step1)) }
        item { CenteredText(stringResource(R.string.face_help_step2)) }
        item { CenteredText(stringResource(R.string.face_help_step3)) }
        item { CenteredText(stringResource(R.string.face_help_step4)) }
        item { CenteredText(stringResource(R.string.face_help_vary), style = MaterialTheme.typography.caption2) }
        item { CenteredText(stringResource(R.string.face_help_shows), style = MaterialTheme.typography.caption2) }
    }
}
