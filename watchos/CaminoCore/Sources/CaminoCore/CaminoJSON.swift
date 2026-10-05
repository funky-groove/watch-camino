import Foundation

/// Codificación JSON usada para la persistencia local (sesión, historial, cola).
///
/// Usa la estrategia de fechas por defecto (segundos desde la fecha de referencia),
/// que hace el round-trip de `Date` exacto bit a bit. Estos ficheros son privados
/// del reloj: no son un formato de intercambio con el backend.
public enum CaminoJSON {
    public static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func decoder() -> JSONDecoder {
        return JSONDecoder()
    }
}
