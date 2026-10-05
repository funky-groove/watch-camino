package org.caminoseguro.watch.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.navigation.SwipeDismissableNavHost
import androidx.wear.compose.navigation.composable
import androidx.wear.compose.navigation.rememberSwipeDismissableNavController

private object Routes {
    const val HOME = "home"
    const val SELECT = "select"
    const val CONFIRM_START = "confirm_start"
    const val CONFIRM_FINISH = "confirm_finish"
    const val SUMMARY = "summary"
    const val STATS = "stats"
    const val SYNC = "sync"
    const val SETTINGS = "settings"
    const val SOS = "sos"
}

/**
 * Navegación (spec §10): cualquier acción V1 en ≤ 2 toques desde Inicio/Trayecto.
 * "home" muestra Inicio (sin trayecto) o el Trayecto en curso según el estado; en ambos, «SOS»
 * fijo arriba a la derecha abre la ruta "sos" (volver = gesto/atrás del sistema o «Volver»).
 */
@Composable
fun CaminoApp(viewModel: CaminoViewModel) {
    val theme by viewModel.theme.collectAsStateWithLifecycle()
    CaminoTheme(theme) {
        val state by viewModel.ui.collectAsStateWithLifecycle()
        val event by viewModel.events.collectAsStateWithLifecycle()
        val startBusy by viewModel.startFlowBusy.collectAsStateWithLifecycle()
        val navController = rememberSwipeDismissableNavController()
        val currentEntry by navController.currentBackStackEntryFlow.collectAsState(initial = null)
        val currentRoute = currentEntry?.destination?.route

        // Al volver a Inicio (atrás desde Elegir etapa, o tras iniciar) se puede volver a pulsar
        // «Iniciar trayecto». Mientras está el diálogo de permisos la ruta no cambia: sigue bloqueado.
        LaunchedEffect(currentRoute) {
            if (currentRoute == Routes.HOME) viewModel.resetStartFlow()
        }

        // Permisos pedidos en contexto, al pulsar «Iniciar trayecto» (spec §11). Si se deniegan,
        // se sigue igualmente: el trayecto funciona con lo disponible y la UI lo indica.
        val permissionLauncher = rememberLauncherForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions(),
        ) { _ ->
            viewModel.onPermissionsResult()
            navController.navigate(Routes.SELECT) { launchSingleTop = true }
        }

        LaunchedEffect(event) {
            when (event) {
                UiEvent.Started -> {
                    navController.popBackStack(Routes.HOME, inclusive = false)
                    viewModel.consumeEvent()
                }
                UiEvent.Finished -> {
                    navController.popBackStack(Routes.HOME, inclusive = false)
                    navController.navigate(Routes.SUMMARY)
                    viewModel.consumeEvent()
                }
                is UiEvent.Rejected -> {
                    navController.popBackStack(Routes.HOME, inclusive = false)
                    viewModel.consumeEvent()
                }
                null -> Unit
            }
        }

        val openSos = { navController.navigate(Routes.SOS) { launchSingleTop = true } }

        SwipeDismissableNavHost(navController = navController, startDestination = Routes.HOME) {
            composable(Routes.HOME) {
                // Estados de lista de la ruta de Inicio: `rememberScalingLazyListState` usa
                // rememberSaveable, que se guarda con la entrada del back stack; al volver de SOS
                // (o de cualquier otra pantalla) se restaura la posición de scroll.
                val idleList = rememberScalingLazyListState(initialCenterItemIndex = 0)
                val activeList = rememberScalingLazyListState(initialCenterItemIndex = 0)
                val active = state.active
                when {
                    !state.ready -> TripLoadingScreen(listState = idleList, onSos = openSos)
                    active != null -> TripActiveScreen(
                        state = state,
                        active = active,
                        listState = activeList,
                        onSos = openSos,
                        onFinish = { navController.navigate(Routes.CONFIRM_FINISH) { launchSingleTop = true } },
                        onStats = { navController.navigate(Routes.STATS) },
                        onSync = { navController.navigate(Routes.SYNC) },
                        onSettings = { navController.navigate(Routes.SETTINGS) },
                        onDismissIssue = { viewModel.dismissStorageIssue(it) },
                    )
                    else -> TripIdleScreen(
                        state = state,
                        listState = idleList,
                        startBusy = startBusy,
                        onStart = {
                            // Primer toque gana (ActionGate en el ViewModel); el chip queda deshabilitado.
                            if (viewModel.beginStartFlow()) {
                                val missing = viewModel.missingPermissions()
                                if (missing.isEmpty()) {
                                    navController.navigate(Routes.SELECT) { launchSingleTop = true }
                                } else {
                                    permissionLauncher.launch(missing)
                                }
                            }
                        },
                        onSos = openSos,
                        onStats = { navController.navigate(Routes.STATS) },
                        onSync = { navController.navigate(Routes.SYNC) },
                        onSettings = { navController.navigate(Routes.SETTINGS) },
                        onDismissIssue = { viewModel.dismissStorageIssue(it) },
                    )
                }
            }
            composable(Routes.SELECT) {
                SelectStageScreen(
                    state = state,
                    onSelect = { stageId ->
                        viewModel.selectStage(stageId)
                        navController.navigate(Routes.CONFIRM_START) { launchSingleTop = true }
                    },
                )
            }
            composable(Routes.CONFIRM_START) {
                ConfirmStartScreen(
                    state = state,
                    onConfirm = { viewModel.confirmStart() },
                    onCancel = { navController.popBackStack() },
                )
            }
            composable(Routes.CONFIRM_FINISH) {
                // Cancelar = volver: el trayecto sigue con todos sus datos.
                ConfirmFinishScreen(
                    state = state,
                    onConfirm = { viewModel.confirmFinish() },
                    onCancel = { navController.popBackStack() },
                )
            }
            composable(Routes.SUMMARY) {
                SummaryScreen(state = state, onDone = { navController.popBackStack() })
            }
            composable(Routes.STATS) {
                StatsScreen(state = state)
            }
            composable(Routes.SYNC) {
                SyncScreen(state = state, onSyncNow = { viewModel.syncNow() })
            }
            composable(Routes.SETTINGS) {
                SettingsScreen(
                    state = state,
                    theme = theme,
                    onTheme = { viewModel.setTheme(it) },
                    onToggle = { category, enabled -> viewModel.setAlertCategory(category, enabled) },
                )
            }
            composable(Routes.SOS) {
                // Abrir SOS no toca el trayecto (ni pausa ni finaliza). Lectura de ubicación única,
                // cancelada al salir; nunca se piden permisos aquí.
                DisposableEffect(Unit) {
                    viewModel.onSosOpened()
                    onDispose { viewModel.onSosClosed() }
                }
                val sos by viewModel.sosState.collectAsStateWithLifecycle()
                SosScreen(
                    state = sos,
                    onDial = { viewModel.dialEmergency() },
                    onBack = { navController.popBackStack() },
                )
            }
        }
    }
}
