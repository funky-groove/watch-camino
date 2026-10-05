import Foundation
import os

/// Logs de la app (§11): NUNCA coordenadas, tokens ni identificadores de usuario.
/// Sólo eventos y códigos de error.
enum Log {
    static let subsystem: String = Bundle.main.bundleIdentifier ?? "org.caminoseguro.watch"

    static let app = Logger(subsystem: subsystem, category: "app")
    static let sensors = Logger(subsystem: subsystem, category: "sensors")
    static let sync = Logger(subsystem: subsystem, category: "sync")
    static let storage = Logger(subsystem: subsystem, category: "storage")

    /// Descripción segura de un error: tipo + dominio/código, sin mensajes que
    /// pudieran contener datos.
    static func describe(_ error: Error) -> String {
        let nsError = error as NSError
        return "\(String(describing: type(of: error))) \(nsError.domain)#\(nsError.code)"
    }
}
