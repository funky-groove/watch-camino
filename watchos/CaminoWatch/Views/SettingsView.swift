import SwiftUI
import CaminoCore
import CaminoDesign

/// Ajustes (V1.1 §A): acceso desde la esfera, unidades, ritmo o velocidad, tema, idioma
/// (informativo), avisos por categoría y estado. Todo se guarda solo, en el reloj; no hay
/// botón "guardar".
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                // Grupos: menos de 10 vistas por bloque del ViewBuilder.
                Group {
                    // Acceso desde la esfera: ruta permanente a las instrucciones (§I).
                    SectionLabel(text: L10n.settingsSectionFace)
                    NavigationLink(value: Route.watchFaceHelp) {
                        RowLabel(symbol: Icon.watchFace, title: L10n.settingsFaceRow)
                    }
                    .buttonStyle(RowButtonStyle())

                    SectionLabel(text: L10n.settingsSectionUnits)
                        .padding(.top, Spacing.m)
                    SelectionRow(
                        title: L10n.settingsUnitsMetric,
                        isSelected: model.preferences.units == .metric
                    ) {
                        model.preferences.units = .metric
                    }
                    SelectionRow(
                        title: L10n.settingsUnitsImperial,
                        isSelected: model.preferences.units == .imperial
                    ) {
                        model.preferences.units = .imperial
                    }

                    SectionLabel(text: L10n.settingsSectionPace)
                        .padding(.top, Spacing.m)
                    SelectionRow(
                        title: L10n.settingsPacePace,
                        isSelected: model.preferences.paceMode == .pace
                    ) {
                        model.preferences.paceMode = .pace
                    }
                    SelectionRow(
                        title: L10n.settingsPaceSpeed,
                        isSelected: model.preferences.paceMode == .speed
                    ) {
                        model.preferences.paceMode = .speed
                    }
                }

                Group {
                    SectionLabel(text: L10n.settingsSectionTheme)
                        .padding(.top, Spacing.m)
                    ForEach(ThemeID.allCases, id: \.self) { theme in
                        SelectionRow(
                            title: themeName(theme),
                            isSelected: themeStore.theme == theme
                        ) {
                            themeStore.theme = theme
                        }
                    }

                    // Informativo: watchOS no permite fijar el idioma de la app desde la app.
                    SectionLabel(text: L10n.settingsSectionLanguage)
                        .padding(.top, Spacing.m)
                    StatusLine(symbol: Icon.language, text: L10n.settingsLanguageInfo)
                }

                Group {
                    SectionLabel(text: L10n.settingsSectionAlerts)
                        .padding(.top, Spacing.m)
                    ForEach(PoiCategory.allCases, id: \.self) { category in
                        Toggle(isOn: binding(for: category)) {
                            HStack(spacing: Spacing.s) {
                                IconView(name: Icon.category(category))
                                Text(PoiText.category(category))
                                    .typeStyle(.body)
                                    .foregroundStyle(palette.textPrimary)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        // Interruptor encendido en verde (con el tinte claro del tema, la pista
                        // encendida apenas se distinguía del pulgar blanco).
                        .tint(palette.positive)
                        .frame(minHeight: Target.minimumHeight)
                        .accessibilityLabel(PoiText.category(category))
                    }
                    Text(L10n.settingsAlertsRule)
                        .typeStyle(.detail)
                        .foregroundStyle(palette.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    SectionLabel(text: L10n.settingsSectionStatus)
                        .padding(.top, Spacing.m)
                    NavigationLink(value: Route.sync) {
                        RowLabel(
                            symbol: SyncText.symbol(model.syncStatus),
                            title: L10n.settingsSyncRow,
                            detail: SyncText.status(model.syncStatus, isDemo: model.isDemo)
                        )
                    }
                    .buttonStyle(RowButtonStyle())

                    // Informativo: dónde está el SOS (pantalla principal) y el SOS nativo del reloj.
                    StatusLine(symbol: Icon.info, text: L10n.settingsSosInfo)
                        .padding(.top, Spacing.m)
                }
            }
        }
        .navigationTitle(L10n.settingsTitle)
    }

    private func themeName(_ theme: ThemeID) -> String {
        switch theme {
        case .negro:
            return L10n.settingsThemeNegro
        case .perla:
            return L10n.settingsThemePerla
        }
    }

    /// Toggle enlazado a la pertenencia de la categoría al conjunto de avisos.
    private func binding(for category: PoiCategory) -> Binding<Bool> {
        return Binding<Bool>(
            get: { model.alertCategories.contains(category) },
            set: { isOn in
                if isOn {
                    model.alertCategories.insert(category)
                } else {
                    model.alertCategories.remove(category)
                }
            }
        )
    }
}

#if DEBUG
#Preview("negro · datos de demostración") {
    NavigationStack {
        SettingsView()
            .themed(.negro)
    }
    .environmentObject(AppModel())
    .environmentObject(ThemeStore())
}

#Preview("perla · datos de demostración") {
    NavigationStack {
        SettingsView()
            .themed(.perla)
    }
    .environmentObject(AppModel())
    .environmentObject(ThemeStore())
}
#endif
