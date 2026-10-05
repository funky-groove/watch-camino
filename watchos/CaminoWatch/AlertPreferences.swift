import Foundation
import CaminoCore

/// Preferencias de avisos POI por categoría, guardadas localmente. Por defecto, todas activas.
enum AlertPreferences {
    static let defaultsKey = "settings.alertCategories"

    static func load(_ defaults: UserDefaults = .standard) -> Set<PoiCategory> {
        guard let stored = defaults.array(forKey: defaultsKey) as? [String] else {
            return Set(PoiCategory.allCases)
        }
        return Set(stored.compactMap(PoiCategory.init(rawValue:)))
    }

    static func save(_ categories: Set<PoiCategory>, _ defaults: UserDefaults = .standard) {
        defaults.set(categories.map { $0.rawValue }.sorted(), forKey: defaultsKey)
    }
}
