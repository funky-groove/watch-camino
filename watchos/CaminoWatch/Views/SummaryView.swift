import SwiftUI
import CaminoCore
import CaminoDesign

/// Resumen al finalizar (hoja, V1.1): distancia, duración total y tiempo en movimiento
/// (diferenciados), ritmo o velocidad media (= distancia ÷ tiempo en movimiento), pasos,
/// subida y bajada, perfil registrado y, con honestidad, dos estados distintos:
/// - guardado: «Guardado en el reloj» sólo si la escritura terminó bien;
/// - envío: «Pendiente de enviar», «Envío no disponible (sin servidor)» o «Sincronizado»
///   (este último sólo con un servidor real; con el de demostración se dice "simulado").
struct SummaryView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    let summary: SessionSummary

    var body: some View {
        let display = model.display
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                // Grupos: menos de 10 vistas por bloque del ViewBuilder.
                Group {
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
                        value: display.distance(summary.distanceMeters),
                        spokenValue: display.spokenDistance(summary.distanceMeters),
                        size: .hero
                    )

                    CompactMetricRow(
                        symbol: Icon.time,
                        label: L10n.tripTotalTime,
                        value: display.duration(seconds: summary.activeSeconds),
                        spokenValue: Spoken.duration(seconds: summary.activeSeconds)
                    )
                    CompactMetricRow(
                        symbol: Icon.walk,
                        label: L10n.tripMovingTime,
                        value: display.duration(seconds: summary.movingSeconds),
                        spokenValue: Spoken.duration(seconds: summary.movingSeconds)
                    )
                    CompactMetricRow(
                        symbol: Icon.pace,
                        label: display.averagePaceOrSpeedLabel,
                        value: display.paceOrSpeed(
                            distanceMeters: Double(summary.distanceMeters),
                            movingSeconds: Double(summary.movingSeconds)
                        ),
                        spokenValue: display.spokenPaceOrSpeed(
                            distanceMeters: Double(summary.distanceMeters),
                            movingSeconds: Double(summary.movingSeconds)
                        )
                    )
                    Text(L10n.summaryAverageNote)
                        .typeStyle(.detail)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    stepsMetric(display)
                }

                Group {
                    SectionLabel(text: L10n.altitudeSection)
                        .padding(.top, Spacing.s)
                    if summary.profile.isEmpty {
                        // Sin ninguna altitud válida: subida/bajada serían un cero ficticio.
                        StatusLine(symbol: Icon.altitude, text: L10n.altitudeNone)
                    } else {
                        CompactMetricRow(
                            symbol: Icon.ascent,
                            label: L10n.altitudeAscent,
                            value: display.elevation(summary.ascentMeters),
                            spokenValue: display.spokenElevation(summary.ascentMeters)
                        )
                        CompactMetricRow(
                            symbol: Icon.descent,
                            label: L10n.altitudeDescent,
                            value: display.elevation(summary.descentMeters),
                            spokenValue: display.spokenElevation(summary.descentMeters)
                        )
                    }
                    ProfileBlock(samples: summary.profile, display: display, emptyText: L10n.profileNotRecorded)
                }

                Hairline()
                    .padding(.top, Spacing.xs)

                StatusLine(symbol: saveSymbol, text: saveText, tone: saveTone)
                StatusLine(symbol: syncSymbol, text: syncText, tone: syncTone)

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

    /// Sin acceso al sensor de movimiento y 0 pasos: "sin datos de pasos", no un cero ficticio.
    private func stepsMetric(_ display: UnitDisplay) -> some View {
        let noData = model.stepsUnavailable && summary.steps == 0
        return CompactMetricRow(
            symbol: Icon.steps,
            label: L10n.statsMetricSteps,
            value: noData ? nil : display.steps(summary.steps),
            spokenValue: noData ? nil : display.spokenSteps(summary.steps),
            emptyText: L10n.statsNoSteps
        )
    }

    // MARK: - Guardado (estado real de la escritura)

    private var saveText: String {
        switch model.finishedSaveState {
        case .saved:
            return L10n.summarySaved
        case .failed:
            return L10n.summarySaveFailed
        case .memoryOnly:
            return model.isDemo ? L10n.summaryMemoryOnlyDemo : L10n.summaryMemoryOnly
        }
    }

    private var saveSymbol: String {
        return model.finishedSaveState == .saved ? Icon.check : Icon.warning
    }

    private var saveTone: StatusLine.Tone {
        switch model.finishedSaveState {
        case .saved:
            return .positive
        case .failed:
            return .critical
        case .memoryOnly:
            return .warning
        }
    }

    // MARK: - Envío (sincronización)

    private var syncText: String {
        if model.isDemo {
            // Servidor de demostración: nunca "sincronizado" a secas.
            return L10n.summarySyncDemo
        }
        switch model.syncStatus {
        case .synced:
            return L10n.summarySyncSynced
        case .pending, .syncing, .offline:
            return L10n.summarySyncPending
        case .blocked:
            return L10n.summarySyncBlocked
        case .needsLink:
            return L10n.summarySyncNeedsLink
        }
    }

    private var syncSymbol: String {
        return SyncText.symbol(model.syncStatus)
    }

    private var syncTone: StatusLine.Tone {
        if model.isDemo {
            return .neutral
        }
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
    activeSeconds: 18_000,
    movingSeconds: 16_200,
    pausedSeconds: 1_500,
    ascentMeters: 412,
    descentMeters: 380,
    profile: (0..<40).map { index in
        ProfileSample(
            d: Double(index) * 560,
            alt: 450 + 60 * sin(Double(index) / 6),
            gapBefore: index == 25
        )
    }
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
