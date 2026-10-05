import Foundation
import os
import CaminoCore

#if DEBUG
/// Escenarios de demostración para capturas automáticas y pruebas de usabilidad (sólo Debug).
///
/// Se eligen con argumentos de lanzamiento (llegan a `UserDefaults.standard` por el
/// dominio de argumentos, que es volátil y no se guarda):
///
///     -demo.scenario idle|active|paused|nearby|alert|finished
///     -demo.route    stats|stat-distance|nearby|nearby-water|places|poi-p01|settings|settings-face|
///                    sync|picker|sos|profile|summary|face-prompt
///
/// `face-prompt` no es una pantalla: fuerza la hoja «Accede desde tu esfera» (§I) sin sus
/// condiciones. `summary` muestra el resumen del último trayecto (escenario `finished`).
///     -demo.scrollToEnd YES   (pantalla principal desplazada hasta «Finalizar trayecto»)
///
/// Con `-demo.scenario`, `AppEnvironment` usa almacenes EN MEMORIA y un reloj desplazable
/// (`DemoOffsetClock`): el almacenamiento real del reloj nunca se toca.
/// Todos los datos son de DEMOSTRACIÓN (la app ya muestra la marca DEMO en Debug).
/// La llamada de emergencia es SIEMPRE simulada (`MockEmergencyDialer`): no abre nada.
enum DemoScenario {
    static let scenarioKey = "demo.scenario"
    static let routeKey = "demo.route"
    static let scrollToEndKey = "demo.scrollToEnd"

    /// Capturas: desplazar la pantalla principal hasta el final (sólo con escenario).
    static var scrollToEnd: Bool {
        return isRequested && UserDefaults.standard.bool(forKey: scrollToEndKey)
    }

    enum Kind: String, CaseIterable {
        case idle
        case active
        /// Como `active`, pero en pausa (V1.1 §C).
        case paused
        case nearby
        case alert
        case finished
    }

    /// `true` si se pidió cualquier escenario (aunque el valor no sea válido): basta para
    /// que `AppEnvironment` aísle la persistencia en memoria.
    static var isRequested: Bool {
        return UserDefaults.standard.string(forKey: scenarioKey) != nil
    }

    static var requestedKind: Kind? {
        guard let raw = UserDefaults.standard.string(forKey: scenarioKey) else {
            return nil
        }
        return Kind(rawValue: raw.trimmingCharacters(in: .whitespaces).lowercased())
    }

    @MainActor
    static func apply(to model: AppModel) {
        if isRequested {
            guard let kind = requestedKind else {
                Log.app.error("Escenario demo desconocido; se ignora")
                applyRoute(to: model)
                return
            }
            // Sin reloj de demo, el controlador está sobre el almacenamiento real: no se siembra nada.
            guard let clock = AppEnvironment.demoClock else {
                Log.app.error("Escenario demo sin entorno en memoria; no se siembra")
                return
            }
            Log.app.info("Escenario demo: \(kind.rawValue, privacy: .public)")
            seed(kind, model: model, clock: clock)
        }
        applyRoute(to: model)
    }

    // MARK: - Datos (DEMO, derivados de shared/fixtures)

    static let stageId = "cf-sarria-portomarin"
    /// Pasos de la etapa en curso.
    static let activeSteps = 5_230
    /// La etapa en curso empezó hace 65 min.
    static let activeElapsedSeconds: TimeInterval = 65 * 60
    /// Precisión de todos los fixes de demo (≤ 50 m, pasa el paso 1 de §5).
    static let accuracyMeters: Double = 8
    /// Precisión vertical de la altitud de demo (≤ 15 m, válida para §E).
    static let verticalAccuracyMeters: Double = 5

    /// Altitud de demostración del trayecto en curso (fracción 0…1 del recorrido):
    /// sube de 412 a 448 m (60 % del recorrido) y baja a 430 m. Con la histéresis de 3 m da
    /// una subida y una bajada reales (≈ 36 m y ≈ 18 m).
    static func activeAltitude(_ fraction: Double) -> Double {
        if fraction < 0.6 {
            return 412 + 36 * (fraction / 0.6)
        }
        return 448 - 18 * ((fraction - 0.6) / 0.4)
    }

    /// Altitud de demostración de la etapa completa (historial): ondulada entre ≈ 300 y 660 m.
    static func finishedAltitude(_ fraction: Double) -> Double {
        return 450 + 150 * sin(fraction * 2.6 * Double.pi) + 60 * fraction
    }

