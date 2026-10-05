import SwiftUI
import CaminoCore

/// Etapa activa (§10), legible de un vistazo:
/// grande los km restantes; debajo recorrido, pasos y tiempo; "Próximo POI";
/// "Finalizar" con confirmación explícita.
struct ActiveStageView: View {
    @EnvironmentObject private var model: AppModel
    let session: StageSession
    @State private var confirmingFinish = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 8) {
                if model.isDemo {
                    DemoBadge()
                }

                Text(model.stageName(id: session.stageId))
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                remainingBlock

                if let alert = model.lastAlert {
                    Label(Formatters.poiAlertText(alert), systemImage: "bell.fill")
                        .font(.footnote)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityLabel(L10n.lastAlert + ": " + Spoken.poiAlert(alert))
                }

                metricsBlock

                nextPoiBlock

                permissionWarnings

                actionsBlock
            }
        }
        .navigationTitle(L10n.activeTitle)
        .confirmationDialog(
            L10n.finishConfirmTitle,
            isPresented: $confirmingFinish,
            titleVisibility: .visible
        ) {
            Button(L10n.finishConfirmAction, role: .destructive) {
                model.finishStage()
            }
            Button(L10n.finishConfirmCancel, role: .cancel) {}
        } message: {
            Text(L10n.finishConfirmMessage)
        }
    }

    private var metricsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            MetricRow(
                title: L10n.walked,
                value: Formatters.distance(meters: session.distanceMeters),
                spoken: Spoken.distance(meters: session.distanceMeters)
            )
            MetricRow(
                title: L10n.steps,
                value: Formatters.steps(session.steps),
                spoken: Spoken.steps(session.steps)
            )
            // El tiempo sólo se refresca mientras esta pantalla está visible.
            TimelineView(.periodic(from: session.startedAt, by: 10)) { context in
                MetricRow(
                    title: L10n.time,
                    value: Formatters.duration(seconds: model.elapsedSeconds(at: context.date)),
                    spoken: Spoken.duration(seconds: model.elapsedSeconds(at: context.date))
                )
            }
        }
    }

    @ViewBuilder
    private var permissionWarnings: some View {
        if model.locationDenied {
            Label(L10n.locationDenied, systemImage: "location.slash")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
        if model.stepsUnavailable {
            Label(L10n.stepsUnavailable, systemImage: "figure.walk.motion")
                .font(.footnote)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actionsBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            NavigationLink(value: Route.stats) {
                Label(L10n.statsTitle, systemImage: "chart.bar")
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            }

            SyncStatusRow()

            Button(role: .destructive) {
                confirmingFinish = true
            } label: {
                Label(L10n.finish, systemImage: "flag.checkered")
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
    }

    private var remainingBlock: some View {
        let remaining = model.remainingMeters
        return VStack(alignment: .leading, spacing: 0) {
            Text(Formatters.distance(meters: remaining))
                .font(.system(.largeTitle, design: .rounded).weight(.bold))
                .lineLimit(1)
                .minimumScaleFactor(0.5)
            Text(L10n.remaining)
                .font(.headline)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Spoken.remaining(meters: remaining))
        .accessibilityAddTraits(.isHeader)
    }

    private var nextPoiBlock: some View {
        let text: String
        let spoken: String
        if let next = model.nextPoi {
            text = Formatters.poiAlertText(next)
            spoken = Spoken.poiAlert(next)
        } else if model.hasPendingPois {
            text = L10n.nextPoiSearching
            spoken = L10n.nextPoiSearching
        } else {
            text = L10n.nextPoiNone
            spoken = L10n.nextPoiNone
        }
        return VStack(alignment: .leading, spacing: 0) {
            Text(L10n.nextPoi)
                .font(.footnote)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.body)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.nextPoi + ": " + spoken)
    }
}
