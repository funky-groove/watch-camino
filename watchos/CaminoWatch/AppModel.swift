import Foundation
import Combine
import CaminoCore

/// Estado observable de la UI. Fino a propósito: la lógica está en `CaminoController`
/// (núcleo); aquí sólo se conectan sensores, notificaciones y SwiftUI.
@MainActor
final class AppModel: ObservableObject {
    @Published private(set) var state: SessionState = .idle
    @Published private(set) var history: History = []
    @Published private(set) var syncStatus: SyncStatus = .synced
    @Published private(set) var pendingCount: Int = 0
    @Published private(set) var deadLetterCount: Int = 0
    /// Último fix con precisión suficiente (sólo en memoria; para "Próximo POI").
    @Published private(set) var lastFix: LocationFix?
    @Published private(set) var lastAlert: PoiAlert?
    /// Última posición recibida con cualquier precisión (para "Cerca" y la calidad de ubicación).
    @Published private(set) var lastAnyFix: LocationFix?
    @Published private(set) var locationPermission: LocationPermission = .notDetermined
    /// Permiso de notificaciones (estado real, se consulta al sistema).
    @Published private(set) var notificationPermission: LocationPermission = .notDetermined
    /// Inicio de trayecto en curso: impide un doble inicio por doble toque.
    @Published private(set) var isStarting: Bool = false
    /// Categorías que generan aviso (preferencia local).
    @Published var alertCategories: Set<PoiCategory> {
        didSet {
            controller.alertCategories = alertCategories
            AlertPreferences.save(alertCategories)
        }
    }
    /// Navegación pedida desde fuera (enlace directo o notificación). `RootView` la consume.
    @Published var requestedRoutes: [Route]?
    @Published private(set) var locationDenied: Bool = false
    @Published private(set) var stepsUnavailable: Bool = false
    /// Resumen a mostrar tras finalizar (hoja modal).
    @Published var finishedSummary: SessionSummary?
    @Published var errorMessage: String?

    let isDemo: Bool

    private let controller: CaminoController
    private let credentials: any CredentialStore
    private let location: LocationSource
    private let steps: StepSource
    private let notifier: Notifier
    /// Llamada de emergencia (sistema, o simulada en escenarios DEMO).
    private let dialer: any EmergencyDialer

    init() {
        let dependencies = AppEnvironment.make()
        self.controller = dependencies.controller
        self.credentials = dependencies.credentials
        self.isDemo = dependencies.controller.isDemo
        self.dialer = dependencies.dialer
        self.location = LocationSource()
        self.steps = StepSource()
        self.notifier = Notifier()
        let categories = AlertPreferences.load()
        self.alertCategories = categories
        dependencies.controller.alertCategories = categories

        wire()
        refresh()
        refreshNotificationPermission()
        // V-03: el estado guardado no se pudo leer (se apartó una copia): avisar, no callar.
        if !dependencies.controller.startupErrors.isEmpty {
            errorMessage = L10n.errorRecover
        }
        restoreActiveSessionIfNeeded()
        #if DEBUG
        DemoScenario.apply(to: self)
        #endif
    }

    // MARK: - Lectura para la UI

    var activeSession: StageSession? {
        return state.activeSession
    }

    var stagesForPicker: [Stage] {
        return controller.stagesForPicker
    }

    var hasSuggestion: Bool {
        return controller.suggestedStage != nil
    }

    var remainingMeters: Double {
        return controller.remainingMeters ?? 0
    }

    var totals: CaminoTotals {
        return controller.totals
    }

    var latestSummary: SessionSummary? {
        return history.first
    }

    func stage(id: String) -> Stage? {
        return controller.stage(id: id)
    }

    func stageName(id: String) -> String {
        return controller.stage(id: id)?.name ?? id
    }

    func elapsedSeconds(at date: Date) -> Int {
        return controller.elapsedSeconds(at: date)
    }

    /// POI no avisado más cercano al último fix, si hay fix.
    var nextPoi: PoiAlert? {
        guard let fix = lastFix else {
            return nil
        }
        return controller.nextPoi(from: fix.point)
    }

    var hasPendingPois: Bool {
        guard let session = activeSession else {
            return false
        }
        let pois = controller.pois(forStage: session.stageId)
        return pois.contains(where: { !session.alertedPoiIds.contains($0.id) })
    }

    /// Calidad de la última ubicación conocida.
    func locationQuality(at date: Date) -> LocationQuality {
        return LocationQuality.of(lastAnyFix, now: date)
    }