    /// Recorrido desde Sarria (inicio de etapa) hacia p01 (Fuente de Barbadelo).
    /// Interpolado cada ≤ 50 m da ≈ 4 165 m acumulados (§5) y termina a ≈ 330 m de p01,
    /// fuera del radio de aviso (300 m, §6). Verificado con una réplica del acumulador.
    static let activeWaypoints: [GeoPoint] = [
        GeoPoint(lat: 42.7808, lon: -7.4141),   // Sarria (start de la etapa)
        GeoPoint(lat: 42.7850, lon: -7.4255),
        GeoPoint(lat: 42.7750, lon: -7.4335),
        GeoPoint(lat: 42.7775, lon: -7.4440),
        GeoPoint(lat: 42.77109, lon: -7.45139)  // ≈ 330 m de p01
    ]

    /// Punto a ≈ 250 m de p01 (≈ 80 m después del último fix): dispara el aviso de p01.
    static let alertPoint = GeoPoint(lat: 42.77085, lon: -7.45231)

    /// Junto a Melide (p07/p08, etapa cf-palas-arzua).
    static let melidePoint = GeoPoint(lat: 42.9132, lon: -8.0118)

    /// Etapa completa (para el historial del escenario "finished"): ≈ 19,6 km acumulados
    /// interpolando cada ≤ 100 m.
    static let finishedWaypoints: [GeoPoint] = [
        GeoPoint(lat: 42.7808, lon: -7.4141),
        GeoPoint(lat: 42.7850, lon: -7.4255),
        GeoPoint(lat: 42.7750, lon: -7.4335),
        GeoPoint(lat: 42.7701, lon: -7.4552),   // p01
        GeoPoint(lat: 42.7640, lon: -7.4800),
        GeoPoint(lat: 42.7790, lon: -7.5050),
        GeoPoint(lat: 42.7720, lon: -7.5300),
        GeoPoint(lat: 42.7835, lon: -7.5536),   // p02
        GeoPoint(lat: 42.7880, lon: -7.5800),
        GeoPoint(lat: 42.7990, lon: -7.5850),
        GeoPoint(lat: 42.8070, lon: -7.6150),   // p03
        GeoPoint(lat: 42.8075, lon: -7.6156)    // Portomarín (end)
    ]
    static let finishedSteps = 29_840
    /// Empezó hace 26 h y duró 5 h 30 min.
    static let finishedStartOffsetSeconds: TimeInterval = -26 * 3600
    static let finishedDurationSeconds: TimeInterval = 5.5 * 3600

    // MARK: - Siembra

    @MainActor
    private static func seed(_ kind: Kind, model: AppModel, clock: DemoOffsetClock) {
        switch kind {
        case .idle:
            break
        case .active:
            seedActive(model: model, clock: clock, withAlert: false)
        case .paused:
            seedActive(model: model, clock: clock, withAlert: false)
            do {
                try model.demoController.pause()
            } catch {
                Log.app.error("Escenario demo: no se pudo pausar: \(Log.describe(error), privacy: .public)")
            }
        case .alert:
            seedActive(model: model, clock: clock, withAlert: true)
        case .nearby:
            let fix = LocationFix(
                point: melidePoint,
                accuracyMeters: accuracyMeters,
                timestamp: Date().addingTimeInterval(-30)
            )
            model.injectDemoFix(fix)
        case .finished:
            seedFinished(model: model, clock: clock)
        }
    }

    @MainActor
    private static func seedActive(model: AppModel, clock: DemoOffsetClock, withAlert: Bool) {
        let controller = model.demoController
        guard controller.activeSession == nil else {
            return
        }
        let now = Date()
        clock.offsetSeconds = -activeElapsedSeconds
        do {
            try controller.start(stageId: stageId)
        } catch {
            clock.offsetSeconds = 0
            Log.app.error("Escenario demo: no se pudo iniciar la etapa: \(Log.describe(error), privacy: .public)")
            return
        }
        clock.offsetSeconds = 0
        controller.updateSteps(activeSteps)

        // Fixes repartidos entre 30 s después del inicio y 60 s antes de ahora (≈ 1,1 m/s).
        let first = now.addingTimeInterval(-activeElapsedSeconds + 30)
        let last = now.addingTimeInterval(-60)
        let points = interpolate(activeWaypoints, maxStepMeters: 50)
        for fix in fixes(points, from: first, to: last, altitude: activeAltitude) {
            model.injectDemoFix(fix)
        }
        if withAlert {
            let fix = LocationFix(
                point: alertPoint,
                accuracyMeters: accuracyMeters,
                timestamp: now.addingTimeInterval(-15)
            )
            model.injectDemoFix(fix)
        }
    }

