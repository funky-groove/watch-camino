import SwiftUI

/// Camino Seguro Watch — app watchOS independiente (sin app iOS compañera).
@main
struct CaminoWatchApp: App {
    @StateObject private var model = AppModel()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(model)
        }
    }
}
