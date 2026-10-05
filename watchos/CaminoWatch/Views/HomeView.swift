import SwiftUI
import CaminoCore
import CaminoDesign

/// Pantalla principal, sin trayecto en curso o con él.
///
/// - Cabecera (barra nativa, fija al desplazar y respetando la hora): ajustes a la izquierda
///   y «SOS» a la derecha. El SOS se alcanza sin recorrer las estadísticas.
/// - Con trayecto en curso, lo primero que se ve responde a: ¿cuánto llevo? (cifra héroe),
///   ¿cuánto tiempo? y ¿cómo va el trayecto? Lo demás queda debajo, con la Digital Crown,
///   y «Finalizar trayecto» va al final, separado por una línea. Con la pantalla atenuada
///   (Always On) sólo se muestran esas tres respuestas.
/// - Abrir el SOS apila una pantalla sobre ésta: al volver, esta vista sigue viva (misma
///   identidad en la raíz del `NavigationStack`) con su posición de desplazamiento.
struct HomeView: View {
    @EnvironmentObject private var model: AppModel
    @Binding var path: [Route]

    @Environment(\.palette) private var palette
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @State private var confirmingFinish = false
    /// Primer toque en «Iniciar trayecto» ya atendido; se rearma al volver a esta pantalla.
    @State private var startTapped = false

    /// Ancla del final del contenido (capturas con `-demo.scrollToEnd`).
    private static let finishAnchor = "home.finish"

