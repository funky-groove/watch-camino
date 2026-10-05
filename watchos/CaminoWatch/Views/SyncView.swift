import SwiftUI
import CaminoCore

/// Sincronizar (§10): estado legible + "Sincronizar ahora".
struct SyncView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.isDemo {
                    DemoBadge()
                }

                Label(SyncText.status(model.syncStatus), systemImage: SyncText.symbol(model.syncStatus))
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                if model.pendingCount > 0 {
                    Text(L10n.syncSavedEvents(model.pendingCount))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if model.deadLetterCount > 0 {
                    Text(L10n.syncDeadLetters(model.deadLetterCount))
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let explanation = explanation {
                    Text(explanation)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Button {
                    model.syncNowManually()
                } label: {
                    Label(L10n.syncNow, systemImage: "arrow.triangle.2.circlepath")
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
                .disabled(model.syncStatus == .syncing)
            }
        }
        .navigationTitle(L10n.syncTitle)
    }

    private var explanation: String? {
        switch model.syncStatus {
        case .blocked:
            return L10n.syncBlockedExplain
        case .needsLink:
            return L10n.syncNeedsLinkExplain
        default:
            return model.isDemo ? L10n.syncDemoExplain : nil
        }
    }
}
