import SwiftUI
import CaminoCore
import CaminoDesign

/// Elegir etapa: la sugerida primero (la siguiente a la última terminada), marcada con
/// el texto "sugerida". Pulsar → confirmar → empieza el trayecto (y se vuelve a la
/// pantalla principal). Tras confirmar, la lista se desactiva: un doble toque no inicia dos veces.
struct StagePickerView: View {
    @EnvironmentObject private var model: AppModel
    /// Cifras con las unidades y el idioma del usuario (V1.1 §G).
    private var display: UnitDisplay { model.display }
    @Environment(\.palette) private var palette
    @State private var selected: Stage?
    @State private var confirming = false
    /// Confirmación ya atendida (además, `AppModel.startStage` ignora un segundo inicio).
    @State private var didConfirm = false

    var body: some View {
        let stages = model.stagesForPicker
        let suggested: Stage? = model.hasSuggestion ? stages.first : nil
        let others: [Stage] = suggested == nil ? stages : Array(stages.dropFirst())

        return ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                if let stage = suggested {
                    SectionLabel(text: L10n.pickStageSuggested)
                    row(stage, suggested: true)
                }

                if !others.isEmpty {
                    SectionLabel(text: L10n.pickStageOthers)
                        .padding(.top, suggested == nil ? 0 : Spacing.s)
                    ForEach(others) { stage in
                        row(stage, suggested: false)
                    }
                }

                if stages.isEmpty {
                    Text(L10n.pickStageEmpty)
                        .typeStyle(.body)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }

                // Aviso discreto: el catálogo de etapas y POI es de demostración.
                StatusLine(symbol: Icon.info, text: L10n.pickStageNotice)
                    .padding(.top, Spacing.s)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(L10n.pickStageTitle)
        .confirmationDialog(
            L10n.pickStageConfirmTitle,
            isPresented: $confirming,
            titleVisibility: .visible,
            presenting: selected
        ) { stage in
            Button(L10n.pickStageConfirmStart) {
                guard !didConfirm else {
                    return
                }
                didConfirm = true
                model.startStage(stage)
                if model.activeSession == nil {
                    // No se pudo iniciar (el error se muestra en la pantalla principal):
                    // se puede volver a intentar.
                    didConfirm = false
                }
            }
            Button(L10n.pickStageCancel, role: .cancel) {}
        } message: { stage in
            Text(verbatim: stage.name + " · " + display.distance(stage.distanceMeters))
        }
    }

    private func row(_ stage: Stage, suggested: Bool) -> some View {
        let distance = display.distance(stage.distanceMeters)
        let detail = suggested ? L10n.pickStageSuggested + " · " + distance : distance
        let spoken = (suggested ? L10n.pickStageSuggested + ". " : "")
            + stage.name + ", " + display.spokenDistance(stage.distanceMeters)
        return Button {
            selected = stage
            confirming = true
        } label: {
            RowLabel(symbol: Icon.walk, title: stage.name, detail: detail)
        }
        .buttonStyle(RowButtonStyle())
        .disabled(didConfirm || model.isStarting || model.activeSession != nil)
        .accessibilityLabel(spoken)
    }
}

#if DEBUG
// Datos de demostración (catálogo de fixtures).
#Preview("Negro · demostración") {
    NavigationStack {
        StagePickerView()
    }
    .themed(.negro)
    .environmentObject(AppModel())
}

#Preview("Perla · demostración") {
    NavigationStack {
        StagePickerView()
    }
    .themed(.perla)
    .environmentObject(AppModel())
}
#endif
