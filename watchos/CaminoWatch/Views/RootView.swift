import SwiftUI
import CaminoCore
import CaminoDesign

/// Raíz: "Mi etapa" (sin etapa o con etapa en curso) dentro de un único `NavigationStack`.
///
/// - Los enlaces directos y las notificaciones piden pantallas con `model.requestedRoutes`;
///   aquí se consumen (se aplican a la pila y se limpian).
/// - Al empezar o terminar una etapa se vuelve a la raíz.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            HomeView(path: $path)
                .themed(themeStore.theme)
                // Aviso de primer uso «Accede desde tu esfera» (§I). Se cuelga de la pantalla
                // principal (no del NavigationStack, que ya presenta el resumen).
                .sheet(isPresented: $model.showFaceAccessPrompt, onDismiss: { faceAccessSheetClosed() }) {
                    FaceAccessPromptView()
                        .sheetCloseButton()
                        .environmentObject(model)
                        .environmentObject(themeStore)
                        .themed(themeStore.theme)
                }
                .navigationDestination(for: Route.self) { route in
                    destination(for: route)
                        .themed(themeStore.theme)
                }
        }
        .sheet(item: $model.finishedSummary) { summary in
            SummaryView(summary: summary)
                .sheetCloseButton()
                .environmentObject(model)
                .environmentObject(themeStore)
                .themed(themeStore.theme)
        }
        .onAppear {
            consume(model.requestedRoutes)
        }
        .onChange(of: model.requestedRoutes) { _, newRoutes in
            consume(newRoutes)
        }
        .onChange(of: scenePhase) { _, newPhase in
            if newPhase == .active {
                model.appBecameActive()
            }
        }
        .onChange(of: model.state.isActive) { _, _ in
            // Al empezar o terminar una etapa se vuelve a la raíz.
            path = []
        }
    }

    /// Al cerrarse el aviso: si se pidió «Cómo añadirlo», se abre la ayuda.
    private func faceAccessSheetClosed() {
        if model.faceAccessSheetClosed() {
            path = [.watchFaceHelp]
        }
    }

    /// Aplica una navegación pedida desde fuera y la marca como atendida.
    private func consume(_ routes: [Route]?) {
        guard let routes = routes else {
            return
        }
        path = routes
        model.requestedRoutes = nil
    }

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .pickStage:
            StagePickerView()
        case .stats:
            StatsView()
        case .statDetail(let metric):
            StatDetailView(metric: metric)
        case .nearby(let waterOnly):
            NearbyView(waterOnly: waterOnly)
        case .poi(let id):
            PoiDetailView(poiId: id)
        case .settings:
            SettingsView()
        case .sync:
            SyncView()
        case .sos:
            SOSView()
        case .profile:
            ProfileDetailView()
        case .watchFaceHelp:
            WatchFaceHelpView()
        }
    }
}

#if DEBUG
/// Tienda de tema sólo para previews (no toca las preferencias del usuario).
@MainActor
private func previewThemeStore(_ theme: ThemeID) -> ThemeStore {
    let store = ThemeStore(defaults: UserDefaults(suiteName: "preview.theme") ?? .standard)
    store.theme = theme
    return store
}

// Datos de demostración (Debug: MockCaminoApi, marca DEMO visible).
#Preview("Negro · demostración") {
    RootView()
        .environmentObject(AppModel())
        .environmentObject(previewThemeStore(.negro))
        .themed(.negro)
}

#Preview("Perla · demostración") {
    RootView()
        .environmentObject(AppModel())
        .environmentObject(previewThemeStore(.perla))
        .themed(.perla)
}
#endif
