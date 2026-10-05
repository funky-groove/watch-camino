import SwiftUI
import UIKit
import CaminoCore

// Bienvenida visual con recurso de marca remoto (docs/WATCH_V1_SPEC.md §K).
//
// - `BrandLogoLoader`: caché local del recurso de marca. Al arrancar sólo LEE la caché, fuera
//   del hilo principal; si la imagen no está lista para el primer fotograma de la bienvenida se
//   usa el logo incluido (`BrandLogo` del catálogo). El refresco remoto es de segundo plano y,
//   mientras el contrato esté BLOQUEADO, usa `BlockedBrandAssetSource` (no hay red).
// - `WelcomeController`: decide UNA vez por proceso con `WelcomePolicy` y lleva los tiempos de
//   `WelcomeTiming` (0,6 s visible + 0,4 s de desvanecimiento; con reducción de movimiento,
//   retirada de golpe a los 0,6 s).
// - `WelcomeHost`: capa superpuesta ENCIMA de la interfaz ya construida. No captura toques
//   (`allowsHitTesting(false)`); un toque en cualquier sitio la retira. Decorativa: oculta a
//   VoiceOver. No toca la pantalla de lanzamiento del sistema.

/// Caché local del recurso de marca (Library/Caches/CaminoSeguro/Brand).
final class BrandLogoLoader: @unchecked Sendable {
    static let shared = BrandLogoLoader()

    private let lock = NSLock()
    private var image: UIImage?
    private var preloadStarted = false
    private var refreshScheduled = false
    private let store: FileBrandAssetStore?
    private let repository: BrandAssetRepository?

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        if let directory = caches?.appendingPathComponent("CaminoSeguro/Brand", isDirectory: true) {
            let store = FileBrandAssetStore(directory: directory)
            self.store = store
            self.repository = BrandAssetRepository(
                store: store,
                // Contrato BLOQUEADO (§K, contracts/README.md): no se descarga nada.
                source: BlockedBrandAssetSource(),
                clock: SystemClock(),
                // §K.1: la plataforma además debe poder decodificarla.
                decodable: { UIImage(data: $0) != nil }
            )
        } else {
            self.store = nil
            self.repository = nil
        }
    }

    /// Imagen de la caché ya decodificada, si terminó de cargarse. Nunca bloquea.
    var readyImage: UIImage? {
        lock.lock()
        defer { lock.unlock() }
        return image
    }

    /// Lee la caché local (si existe) fuera del hilo principal. Sin red. Una vez por proceso.
    func preload() {
        lock.lock()
        let alreadyStarted = preloadStarted
        preloadStarted = true
        lock.unlock()
        guard !alreadyStarted, let store = store, let repository = repository else {
            return
        }
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            // `current()` valida la caché (§K.1); inválida o ausente → logo incluido.
            guard case .cached(_, let meta) = repository.current(),
                  let url = store.assetURL(for: meta),
                  let loaded = UIImage(contentsOfFile: url.path) else {
                return
            }
            guard let self = self else {
                return
            }
            self.lock.lock()
            self.image = loaded
            self.lock.unlock()
        }
    }

    /// Refresco del recurso remoto, en segundo plano y nunca durante la apertura. Una vez por
    /// proceso. Con `BlockedBrandAssetSource` termina sin descargar ni escribir nada.
    func scheduleBackgroundRefresh() {
        lock.lock()
        let alreadyScheduled = refreshScheduled
        refreshScheduled = true
        lock.unlock()
        guard !alreadyScheduled, let repository = repository else {
            return
        }
        Task.detached(priority: .background) {
            // Lejos de la apertura: la interfaz y los datos ya están listos.
            try? await Task.sleep(nanoseconds: 10_000_000_000)
            let outcome = await repository.refresh()
            Log.app.info("Recurso de marca: \(String(describing: outcome), privacy: .public)")
        }
    }
}

/// Estado de la bienvenida (una por proceso).
@MainActor
final class WelcomeController: ObservableObject {
    enum Phase {
        case hidden
        case visible
        case fading
    }

    @Published private(set) var phase: Phase = .hidden
    /// Se llama una vez cuando la capa se retira (o al decidir no mostrarla).
    var onFinished: (@MainActor () -> Void)?

