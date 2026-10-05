import SwiftUI

// Estilos tipográficos. Todos derivan de estilos de Dynamic Type para respetar el tamaño
// de texto del usuario; ninguno usa `minimumScaleFactor`: el contenido se reorganiza o se
// desplaza, nunca se encoge hasta ser ilegible.
//
// Familia: SF (sistema). La familia de la app principal no está confirmada en código ni
// se ha recibido su licencia; SF es la elección nativa legible en el reloj.

enum TypeStyle {
    /// Título de pantalla o de etapa. Sobrio, en minúsculas por contenido (no por transformación).
    case title
    /// Encabezado breve de sección, en mayúsculas con espaciado moderado.
    case sectionLabel
    /// Cifra principal de la pantalla (distancia recorrida).
    case metricHero
    /// Cifras secundarias (tiempo, pasos).
    case metric
    /// Texto normal.
    case body
    /// Texto auxiliar. Nunca por debajo de `.footnote` para información esencial.
    case detail

    var font: Font {
        switch self {
        case .title:
            return .system(.headline).weight(.semibold)
        case .sectionLabel:
            return .system(.footnote).weight(.semibold)
        case .metricHero:
            return .system(.title, design: .default).weight(.medium).monospacedDigit()
        case .metric:
            return .system(.title3, design: .default).weight(.medium).monospacedDigit()
        case .body:
            return .system(.body)
        case .detail:
            return .system(.footnote)
        }
    }
}

extension View {
    func typeStyle(_ style: TypeStyle) -> some View {
        modifier(TypeStyleModifier(style: style))
    }
}

private struct TypeStyleModifier: ViewModifier {
    let style: TypeStyle

    func body(content: Content) -> some View {
        switch style {
        case .sectionLabel:
            content
                .font(style.font)
                .textCase(.uppercase)
                .tracking(0.6)
        default:
            content.font(style.font)
        }
    }
}
