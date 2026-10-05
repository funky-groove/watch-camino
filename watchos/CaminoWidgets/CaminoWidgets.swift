import CaminoCore
import CaminoDesign
import SwiftUI
import WidgetKit

// Complicación / widget "Trayecto" (watchOS 10+). Ver CaminoWidgets/README.md.
// Las complicaciones no se pueden capturar con simctl: se verifican con los #Preview de
// abajo en Xcode (activo, pausado en millas, datos antiguos, sin trayecto, sin datos).
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
        var entries = [CaminoEntry(date: now, snapshot: snapshot)]
        let policy: TimelineReloadPolicy
        if let snapshot = snapshot, snapshot.isActive {
            // Si la app deja de publicar (p. ej. la cerró el sistema), la esfera no promete
            // frescura: a partir de 15 min sin datos nuevos dice "hace X min" (cada 5 min).
            var next = max(now.addingTimeInterval(60), snapshot.updatedAt.addingTimeInterval(WidgetFormat.staleAfter))
            for _ in 0..<12 {
                entries.append(CaminoEntry(date: next, snapshot: snapshot))
                next = next.addingTimeInterval(5 * 60)
            }
            policy = .after(now.addingTimeInterval(CaminoProvider.activeRefresh))
        } else {
            // Sin trayecto no hay nada que cambie solo: la app pide recarga al empezar uno.
            policy = .never
        }
        completion(Timeline(entries: entries, policy: policy))
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

/// Con trayecto: distancia en las unidades del usuario + «en marcha» / «pausado».
/// Sin trayecto: icono + «Iniciar trayecto». Tocar SIEMPRE sólo abre la pantalla Trayecto
/// (`DeepLink.stage`): nunca inicia un trayecto ni una llamada (V1.1 §H).
struct CaminoWidgetView: View {
    let entry: CaminoEntry

    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode

    var body: some View {
        content
            .widgetURL(DeepLink.stage.url)
            .containerBackground(for: .widget) {
                Color.clear
            }
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular:
            CircularView(snapshot: entry.snapshot, now: entry.date, tint: tint)
        case .accessoryCorner:
            CornerView(snapshot: entry.snapshot, now: entry.date, tint: tint)
        case .accessoryInline:
            InlineView(snapshot: entry.snapshot, now: entry.date)
        default:
            RectangularView(snapshot: entry.snapshot, now: entry.date)
        }
    }

    /// Color sólo a todo color. En modo acentuado/monocromo (vibrant) el sistema tiñe:
    /// la información nunca depende del color (cifra + unidad + estado siempre en texto).
    private var tint: Color? {
        return renderingMode == .fullColor ? WidgetFormat.progressColor : nil
    }
}

/// Circular: Gauge de progreso de etapa (recorrido / plan), cifra en el centro.
private struct CircularView: View {
    let snapshot: WidgetSnapshot?
    let now: Date
    let tint: Color?

    var body: some View {
        if let snapshot = snapshot, snapshot.isActive {
            let parts = WidgetFormat.distanceParts(snapshot.walkedMeters, snapshot)
            Gauge(value: snapshot.progress, in: 0...1) {
                if snapshot.isPaused {
                    Image(systemName: "pause.fill")
                } else {
                    Text(snapshot.isDemo ? WidgetStrings.demo : parts.unit)
                }
            } currentValueLabel: {
                Text(parts.number)
                    .widgetAccentable()
            }
            .gaugeStyle(.accessoryCircular)
            .tint(tint)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(WidgetFormat.fullLabel(snapshot, now: now))
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "figure.walk")
                    .font(.title3)
                    .widgetAccentable()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(snapshot == nil ? WidgetStrings.openApp : WidgetStrings.start)
        }
    }
}

/// Esquina: cifra en el centro y etiqueta curva ("km · pausado", "km de 22 km", "hace 20 min").
private struct CornerView: View {
    let snapshot: WidgetSnapshot?
    let now: Date
    let tint: Color?

