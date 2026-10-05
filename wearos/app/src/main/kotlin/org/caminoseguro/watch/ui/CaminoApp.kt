package org.caminoseguro.watch.ui

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.wear.compose.material.MaterialTheme
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
}

/**
 * Navegación (spec §10): cualquier acción V1 en ≤ 2 toques desde Inicio/Etapa.
 * "home" muestra Inicio (Idle) o la Etapa activa según el estado.
 */
@Composable
fun CaminoApp(viewModel: CaminoViewModel) {
    MaterialTheme {
        val state by viewModel.ui.collectAsStateWithLifecycle()
        val event by viewModel.events.collectAsStateWithLifecycle()
        val navController = rememberSwipeDismissableNavController()

        // Permisos pedidos en contexto, al pulsar "Comenzar etapa" (spec §11). Si se deniegan,
        // se sigue igualmente: la etapa funciona con lo disponible y la UI lo indica.
        val permissionLauncher = rememberLauncherForActivityResult(
            ActivityResultContracts.RequestMultiplePermissions(),
        ) { _ ->
            viewModel.onPermissionsResult()
            navController.navigate(Routes.SELECT)
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

        SwipeDismissableNavHost(navController = navController, startDestination = Routes.HOME) {
            composable(Routes.HOME) {
                val active = state.active
                when {
                    !state.ready -> LoadingScreen()
                    active != null -> ActiveStageScreen(
                        state = state,
                        active = active,
                        onFinish = { navController.navigate(Routes.CONFIRM_FINISH) },
                        onStats = { navController.navigate(Routes.STATS) },
                        onSync = { navController.navigate(Routes.SYNC) },
                    )
                    else -> HomeScreen(
                        state = state,
                        onStart = {
                            val missing = viewModel.missingPermissions()
                            if (missing.isEmpty()) {
                                navController.navigate(Routes.SELECT)
                            } else {
                                permissionLauncher.launch(missing)
                            }
                        },
                        onStats = { navController.navigate(Routes.STATS) },
                        onSync = { navController.navigate(Routes.SYNC) },
                    )
                }
            }
            composable(Routes.SELECT) {
                SelectStageScreen(
                    state = state,
                    onSelect = { stageId ->
                        viewModel.selectStage(stageId)
                        navController.navigate(Routes.CONFIRM_START)
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
        }
    }
}
