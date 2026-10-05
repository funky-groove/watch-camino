import CaminoCore
import CaminoDesign
import SwiftUI
import WidgetKit

// Complicación / widget "Mi etapa" (watchOS 10+). Ver CaminoWidgets/README.md.
//
// Fuente de datos: `WidgetSnapshot` (Shared/WidgetSnapshot.swift) que escribe la app en el
// App Group. Nunca contiene coordenadas. Sin datos → "Abre Camino Seguro".

// MARK: - Entrada y proveedor

struct CaminoEntry: TimelineEntry {
    let date: Date
    /// `nil`: no hay App Group o la app aún no ha publicado nada.
    let snapshot: WidgetSnapshot?
}

struct CaminoProvider: TimelineProvider {
    /// Durante una etapa el widget vuelve a leer la instantánea cada 15 min (sujeto a presupuesto).
    static let activeRefresh: TimeInterval = 15 * 60

    func placeholder(in context: Context) -> CaminoEntry {
        return CaminoEntry(date: Date(), snapshot: .demoActive)
    }

    func getSnapshot(in context: Context, completion: @escaping (CaminoEntry) -> Void) {
        let snapshot = WidgetSnapshotStore.load() ?? (context.isPreview ? .demoActive : nil)
        completion(CaminoEntry(date: Date(), snapshot: snapshot))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<CaminoEntry>) -> Void) {
        let now = Date()
        let snapshot = WidgetSnapshotStore.load()
        let entry = CaminoEntry(date: now, snapshot: snapshot)
        let policy: TimelineReloadPolicy
        if snapshot?.isActive == true {
            policy = .after(now.addingTimeInterval(CaminoProvider.activeRefresh))
        } else {
            // Sin etapa no hay nada que cambie solo: la app pide recarga al empezar una.
            policy = .never
        }
        completion(Timeline(entries: [entry], policy: policy))
    }
}

// MARK: - Widget

@main
struct CaminoStageWidget: Widget {
    static let kind = "org.caminoseguro.watch.widgets.stage"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: CaminoStageWidget.kind, provider: CaminoProvider()) { entry in
            CaminoWidgetView(entry: entry)
        }
        .configurationDisplayName(WidgetStrings.displayName)
        .description(WidgetStrings.description)
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline, .accessoryCorner])
    }
}

// MARK: - Vistas

struct CaminoWidgetView: View {
    let entry: CaminoEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        content
            .widgetURL(entry.snapshot?.isActive == true ? DeepLink.stage.url : DeepLink.stats.url)
            .containerBackground(for: .widget) {
                Color.clear
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            CircularView(snapshot: entry.snapshot, tint: tint)
        case .accessoryCorner:
            CornerView(snapshot: entry.snapshot, tint: tint)
        case .accessoryInline:
            InlineView(snapshot: entry.snapshot)
        default:
            RectangularView(snapshot: entry.snapshot)
        }
    }

    /// Color sólo a todo color. En modo acentuado/monocromo (vibrant) el sistema tiñe:
    /// la información nunca depende del color (cifra + unidad siempre en texto).
    private var tint: Color? {
        return renderingMode == .fullColor ? WidgetFormat.progressColor : nil
    }
}

/// Circular: Gauge de progreso de etapa (recorrido / plan), cifra en km.
private struct CircularView: View {
    let snapshot: WidgetSnapshot?
    let tint: Color?

    var body: some View {
        if let snapshot = snapshot, snapshot.isActive {
            Gauge(value: snapshot.progress, in: 0...1) {
                Text(snapshot.isDemo ? WidgetStrings.demo : WidgetStrings.unitKm)
            } currentValueLabel: {
                Text(WidgetFormat.kmNumber(snapshot.walkedMeters))
                    .widgetAccentable()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetFormat.progressLabel(snapshot))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "figure.walk")
                    .font(.title3)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot == nil ? WidgetStrings.openApp : WidgetStrings.noStageLong)
        }
    }
}

