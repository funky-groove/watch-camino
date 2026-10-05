import SwiftUI
import CaminoCore

/// Elegir etapa (§10): la primera es la sugerida. Toque → confirmar → Active.
struct StagePickerView: View {
    @EnvironmentObject private var model: AppModel
    @State private var selected: Stage?
    @State private var confirming = false

    var body: some View {
        List {
            ForEach(Array(model.stagesForPicker.enumerated()), id: \.element.id) { index, stage in
                Button {
                    selected = stage
                    confirming = true
                } label: {
                    StageRow(stage: stage, suggested: index == 0 && model.hasSuggestion)
                }
            }

            Section {
                Text(L10n.fixturesNotice)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle(L10n.pickerTitle)
        .confirmationDialog(
            L10n.pickerConfirmTitle,
            isPresented: $confirming,
            titleVisibility: .visible,
            presenting: selected
        ) { stage in
            Button(L10n.pickerConfirmStart) {
                model.startStage(stage)
            }
            Button(L10n.cancel, role: .cancel) {}
        } message: { stage in
            Text(verbatim: stage.name + " · " + Formatters.distance(meters: stage.distanceMeters))
        }
    }
}

private struct StageRow: View {
    let stage: Stage
    let suggested: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if suggested {
                Label(L10n.pickerSuggested, systemImage: "star.fill")
                    .font(.caption2)
                    .foregroundStyle(Color.accentColor)
            }
            Text(stage.name)
                .font(.headline)
                .fixedSize(horizontal: false, vertical: true)
            Text(Formatters.distance(meters: stage.distanceMeters))
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        let base = stage.name + ", " + Spoken.distance(meters: stage.distanceMeters)
        return suggested ? L10n.pickerSuggested + ". " + base : base
    }
}
