import SwiftUI
import CaminoCore
import CaminoDesign

/// Perfil de altitud ampliado (`Route.profile`, V1.1 §B-C): el del trayecto en curso o, si no
/// hay, el del último terminado. Sólo perfil REGISTRADO; tramos con hueco sin unir.
struct ProfileDetailView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        let display = model.display
        let samples = model.displayedProfile
        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(caption)
                    .typeStyle(.detail)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                ProfileBlock(
                    samples: samples,
                    display: display,
                    height: 120,
                    emptyText: model.activeSession == nil ? L10n.profileNotRecorded : L10n.profileEmpty
                )

                ascentDescent(display)

                SectionLabel(text: L10n.statDetailSource)
                    .padding(.top, Spacing.s)
                Text(L10n.profileNote)
                    .typeStyle(.detail)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(L10n.profileTitle)
    }

    private var caption: String {
        if let session = model.activeSession {
            return L10n.statsInProgress(model.stageName(id: session.stageId))
        }
        if let summary = model.latestSummary {
            return L10n.statsLastFinished(model.stageName(id: summary.stageId))
        }
        return L10n.statsNoStages
    }

    @ViewBuilder
    private func ascentDescent(_ display: UnitDisplay) -> some View {
        if let session = model.activeSession {
            if session.altitude != nil {
                elevationRows(ascent: session.ascentMeters, descent: session.descentMeters, display)
            }
        } else if let summary = model.latestSummary, !summary.profile.isEmpty {
            elevationRows(ascent: Double(summary.ascentMeters), descent: Double(summary.descentMeters), display)
        }
    }

    private func elevationRows(ascent: Double, descent: Double, _ display: UnitDisplay) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            CompactMetricRow(
                symbol: Icon.ascent,
                label: L10n.altitudeAscent,
                value: display.elevation(ascent),
                spokenValue: display.spokenElevation(ascent)
            )
            CompactMetricRow(
                symbol: Icon.descent,
                label: L10n.altitudeDescent,
                value: display.elevation(descent),
                spokenValue: display.spokenElevation(descent)
            )
        }
    }
}

#if DEBUG
// Datos de demostración (Debug: MockCaminoApi).
#Preview("Negro · demostración") {
    NavigationStack {
        ProfileDetailView()
    }
    .themed(.negro)
    .environmentObject(AppModel())
}

#Preview("Perla · demostración") {
    NavigationStack {
        ProfileDetailView()
    }
    .themed(.perla)
    .environmentObject(AppModel())
}
#endif
