import SwiftUI
import CaminoCore

/// Resumen al finalizar (§10): km, pasos, tiempo y "Guardado · se sincronizará".
struct SummaryView: View {
    @EnvironmentObject private var model: AppModel
    let summary: SessionSummary

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                Label(L10n.summaryTitle, systemImage: "checkmark.seal.fill")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)

                Text(model.stageName(id: summary.stageId))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                MetricRow(
                    title: L10n.walked,
                    value: Formatters.distance(meters: summary.distanceMeters),
                    spoken: Spoken.distance(meters: summary.distanceMeters)
                )
                MetricRow(
                    title: L10n.steps,
                    value: Formatters.steps(summary.steps),
                    spoken: Spoken.steps(summary.steps)
                )
                MetricRow(
                    title: L10n.time,
                    value: Formatters.duration(seconds: summary.activeSeconds),
                    spoken: Spoken.duration(seconds: summary.activeSeconds)
                )

                Label(L10n.summarySaved, systemImage: "tray.and.arrow.down.fill")
                    .font(.footnote)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    model.finishedSummary = nil
                } label: {
                    Text(L10n.done)
                        .frame(maxWidth: .infinity, minHeight: 44)
                }
            }
        }
    }
}
