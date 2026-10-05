import SwiftUI
import CaminoCore
import CaminoDesign

/// Estadísticas: "esta etapa" (la que está en curso o, si no hay, la última terminada,
/// diciendo cuál) y "acumulado" (suma de las etapas terminadas).
///
/// Sólo métricas con fuente real: distancia (GPS), duración total y tiempo en movimiento
/// (reloj + GPS), pasos (sensor de movimiento) y subida (altitud GPS). Ni calorías ni
/// estimaciones. Unidades e idioma según las preferencias (V1.1 §G).
struct StatsView: View {
    @EnvironmentObject private var model: AppModel
    /// Cifras con las unidades y el idioma del usuario (V1.1 §G).
    private var display: UnitDisplay { model.display }
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionLabel(text: L10n.statsThisStage)
                thisStage

                SectionLabel(text: L10n.statsCumulative)
                    .padding(.top, Spacing.s)
                cumulative
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(L10n.statsListTitle)
    }

    // MARK: - Esta etapa

    @ViewBuilder
    private var thisStage: some View {
        if let session = model.activeSession {
            caption(L10n.statsInProgress(model.stageName(id: session.stageId)))
            StatLinkRow(metric: .distance) {
                MetricView(
                    label: L10n.statsMetricDistance,
                    value: display.distance(session.distanceMeters),
                    spokenValue: display.spokenDistance(session.distanceMeters)
                )
            }
            StatLinkRow(metric: .time) {
                TimelineView(.periodic(from: session.startedAt, by: 60)) { context in
                    let seconds = model.elapsedSeconds(at: context.date)
                    MetricView(
                        label: L10n.statsMetricTime,
                        value: Formatters.duration(seconds: seconds),
                        spokenValue: Spoken.duration(seconds: seconds)
                    )
                }
            }
            // F-06: acotado por la duración, como en el resumen.
            let moving = model.liveMovingSeconds(session)
            MetricView(
                label: L10n.tripMovingTime,
                value: display.duration(interval: moving),
                spokenValue: Spoken.duration(interval: moving)
            )
            StatLinkRow(metric: .steps) {
                MetricView(
                    label: L10n.statsMetricSteps,
                    value: model.stepsUnavailable ? nil : display.steps(session.steps),
                    spokenValue: model.stepsUnavailable ? nil : display.spokenSteps(session.steps),
                    emptyText: L10n.statsNoSteps
                )
            }
        } else if let summary = model.latestSummary {
            caption(L10n.statsLastFinished(model.stageName(id: summary.stageId)))
            StatLinkRow(metric: .distance) {
                MetricView(
                    label: L10n.statsMetricDistance,
                    value: display.distance(summary.distanceMeters),
                    spokenValue: display.spokenDistance(summary.distanceMeters)
                )
            }
            StatLinkRow(metric: .time) {
                MetricView(
                    label: L10n.statsMetricTime,
                    value: Formatters.duration(seconds: summary.activeSeconds),
                    spokenValue: Spoken.duration(seconds: summary.activeSeconds)
                )
            }
            MetricView(
                label: L10n.tripMovingTime,
                value: display.duration(seconds: summary.movingSeconds),
                spokenValue: Spoken.duration(seconds: summary.movingSeconds)
            )
            StatLinkRow(metric: .steps) {
                MetricView(
                    label: L10n.statsMetricSteps,
                    value: display.steps(summary.steps),
                    spokenValue: display.spokenSteps(summary.steps)
                )
            }
        } else {
            caption(L10n.statsNoStages)
        }
    }

    // MARK: - Acumulado

    @ViewBuilder
    private var cumulative: some View {
        let totals = model.totals
        if totals.stages == 0 {
            caption(L10n.statsNoStages)
        } else {
            MetricView(
                label: L10n.statsFinishedStages,
                value: String(totals.stages),
                spokenValue: String(totals.stages)
            )
            StatLinkRow(metric: .distance) {
                MetricView(
                    label: L10n.statsMetricDistance,
                    value: display.distance(totals.distanceMeters),
                    spokenValue: display.spokenDistance(totals.distanceMeters)
                )
            }
            StatLinkRow(metric: .time) {
                MetricView(
                    label: L10n.statsMetricTime,
                    value: Formatters.duration(seconds: totals.activeSeconds),
                    spokenValue: Spoken.duration(seconds: totals.activeSeconds)
                )
            }
            StatLinkRow(metric: .steps) {
                MetricView(
                    label: L10n.statsMetricSteps,
                    value: display.steps(totals.steps),
                    spokenValue: display.spokenSteps(totals.steps)
                )
            }
            MetricView(
                label: L10n.altitudeAscent,
                value: display.elevation(totals.ascentMeters),
                spokenValue: display.spokenElevation(totals.ascentMeters)
            )
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .typeStyle(.detail)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Fila de métrica pulsable que abre su ficha (`Route.statDetail`).
struct StatLinkRow<Content: View>: View {
    let metric: StatMetric
    private let content: Content

    @Environment(\.palette) private var palette

    init(metric: StatMetric, @ViewBuilder content: () -> Content) {
        self.metric = metric
        self.content = content()
    }

    var body: some View {
        NavigationLink(value: Route.statDetail(metric)) {
            HStack(alignment: .center, spacing: Spacing.s) {
                content
                Image(systemName: Icon.chevron)
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(palette.textSecondary)
                    .accessibilityHidden(true)
            }
            .padding(.vertical, Spacing.s)
            .frame(maxWidth: .infinity, minHeight: Target.minimumHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityHint(L10n.myStageOpenDetailHint)
    }
}

#if DEBUG
// Datos de demostración (Debug: MockCaminoApi, marca DEMO en otras pantallas).
#Preview("Negro · demostración") {
    NavigationStack {
        StatsView()
    }
    .themed(.negro)
    .environmentObject(AppModel())
}

#Preview("Perla · demostración") {
    NavigationStack {
        StatsView()
    }
    .themed(.perla)
    .environmentObject(AppModel())
}
#endif
