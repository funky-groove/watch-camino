import SwiftUI
import CaminoCore
import CaminoDesign

/// Pantalla Trayecto (principal), sin trayecto en curso o con él.
///
/// - Cabecera (barra nativa, fija al desplazar y respetando la hora): ajustes a la izquierda
///   y «SOS» a la derecha. El SOS se alcanza sin recorrer las estadísticas.
/// - Con trayecto en curso, orden de V1.1 §B:
///   A. estadísticas principales (estado «En marcha»/«Pausado», distancia destacada, tiempo
///      en movimiento y ritmo o velocidad), visibles sin desplazarse en 40 mm;
///   B. altitud actual, subida y bajada (fuente GPS; ausente o antigua se dice);
///   C. perfil registrado compacto (tocar → ampliado);
///   D. hasta 3 lugares útiles («en línea recta») y «Ver todos» → Lugares;
///   E. «Pausar»/«Reanudar» y, al final y separado, «Finalizar trayecto».
///   Con la pantalla atenuada (Always On) sólo se muestra A.
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
        .onAppear {
            // Cuenta como "pantalla principal mostrada" y, en la primera aparición del
            // arranque, decide si se ofrece el aviso «Accede desde tu esfera» (§I).
            model.homeAppeared(pathIsEmpty: path.isEmpty)
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
        let display = model.display
        // A. Orden visual = orden de lectura de VoiceOver.
        TripStateLine(isPaused: session.isPaused)

        NavigationLink(value: Route.statDetail(.distance)) {
            distanceMetric(session, display)
        }
        .buttonStyle(.plain)
        .accessibilityHint(L10n.myStageOpenDetailHint)

        // Filas compactas (no pulsables) para que A quepa sin desplazarse en 40 mm;
        // el detalle del tiempo está en Estadísticas.
        CompactMetricRow(
            label: L10n.tripMovingTimeShort,
            value: display.duration(interval: session.movingSeconds),
            spokenValue: Spoken.duration(interval: session.movingSeconds)
        )

        CompactMetricRow(
            label: display.paceOrSpeedLabel,
            value: display.paceOrSpeed(distanceMeters: session.distanceMeters, movingSeconds: session.movingSeconds),
            spokenValue: display.spokenPaceOrSpeed(
                distanceMeters: session.distanceMeters,
                movingSeconds: session.movingSeconds
            )
        )

        if !isLuminanceReduced {
            // Grupos: menos de 10 vistas por bloque del ViewBuilder.
            Group {
                if session.isPaused {
                    Text(L10n.tripPausedNote)
                        .typeStyle(.detail)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if model.isDemo {
                    DemoBadge()
                }
                staleLocationLine
                stageProgress(session, display)
                NavigationLink(value: Route.statDetail(.steps)) {
                    stepsMetric(session, display)
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.myStageOpenDetailHint)
                if let alert = model.lastAlert {
                    alertCard(alert, display)
                }
            }

            Group {
                // B. Altitud y desnivel.
                altitudeSection(session, display)
                // C. Perfil registrado.
                profileSection(session, display)
                // D. Lugares útiles.
                placesSection(display)
            }

            Group {
                statsRow
                syncRow
                warnings
                // E. Controles.
                controlsSection(session)
            }
        }
    }

    /// ¿Cuánto llevo recorrido? Sin ningún fix en la sesión: "esperando GPS", nunca "0 m".
    private func distanceMetric(_ session: StageSession, _ display: UnitDisplay) -> some View {
        // En pausa sin ningún tramo medido no se espera al GPS (no suma): "sin datos".
        let waiting = session.lastFix == nil && session.distanceMeters <= 0
        return MetricView(
            label: L10n.myStageWalked,
            value: waiting ? nil : display.distance(session.distanceMeters),
            spokenValue: waiting ? nil : display.spokenDistance(session.distanceMeters),
            size: .hero,
            emptyText: session.isPaused ? L10n.noData : L10n.myStageWaitingGps
        )
        .frame(minHeight: Target.minimumHeight)
        .contentShape(Rectangle())
    }

    /// Pasos del sensor de movimiento; sin acceso: "sin datos de pasos", no un cero ficticio.
    /// Los pasos no se pausan (el sensor no se puede pausar).
    private func stepsMetric(_ session: StageSession, _ display: UnitDisplay) -> some View {
        let unavailable = model.stepsUnavailable
        return CompactMetricRow(
            symbol: Icon.steps,
            label: L10n.statsMetricSteps,
            value: unavailable ? nil : display.steps(session.steps),
            spokenValue: unavailable ? nil : display.spokenSteps(session.steps),
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

    /// Nombre de la etapa, progreso recorrido/plan y "quedan X km" en texto
    /// (el color de la línea no es la única señal).
    private func stageProgress(_ session: StageSession, _ display: UnitDisplay) -> some View {
        let name = model.stageName(id: session.stageId)
        let plan = model.stage(id: session.stageId)?.distanceMeters ?? 0
        let remaining = model.remainingMeters
        let spokenRemaining = plan > 0 ? L10n.myStageRemaining(display.spokenDistance(remaining)) : ""
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            Text(name)
                .typeStyle(.detail)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if plan > 0 {
                ProgressLine(fraction: session.distanceMeters / Double(plan))
                Text(L10n.myStageRemaining(display.distance(remaining)))
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

    private func alertCard(_ alert: PoiAlert, _ display: UnitDisplay) -> some View {
        let detail = PoiText.category(alert.poi.category) + " · "
            + L10n.myStageAtAlert(display.distance(alert.distanceMeters))
        return VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionLabel(text: L10n.myStageLastAlert)
            NavigationLink(value: Route.poi(id: alert.poi.id)) {
                RowLabel(symbol: Icon.category(alert.poi.category), title: alert.poi.name, detail: detail)
            }
            .buttonStyle(RowButtonStyle())
            .accessibilityLabel(L10n.myStageLastAlert + ": " + PoiText.category(alert.poi.category)
                + ", " + Spoken.poiAlert(alert, display))
        }
    }

    // MARK: B. Altitud y desnivel

    private func altitudeSection(_ session: StageSession, _ display: UnitDisplay) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionLabel(text: L10n.altitudeSection)
                .padding(.top, Spacing.s)
            // "Antigua" depende del tiempo: se recalcula cada 30 s (sin animación).
            TimelineView(.periodic(from: Date(), by: 30)) { context in
                AltitudeBlock(session: session, display: display, now: context.date)
            }
        }
    }

    // MARK: C. Perfil

    @ViewBuilder
    private func profileSection(_ session: StageSession, _ display: UnitDisplay) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            SectionLabel(text: L10n.profileSection)
                .padding(.top, Spacing.s)
            if session.profile.count >= 2 {
                NavigationLink(value: Route.profile) {
                    ProfileBlock(samples: session.profile, display: display)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .combine)
                .accessibilityHint(L10n.profileHint)
            } else {
                ProfileBlock(samples: session.profile, display: display)
            }
        }
    }

    // MARK: D. Lugares útiles

    private func placesSection(_ display: UnitDisplay) -> some View {
        let places = model.usefulPlaces
        let approximate = model.locationQuality(at: Date()).isApproximate
        return VStack(alignment: .leading, spacing: Spacing.s) {
            SectionLabel(text: L10n.placesSection)
                .padding(.top, Spacing.s)
            if model.lastAnyFix == nil {
                StatusLine(symbol: Icon.locationOff, text: L10n.myStageNoLocation)
            } else if places.isEmpty {
                StatusLine(symbol: Icon.places, text: L10n.nearbyEmptyAllStage)
            } else {
                ForEach(places, id: \.poi.id) { item in
                    placeRow(item, approximate: approximate, display: display)
                }
            }
            NavigationLink(value: Route.nearby(waterOnly: false)) {
                RowLabel(symbol: Icon.places, title: L10n.placesSeeAll)
            }
            .buttonStyle(RowButtonStyle())
        }
    }

    private func placeRow(_ item: PoiAlert, approximate: Bool, display: UnitDisplay) -> some View {
        let category = PoiText.category(item.poi.category)
        let detail = category + " · " + PoiText.straightLine(item.distanceMeters, approximate: approximate, display)
        let spoken = item.poi.name + ", " + category + ", "
            + PoiText.spokenStraightLine(item.distanceMeters, approximate: approximate, display)
        return NavigationLink(value: Route.poi(id: item.poi.id)) {
            RowLabel(symbol: Icon.category(item.poi.category), title: item.poi.name, detail: detail)
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityLabel(spoken)
    }

    // MARK: E. Controles

    /// «Pausar»/«Reanudar» y, al final, separado por una línea y espacio, «Finalizar trayecto».
    /// Neutros (no rojos) y a todo el ancho: no se confunden con el «SOS» compacto y rojo.
    private func controlsSection(_ session: StageSession) -> some View {
        VStack(alignment: .leading, spacing: Spacing.m) {
            Button {
                if session.isPaused {
                    model.resumeTrip()
                } else {
                    model.pauseTrip()
                }
            } label: {
                HStack(spacing: Spacing.xs) {
                    IconView(name: session.isPaused ? Icon.resume : Icon.pause)
                    Text(session.isPaused ? L10n.tripResume : L10n.tripPause)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityHint(session.isPaused ? L10n.tripResumeHint : L10n.tripPauseHint)

            Hairline()
                .padding(.top, Spacing.s)
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
            placesRow
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
            let display = model.display
            Text(L10n.myStageLastFinished(
                model.stageName(id: last.stageId) + " · " + display.distance(last.distanceMeters)
            ))
            .typeStyle(.detail)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel(L10n.myStageLastFinished(
                model.stageName(id: last.stageId) + ", " + display.spokenDistance(last.distanceMeters)
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
        let display = model.display
        let title: String
        let detail: String
        let spoken: String
        if model.lastAnyFix == nil {
            title = L10n.myStageWater
            detail = L10n.myStageNoLocation
            spoken = title + ", " + detail
        } else if let water = model.nearestWater {
            let approximate = model.locationQuality(at: Date()).isApproximate
            title = L10n.myStageWaterAt(PoiText.distance(water.distanceMeters, approximate: approximate, display))
            detail = water.poi.name
            spoken = L10n.myStageWater + ", "
                + PoiText.spokenStraightLine(water.distanceMeters, approximate: approximate, display)
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

    /// Destino «Lugares» sin trayecto en curso (V1.1 §A).
    private var placesRow: some View {
        NavigationLink(value: Route.nearby(waterOnly: false)) {
            RowLabel(symbol: Icon.places, title: L10n.placesTitle)
        }
        .buttonStyle(RowButtonStyle())
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

/// Altitud actual (fuente GPS), subida y bajada (V1.1 §B-B, §E). Sin altitud válida:
/// "sin datos de altitud"; medida hace > 5 min: "altitud antigua · hace X".
struct AltitudeBlock: View {
    let session: StageSession
    let display: UnitDisplay
    let now: Date

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if let altitude = session.altitude {
                MetricView(
                    label: L10n.altitudeCurrent,
                    value: display.elevation(altitude),
                    spokenValue: display.spokenElevation(altitude)
                )
                if session.isAltitudeStale(at: now), let measuredAt = session.altitudeAt {
                    let age = max(0, Int(now.timeIntervalSince(measuredAt)))
                    StatusLine(
                        symbol: Icon.time,
                        text: L10n.altitudeStale(NearbyLocationLine.ageText(age)),
                        tone: .warning
                    )
                    .accessibilityLabel(L10n.altitudeStale(NearbyLocationLine.spokenAge(age)))
                }
                CompactMetricRow(
                    symbol: Icon.ascent,
                    label: L10n.altitudeAscent,
                    value: display.elevation(session.ascentMeters),
                    spokenValue: display.spokenElevation(session.ascentMeters)
                )
                CompactMetricRow(
                    symbol: Icon.descent,
                    label: L10n.altitudeDescent,
                    value: display.elevation(session.descentMeters),
                    spokenValue: display.spokenElevation(session.descentMeters)
                )
            } else {
                StatusLine(symbol: Icon.altitude, text: L10n.altitudeNone)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
