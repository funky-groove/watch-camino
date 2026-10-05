import SwiftUI
import CaminoCore
import CaminoDesign

/// Ajustes: tema, avisos por categoría y acceso al estado de sincronización.
/// Todo se guarda solo, en el reloj; no hay botón "guardar".
struct SettingsView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var themeStore: ThemeStore
    @Environment(\.palette) private var palette

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                SectionLabel(text: L10n.settingsSectionTheme)
                ForEach(ThemeID.allCases, id: \.self) { theme in
                    themeRow(theme)
                }

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
        .navigationTitle(L10n.settingsTitle)
    }

    private func themeRow(_ theme: ThemeID) -> some View {
        let isSelected = themeStore.theme == theme
        let name = themeName(theme)
        return Button {
            themeStore.theme = theme
        } label: {
            HStack(spacing: Spacing.s) {
                IconView(name: Icon.theme)
                Text(name)
                    .typeStyle(.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
                if isSelected {
                    HStack(spacing: Spacing.xxs) {
                        IconView(name: Icon.check)
                        Text(L10n.settingsThemeSelected)
                            .typeStyle(.detail)
                            .foregroundStyle(palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .frame(maxWidth: .infinity, minHeight: Target.minimumHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(name)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
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
