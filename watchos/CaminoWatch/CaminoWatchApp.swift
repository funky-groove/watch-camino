import SwiftUI

/// Camino Seguro Watch — app watchOS independiente (sin app iOS compañera).
@main
@MainActor
struct CaminoWatchApp: App {
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
                .environmentObject(themeStore)
                .themed(themeStore.theme)
                .onOpenURL { url in
                    model.open(url)
                }
        }
    }
}