    var body: some View {
        ScrollViewReader { proxy in
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
            .onAppear {
                #if DEBUG
                scrollToEndForScreenshots(proxy)
                #endif
            }
        }
        .toolbar {
            // Posiciones fijas: no cambian con el estado del trayecto.
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
                    openSOS()
                } label: {
                    Text(L10n.sosButton)
                }
                .buttonStyle(SOSButtonStyle())
                .accessibilityLabel(L10n.sosButton)
                .accessibilityHint(L10n.sosButtonHint)
            }
        }
        .onChange(of: path.isEmpty) { _, isEmpty in
            // De vuelta en esta pantalla (p. ej. al salir de elegir etapa sin iniciar).
            if isEmpty {
                startTapped = false
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

    // MARK: - Acciones

    /// Un toque abre la pantalla SOS. Un segundo toque rápido no apila otra.
    private func openSOS() {
        guard path.last != .sos else {
            return
        }
        path.append(.sos)
    }

    /// Iniciar trayecto → elegir etapa. Se ignora un segundo toque (doble toque).
    private func startTrip() {
        guard !startTapped, !model.isStarting, model.activeSession == nil, path.isEmpty else {
            return
        }
        startTapped = true
        // Permisos pedidos en contexto (§11), antes de elegir la etapa.
        model.requestPermissions()
        path.append(.pickStage)
    }

    #if DEBUG
    /// Sólo capturas: con `-demo.scrollToEnd YES` se desplaza hasta «Finalizar trayecto».
    private func scrollToEndForScreenshots(_ proxy: ScrollViewProxy) {
        guard DemoScenario.scrollToEnd else {
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            proxy.scrollTo(HomeView.finishAnchor, anchor: .bottom)
        }
    }
    #endif

    // MARK: - Con trayecto en curso

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
            NavigationLink(value: Route.statDetail(.steps)) {
                stepsMetric(session)
            }
            .buttonStyle(.plain)
            .accessibilityHint(L10n.myStageOpenDetailHint)

            staleLocationLine

            // Agua: a una pulsación, cerca de arriba.
            waterRow
            // §10.3: debajo de las cifras principales, para no desplazarlas.
            if let next = model.nextPoi {
                nextPoiRow(next)
            }
            if let alert = model.lastAlert {
                alertCard(alert)
            }
            statsRow
            syncRow
            warnings
            finishSection
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

    /// Pasos del sensor de movimiento; sin acceso: "sin datos de pasos", no un cero ficticio.
    private func stepsMetric(_ session: StageSession) -> some View {
        let unavailable = model.stepsUnavailable
        return MetricView(
            label: L10n.statsMetricSteps,
            value: unavailable ? nil : Formatters.steps(session.steps),
            spokenValue: unavailable ? nil : Spoken.steps(session.steps),
            emptyText: L10n.statsNoSteps
        )
        .frame(minHeight: Target.minimumHeight)
        .contentShape(Rectangle())
    }

    /// Si la última posición es antigua (> 5 min), se dice: la distancia no se está actualizando.
    private var staleLocationLine: some View {
        TimelineView(.periodic(from: Date(), by: 30)) { context in
            let quality = LocationQuality.of(model.latestKnownFix, now: context.date)
            if HomeView.isStale(quality) {
                NearbyLocationStatus(line: NearbyLocationLine.of(quality))
            }
        }
    }

    private static func isStale(_ quality: LocationQuality) -> Bool {
        switch quality {
        case .stale:
            return true
        case .none, .good, .imprecise:
            return false
        }
    }

    /// ¿Cómo va el trayecto? Nombre de la etapa, progreso recorrido/plan y "quedan X km" en
    /// texto (el color de la línea no es la única señal).
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
        .accessibilityLabel(L10n.myStageActive + ": " + name)
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

    /// Al final del contenido, separado por una línea y espacio. Neutro (no rojo) y a todo
    /// el ancho: no se confunde con el «SOS» compacto y rojo de la cabecera.
    private var finishSection: some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Hairline()
            Button {
                confirmingFinish = true
            } label: {
                HStack(spacing: Spacing.xs) {
                    IconView(name: Icon.finish)
                    Text(L10n.myStageFinish)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityHint(L10n.myStageFinishHint)
        }
        .padding(.top, Spacing.l)
        .id(HomeView.finishAnchor)
    }

    // MARK: - Sin trayecto en curso

    @ViewBuilder
    private var idleContent: some View {
        if isLuminanceReduced {
            SectionLabel(text: L10n.myStageIdle)
            lastFinishedLine
        } else {
            Button {
                startTrip()
            } label: {
                Text(L10n.myStageStart)
            }
            .buttonStyle(PrimaryButtonStyle())
            .disabled(startTapped || model.isStarting)
            .accessibilityHint(L10n.myStageStartHint)
            if model.isDemo {
                DemoBadge()
            }
            waterRow
            lastFinishedLine
            permissionLines
            statsRow
            syncRow
            warnings
        }
    }

    @ViewBuilder
    private var lastFinishedLine: some View {
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
    }

    /// Estado real de los permisos y, en una línea, para qué sirve cada uno.
    @ViewBuilder
    private var permissionLines: some View {
        switch model.locationPermission {
        case .granted:
            StatusLine(symbol: Icon.location, text: L10n.permLocationGranted, tone: .positive)
        case .notDetermined:
            StatusLine(symbol: Icon.location, text: L10n.permLocationAsk)
        case .denied:
            StatusLine(symbol: Icon.locationOff, text: L10n.locationDenied, tone: .warning)
        }
        switch model.notificationPermission {
        case .granted:
            StatusLine(symbol: Icon.alert, text: L10n.permNotificationsGranted, tone: .positive)
        case .notDetermined:
            StatusLine(symbol: Icon.alert, text: L10n.permNotificationsAsk)
        case .denied:
            StatusLine(symbol: Icon.alert, text: L10n.permNotificationsDenied, tone: .warning)
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

    /// "próximo lugar · 1,2 km" + nombre: el POI no avisado más cercano (sólo con fix).
    private func nextPoiRow(_ next: PoiAlert) -> some View {
        let distance = PoiText.distance(next.distanceMeters, approximate: false)
        let spoken = L10n.myStageNextPoiLabel + ", " + next.poi.name + ", "
            + PoiText.spokenDistance(next.distanceMeters, approximate: false)
        return NavigationLink(value: Route.poi(id: next.poi.id)) {
            RowLabel(
                symbol: Icon.category(next.poi.category),
                title: L10n.myStageNextPoi(distance),
                detail: next.poi.name
            )
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
        // Sin servidor (Release) se dice qué pasa de verdad: guardado en el reloj, sin enviar.
        let text = status == .blocked ? L10n.syncBlockedRow : SyncText.status(status, isDemo: model.isDemo)
        return NavigationLink(value: Route.sync) {
            StatusLine(
                symbol: SyncText.symbol(status),
                text: text,
                tone: SyncText.tone(status)
            )
            .frame(minHeight: Target.minimumHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.myStageSyncLabel + ": " + text)
        .accessibilityHint(L10n.myStageSyncHint)
    }

    /// Avisos de permiso denegado (con trayecto: sin trayecto lo dicen `permissionLines`),
    /// pasos no disponibles y error recuperable.
    @ViewBuilder
    private var warnings: some View {
        if model.activeSession != nil && model.locationDenied {
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