/// Esquina: cifra en el centro y etiqueta curva "de 22 km".
private struct CornerView: View {
    let snapshot: WidgetSnapshot?
    let tint: Color?

    var body: some View {
        if let snapshot = snapshot, snapshot.isActive {
            Text(WidgetFormat.kmNumber(snapshot.walkedMeters))
                .font(.title3.monospacedDigit())
                .widgetAccentable()
                .widgetCurvesContent()
                .widgetLabel {
                    Text(WidgetFormat.cornerLabel(snapshot))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(WidgetFormat.progressLabel(snapshot))
        } else {
            Image(systemName: "figure.walk")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel {
                    Text(snapshot == nil ? WidgetStrings.open : WidgetStrings.noStage)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot == nil ? WidgetStrings.openApp : WidgetStrings.noStageLong)
        }
    }
}

/// En línea: "4,2 km · 1:05:12" (el tiempo avanza solo) o "Camino Seguro".
private struct InlineView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        if let snapshot = snapshot, let startedAt = snapshot.startedAt {
            let prefix = snapshot.isDemo ? WidgetStrings.demo + " · " : ""
            Text(prefix + Formatters.distance(meters: snapshot.walkedMeters) + " · ")
                + Text(startedAt, style: .timer)
        } else {
            Text(WidgetStrings.appTitle)
        }
    }
}

/// Rectangular (también Smart Stack en watchOS 10): etapa, distancia y tiempo.
private struct RectangularView: View {
    let snapshot: WidgetSnapshot?

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let snapshot = snapshot, let startedAt = snapshot.startedAt {
                header(snapshot.stageName ?? WidgetStrings.displayName, isDemo: snapshot.isDemo)
                HStack(spacing: 4) {
                    Text(WidgetFormat.distanceLine(snapshot))
                        .font(.headline.monospacedDigit())
                        .widgetAccentable()
                    if !snapshot.hasFix {
                        Image(systemName: "location.slash")
                            .font(.footnote)
                            .accessibilityLabel(WidgetStrings.noGps)
                    }
                }
                HStack(spacing: 4) {
                    Image(systemName: "timer")
                        .font(.footnote)
                        .accessibilityLabel(WidgetStrings.elapsedA11y)
                    Text(startedAt, style: .timer)
                        .font(.body.monospacedDigit())
                }
            } else if let snapshot = snapshot {
                header(WidgetStrings.appTitle, isDemo: snapshot.isDemo)
                Text(WidgetStrings.noStageLong)
                    .font(.body)
                    .widgetAccentable()
                if let lastName = snapshot.lastStageName {
                    Text(WidgetFormat.lastLine(name: lastName, meters: snapshot.lastStageMeters))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } else {
                header(WidgetStrings.appTitle, isDemo: false)
                Text(WidgetStrings.openApp)
                    .font(.body)
                    .widgetAccentable()
            }
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func header(_ title: String, isDemo: Bool) -> some View {
        HStack(spacing: 4) {
            Text(title)
                .font(.headline)
            if isDemo {
                Text(WidgetStrings.demo)
                    .font(.footnote.weight(.bold))
                    .accessibilityLabel(WidgetStrings.demoA11y)
            }
        }
    }
}

// MARK: - Formato

enum WidgetFormat {
    /// Color del progreso a todo color (token "positivo" del tema Negro).
    static var progressColor: Color {
        let rgb = Palette.of(.negro).positive
        return Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }

    /// Cifra en km sin unidad, coherente con `Formatters.distance`: "0,3", "4,2", "12".
    static func kmNumber(_ meters: Double) -> String {
        let m = (meters.isFinite && meters > 0) ? min(meters, 1.0e9) : 0
        let tenths = Int(floor(m / 100.0 + 0.5))
        if tenths < 100 {
            return "\(tenths / 10),\(tenths % 10)"
        }
        return "\(Int(floor(m / 1000.0 + 0.5)))"
    }

