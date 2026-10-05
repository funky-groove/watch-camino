import SwiftUI
import CaminoCore
import CaminoDesign

/// Ajustes → Acceso desde la esfera → Cómo añadirlo (V1.1 §I).
///
/// Pasos manuales del sistema (Apple Watch, watchOS 10: "Change the watch face" /
/// "Add complications"): mantener pulsada la esfera → Editar → deslizar hasta
/// Complicaciones → tocar un hueco → elegir con la Digital Crown → pulsar la Digital Crown.
/// No hay botón para "abrir el editor": no existe API pública para ello. Tampoco se dice
/// si la complicación está instalada (la app no puede saberlo).
struct WatchFaceHelpView: View {
    @Environment(\.palette) private var palette

    private var steps: [String] {
        return [L10n.faceHelpStep1, L10n.faceHelpStep2, L10n.faceHelpStep3, L10n.faceHelpStep4]
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Text(L10n.faceHelpIntro)
                    .typeStyle(.body)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                ForEach(Array(steps.enumerated()), id: \.offset) { index, text in
                    HStack(alignment: .firstTextBaseline, spacing: Spacing.s) {
                        Text(verbatim: "\(index + 1).")
                            .font(TypeStyle.body.font.weight(.semibold).monospacedDigit())
                            .foregroundStyle(palette.textSecondary)
                        Text(text)
                            .typeStyle(.body)
                            .foregroundStyle(palette.textPrimary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel(L10n.faceHelpStepLabel(index + 1) + ": " + text)
                }

                StatusLine(symbol: Icon.info, text: L10n.faceHelpNoSlot)
                    .padding(.top, Spacing.xs)
                StatusLine(symbol: Icon.watchFace, text: L10n.faceHelpIPhone)
                StatusLine(symbol: Icon.walk, text: L10n.faceHelpTapOnly)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(L10n.faceHelpTitle)
    }
}

/// Aviso de primer uso «Accede desde tu esfera» (hoja, V1.1 §I). Lo decide `FaceAccessPrompt`.
/// Nunca afirma que la complicación esté instalada.
struct FaceAccessPromptView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                IconView(name: Icon.watchFace, color: palette.textSecondary)
                Text(L10n.faceTitle)
                    .typeStyle(.title)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)
                Text(L10n.faceBody)
                    .typeStyle(.body)
                    .foregroundStyle(palette.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    model.faceAccessOpenHelp()
                } label: {
                    Text(L10n.faceHowTo)
                }
                .buttonStyle(PrimaryButtonStyle())
                .padding(.top, Spacing.xs)

                Button {
                    model.faceAccessNotNow()
                } label: {
                    Text(L10n.faceNotNow)
                }
                .buttonStyle(SecondaryButtonStyle())
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .screenBackground(palette)
    }
}

#if DEBUG
#Preview("negro · ayuda de la esfera") {
    NavigationStack {
        WatchFaceHelpView()
            .themed(.negro)
    }
}

#Preview("perla · ayuda de la esfera") {
    NavigationStack {
        WatchFaceHelpView()
            .themed(.perla)
    }
}

#Preview("negro · aviso de primer uso") {
    FaceAccessPromptView()
        .themed(.negro)
        .environmentObject(AppModel())
}

#Preview("perla · aviso de primer uso") {
    FaceAccessPromptView()
        .themed(.perla)
        .environmentObject(AppModel())
}
#endif
