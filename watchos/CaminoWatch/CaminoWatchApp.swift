import SwiftUI

/// Camino Seguro Watch — app watchOS independiente (sin app iOS compañera).
@main
@MainActor
struct CaminoWatchApp: App {
    @StateObject private var themeStore = ThemeStore()
    @StateObject private var model = AppModel()

    init() {
        // Bienvenida (§K): lee la caché local del logo fuera del hilo principal, lo antes
        // posible. Si no está lista para el primer fotograma se usa el logo incluido.
        BrandLogoLoader.shared.preload()
    }

    var body: some Scene {
        WindowGroup {
            // La interfaz se construye debajo desde el primer fotograma; la bienvenida sólo
            // se superpone (no retrasa datos ni toques).
            WelcomeHost(welcome: model.welcome) {
                RootView()
                    .environmentObject(model)
                    .environmentObject(themeStore)
                    .themed(themeStore.theme)
            }
            .onOpenURL { url in
                model.open(url)
            }
        }
    }
}
