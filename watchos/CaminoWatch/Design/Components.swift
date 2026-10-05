import SwiftUI
import CaminoCore
import CaminoDesign

// Componentes del sistema de diseño. Las pantallas se construyen SOLO con estas piezas
// y los tokens; no repiten tamaños, radios ni colores sueltos.

// MARK: - Estructura

/// Encabezado breve de sección, en mayúsculas.
struct SectionLabel: View {
    let text: String
    @Environment(\.palette) private var palette

    var body: some View {
        Text(text)
            .typeStyle(.sectionLabel)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Tarjeta: superficie redondeada con borde fino. Sin sombras ni degradados.
/// Su contenido usa los colores "sobre superficie" (`ThemePalette.onSurface`).
struct Card<Content: View>: View {
    @Environment(\.palette) private var palette
    private let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            content
        }
        .onSurface(palette)
        .padding(Spacing.m)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .fill(palette.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                .strokeBorder(palette.hairline, lineWidth: Stroke.hairline)
        )
    }
}

/// Separador fino.
struct Hairline: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Rectangle()
            .fill(palette.hairline)
            .frame(height: Stroke.hairline)
            .accessibilityHidden(true)
    }
}

// MARK: - Datos

/// Cifra con su etiqueta. `value == nil` significa "sin datos" (nunca un cero ficticio).
struct MetricView: View {
    enum Size {
        case hero
        case regular
    }

    let label: String
    let value: String?
    /// Lectura para VoiceOver del valor ("4,2 kilómetros").
    let spokenValue: String?
    var size: Size = .regular
    /// Texto que sustituye al valor cuando no hay datos ("esperando GPS").
    var emptyText: String = L10n.noData

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if let value = value {
                Text(value)
                    .typeStyle(size == .hero ? .metricHero : .metric)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text(emptyText)
                    .typeStyle(.body)
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text(label)
                .typeStyle(.detail)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue ?? value ?? emptyText)
    }
}

/// Barra de progreso fina (sin animación).
struct ProgressLine: View {
    /// 0…1
    let fraction: Double
    @Environment(\.palette) private var palette

    var body: some View {
        GeometryReader { proxy in
            let clamped = min(1, max(0, fraction.isFinite ? fraction : 0))
            ZStack(alignment: .leading) {
                Capsule().fill(palette.hairline)
                Capsule()
                    .fill(palette.positive)
                    .frame(width: proxy.size.width * clamped)
            }
        }
        .frame(height: 4)
        .accessibilityHidden(true)
    }
}

/// Estado con símbolo + texto. El color nunca es la única señal.
struct StatusLine: View {
    enum Tone {
        case neutral
        case positive
        case warning
        case critical
    }

    let symbol: String
    let text: String
    var tone: Tone = .neutral

    @Environment(\.palette) private var palette

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            IconView(name: symbol, color: color)
            Text(text)
                .typeStyle(.detail)
                .foregroundStyle(tone == .neutral ? palette.textSecondary : color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    private var color: Color {
        switch tone {
        case .neutral:
            return palette.textSecondary
        case .positive:
            return palette.positive
        case .warning:
            return palette.warning
        case .critical:
            return palette.critical
        }
    }
}

/// Marca DEMO: visible siempre que los datos sean de demostración (MockCaminoApi).
struct DemoBadge: View {
    @Environment(\.palette) private var palette

    var body: some View {
        Text(L10n.demoBadge)
            .typeStyle(.sectionLabel)
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xxs)
            .foregroundStyle(palette.warning)
            .overlay(Capsule().strokeBorder(palette.warning, lineWidth: Stroke.hairline))
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(L10n.demoAccessibility)
    }
}

// MARK: - Filas navegables

/// Fila pulsable de la casa: icono, título, detalle opcional y chevron.
struct RowLabel: View {
    let symbol: String
    let title: String
    var detail: String? = nil

    @Environment(\.palette) private var palette

