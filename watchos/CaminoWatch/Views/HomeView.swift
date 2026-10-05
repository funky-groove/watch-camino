import SwiftUI
import CaminoCore

/// Inicio (Idle), §10: botón grande "Comenzar etapa" y, debajo, el estado de sync.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var path: [Route]

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if model.isDemo {
                    DemoBadge()
                }

                Button {
                    // Permisos pedidos en contexto (§11).
                    model.requestPermissions()
                    path.append(.pickStage)
                } label: {
                    Label(L10n.startStage, systemImage: "figure.walk")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 56)
                }
                .buttonStyle(.borderedProminent)
                .accessibilityHint(L10n.startStageHint)

                if let message = model.errorMessage {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .font(.footnote)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                SyncStatusRow()

                NavigationLink(value: Route.stats) {
                    Label(L10n.statsTitle, systemImage: "chart.bar")
                        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                }
            }
        }
        .navigationTitle(L10n.appTitle)
    }
}
