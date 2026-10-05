import Foundation
import CaminoCore

// Textos de la pantalla SOS y del botón de cabecera (prefijo sos.).
// Honestos a propósito: la app pide la llamada al reloj; nunca dice que se haya
// conectado ni que se haya enviado nada (docs/accessibility/SOS_FEASIBILITY.md).

extension L10n {
    // MARK: Botón de cabecera

    static var sosButton: String { tr("sos.button", "SOS") }
    static var sosButtonHint: String { tr("sos.button.hint", "Abre la pantalla de emergencia.") }

    // MARK: Pantalla

    static var sosTitle: String { tr("sos.title", "emergencia") }
    static var sosCall: String { tr("sos.call", "Llamar al 112") }
    static var sosCallHint: String {
        tr("sos.call.hint", "El reloj te pedirá confirmar antes de llamar.")
    }
    static var sosScope: String { tr("sos.scope", "112: España y UE") }
    static var sosHandedToSystem: String {
        tr("sos.result.handed", "Llamada solicitada al reloj. Si no aparece, usa el SOS del reloj: mantén pulsado el botón lateral.")
    }
    /// Marcador simulado (escenarios DEMO): nunca «Llamada solicitada».
    static var sosSimulated: String {
        tr("sos.result.simulated", "Simulado: no se ha pedido ninguna llamada.")
    }
    static var sosFailed: String {
        tr("sos.result.failed", "No se pudo pedir la llamada. Usa el SOS del reloj: mantén pulsado el botón lateral.")
    }
    static var sosDemoNote: String {
        tr("sos.demo", "Modo demostración: no se abre ninguna llamada.")
    }

    // MARK: Ubicación

    static var sosLocationSection: String { tr("sos.location.section", "tu ubicación") }
    static var sosLocationCurrent: String { tr("sos.location.current", "ubicación actual") }
    static var sosLocationLastKnown: String { tr("sos.location.lastKnown", "última ubicación conocida") }
    static var sosLocationStale: String { tr("sos.location.stale", "ubicación antigua: puede que ya no estés ahí") }
    static var sosLocationNoSignal: String { tr("sos.location.noSignal", "sin ubicación disponible") }
    static var sosLocationDenied: String { tr("sos.location.denied", "sin permiso de ubicación") }
    static var sosLocationNotSent: String {
        tr("sos.location.notSent", "Estas coordenadas no se envían al 112 automáticamente.")
    }
    static var sosLatitude: String { tr("sos.a11y.latitude", "latitud") }
    static var sosLongitude: String { tr("sos.a11y.longitude", "longitud") }

    /// "±8 m"
    static func sosAccuracy(_ meters: Int) -> String {
        return format("sos.accuracy", "±%ld m", meters)
    }

    /// "precisión de 8 metros"
    static func sosSpokenAccuracy(_ meters: Int) -> String {
        return format("sos.a11y.accuracy", "precisión de %ld metros", meters)
    }

    static func sosHemisphereLetter(_ hemisphere: Hemisphere) -> String {
        switch hemisphere {
        case .north:
            return tr("sos.hemisphere.n", "N")
        case .south:
            return tr("sos.hemisphere.s", "S")
        case .east:
            return tr("sos.hemisphere.e", "E")
        case .west:
            return tr("sos.hemisphere.w", "O")
        }
    }

    static func sosHemisphereSpoken(_ hemisphere: Hemisphere) -> String {
        switch hemisphere {
        case .north:
            return tr("sos.a11y.hemisphere.n", "norte")
        case .south:
            return tr("sos.a11y.hemisphere.s", "sur")
        case .east:
            return tr("sos.a11y.hemisphere.e", "este")
        case .west:
            return tr("sos.a11y.hemisphere.w", "oeste")
        }
    }

    // MARK: Ayuda

    static var sosNativeSection: String { tr("sos.native.section", "SOS del reloj") }
    static var sosNativeHelp: String {
        tr("sos.native.help", "Mantén pulsado el botón lateral para usar el SOS del reloj.")
    }
    static var sosSatellite: String {
        tr("sos.satellite", "En Apple Watch Ultra 3 o posterior y regiones compatibles, el SOS del reloj puede enviar mensajes por satélite; esta app no lo controla.")
    }
}