    /// Lista "Cerca" a partir de la última ubicación conocida (vacía si no hay ninguna).
    func nearby(waterOnly: Bool) -> [PoiAlert] {
        guard let fix = lastAnyFix else {
            return []
        }
        let categories: Set<PoiCategory> = waterOnly ? [.water] : Set(PoiCategory.allCases)
        return controller.nearby(from: fix.point, categories: categories)
    }

    /// Agua más cercana (para el acceso directo de "Mi etapa").
    var nearestWater: PoiAlert? {
        return nearby(waterOnly: true).first
    }

    // MARK: - SOS

    /// `true` si la llamada de emergencia es simulada (escenarios DEMO / capturas).
    var usesSimulatedDialer: Bool {
        return dialer is MockEmergencyDialer
    }

    /// Posición más reciente disponible, de cualquier precisión: la última recibida en esta
    /// ejecución o, tras relanzar, la guardada en la sesión activa.
    var latestKnownFix: LocationFix? {
        let candidates = [lastAnyFix, lastFix, activeSession?.lastFix].compactMap { $0 }
        return candidates.max(by: { $0.timestamp < $1.timestamp })
    }

    /// Resumen de ubicación para la pantalla SOS (no pide permiso ni espera al GPS).
    func emergencyLocation(at date: Date) -> EmergencyLocationSummary {
        let permission: EmergencyLocationPermission
        switch locationPermission {
        case .granted:
            permission = .granted
        case .denied:
            permission = .denied
        case .notDetermined:
            permission = .notDetermined
        }
        return EmergencyLocationSummary.of(fix: latestKnownFix, now: date, permission: permission)
    }

    /// Entrega la llamada al 112 al sistema (que pide confirmación). No pausa ni finaliza
    /// el trayecto y no envía la ubicación a ningún sitio.
    func requestEmergencyCall() -> DialResult {
        let result = dialer.requestCall(number: .spainEU)
        switch result {
        case .handedToSystem:
            Log.app.info("SOS: petición de llamada entregada")
        case .failed:
            Log.app.error("SOS: no se pudo pedir la llamada")
        }
        return result
    }

    /// Una lectura de ubicación para la pantalla SOS SÓLO si el permiso ya está concedido:
    /// nunca lo pide. Con trayecto en curso la ubicación ya está activa y no hace nada.
    func refreshLocationIfAuthorized() {
        guard locationPermission == .granted else {
            return
        }
        location.requestOnce()
    }

    func poi(id: String) -> Poi? {
        return controller.poi(id: id)
    }

    /// Distancia actual a un POI, si hay ubicación.
    func distance(to poi: Poi) -> Double? {
        guard let fix = lastAnyFix else {
            return nil
        }
        return Geo.haversine(fix.point, poi.location)
    }

    /// Si el POI ya se avisó en la etapa en curso.
    func wasAlerted(_ poiId: String) -> Bool {
        return activeSession?.alertedPoiIds.contains(poiId) ?? false
    }

    // MARK: - Acciones

    /// Abre un enlace directo (complicación, widget, notificación). Nunca ejecuta acciones.
    func open(_ url: URL) {
        guard let link = DeepLink.parse(url) else {
            Log.app.info("Enlace directo descartado")
            return
        }
        requestedRoutes = link.routes
    }

    /// Una sola lectura de ubicación para "Cerca" cuando no hay etapa en curso
    /// (con etapa en curso la ubicación ya está activa). No activa seguimiento continuo.
    func refreshLocationOnce() {
        location.requestPermissionIfNeeded()
        location.requestOnce()
    }

    /// Permisos en contexto: al pulsar "Iniciar trayecto" (§11).
    func requestPermissions() {
        location.requestPermissionIfNeeded()
        notifier.requestPermissionIfNeeded { [weak self] in
            self?.refreshNotificationPermission()
        }
    }

    /// Consulta el estado real del permiso de notificaciones.
    func refreshNotificationPermission() {
        notifier.currentPermission { [weak self] permission in
            self?.notificationPermission = permission
        }
    }

