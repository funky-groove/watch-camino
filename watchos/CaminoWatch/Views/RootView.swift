import SwiftUI
import CaminoCore

/// Destinos de navegación.
enum Route: Hashable {
    case pickStage
    case stats
    case sync
}

/// Raíz: Inicio (Idle) o Etapa (Active), dentro de un único `NavigationStack`.
struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.scenePhase) private var scenePhase
    @State private var path: [Route] = []

    var body: some View {
        NavigationStack(path: $path) {
            Group {
                if let session = model.activeSession {
                    ActiveStageView(session: session)
                } else {
                    HomeView(path: $path)
                }
            }
            .navigationDestination(for: Route.self) { route in
                destination(for: route)
            }
        }
        .sheet(item: $model.finishedSummary) { summary in
            SummaryView(summary: summary)
                .environmentObject(model)
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

    @ViewBuilder
    private func destination(for route: Route) -> some View {
        switch route {
        case .pickStage:
            StagePickerView()
        case .stats:
            StatsView()
        case .sync:
            SyncView()
        }
    }
}
