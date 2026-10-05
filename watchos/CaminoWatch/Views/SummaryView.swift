import SwiftUI
import CaminoCore
import CaminoDesign

/// Resumen al finalizar (hoja): distancia, tiempo, pasos y dónde está guardado,
/// dicho con honestidad según el estado real de la sincronización.
struct SummaryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let summary: SessionSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(L10n.finishedTitle)
                    .typeStyle(.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text(model.stageName(id: summary.stageId))
                    .typeStyle(.detail)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                MetricView(
                    label: L10n.statsMetricDistance,
                    value: Formatters.distance(meters: summary.distanceMeters),
                    spokenValue: Spoken.distance(meters: summary.distanceMeters),
                    size: .hero
                )

                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        timeMetric
                        stepsMetric
                    }
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        timeMetric
                        stepsMetric
                    }
                }

                Hairline()

                StatusLine(symbol: savedSymbol, text: savedText, tone: savedTone)

                if model.isDemo {
                    DemoBadge()
                }

                Button {
                    model.finishedSummary = nil
                } label: {
                    Text(L10n.finishedDone)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Spacing.xs)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground(palette)
    }

    private var timeMetric: some View {
        MetricView(
            label: L10n.statsMetricTime,
            value: Formatters.duration(seconds: summary.activeSeconds),
            spokenValue: Spoken.duration(seconds: summary.activeSeconds)
        )
    }

    /// Sin acceso al sensor de movimiento y 0 pasos: "sin datos de pasos", no un cero ficticio.
    private var stepsMetric: some View {
        let noData = model.stepsUnavailable && summary.steps == 0
        return MetricView(
            label: L10n.statsMetricSteps,
            value: noData ? nil : Formatters.steps(summary.steps),
            spokenValue: noData ? nil : Spoken.steps(summary.steps),
            emptyText: L10n.statsNoSteps
        )
    }

    // MARK: - Guardado y sincronización

    private var savedText: String {
        switch model.syncStatus {
        case .synced:
            return L10n.finishedSynced
        case .pending, .syncing:
            return L10n.finishedWillSync
        case .offline:
            return L10n.finishedOffline
        case .blocked:
            return L10n.finishedBlocked
        case .needsLink:
            return L10n.finishedNeedsLink
        }
    }

    private var savedSymbol: String {
        switch model.syncStatus {
        case .synced:
            return Icon.check
        default:
            return SyncText.symbol(model.syncStatus)
        }
    }

    private var savedTone: StatusLine.Tone {
        switch model.syncStatus {
        case .synced:
            return .positive
        default:
            // Guardado en el reloj: no es un error, sólo falta enviarlo.
            return .neutral
        }
    }
}

#if DEBUG
/// Resumen de ejemplo, claramente de demostración.
private let previewSummary = SessionSummary(
    sessionId: "demo-preview",
    stageId: "demo-stage",
    startedAt: Date(timeIntervalSince1970: 1_790_000_000),
    finishedAt: Date(timeIntervalSince1970: 1_790_018_000),
    steps: 28_450,
    distanceMeters: 22_400,
    activeSeconds: 18_000
)

#Preview("Negro · demostración") {
    SummaryView(summary: previewSummary)
        .themed(.negro)
        .environmentObject(AppModel())
}

#Preview("Perla · demostración") {
    SummaryView(summary: previewSummary)
        .themed(.perla)
        .environmentObject(AppModel())
}
#endif