    func startStage(_ stage: Stage) {
        // Doble toque o confirmación repetida: un único inicio.
        guard !isStarting, controller.activeSession == nil else {
            Log.app.info("Inicio de trayecto ignorado: ya en curso")
            return
        }
        isStarting = true
        defer {
            isStarting = false
        }
        do {
            let session = try controller.start(stageId: stage.id)
            errorMessage = nil
            lastAlert = nil
            lastFix = nil
            attachSensors(startedAt: session.startedAt)
            Log.app.info("Etapa iniciada")
        } catch {
            errorMessage = L10n.errorStart
            Log.app.error("No se pudo iniciar la etapa: \(Log.describe(error), privacy: .public)")
        }
        refresh()
    }

    func finishStage() {
        // Confirmación repetida: no hay nada que finalizar (sin mensaje de error falso).
        guard controller.activeSession != nil else {
            return
        }
        do {
            let summary = try controller.finish()
            detachSensors()
            lastAlert = nil
            lastFix = nil
            errorMessage = nil
            finishedSummary = summary
            Log.app.info("Etapa finalizada")
        } catch {
            errorMessage = L10n.errorFinish
            Log.app.error("No se pudo finalizar la etapa: \(Log.describe(error), privacy: .public)")
        }
        refresh()
    }

    /// Botón "Sincronizar ahora": ignora el backoff (§7).
    func syncNowManually() {
        Task {
            await controller.syncNow(manual: true)
            refresh()
        }
    }

    /// La app vuelve a primer plano (scenePhase == .active): disparador de sync (§7).
    func appBecameActive() {
        refreshNotificationPermission()
        Task {
            await controller.syncNow(manual: false)
            refresh()
        }
    }

    // MARK: - Privado

    private func wire() {
        controller.onChange = { [weak self] in
            self?.refresh()
        }
        controller.onStorageError = { [weak self] error in
            Log.storage.error("Error de escritura: \(Log.describe(error), privacy: .public)")
            self?.errorMessage = L10n.errorStorage
        }

        // Los sensores pueden llamar desde otras colas: se salta siempre al MainActor.
        location.onFix = { [weak self] fix in
            Task { @MainActor in
                self?.handleFix(fix)
            }
        }
        location.onPermissionChange = { [weak self] permission in
            Task { @MainActor in
                self?.locationDenied = (permission == .denied)
                self?.locationPermission = permission
            }
        }
        steps.onSteps = { [weak self] count in
            Task { @MainActor in
                self?.handleSteps(count)
            }
        }
        steps.onUnavailable = { [weak self] in
            Task { @MainActor in
                self?.stepsUnavailable = true
            }
        }

        locationDenied = (location.permission == .denied)
        locationPermission = location.permission
        notifier.onOpenPoi = { [weak self] poiId in
            Task { @MainActor in
                self?.requestedRoutes = [.poi(id: poiId)]
            }
        }
    }

    /// Restauración tras muerte del proceso (§12): si había etapa activa, se
    /// reenganchan los sensores; los pasos se re-consultan desde `startedAt`.
    private func restoreActiveSessionIfNeeded() {
        guard let session = controller.activeSession else {
            return
        }
        lastFix = session.lastFix
        attachSensors(startedAt: session.startedAt)
        Log.app.info("Etapa activa restaurada")
    }

    private func attachSensors(startedAt: Date) {
        stepsUnavailable = false
        location.start()
        steps.start(from: startedAt)
    }

    private func detachSensors() {
        location.stop()
        steps.stop()
    }

    private func handleFix(_ fix: LocationFix) {
        lastAnyFix = fix
        guard controller.activeSession != nil else {
            return
        }
        if DistanceAccumulator.isAccurateEnough(fix) {
            lastFix = fix
        }
        guard let result = controller.updateLocation(fix) else {
            return
        }
        if let alert = result.alert {
            lastAlert = alert
            notifier.notifyPoi(poiId: alert.poi.id, text: PoiText.alertText(alert))
            Log.app.info("Aviso POI emitido")
        }
    }

    private func handleSteps(_ count: Int) {
        controller.updateSteps(count)
    }

    #if DEBUG
    /// Sólo Debug (capturas y previews con DemoScenario): inyecta una posición de demostración.
    func injectDemoFix(_ fix: LocationFix) {
        handleFix(fix)
    }

    /// Sólo Debug: acceso al controlador para sembrar escenarios de demostración.
    var demoController: CaminoController {
        return controller
    }
    #endif

    private func refresh() {
        state = controller.state
        history = controller.history
        syncStatus = controller.sync.status
        pendingCount = controller.sync.pendingCount
        deadLetterCount = controller.sync.deadLetterCount
        WidgetBridge.update(from: self)
    }
}