    var body: some View {
        // Siempre dentro de una fila (`RowButtonStyle`): colores "sobre superficie".
        HStack(alignment: .center, spacing: Spacing.s) {
            IconView(name: symbol, color: palette.onSurfacePrimary)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .typeStyle(.body)
                    .foregroundStyle(palette.onSurfacePrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = detail {
                    Text(detail)
                        .typeStyle(.detail)
                        .foregroundStyle(palette.onSurfaceSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .layoutPriority(1)
            Spacer(minLength: 0)
            Image(systemName: Icon.chevron)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.onSurfaceSecondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: Target.minimumHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Botones

/// Acción principal: relleno claro (Negro: casi blanco; Perla en watchOS: perla) con texto
/// oscuro en contraste (`actionPrimaryText`).
struct PrimaryButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeStyle(.title)
            .multilineTextAlignment(.center)
            .foregroundStyle(palette.actionPrimaryText)
            .frame(maxWidth: .infinity, minHeight: Target.primaryHeight)
            .padding(.horizontal, Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(palette.actionPrimaryFill)
            )
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.4))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

/// Acción secundaria: contorno y fondo discreto. `destructive` usa el rojo + texto explícito.
struct SecondaryButtonStyle: ButtonStyle {
    var destructive: Bool = false
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        // Texto sobre la superficie del botón (en Perla de watchOS, oscuro sobre perla).
        let tint = destructive ? palette.criticalOnSurface : palette.onSurfacePrimary
        return configuration.label
            .typeStyle(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(tint)
            .onSurface(palette)
            .frame(maxWidth: .infinity, minHeight: Target.minimumHeight)
            .padding(.horizontal, Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(configuration.isPressed ? palette.surfaceRaised : palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(
                        destructive ? palette.criticalOnSurface : palette.controlOutline,
                        lineWidth: Stroke.control
                    )
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

/// Botón «SOS» de la cabecera: compacto a la vista (texto rojo con contorno rojo sobre el
/// fondo, pares verificados en `ContrastTests`), pero con objetivo táctil ≥ 44×44 pt.
/// Forma de cápsula pequeña: no se confunde con «Finalizar trayecto» (ancho completo, neutro,
/// al final del contenido).
struct SOSButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        // Pulsado se pinta sobre `surfaceRaised`: rojo "sobre superficie" (perla en Perla).
        configuration.label
            .typeStyle(.sectionLabel)
            .foregroundStyle(configuration.isPressed ? palette.criticalOnSurface : palette.critical)
            .fixedSize()
            .padding(.horizontal, Spacing.s)
            .padding(.vertical, Spacing.xs)
            .background(
                Capsule().fill(configuration.isPressed ? palette.surfaceRaised : palette.background)
            )
            .overlay(
                Capsule().strokeBorder(palette.critical, lineWidth: Stroke.control)
            )
            .frame(minWidth: Target.minimumHeight, minHeight: Target.minimumHeight)
            .contentShape(Rectangle())
    }
}

/// Acción de emergencia («Llamar al 112»): relleno rojo sobrio con texto en contraste
/// (par «texto de acción de emergencia» en `ContrastTests`), alto ≥ 52 pt.
struct EmergencyCallButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .typeStyle(.title)
            .multilineTextAlignment(.center)
            .foregroundStyle(palette.actionPrimaryText)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, minHeight: Target.primaryHeight)
            .padding(.horizontal, Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(palette.critical)
            )
            .opacity(configuration.isPressed ? 0.75 : (isEnabled ? 1 : 0.4))
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

/// Botón de icono de la barra superior (ajustes, cerrar hoja): círculo de superficie con el
/// icono en contraste. Estilo propio: con el estilo del sistema el círculo se rellenaba con el
/// tinte y el icono (mismo color) desaparecía. Objetivo táctil ≥ 44×44 pt.
struct ToolbarIconButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.iconOnly)
            .font(.system(.body).weight(.semibold))
            .imageScale(.medium)
            .foregroundStyle(palette.onSurfacePrimary)
            .frame(width: 36, height: 36)
            .background(
                Circle().fill(configuration.isPressed ? palette.surfaceRaised : palette.surface)
            )
            .overlay(
                Circle().strokeBorder(palette.hairline, lineWidth: Stroke.hairline)
            )
            .frame(minWidth: Target.minimumHeight, minHeight: Target.minimumHeight)
            .contentShape(Rectangle())
    }
}

/// Botón «cerrar» de las hojas con `ToolbarIconButtonStyle` (sustituye al del sistema, cuyo
/// icono no se veía sobre el círculo tintado). Cierra igual que el del sistema (`dismiss`).
struct SheetCloseButton: ViewModifier {
    @Environment(\.dismiss) private var dismiss

    func body(content: Content) -> some View {
        content.toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button {
                    dismiss()
                } label: {
                    Label(L10n.commonClose, systemImage: Icon.close)
                }
                .buttonStyle(ToolbarIconButtonStyle())
                .accessibilityLabel(L10n.commonClose)
            }
        }
    }
}

extension View {
    /// Hojas: botón «cerrar» propio, legible en ambos temas.
    func sheetCloseButton() -> some View {
        modifier(SheetCloseButton())
    }
}

