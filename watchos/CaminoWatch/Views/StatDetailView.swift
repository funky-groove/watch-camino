import SwiftUI
import CaminoCore
import CaminoDesign

/// Ficha de una métrica: valor de la etapa (en curso o última terminada), acumulado y
/// de dónde sale el dato. Breve a propósito.
struct StatDetailView: View {
    let metric: StatMetric

    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .top, spacing: Spacing.m) {
                        stageValue
                        cumulativeValue
                    }
                    VStack(alignment: .leading, spacing: Spacing.s) {
                        stageValue
                        cumulativeValue
                    }
                }

                SectionLabel(text: L10n.statDetailSource)
                    .padding(.top, Spacing.s)
                Text(sourceText)
                    .typeStyle(.detail)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                if metric == .distance {
                    TimelineView(.everyMinute) { context in
                        qualityLine(at: context.date)
                    }
                    if model.locationDenied {
                        StatusLine(symbol: Icon.locationOff, text: L10n.locationDenied, tone: .warning)
                    }
                }
                if metric == .steps && model.activeSession != nil && model.stepsUnavailable {
                    StatusLine(symbol: Icon.steps, text: L10n.stepsUnavailable, tone: .warning)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(title)
    }

    // MARK: - Valores

    private enum Reading {
        case distance(Double)
        case time(Int)
        case steps(Int)
        case empty(String)
    }

    private func metricView(_ label: String, _ reading: Reading) -> MetricView {
        switch reading {
        case .distance(let meters):
            return MetricView(
                label: label,
                value: Formatters.distance(meters: meters),
                spokenValue: Spoken.distance(meters: meters)
            )
        case .time(let seconds):
            return MetricView(
                label: label,
                value: Formatters.duration(seconds: seconds),
                spokenValue: Spoken.duration(seconds: seconds)
            )
        case .steps(let count):
            return MetricView(
                label: label,
                value: Formatters.steps(count),
                spokenValue: Spoken.steps(count)
            )
        case .empty(let text):
            return MetricView(label: label, value: nil, spokenValue: nil, emptyText: text)
        }
    }

    @ViewBuilder
    private var stageValue: some View {
        if let session = model.activeSession {
            let label = L10n.statsInProgress(model.stageName(id: session.stageId))
            switch metric {
            case .distance:
                if session.lastFix == nil && session.distanceMeters <= 0 {
                    metricView(label, .empty(L10n.myStageWaitingGps))
                } else {
                    metricView(label, .distance(session.distanceMeters))
                }
            case .time:
                TimelineView(.periodic(from: session.startedAt, by: 60)) { context in
                    metricView(label, .time(model.elapsedSeconds(at: context.date)))
                }
            case .steps:
                if model.stepsUnavailable {
                    metricView(label, .empty(L10n.statsNoSteps))
                } else {
                    metricView(label, .steps(session.steps))
                }
            }
        } else if let summary = model.latestSummary {
            let label = L10n.statsLastFinished(model.stageName(id: summary.stageId))
            switch metric {
            case .distance:
                metricView(label, .distance(Double(summary.distanceMeters)))
            case .time:
                metricView(label, .time(summary.activeSeconds))
            case .steps:
                metricView(label, .steps(summary.steps))
            }
        } else {
            metricView(L10n.statsThisStage, .empty(L10n.statsNoStages))
        }
    }

    @ViewBuilder
    private var cumulativeValue: some View {
        let totals = model.totals
        if totals.stages == 0 {
            metricView(L10n.statsCumulative, .empty(L10n.statsNoStages))
        } else {
            switch metric {
            case .distance:
                metricView(L10n.statsCumulative, .distance(Double(totals.distanceMeters)))
            case .time:
                metricView(L10n.statsCumulative, .time(totals.activeSeconds))
            case .steps:
                metricView(L10n.statsCumulative, .steps(totals.steps))
            }
        }
    }

    // MARK: - Textos

    private var title: String {
        switch metric {
        case .distance:
            return L10n.statsMetricDistance
        case .time:
            return L10n.statsMetricTime
        case .steps:
            return L10n.statsMetricSteps
        }
    }

    private var sourceText: String {
        switch metric {
        case .distance:
            return L10n.statDetailDistanceSource
        case .time:
            return L10n.statDetailTimeSource
        case .steps:
            return L10n.statDetailStepsSource
        }
    }

    /// Calidad de la ubicación actual (precisión o antigüedad), con símbolo y texto.
    private func qualityLine(at date: Date) -> some View {
        let text: String
        let symbol: String
        let tone: StatusLine.Tone
        switch model.locationQuality(at: date) {
        case .none:
            text = L10n.statDetailLocationNone
            symbol = Icon.locationOff
            tone = .warning
        case .good(let accuracy, _):
            text = L10n.statDetailLocationGood(Formatters.distance(meters: accuracy))
            symbol = Icon.location
            tone = .positive
        case .imprecise(let accuracy, _):
            text = L10n.statDetailLocationImprecise(Formatters.distance(meters: accuracy))
            symbol = Icon.location
            tone = .warning
        case .stale(_, let age):
            text = L10n.statDetailLocationStale(Formatters.duration(seconds: age))
            symbol = Icon.location
            tone = .warning
        }
        return StatusLine(symbol: symbol, text: text, tone: tone)
    }
}

#if DEBUG
// Datos de demostración (Debug: MockCaminoApi).
#Preview("Negro · demostración") {
    NavigationStack {
        StatDetailView(metric: .distance)
    }
    .themed(.negro)
    .environmentObject(AppModel())
}

#Preview("Perla · demostración") {
    NavigationStack {
        StatDetailView(metric: .time)
    }
    .themed(.perla)
    .environmentObject(AppModel())
}
#endif
