import SwiftUI
import CaminoCore
import CaminoDesign

// Iconografía: SF Symbols de contorno, mismo peso y escala en toda la app.
// Los iconos siempre acompañan a un texto; VoiceOver lee el texto, no el icono.

enum Icon {
    static let walk = "figure.walk"
    static let stats = "chart.bar"
    static let nearby = "mappin.and.ellipse"
    static let water = "drop"
    static let settings = "gearshape"
    static let finish = "flag.checkered"
    static let alert = "bell"
    static let time = "clock"
    static let distance = "point.topleft.down.to.point.bottomright.curvepath"
    static let steps = "figure.walk.motion"
    static let location = "location"
    static let locationOff = "location.slash"
    static let check = "checkmark"
    static let warning = "exclamationmark.triangle"
    static let info = "info.circle"
    static let chevron = "chevron.right"
    static let theme = "circle.lefthalf.filled"
    static let phone = "phone"
    static let satellite = "antenna.radiowaves.left.and.right"

    static func category(_ category: PoiCategory) -> String {
        switch category {
        case .water:
            return "drop"
        case .shelter:
            return "bed.double"
        case .pharmacy:
            return "cross.case"
        case .health:
            return "stethoscope"
        case .food:
            return "fork.knife"
        case .landmark:
            return "building.columns"
        }
    }
}

/// Icono con el tamaño y grosor de la casa.
struct IconView: View {
    let name: String
    var color: Color? = nil

    @ViewBuilder
    var body: some View {
        let image = Image(systemName: name)
            .symbolRenderingMode(.monochrome)
            .font(.system(.body).weight(.regular))
            .imageScale(.medium)
            .accessibilityHidden(true)
        if let color = color {
            image.foregroundStyle(color)
        } else {
            image
        }
    }
}
