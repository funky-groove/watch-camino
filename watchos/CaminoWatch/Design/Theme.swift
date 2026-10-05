import SwiftUI
import CaminoDesign

// Puente entre los tokens puros (`CaminoDesign`) y SwiftUI.
// Las pantallas leen la paleta con `@Environment(\.palette)`; nunca usan colores sueltos.

extension Color {
    init(_ rgb: RGB) {
        self.init(
            .sRGB,
            red: Double(rgb.red) / 255.0,
            green: Double(rgb.green) / 255.0,
            blue: Double(rgb.blue) / 255.0,
            opacity: 1
        )
    }
}

/// Paleta resuelta a `Color`.
struct ThemePalette {
    let id: ThemeID
    let background: Color
    let surface: Color
    let surfaceRaised: Color
    let textPrimary: Color
    let textSecondary: Color
    let hairline: Color
    let controlOutline: Color
    let actionPrimaryFill: Color
    let actionPrimaryText: Color
    let positive: Color
    let warning: Color
    let critical: Color

    init(_ id: ThemeID) {
        let p = Palette.of(id)
        self.id = id
        background = Color(p.background)
        surface = Color(p.surface)
        surfaceRaised = Color(p.surfaceRaised)
        textPrimary = Color(p.textPrimary)
        textSecondary = Color(p.textSecondary)
        hairline = Color(p.hairline)
        controlOutline = Color(p.controlOutline)
        actionPrimaryFill = Color(p.actionPrimaryFill)
        actionPrimaryText = Color(p.actionPrimaryText)
        positive = Color(p.positive)
        warning = Color(p.warning)
        critical = Color(p.critical)
    }

    static let negro = ThemePalette(.negro)
    static let perla = ThemePalette(.perla)

    static func of(_ id: ThemeID) -> ThemePalette {
        return id == .perla ? .perla : .negro
    }
}

private struct PaletteKey: EnvironmentKey {
    static let defaultValue = ThemePalette.negro
}

extension EnvironmentValues {
    var palette: ThemePalette {
        get { self[PaletteKey.self] }
        set { self[PaletteKey.self] = newValue }
    }
}

/// Preferencia de tema, guardada localmente. Negro por defecto.
final class ThemeStore: ObservableObject {
    static let defaultsKey = "settings.theme"

    @Published var theme: ThemeID {
        didSet {
            defaults.set(theme.rawValue, forKey: ThemeStore.defaultsKey)
        }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        let stored = defaults.string(forKey: ThemeStore.defaultsKey).flatMap(ThemeID.init(rawValue:))
        self.theme = stored ?? ThemeID.initial
    }
}

/// Aplica el tema a una jerarquía de vistas.
///
/// - Con pantalla siempre activa atenuada (`isLuminanceReduced`) se usa siempre Negro:
///   un fondo claro en Always On gasta batería y deslumbra (HIG, Always On).
/// - El fondo se pinta en `containerBackground` para que la navegación del sistema lo respete.
struct ThemedModifier: ViewModifier {
    let theme: ThemeID
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    func body(content: Content) -> some View {
        let palette = ThemePalette.of(isLuminanceReduced ? .negro : theme)
        return content
            .environment(\.palette, palette)
            .foregroundStyle(palette.textPrimary)
            .tint(palette.textPrimary)
            .containerBackground(palette.background, for: .navigation)
    }
}

extension View {
    func themed(_ theme: ThemeID) -> some View {
        modifier(ThemedModifier(theme: theme))
    }

    /// Fondo de pantalla del tema (para vistas presentadas como hoja).
    func screenBackground(_ palette: ThemePalette) -> some View {
        background(palette.background.ignoresSafeArea())
    }
}