/// Fila pulsable sin estilo de botón del sistema (para NavigationLink y Button con RowLabel).
/// Su contenido usa los colores "sobre superficie" (`ThemePalette.onSurface`).
struct RowButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .onSurface(palette)
            .padding(.horizontal, Spacing.m)
            .background(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .fill(configuration.isPressed ? palette.surfaceRaised : palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.card, style: .continuous)
                    .strokeBorder(palette.hairline, lineWidth: Stroke.hairline)
            )
    }
}

// MARK: - Sincronización

/// Textos y símbolos del estado de sincronización.
enum SyncText {
    /// - Parameter isDemo: con `MockCaminoApi` nunca se dice "sincronizado" a secas:
    ///   el servidor es de demostración.
    static func status(_ status: SyncStatus, isDemo: Bool = false) -> String {
        switch status {
        case .synced:
            return isDemo ? L10n.syncSyncedDemo : L10n.syncSynced
        case .pending(let count):
            return L10n.syncPending(count)
        case .offline:
            return L10n.syncOffline
        case .blocked:
            return L10n.syncBlocked
        case .needsLink:
            return L10n.syncNeedsLink
        case .syncing:
            return L10n.syncSyncing
        }
    }

    static func symbol(_ status: SyncStatus) -> String {
        switch status {
        case .synced:
            return "checkmark.icloud"
        case .pending:
            return "clock.arrow.circlepath"
        case .offline:
            return "wifi.slash"
        case .blocked:
            return "lock.icloud"
        case .needsLink:
            return "person.crop.circle.badge.exclamationmark"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        }
    }

    static func tone(_ status: SyncStatus) -> StatusLine.Tone {
        switch status {
        case .synced:
            return .positive
        case .pending, .syncing, .blocked, .offline:
            return .warning
        case .needsLink:
            return .critical
        }
    }
}

// MARK: - Cifras compactas (V1.1)

/// Cifra secundaria en una sola fila: etiqueta a la izquierda y valor a la derecha
/// (con texto grande pasa a dos líneas). `value == nil` → `emptyText`, nunca un cero ficticio.
struct CompactMetricRow: View {
    var symbol: String? = nil
    let label: String
    let value: String?
    /// Lectura para VoiceOver del valor.
    let spokenValue: String?
    var emptyText: String = L10n.noData

    @Environment(\.palette) private var palette

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
                labelView
                Spacer(minLength: Spacing.xs)
                valueView
            }
            VStack(alignment: .leading, spacing: 0) {
                labelView
                valueView
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(spokenValue ?? value ?? emptyText)
    }

    private var labelView: some View {
        HStack(alignment: .firstTextBaseline, spacing: Spacing.xxs) {
            if let symbol = symbol {
                IconView(name: symbol, color: palette.textSecondary)
            }
            Text(label)
                .typeStyle(.detail)
                .foregroundStyle(palette.textSecondary)
                .fixedSize()
        }
    }

    @ViewBuilder
    private var valueView: some View {
        if let value = value {
            Text(value)
                .font(TypeStyle.body.font.weight(.semibold).monospacedDigit())
                .foregroundStyle(palette.textPrimary)
                .fixedSize()
        } else {
            Text(emptyText)
                .typeStyle(.detail)
                .foregroundStyle(palette.textSecondary)
                .fixedSize()
        }
    }
}

/// Fila de opción (ajustes): marca de selección (círculo / círculo con check) y título
/// completo. El título ocupa todo el ancho restante y salta de línea por palabras; nunca se
/// encoge ni se corta. La selección se anuncia con el rasgo `.isSelected`, no con una palabra.
struct SelectionRow: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.palette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(alignment: .center, spacing: Spacing.s) {
                IconView(
                    name: isSelected ? Icon.selected : Icon.unselected,
                    color: isSelected ? palette.onSurfacePrimary : palette.onSurfaceSecondary
                )
                Text(title)
                    .typeStyle(.body)
                    .foregroundStyle(palette.onSurfacePrimary)
                    .lineLimit(nil)
                    .multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .layoutPriority(1)
            }
            .padding(.vertical, Spacing.xs)
            .frame(maxWidth: .infinity, minHeight: Target.minimumHeight, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(RowButtonStyle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : [.isButton])
    }
}

/// Estado del trayecto con símbolo + texto (el color nunca va solo): «En marcha» / «Pausado».
struct TripStateLine: View {
    let isPaused: Bool

    var body: some View {
        StatusLine(
            symbol: isPaused ? Icon.paused : Icon.running,
            text: isPaused ? L10n.tripPaused : L10n.tripRunning,
            tone: isPaused ? .warning : .positive
        )
    }
}