    @MainActor
    private static func seedFinished(model: AppModel, clock: DemoOffsetClock) {
        let controller = model.demoController
        guard controller.activeSession == nil else {
            return
        }
        let now = Date()
        let startedAt = now.addingTimeInterval(finishedStartOffsetSeconds)
        clock.offsetSeconds = finishedStartOffsetSeconds
        defer {
            clock.offsetSeconds = 0
        }
        do {
            try controller.start(stageId: stageId)
        } catch {
            Log.app.error("Escenario demo: no se pudo iniciar la etapa: \(Log.describe(error), privacy: .public)")
            return
        }
        controller.updateSteps(finishedSteps)
        let points = interpolate(finishedWaypoints, maxStepMeters: 100)
        let first = startedAt.addingTimeInterval(30)
        let last = startedAt.addingTimeInterval(finishedDurationSeconds - 30)
        // Directo al controlador: sin notificaciones de avisos pasados.
        for fix in fixes(points, from: first, to: last, altitude: finishedAltitude) {
            controller.updateLocation(fix)
        }
        clock.offsetSeconds = finishedStartOffsetSeconds + finishedDurationSeconds
        do {
            try controller.finish()
        } catch {
            Log.app.error("Escenario demo: no se pudo finalizar la etapa: \(Log.describe(error), privacy: .public)")
        }
    }

    // MARK: - Ruta

    @MainActor
    private static func applyRoute(to model: AppModel) {
        guard let raw = UserDefaults.standard.string(forKey: routeKey) else {
            return
        }
        switch raw.trimmingCharacters(in: .whitespaces).lowercased() {
        case "face-prompt":
            model.presentFaceAccessPromptForDemo()
            return
        case "summary":
            model.presentLatestSummaryForDemo()
            return
        default:
            break
        }
        guard let routes = routes(for: raw) else {
            Log.app.error("Ruta demo desconocida; se ignora")
            return
        }
        model.requestedRoutes = routes
    }

    static func routes(for raw: String) -> [Route]? {
        let key = raw.trimmingCharacters(in: .whitespaces).lowercased()
        switch key {
        case "home", "":
            return []
        case "stats":
            return [.stats]
        case "stat-distance":
            return [.stats, .statDetail(.distance)]
        case "stat-time":
            return [.stats, .statDetail(.time)]
        case "stat-steps":
            return [.stats, .statDetail(.steps)]
        case "nearby":
            return [.nearby(waterOnly: false)]
        case "nearby-water":
            return [.nearby(waterOnly: true)]
        case "places":
            return [.nearby(waterOnly: false)]
        case "settings":
            return [.settings]
        case "settings-face":
            return [.settings, .watchFaceHelp]
        case "profile":
            return [.profile]
        case "sync":
            return [.sync]
        case "picker":
            return [.pickStage]
        case "sos":
            return [.sos]
        default:
            if key.hasPrefix("poi-") {
                let id = String(key.dropFirst(4))
                return id.isEmpty ? nil : [.poi(id: id)]
            }
            return nil
        }
    }

    // MARK: - Geometría

    /// Puntos equiespaciados (en lat/lon) por tramo, con ≤ `maxStepMeters` entre vecinos.
    /// Incluye el primer waypoint y todos los demás.
    static func interpolate(_ waypoints: [GeoPoint], maxStepMeters: Double) -> [GeoPoint] {
        guard let firstPoint = waypoints.first else {
            return []
        }
        var points: [GeoPoint] = [firstPoint]
        var index = 1
        while index < waypoints.count {
            let a = waypoints[index - 1]
            let b = waypoints[index]
            let length = Geo.haversine(a, b)
            let parts = max(1, Int((length / maxStepMeters).rounded(.up)))
            var part = 1
            while part <= parts {
                let t = Double(part) / Double(parts)
                points.append(GeoPoint(
                    lat: a.lat + (b.lat - a.lat) * t,
                    lon: a.lon + (b.lon - a.lon) * t
                ))
                part += 1
            }
            index += 1
        }
        return points
    }

    /// Fixes con marcas de tiempo repartidas uniformemente entre `first` y `last` y, si se
    /// da `altitude` (fracción del recorrido → metros), altitud GPS con precisión vertical 5 m.
    static func fixes(
        _ points: [GeoPoint],
        from first: Date,
        to last: Date,
        altitude: ((Double) -> Double)? = nil
    ) -> [LocationFix] {
        let count = points.count
        let span = last.timeIntervalSince(first)
        var result: [LocationFix] = []
        result.reserveCapacity(count)
        for (index, point) in points.enumerated() {
            let fraction = count > 1 ? Double(index) / Double(count - 1) : 1.0
            result.append(LocationFix(
                point: point,
                accuracyMeters: accuracyMeters,
                timestamp: first.addingTimeInterval(span * fraction),
                altitudeMeters: altitude.map { $0(fraction) },
                verticalAccuracyMeters: altitude == nil ? nil : verticalAccuracyMeters
            ))
        }
        return result
    }
}
#endif
