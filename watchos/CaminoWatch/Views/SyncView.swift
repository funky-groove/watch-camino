import SwiftUI
import CaminoCore
import CaminoDesign

/// Sincronización (§7, §10): estado legible, qué significa para el usuario y
/// "sincronizar ahora". Nunca promete un envío que no ocurre (servidor de demostración).
struct SyncView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        let status = model.syncStatus

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                if model.isDemo {
                    DemoBadge()
                }

                StatusLine(
                    symbol: SyncText.symbol(status),
                    text: SyncText.status(status),
                    tone: SyncText.tone(status)
                )
                .accessibilityAddTraits(.isHeader)

                explanationText(explanation(for: status))

                if model.pendingCount > 0 && !isPending(status) {
                    explanationText(L10n.sync2Pending(model.pendingCount))
                }

                if model.isDemo && !isSynced(status) {
                    explanationText(L10n.sync2Demo)
                }

                if model.deadLetterCount > 0 {
                    StatusLine(
                        symbol: Icon.warning,
                        text: L10n.sync2DeadLetters(model.deadLetterCount),
                        tone: .warning
                    )
                    .padding(.top, Spacing.xs)
                    explanationText(L10n.sync2DeadLettersExplain)
                }

                Button {
                    model.syncNowManually()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        IconView(name: SyncText.symbol(.syncing))
                        Text(L10n.sync2Now)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(SecondaryButtonStyle())
                .disabled(status == .syncing)
                .padding(.top, Spacing.s)
            }
        }
        .navigationTitle(L10n.sync2Title)
    }

    private func explanationText(_ text: String) -> some View {
        Text(text)
            .typeStyle(.body)
            .foregroundStyle(palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func explanation(for status: SyncStatus) -> String {
        switch status {
        case .synced:
            // En Debug el servidor es simulado: no decir "guardado en el servidor".
            return model.isDemo ? L10n.sync2Demo : L10n.sync2Synced
        case .pending(let count):
            return L10n.sync2Pending(count)
        case .offline:
            return L10n.sync2Offline
        case .blocked:
            return L10n.sync2Blocked
        case .needsLink:
            return L10n.sync2NeedsLink
        case .syncing:
            return L10n.sync2Syncing
        }
    }

    private func isPending(_ status: SyncStatus) -> Bool {
        if case .pending = status {
            return true
        }
        return false
    }

    private func isSynced(_ status: SyncStatus) -> Bool {
        return status == .synced
    }
}

#Preview("negro · servidor de demostración") {
    NavigationStack {
        SyncView()
            .themed(.negro)
    }
    .environmentObject(AppModel())
    .environmentObject(ThemeStore())
}

#Preview("perla · servidor de demostración") {
    NavigationStack {
        SyncView()
            .themed(.perla)
    }
    .environmentObject(AppModel())
    .environmentObject(ThemeStore())
}
