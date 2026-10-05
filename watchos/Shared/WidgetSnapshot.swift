import Foundation

/// Instantánea mínima que la app publica para la complicación / widget.
///
/// Se compila en DOS targets (app `CaminoWatch` y extensión `CaminoWidgets`): sólo Foundation.
///
/// Privacidad: NUNCA lleva coordenadas, ni identificadores de sesión, ni POI. Sólo lo que se
/// ve en la esfera: nombre de etapa, distancias, hora de inicio y marcas de estado.
struct WidgetSnapshot: Codable, Equatable {
    /// Versión del formato. Si cambia, el widget ignora ficheros antiguos (degrada a "abre la app").
    /// v2 (V1.1): pausa, unidades e idioma.
    static let currentVersion = 2

    var version: Int
    /// Nombre visible de la etapa en curso; `nil` si no hay etapa.
    var stageName: String?
    /// Inicio de la etapa en curso (para `Text(_, style: .timer)`); `nil` si no hay etapa.
    var startedAt: Date?
    /// Metros recorridos en la etapa en curso.
    var walkedMeters: Double
    /// Metros planificados de la etapa en curso (0 si se desconocen).
    var plannedMeters: Double
    /// Hay una posición aceptada en la etapa en curso.
    var hasFix: Bool
    /// Datos de demostración: el widget muestra "DEMO".
    var isDemo: Bool
    /// Momento en que la app generó la instantánea.
    var updatedAt: Date
    /// Última etapa terminada (estado sin etapa).
    var lastStageName: String?
    var lastStageMeters: Int?
    var lastStageSeconds: Int?
    /// Trayecto en pausa (V1.1 §C): el widget dice «pausado».
    var isPaused: Bool
    /// Preferencias de presentación (V1.1 §G) como texto crudo para no depender del núcleo:
    /// `UnitSystem.rawValue` ("metric"/"imperial") y `AppLanguage.rawValue` ("es"/"en").
    var units: String
    var lang: String

    init(
        stageName: String?,
        startedAt: Date?,
        walkedMeters: Double,
        plannedMeters: Double,
        hasFix: Bool,
        isDemo: Bool,
        updatedAt: Date,
        lastStageName: String? = nil,
        lastStageMeters: Int? = nil,
        lastStageSeconds: Int? = nil,
        isPaused: Bool = false,
        units: String = "metric",
        lang: String = "es"
    ) {
        self.version = WidgetSnapshot.currentVersion
        self.stageName = stageName
        self.startedAt = startedAt
        self.walkedMeters = WidgetSnapshot.sanitized(walkedMeters)
        self.plannedMeters = WidgetSnapshot.sanitized(plannedMeters)
        self.hasFix = hasFix
        self.isDemo = isDemo
        self.updatedAt = updatedAt
        self.lastStageName = lastStageName
        self.lastStageMeters = lastStageMeters
        self.lastStageSeconds = lastStageSeconds
        self.isPaused = isPaused
        self.units = units
        self.lang = lang
    }

    /// Hay etapa en curso.
    var isActive: Bool {
        return startedAt != nil
    }

    /// Fracción recorrido / plan en 0...1 (0 si el plan es desconocido).
    var progress: Double {
        guard plannedMeters > 0 else {
            return 0
        }
        return min(max(walkedMeters / plannedMeters, 0), 1)
    }

    /// Igualdad "a efectos de pantalla": ignora `updatedAt` y variaciones de distancia
    /// menores que `meterTolerance` (la esfera muestra décimas de km).
    func isEquivalent(to other: WidgetSnapshot, meterTolerance: Double = 100) -> Bool {
        return version == other.version
            && stageName == other.stageName
            && startedAt == other.startedAt
            && plannedMeters == other.plannedMeters
            && hasFix == other.hasFix
            && isDemo == other.isDemo
            && lastStageName == other.lastStageName
            && lastStageMeters == other.lastStageMeters
            && lastStageSeconds == other.lastStageSeconds
            && isPaused == other.isPaused
            && units == other.units
            && lang == other.lang
            && abs(walkedMeters - other.walkedMeters) < meterTolerance
    }

    private static func sanitized(_ meters: Double) -> Double {
        guard meters.isFinite, meters > 0 else {
            return 0
        }
        return min(meters, 1.0e7)
    }
}

/// Lectura / escritura de la instantánea en el contenedor del App Group.
///
/// Sin firma real (p. ej. simulador con `CODE_SIGNING_ALLOWED=NO`) el contenedor puede ser
/// `nil`: entonces la app no escribe nada y el widget muestra "Abre Camino Seguro".
enum WidgetSnapshotStore {
    static let appGroupIdentifier = "group.org.caminoseguro.watch"
    static let fileName = "widget-snapshot.json"

    static var fileURL: URL? {
        guard let container = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: appGroupIdentifier
        ) else {
            return nil
        }
        return container.appendingPathComponent(fileName, isDirectory: false)
    }

    /// `nil` si no hay contenedor, no hay fichero, está corrupto o es de otra versión.
    static func load() -> WidgetSnapshot? {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else {
            return nil
        }
        guard let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data),
              snapshot.version == WidgetSnapshot.currentVersion else {
            return nil
        }
        return snapshot
    }

    /// Escritura atómica. Devuelve `false` si no hay contenedor de App Group.
    @discardableResult
    static func save(_ snapshot: WidgetSnapshot) throws -> Bool {
        guard let url = fileURL else {
            return false
        }
        let data = try JSONEncoder().encode(snapshot)
        // Sin protección "complete": el widget debe poder leerla con el reloj bloqueado.
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return true
    }
}
