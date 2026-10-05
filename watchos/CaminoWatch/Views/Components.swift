import SwiftUI
import CaminoCore

/// Marca DEMO (§10): visible siempre que el adaptador sea `MockCaminoApi`.
/// Texto, no sólo color.
struct DemoBadge: View {
    var body: some View {
        Text(L10n.demoBadge)
            .font(.caption2.weight(.bold))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .foregroundStyle(Color.black)
            .background(Capsule().fill(Color.orange))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.demoAccessibility)
    }
}

/// Fila "título / valor" con etiqueta de accesibilidad hablada.
struct MetricRow: View {
    let title: String
    let value: String
    let spoken: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(title)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.body.monospacedDigit())
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + ": " + spoken)
    }
}

/// Textos e iconos del estado de sincronización. El icono acompaña al texto;
/// el color nunca es la única señal.
enum SyncText {
    static func status(_ status: SyncStatus) -> String {
        switch status {
        case .synced:
            return L10n.syncSynced
        case .pending(let count):
            return L10n.syncPending(count)
        case .offline:
            return L10n.syncOffline
        case .blocked:
            return L10n.syncBlocked
        case .needsLink:
            return L10n.syncNeedsLink
        case .syncing:
            return L10n.syncSyncing
        }
    }

    static func symbol(_ status: SyncStatus) -> String {
        switch status {
        case .synced:
            return "checkmark.icloud"
        case .pending:
            return "clock.arrow.circlepath"
        case .offline:
            return "wifi.slash"
        case .blocked:
            return "lock.icloud"
        case .needsLink:
            return "link"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        }
    }
}

/// Fila de estado de sincronización (Inicio y Etapa); abre la pantalla de sync.
struct SyncStatusRow: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationLink(value: Route.sync) {
            Label(SyncText.status(model.syncStatus), systemImage: SyncText.symbol(model.syncStatus))
                .font(.footnote)
        }
        .accessibilityLabel(L10n.syncTitle + ": " + SyncText.status(model.syncStatus))
    }
}
