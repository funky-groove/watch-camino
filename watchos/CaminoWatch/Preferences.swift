import Foundation
import Combine
import CaminoCore

/// Preferencias de presentación (V1.1 §G), guardadas localmente como `ThemeStore`.
///
/// - `units`: métrico (por defecto) o imperial.
/// - `paceMode`: ritmo (por defecto) o velocidad.
/// - Idioma: watchOS no ofrece una API pública para fijar el idioma de una app desde la
///   propia app; se sigue el idioma del reloj (`Bundle.main.preferredLocalizations`:
///   español o inglés). Ajustes lo explica con una fila informativa, sin interruptor.
final class Preferences: ObservableObject {
    static let unitsKey = "settings.units"
    static let paceModeKey = "settings.paceMode"

    @Published var units: UnitSystem {
        didSet {
            defaults.set(units.rawValue, forKey: Preferences.unitsKey)
            onChange?()
        }
    }

    @Published var paceMode: PaceMode {
        didSet {
            defaults.set(paceMode.rawValue, forKey: Preferences.paceModeKey)
            onChange?()
        }
    }

    /// Idioma de presentación (separadores decimales y de miles). Fijo durante la ejecución.
    let language: AppLanguage

    /// Se llama DESPUÉS de cada cambio (los valores ya están actualizados).
    var onChange: (() -> Void)?

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard, language: AppLanguage = Preferences.systemLanguage) {
        self.defaults = defaults
        self.language = language
        self.units = defaults.string(forKey: Preferences.unitsKey).flatMap(UnitSystem.init(rawValue:)) ?? .metric
        self.paceMode = defaults.string(forKey: Preferences.paceModeKey).flatMap(PaceMode.init(rawValue:)) ?? .pace
    }

    /// Idioma con el que el sistema ha cargado los textos de la app (es / en; español si otro).
    static var systemLanguage: AppLanguage {
        return AppLanguage.preferred(from: Bundle.main.preferredLocalizations)
    }

    var display: UnitDisplay {
        return UnitDisplay(units: units, paceMode: paceMode, lang: language)
    }
}