    var body: some View {
        if let snapshot = snapshot, snapshot.isActive {
            let parts = WidgetFormat.distanceParts(snapshot.walkedMeters, snapshot)
            Text(parts.number)
                .font(.title3.monospacedDigit())
                .widgetAccentable()
                .widgetCurvesContent()
                .widgetLabel {
                    Text(WidgetFormat.cornerLabel(snapshot, unit: parts.unit, now: now))
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(WidgetFormat.fullLabel(snapshot, now: now))
        } else {
            Image(systemName: "figure.walk")
                .font(.title3)
                .widgetAccentable()
                .widgetLabel {
                    Text(snapshot == nil ? WidgetStrings.open : WidgetStrings.startShort)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(snapshot == nil ? WidgetStrings.openApp : WidgetStrings.start)
        }
    }
}

/// En línea: "4,2 km · en marcha" / "4,2 km · pausado" / "4,2 km · hace 20 min", o
/// «Iniciar trayecto» con icono.
private struct InlineView: View {
    let snapshot: WidgetSnapshot?
    let now: Date

    var body: some View {
        if let snapshot = snapshot, snapshot.isActive {
            let prefix = snapshot.isDemo ? WidgetStrings.demo + " · " : ""
            Text(prefix + WidgetFormat.distance(snapshot.walkedMeters, snapshot) + " · "
                + WidgetFormat.statusOrAge(snapshot, now: now))
        } else if snapshot != nil {
            Label(WidgetStrings.start, systemImage: "figure.walk")
        } else {
            Text(WidgetStrings.appTitle)
        }
    }
}

/// Rectangular (también Smart Stack): etapa, distancia y estado (o antigüedad de los datos).
private struct RectangularView: View {
    let snapshot: WidgetSnapshot?
    let now: Date

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
                statusLine(snapshot, startedAt: startedAt)
            } else if let snapshot = snapshot {
                header(WidgetStrings.appTitle, isDemo: snapshot.isDemo)
                Label(WidgetStrings.start, systemImage: "figure.walk")
                    .font(.body)
                    .widgetAccentable()
                if let lastName = snapshot.lastStageName {
                    Text(WidgetFormat.lastLine(name: lastName, meters: snapshot.lastStageMeters, snapshot))
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

    /// «en marcha · 1:05:12» (el tiempo total avanza solo) o «pausado»; con datos de más de
    /// 15 min, «hace 20 min» en lugar del tiempo: no se promete frescura.
    @ViewBuilder
    private func statusLine(_ snapshot: WidgetSnapshot, startedAt: Date) -> some View {
        HStack(spacing: 4) {
            Image(systemName: WidgetFormat.statusSymbol(snapshot, now: now))
                .font(.footnote)
                .accessibilityHidden(true)
            if let minutes = WidgetFormat.staleMinutes(snapshot, now: now) {
                Text(WidgetStrings.ago(minutes))
                    .font(.footnote)
                    .accessibilityLabel(WidgetStrings.staleA11y(minutes))
            } else if snapshot.isPaused {
                Text(WidgetStrings.paused)
                    .font(.body)
            } else {
                Text(WidgetStrings.running + " · ")
                    .font(.body)
                    + Text(startedAt, style: .timer)
                    .font(.body.monospacedDigit())
            }
        }
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
    /// A partir de cuánto tiempo sin datos nuevos se marca la instantánea como antigua.
    static let staleAfter: TimeInterval = 15 * 60

    /// Color del progreso a todo color (token "positivo" del tema Negro).
    static var progressColor: Color {
        let rgb = Palette.of(.negro).positive
        return Color(red: Double(rgb.red) / 255, green: Double(rgb.green) / 255, blue: Double(rgb.blue) / 255)
    }

    static func units(_ snapshot: WidgetSnapshot) -> UnitSystem {
        return UnitSystem(rawValue: snapshot.units) ?? .metric
    }

    static func lang(_ snapshot: WidgetSnapshot) -> AppLanguage {
        return AppLanguage(rawValue: snapshot.lang) ?? .es
    }

    /// Distancia con las unidades e idioma del usuario (mismas reglas que la app).
    static func distance(_ meters: Double, _ snapshot: WidgetSnapshot) -> String {
        return UnitFormatter.distance(meters: meters, units: units(snapshot), lang: lang(snapshot))
    }

    /// "4,2 km" → ("4,2", "km").
    static func distanceParts(_ meters: Double, _ snapshot: WidgetSnapshot) -> (number: String, unit: String) {
        let text = distance(meters, snapshot)
        guard let space = text.lastIndex(of: " ") else {
            return (text, "")
        }
        return (String(text[..<space]), String(text[text.index(after: space)...]))
    }

    /// Minutos desde la última instantánea si hay trayecto y pasan de 15; si no, `nil`.
    static func staleMinutes(_ snapshot: WidgetSnapshot, now: Date) -> Int? {
        guard snapshot.isActive else {
            return nil
        }
        let age = now.timeIntervalSince(snapshot.updatedAt)
        guard age.isFinite, age > staleAfter else {
            return nil
        }
        return Int(min(age, 1.0e7) / 60)
    }

    static func statusText(_ snapshot: WidgetSnapshot) -> String {
        return snapshot.isPaused ? WidgetStrings.paused : WidgetStrings.running
    }

    /// Estado o, si los datos son antiguos, "hace X min".
    static func statusOrAge(_ snapshot: WidgetSnapshot, now: Date) -> String {
        if let minutes = staleMinutes(snapshot, now: now) {
            return WidgetStrings.ago(minutes)
        }
        return statusText(snapshot)
    }

    static func statusSymbol(_ snapshot: WidgetSnapshot, now: Date) -> String {
        if staleMinutes(snapshot, now: now) != nil {
            return "clock"
        }
        return snapshot.isPaused ? "pause.circle" : "figure.walk"
    }

    /// "4,2 km de 22 km" o "4,2 km" si no hay plan.
    static func distanceLine(_ snapshot: WidgetSnapshot) -> String {
        let walked = distance(snapshot.walkedMeters, snapshot)
        guard snapshot.plannedMeters > 0 else {
            return walked
        }
        return walked + " " + WidgetStrings.ofPlanned(distance(snapshot.plannedMeters, snapshot))
    }

    /// Etiqueta curva de la esquina: "km · pausado", "km de 22 km" o "hace 20 min" (+ "DEMO").
    static func cornerLabel(_ snapshot: WidgetSnapshot, unit: String, now: Date) -> String {
        var text = unit
        if let minutes = staleMinutes(snapshot, now: now) {
            text += " · " + WidgetStrings.ago(minutes)
        } else if snapshot.isPaused {
            text += " · " + WidgetStrings.paused
        } else if snapshot.plannedMeters > 0 {
            text += " " + WidgetStrings.ofPlanned(distance(snapshot.plannedMeters, snapshot))
        }
        if snapshot.isDemo {
            text += " · " + WidgetStrings.demo
        }
        return text
    }

    /// Etiqueta VoiceOver completa: progreso, estado y antigüedad.
    static func fullLabel(_ snapshot: WidgetSnapshot, now: Date) -> String {
        let walked = distance(snapshot.walkedMeters, snapshot)
        var text: String
        if snapshot.plannedMeters > 0 {
            text = WidgetStrings.progressA11y(walked: walked, planned: distance(snapshot.plannedMeters, snapshot))
        } else {
            text = walked
        }
        text += ". " + statusText(snapshot)
        if let minutes = staleMinutes(snapshot, now: now) {
            text += ". " + WidgetStrings.staleA11y(minutes)
        }
        if snapshot.isDemo {
            text += ". " + WidgetStrings.demoA11y
        }
        return text
    }

    /// "Última: Sarria – Portomarín · 22 km"
    static func lastLine(name: String, meters: Int?, _ snapshot: WidgetSnapshot) -> String {
        var text = WidgetStrings.last + ": " + name
        if let meters = meters {
            text += " · " + distance(Double(meters), snapshot)
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

    /// Demostración: trayecto en pausa, en millas.
    static var demoPausedImperial: WidgetSnapshot {
        let now = Date()
        return WidgetSnapshot(
            stageName: "Sarria – Portomarín",
            startedAt: now.addingTimeInterval(-(80 * 60)),
            walkedMeters: 4_200,
            plannedMeters: 22_000,
            hasFix: true,
            isDemo: true,
            updatedAt: now,
            isPaused: true,
            units: "imperial",
            lang: "en"
        )
    }

    /// Demostración: datos de hace 40 min (la app no ha publicado desde entonces).
    static var demoStale: WidgetSnapshot {
        let now = Date()
        return WidgetSnapshot(
            stageName: "Sarria – Portomarín",
            startedAt: now.addingTimeInterval(-(120 * 60)),
            walkedMeters: 6_300,
            plannedMeters: 22_000,
            hasFix: true,
            isDemo: true,
            updatedAt: now.addingTimeInterval(-(40 * 60))
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

#if DEBUG
#Preview("Rectangular", as: .accessoryRectangular) {
    CaminoStageWidget()
} timeline: {
    CaminoEntry(date: .now, snapshot: .demoActive)
    CaminoEntry(date: .now, snapshot: .demoPausedImperial)
    CaminoEntry(date: .now, snapshot: .demoStale)
    CaminoEntry(date: .now, snapshot: .demoIdle)
    CaminoEntry(date: .now, snapshot: nil)
}

#Preview("Circular", as: .accessoryCircular) {
    CaminoStageWidget()
} timeline: {
    CaminoEntry(date: .now, snapshot: .demoActive)
    CaminoEntry(date: .now, snapshot: .demoPausedImperial)
    CaminoEntry(date: .now, snapshot: .demoIdle)
}

#Preview("En línea", as: .accessoryInline) {
    CaminoStageWidget()
} timeline: {
    CaminoEntry(date: .now, snapshot: .demoActive)
    CaminoEntry(date: .now, snapshot: .demoPausedImperial)
    CaminoEntry(date: .now, snapshot: .demoStale)
    CaminoEntry(date: .now, snapshot: .demoIdle)
    CaminoEntry(date: .now, snapshot: nil)
}

#Preview("Esquina", as: .accessoryCorner) {
    CaminoStageWidget()
} timeline: {
    CaminoEntry(date: .now, snapshot: .demoActive)
    CaminoEntry(date: .now, snapshot: .demoPausedImperial)
    CaminoEntry(date: .now, snapshot: .demoIdle)
}
#endif