    /// "4,2 km de 22 km" o "4,2 km" si no hay plan.
    static func distanceLine(_ snapshot: WidgetSnapshot) -> String {
        let walked = Formatters.distance(meters: snapshot.walkedMeters)
        guard snapshot.plannedMeters > 0 else {
            return walked
        }
        return walked + " " + WidgetStrings.ofPlanned(Formatters.distance(meters: snapshot.plannedMeters))
    }

    /// Etiqueta curva de la esquina: "km de 22 km" / "km" (+ "DEMO").
    static func cornerLabel(_ snapshot: WidgetSnapshot) -> String {
        var text = WidgetStrings.unitKm
        if snapshot.plannedMeters > 0 {
            text += " " + WidgetStrings.ofPlanned(Formatters.distance(meters: snapshot.plannedMeters))
        }
        if snapshot.isDemo {
            text += " · " + WidgetStrings.demo
        }
        return text
    }

    static func progressLabel(_ snapshot: WidgetSnapshot) -> String {
        let walked = Formatters.distance(meters: snapshot.walkedMeters)
        var text: String
        if snapshot.plannedMeters > 0 {
            text = WidgetStrings.progressA11y(walked: walked, planned: Formatters.distance(meters: snapshot.plannedMeters))
        } else {
            text = walked
        }
        if snapshot.isDemo {
            text += ". " + WidgetStrings.demoA11y
        }
        return text
    }

    /// "Última: Sarria – Portomarín · 22 km"
    static func lastLine(name: String, meters: Int?) -> String {
        var text = WidgetStrings.last + ": " + name
        if let meters = meters {
            text += " · " + Formatters.distance(meters: meters)
        }
        return text
    }
}

// MARK: - Datos de demostración (previews y placeholder)

extension WidgetSnapshot {
    /// Demostración: etapa en curso. Marcada `isDemo` → el widget muestra "DEMO".
    static var demoActive: WidgetSnapshot {
        let now = Date()
        return WidgetSnapshot(
            stageName: "Sarria – Portomarín",
            startedAt: now.addingTimeInterval(-(65 * 60)),
            walkedMeters: 4_200,
            plannedMeters: 22_000,
            hasFix: true,
            isDemo: true,
            updatedAt: now
        )
    }

    /// Demostración: sin etapa, con la última terminada.
    static var demoIdle: WidgetSnapshot {
        return WidgetSnapshot(
            stageName: nil,
            startedAt: nil,
            walkedMeters: 0,
            plannedMeters: 0,
            hasFix: false,
            isDemo: true,
            updatedAt: Date(),
            lastStageName: "Sarria – Portomarín",
            lastStageMeters: 22_000,
            lastStageSeconds: 5 * 3600 + 40 * 60
        )
    }
}

// MARK: - Previews (datos de demostración)

#Preview("Rectangular", as: .accessoryRectangular) {
    CaminoStageWidget()
} timeline: {
    CaminoEntry(date: .now, snapshot: .demoActive)
    CaminoEntry(date: .now, snapshot: .demoIdle)
    CaminoEntry(date: .now, snapshot: nil)
}

#Preview("Circular", as: .accessoryCircular) {
    CaminoStageWidget()
} timeline: {
    CaminoEntry(date: .now, snapshot: .demoActive)
    CaminoEntry(date: .now, snapshot: .demoIdle)
}

#Preview("En línea", as: .accessoryInline) {
    CaminoStageWidget()
} timeline: {
    CaminoEntry(date: .now, snapshot: .demoActive)
    CaminoEntry(date: .now, snapshot: nil)
}

#Preview("Esquina", as: .accessoryCorner) {
    CaminoStageWidget()
} timeline: {
    CaminoEntry(date: .now, snapshot: .demoActive)
    CaminoEntry(date: .now, snapshot: .demoIdle)
}