    /// Primera evaluación del proceso (= apertura desde cero; volver de segundo plano no
    /// crea otro proceso ni otra evaluación).
    private static var evaluatedInProcess = false
    private static var shownInProcess = false

    /// Capturas (`-demo.welcome show`): la capa se queda hasta que se toca.
    private var hold = false
    private var timersStarted = false
    private var finished = false

    var isShowing: Bool {
        return phase != .hidden
    }

    /// Decide al construir el modelo, antes del primer fotograma.
    func evaluateAtLaunch(hasActiveOrRestoredTrip: Bool, launchedFromDeepLink: Bool, launchedForSos: Bool) {
        let coldStart = !WelcomeController.evaluatedInProcess
        WelcomeController.evaluatedInProcess = true
        let policy = WelcomePolicy.shouldShow(
            coldStart: coldStart,
            hasActiveOrRestoredTrip: hasActiveOrRestoredTrip,
            launchedFromDeepLink: launchedFromDeepLink,
            launchedForSos: launchedForSos,
            alreadyShown: WelcomeController.shownInProcess
        )
        let show: Bool
        #if DEBUG
        if DemoScenario.welcomeForced {
            show = true
            hold = true
        } else {
            // Escenarios y capturas: sin bienvenida salvo que se pida.
            show = policy && !DemoScenario.isRequested
        }
        #else
        show = policy
        #endif
        guard show else {
            finish()
            return
        }
        WelcomeController.shownInProcess = true
        phase = .visible
    }

    /// Primer fotograma de la capa: arrancan los tiempos de §K.3.
    func overlayAppeared(reduceMotion: Bool) {
        guard phase == .visible, !timersStarted, !hold else {
            return
        }
        timersStarted = true
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(WelcomeTiming.visibleMs) * 1_000_000)
            guard let self = self, self.phase == .visible else {
                return
            }
            if reduceMotion {
                // Sin animación: se retira de golpe.
                self.finish()
                return
            }
            withAnimation(.easeOut(duration: WelcomeTiming.fadeSeconds)) {
                self.phase = .fading
            }
            try? await Task.sleep(nanoseconds: UInt64(WelcomeTiming.fadeMs) * 1_000_000)
            self.finish()
        }
    }

    /// Un toque en cualquier sitio la descarta (el toque llega igualmente a la interfaz).
    func dismissByTap() {
        if isShowing {
            finish()
        }
    }

    /// Apertura desde complicación, widget o notificación: nunca se muestra (§K.2).
    func cancelForExternalLaunch() {
        if isShowing {
            finish()
        }
    }

    private func finish() {
        if phase != .hidden {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                phase = .hidden
            }
        }
        guard !finished else {
            return
        }
        finished = true
        onFinished?()
    }
}

/// Raíz de la ventana: la interfaz y, encima, la bienvenida mientras dure.
struct WelcomeHost<Content: View>: View {
    @ObservedObject var welcome: WelcomeController
    private let content: Content

    init(welcome: WelcomeController, @ViewBuilder content: () -> Content) {
        self.welcome = welcome
        self.content = content()
    }

    var body: some View {
        ZStack {
            content
            if welcome.isShowing {
                WelcomeOverlay(welcome: welcome)
            }
        }
        // El toque lo recibe la interfaz (la capa no captura toques) y además retira la capa.
        .simultaneousGesture(
            TapGesture().onEnded { welcome.dismissByTap() },
            including: welcome.isShowing ? .all : .subviews
        )
    }
}

/// Logo sobre negro. Decorativo.
private struct WelcomeOverlay: View {
    @ObservedObject var welcome: WelcomeController
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// Se fija con el primer fotograma: la imagen de caché sólo si ya estaba cargada.
    @State private var cachedImage: UIImage? = BrandLogoLoader.shared.readyImage

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height) * 0.78
            ZStack {
                Color.black
                logo
                    .resizable()
                    .interpolation(.high)
                    .scaledToFit()
                    .frame(width: side, height: side)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .opacity(welcome.phase == .fading ? 0 : 1)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            welcome.overlayAppeared(reduceMotion: reduceMotion)
        }
    }

    private var logo: Image {
        if let image = cachedImage {
            return Image(uiImage: image)
        }
        return Image("BrandLogo")
    }
}
