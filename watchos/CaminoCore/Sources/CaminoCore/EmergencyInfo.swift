import Foundation

// Lógica pura de la pantalla SOS (docs/WATCH_V1_SPEC.md §10.2 y
// docs/accessibility/SOS_CAPABILITY_MATRIX.md). Sin UI ni plataforma: la app
// conecta `EmergencyDialer` con el sistema (`WKApplication.openSystemURL`).

// MARK: - Número de emergencia

/// Número de emergencia que ofrece la app.
///
/// Alcance documentado: **112, número único de emergencia en España y en la UE**.
/// NO es universal (p. ej. EE. UU. usa 911) y la app NO lo deduce del idioma ni de la
/// región del reloj: un peregrino con el reloj en inglés sigue estando en España.
public struct EmergencyNumber: Equatable, Hashable, Sendable {
    /// Sólo dígitos, sin espacios ni prefijos.
    public let digits: String

    public init(digits: String) {
        self.digits = digits
    }

    /// 112: España y Unión Europea.
    public static let spainEU = EmergencyNumber(digits: "112")

    /// `tel:112`. `nil` si el número está vacío o contiene algo que no sea un dígito
    /// (nunca se entrega al sistema una URL construida con texto arbitrario).
    public var telURL: URL? {
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else {
            return nil
        }
        return URL(string: "tel:" + digits)
    }
}

// MARK: - Entrega de la llamada

/// Motivo por el que no se pudo entregar la petición de llamada al sistema.
public enum DialFailureReason: Equatable, Sendable {
    /// El número no forma una URL `tel:` válida.
    case invalidURL
    /// La petición no llegó desde el hilo principal (la API del sistema lo exige).
    case notMainThread
}

/// Resultado de pedir una llamada. Honesto a propósito: la app sólo puede saber que
/// entregó la petición al sistema, nunca que la llamada se haya conectado.
public enum DialResult: Equatable, Sendable {
    /// La petición se entregó al sistema, que pide confirmación al usuario.
    case handedToSystem
    case failed(DialFailureReason)
}

/// Puerto para pedir una llamada. La app usa `SystemEmergencyDialer`
/// (`WKApplication.shared().openSystemURL(tel:)`); escenarios DEMO, capturas y tests usan
/// `MockEmergencyDialer`, que no abre nada.
public protocol EmergencyDialer: AnyObject {
    func requestCall(number: EmergencyNumber) -> DialResult
}

/// Marcador simulado: registra las peticiones y NO abre ninguna llamada.
public final class MockEmergencyDialer: EmergencyDialer {
    public private(set) var requests: [EmergencyNumber] = []
    /// Resultado que devolverá (por defecto, entregado al sistema).
    public var nextResult: DialResult

    public init(result: DialResult = .handedToSystem) {
        self.nextResult = result
    }

    public func requestCall(number: EmergencyNumber) -> DialResult {
        requests.append(number)
        if number.telURL == nil {
            return .failed(.invalidURL)
        }
        return nextResult
    }
}

// MARK: - Ubicación en emergencia

/// Estado del permiso de ubicación, tal como lo ve la pantalla SOS.
public enum EmergencyLocationPermission: Equatable, Sendable {
    case notDetermined
    case denied
    case granted
}

/// Hemisferio de una coordenada (la app pone la letra en el idioma: N/S/E/O o N/S/E/W).
public enum Hemisphere: String, Equatable, Sendable {
    case north
    case south
    case east
    case west
}

/// Una coordenada legible: valor absoluto con 5 decimales (≈ 1 m) y hemisferio.
public struct EmergencyCoordinate: Equatable, Sendable {
    /// "42.78080": siempre punto decimal, que es como se dictan las coordenadas.
    public let degrees: String
    public let hemisphere: Hemisphere

    public init(degrees: String, hemisphere: Hemisphere) {
        self.degrees = degrees
        self.hemisphere = hemisphere
    }

    public static func latitude(_ value: Double) -> EmergencyCoordinate {
        let text = format(value)
        let negative = value < 0 && !isZero(text)
        return EmergencyCoordinate(degrees: text, hemisphere: negative ? .south : .north)
    }

