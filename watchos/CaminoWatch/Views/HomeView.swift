import SwiftUI
import CaminoCore
import CaminoDesign

/// "Mi etapa": pantalla inicial, sin etapa en curso o con ella.
///
/// Con etapa en curso, lo primero que se ve (sin desplazarse en 40 mm, texto por defecto)
/// responde a tres preguntas: ¿cuánto llevo? (cifra héroe), ¿cuánto tiempo? y ¿cómo va
/// mi etapa? (nombre, línea de progreso y "quedan X km"). Lo demás queda debajo, al
/// alcance de la Digital Crown. Con la pantalla atenuada (Always On) sólo se muestran
/// esas tres respuestas.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var path: [Route]

    @Environment(\.palette) private var palette
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var confirmingFinish = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                if let session = model.activeSession {
                    activeContent(session)
                } else {
                    idleContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toolbar {
            // Posiciones fijas: no cambian con el estado de la etapa.
            ToolbarItem(placement: .topBarLeading) {
                Button {
                    path.append(.settings)
                } label: {
                    Label(L10n.myStageSettings, systemImage: Icon.settings)
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(L10n.myStageSettings)
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    path.append(.nearby(waterOnly: true))
                } label: {
                    Label(L10n.myStageWaterButton, systemImage: Icon.water)
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel(L10n.myStageWaterButton)
            }
        }
        .confirmationDialog(
            L10n.myStageFinishConfirmTitle,
            isPresented: $confirmingFinish,
            titleVisibility: .visible
        ) {
            Button(L10n.myStageFinishConfirmAction, role: .destructive) {
                model.finishStage()
            }
            Button(L10n.myStageFinishConfirmCancel, role: .cancel) {}
        } message: {
            Text(L10n.myStageFinishConfirmMessage)
        }
    }

    // MARK: - Con etapa en curso

    @ViewBuilder
    private func activeContent(_ session: StageSession) -> some View {
        // Orden visual = orden de lectura de VoiceOver: la cifra héroe primero.
        NavigationLink(value: Route.statDetail(.distance)) {
            distanceMetric(session)
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.myStageOpenDetailHint)

        NavigationLink(value: Route.statDetail(.time)) {
            timeMetric(session)
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.myStageOpenDetailHint)

        stageProgress(session)

        if !isLuminanceReduced {
            if model.isDemo {
                DemoBadge()
            }
            if let alert = model.lastAlert {
                alertCard(alert)
            }
            waterRow
            statsRow
            syncRow
            warnings
            Button {
                confirmingFinish = true
            } label: {
                Text(L10n.myStageFinish)
            }
            .buttonStyle(SecondaryButtonStyle(destructive: true))
        }
    }

    /// ¿Cuánto llevo recorrido? Sin ningún fix en la sesión: "esperando GPS", nunca "0 m".
    private func distanceMetric(_ session: StageSession) -> some View {
        let waiting = session.lastFix == nil && session.distanceMeters <= 0
        return MetricView(
            label: L10n.myStageWalked,
            value: waiting ? nil : Formatters.distance(meters: session.distanceMeters),
            spokenValue: waiting ? nil : Spoken.distance(meters: session.distanceMeters),
            size: .hero,
            emptyText: L10n.myStageWaitingGps
        )
        .frame(minHeight: Target.minimumHeight)
        .contentShape(Rectangle())
    }

    /// ¿Cuánto tiempo llevo? El formato es en minutos: basta refrescar cada minuto.
    private func timeMetric(_ session: StageSession) -> some View {
        TimelineView(.periodic(from: session.startedAt, by: 60)) { context in
            let seconds = model.elapsedSeconds(at: context.date)
            MetricView(
                label: L10n.myStageTime,
                value: Formatters.duration(seconds: seconds),
                spokenValue: Spoken.duration(seconds: seconds)
            )
            .frame(minHeight: Target.minimumHeight)
            .contentShape(Rectangle())
        }
    }

    /// ¿Cómo va mi etapa? Nombre, progreso recorrido/plan y "quedan X km" en texto
    /// (el color de la línea no es la única señal).
    private func stageProgress(_ session: StageSession) -> some View {
        let name = model.stageName(id: session.stageId)
        let plan = model.stage(id: session.stageId)?.distanceMeters ?? 0
        let remaining = model.remainingMeters
        let spokenRemaining = plan > 0 ? L10n.myStageRemaining(Spoken.distance(meters: remaining)) : ""
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(name)
                .typeStyle(.detail)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if plan > 0 {
                ProgressLine(fraction: session.distanceMeters / Double(plan))
                Text(L10n.myStageRemaining(Formatters.distance(meters: remaining)))
                    .typeStyle(.detail)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.myStageStage + ": " + name)
        .accessibilityValue(spokenRemaining)
    }

    private func alertCard(_ alert: PoiAlert) -> some View {
        let detail = PoiText.category(alert.poi.category) + " · "
            + L10n.myStageAtAlert(Formatters.distance(meters: alert.distanceMeters))
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionLabel(text: L10n.myStageLastAlert)
            NavigationLink(value: Route.poi(id: alert.poi.id)) {
                RowLabel(symbol: Icon.category(alert.poi.category), title: alert.poi.name, detail: detail)
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityLabel(L10n.myStageLastAlert + ": " + PoiText.category(alert.poi.category)
                + ", " + Spoken.poiAlert(alert))
        }
    }

    // MARK: - Sin etapa en curso

    @ViewBuilder
    private var idleContent: some View {
        SectionLabel(text: L10n.myStageIdle)
        if let last = model.latestSummary {
            Text(L10n.myStageLastFinished(
                model.stageName(id: last.stageId) + " · " + Formatters.distance(meters: last.distanceMeters)
            ))
            .typeStyle(.detail)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(L10n.myStageLastFinished(
                model.stageName(id: last.stageId) + ", " + Spoken.distance(meters: last.distanceMeters)
            ))
        }
        if !isLuminanceReduced {
            if model.isDemo {
                DemoBadge()
            }
            Button {
                // Permisos pedidos en contexto (§11), antes de elegir la etapa.
                model.requestPermissions()
                path.append(.pickStage)
            } label: {
                Text(L10n.myStageStart)
            }
            .buttonStyle(PrimaryButtonStyle())
            .accessibilityHint(L10n.myStageStartHint)
            waterRow
            statsRow
            syncRow
            warnings
        }
    }

    // MARK: - Filas comunes

    /// "agua · 340 m" (aproximada si la ubicación lo es); sin ubicación, "agua cercana · sin ubicación".
    private var waterRow: some View {
        let title: String
        let detail: String
        let spoken: String
        if model.lastAnyFix == nil {
            title = L10n.myStageWater
            detail = L10n.myStageNoLocation
            spoken = title + ", " + detail
        } else if let water = model.nearestWater {
            let approximate = model.locationQuality(at: Date()).isApproximate
            title = L10n.myStageWaterAt(PoiText.distance(water.distanceMeters, approximate: approximate))
            detail = water.poi.name
            spoken = L10n.myStageWater + ", "
                + PoiText.spokenDistance(water.distanceMeters, approximate: approximate)
                + ", " + water.poi.name
        } else {
            title = L10n.myStageWater
            detail = L10n.myStageNoWater
            spoken = title + ", " + detail
        }
        return NavigationLink(value: Route.nearby(waterOnly: true)) {
            RowLabel(symbol: Icon.water, title: title, detail: detail)
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(spoken)
    }

    private var statsRow: some View {
        NavigationLink(value: Route.stats) {
            RowLabel(symbol: Icon.stats, title: L10n.myStageStats)
        }
        .buttonStyle(RowButtonStyle())
    }

    /// Estado de sincronización, discreto: línea de estado pulsable.
    private var syncRow: some View {
        let status = model.syncStatus
        return NavigationLink(value: Route.sync) {
            StatusLine(
                symbol: SyncText.symbol(status),
                text: SyncText.status(status),
                tone: SyncText.tone(status)
            )
            .frame(minHeight: Target.minimumHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.myStageSyncLabel + ": " + SyncText.status(status))
        .accessibilityHint(L10n.myStageSyncHint)
    }

    /// Avisos de permiso denegado, pasos no disponibles y error recuperable.
    @ViewBuilder
    private var warnings: some View {
        if model.locationDenied {
            StatusLine(symbol: Icon.locationOff, text: L10n.locationDenied, tone: .warning)
        }
        if model.activeSession != nil && model.stepsUnavailable {
            StatusLine(symbol: Icon.steps, text: L10n.stepsUnavailable, tone: .warning)
        }
        if let message = model.errorMessage {
            StatusLine(symbol: Icon.warning, text: message, tone: .critical)
        }
    }
}

#if DEBUG
// Datos de demostración (Debug: MockCaminoApi, marca DEMO visible).
#Preview("Negro · demostración") {
    NavigationStack {
        HomeView(path: .constant([]))
    }
    .themed(.negro)
    .environmentObject(AppModel())
}

#Preview("Perla · demostración") {
    NavigationStack {
        HomeView(path: .constant([]))
    }
    .themed(.perla)
    .environmentObject(AppModel())
}
#endif
