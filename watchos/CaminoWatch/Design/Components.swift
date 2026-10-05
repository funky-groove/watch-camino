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
        HStack(alignment: .center, spacing: Spacing.s) {
            IconView(name: symbol)
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .typeStyle(.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                if let detail = detail {
                    Text(detail)
                        .typeStyle(.detail)
                        .foregroundStyle(palette.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 0)
            Image(systemName: Icon.chevron)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .accessibilityHidden(true)
        }
        .frame(maxWidth: .infinity, minHeight: Target.minimumHeight, alignment: .leading)
        .contentShape(Rectangle())
    }
}

// MARK: - Botones

/// Acción principal: relleno claro (Negro) u oscuro (Perla), texto en contraste.
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
        let tint = destructive ? palette.critical : palette.textPrimary
        return configuration.label
            .typeStyle(.body)
            .multilineTextAlignment(.center)
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity, minHeight: Target.minimumHeight)
            .padding(.horizontal, Spacing.s)
            .background(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .fill(configuration.isPressed ? palette.surfaceRaised : palette.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
                    .strokeBorder(destructive ? palette.critical : palette.controlOutline, lineWidth: Stroke.control)
            )
            .opacity(isEnabled ? 1 : 0.4)
            .contentShape(RoundedRectangle(cornerRadius: Radius.control, style: .continuous))
    }
}

/// Fila pulsable sin estilo de botón del sistema (para NavigationLink y Button con RowLabel).
struct RowButtonStyle: ButtonStyle {
    @Environment(\.palette) private var palette

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
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
    static func status(_ status: SyncStatus) -> String {
        switch status {
        case .synced:
            return L10n.syncSynced
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