    public static func longitude(_ value: Double) -> EmergencyCoordinate {
        let text = format(value)
        let negative = value < 0 && !isZero(text)
        return EmergencyCoordinate(degrees: text, hemisphere: negative ? .west : .east)
    }

    /// Formato independiente del idioma del reloj (POSIX: punto decimal, sin miles).
    static func format(_ value: Double) -> String {
        return String(format: "%.5f", locale: Locale(identifier: "en_US_POSIX"), abs(value))
    }

    private static func isZero(_ text: String) -> Bool {
        return text.allSatisfy { $0 == "0" || $0 == "." }
    }
}

/// Resumen de la ubicación para la pantalla SOS. No pide permiso ni espera al GPS:
/// clasifica lo que ya hay. No se envía a ningún sitio.
public struct EmergencyLocationSummary: Equatable, Sendable {
    public enum Status: Equatable, Sendable {
        /// Posición de hace ≤ `currentMaxAgeSeconds`.
        case current
        /// Última conocida: más antigua que `current`, hasta `staleAfterSeconds`.
        case lastKnown
        /// Más antigua que `staleAfterSeconds`: puede no ser donde estás.
        case stale
        /// Sin ninguna posición válida (con permiso concedido o sin decidir).
        case noSignal
        /// Sin permiso de ubicación y sin ninguna posición anterior.
        case permissionDenied
    }

    /// Hasta 60 s se considera la posición actual.
    public static let currentMaxAgeSeconds = 60
    /// Más de 5 min: antigua (mismo umbral que `LocationQuality`).
    public static let staleAfterSeconds = LocationQuality.staleAfterSeconds

    public let status: Status
    public let latitude: EmergencyCoordinate?
    public let longitude: EmergencyCoordinate?
    /// Antigüedad en segundos (0 si la hora del fix es futura).
    public let ageSeconds: Int?
    /// Precisión redondeada (±m); `nil` si el sistema no la da.
    public let accuracyMeters: Int?
    /// El permiso está denegado (puede quedar una posición anterior a la denegación).
    public let permissionDenied: Bool

    public var hasCoordinates: Bool {
        return latitude != nil && longitude != nil
    }

    public static func of(
        fix: LocationFix?,
        now: Date,
        permission: EmergencyLocationPermission
    ) -> EmergencyLocationSummary {
        let denied = permission == .denied
        guard let fix = fix, isValid(fix) else {
            return EmergencyLocationSummary(
                status: denied ? .permissionDenied : .noSignal,
                latitude: nil,
                longitude: nil,
                ageSeconds: nil,
                accuracyMeters: nil,
                permissionDenied: denied
            )
        }
        let rawAge = now.timeIntervalSince(fix.timestamp)
        let age = rawAge.isFinite ? max(0, Int(min(rawAge, 1.0e9).rounded(.down))) : 0
        let status: Status
        if age <= currentMaxAgeSeconds {
            status = .current
        } else if age <= staleAfterSeconds {
            status = .lastKnown
        } else {
            status = .stale
        }
        let accuracy: Int?
        if fix.accuracyMeters.isFinite && fix.accuracyMeters > 0 {
            accuracy = Int(min(fix.accuracyMeters, 1.0e6).rounded())
        } else {
            accuracy = nil
        }
        return EmergencyLocationSummary(
            status: status,
            latitude: .latitude(fix.point.lat),
            longitude: .longitude(fix.point.lon),
            ageSeconds: age,
            accuracyMeters: accuracy,
            permissionDenied: denied
        )
    }

    /// Coordenadas finitas y en rango; precisión negativa = posición inválida (CoreLocation).
    private static func isValid(_ fix: LocationFix) -> Bool {
        let lat = fix.point.lat
        let lon = fix.point.lon
        guard lat.isFinite, lon.isFinite, abs(lat) <= 90, abs(lon) <= 180 else {
            return false
        }
        if fix.accuracyMeters.isNaN || fix.accuracyMeters < 0 {
            return false
        }
        return true
    }
}
