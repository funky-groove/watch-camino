import SwiftUI
import CaminoCore

/// Estadísticas (§10): hoy (sesión activa o última) y acumulado del Camino (suma del historial).
struct StatsView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            Section {
                todayRows
            } header: {
                Text(L10n.statsToday)
            }

            Section {
                let totals = model.totals
                MetricRow(
                    title: L10n.statsStages,
                    value: String(totals.stages),
                    spoken: String(totals.stages)
                )
                MetricRow(
                    title: L10n.statsDistance,
                    value: Formatters.distance(meters: totals.distanceMeters),
                    spoken: Spoken.distance(meters: totals.distanceMeters)
                )
                MetricRow(
                    title: L10n.steps,
                    value: Formatters.steps(totals.steps),
                    spoken: Spoken.steps(totals.steps)
                )
                MetricRow(
                    title: L10n.time,
                    value: Formatters.duration(seconds: totals.activeSeconds),
                    spoken: Spoken.duration(seconds: totals.activeSeconds)
                )
            } header: {
                Text(L10n.statsTotal)
            }
        }
        .navigationTitle(L10n.statsTitle)
    }

    @ViewBuilder
    private var todayRows: some View {
        if let session = model.activeSession {
            let seconds = model.elapsedSeconds(at: Date())
            Text(model.stageName(id: session.stageId))
                .font(.footnote)
            MetricRow(
                title: L10n.statsDistance,
                value: Formatters.distance(meters: session.distanceMeters),
                spoken: Spoken.distance(meters: session.distanceMeters)
            )
            MetricRow(
                title: L10n.steps,
                value: Formatters.steps(session.steps),
                spoken: Spoken.steps(session.steps)
            )
            MetricRow(
                title: L10n.time,
                value: Formatters.duration(seconds: seconds),
                spoken: Spoken.duration(seconds: seconds)
            )
        } else if let summary = model.latestSummary {
            Text(model.stageName(id: summary.stageId))
                .font(.footnote)
            MetricRow(
                title: L10n.statsDistance,
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
        } else {
            Text(L10n.statsTodayEmpty)
                .font(.footnote)
        }
    }
}
