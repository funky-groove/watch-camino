import SwiftUI
import Charts
import CaminoCore
import CaminoDesign

/// Perfil de altitud REGISTRADO (V1.1 §B-C, §F): distancia × altitud con Swift Charts.
///
/// - Sólo lo recorrido: no se dibuja relieve futuro (no hay ruta con elevación verificada).
/// - Los tramos con `gapBefore` no se unen: cada tramo es una serie (`series:`) distinta.
/// - Ejes mínimos con unidades del usuario; sin animación.
/// - VoiceOver lee un resumen ("perfil de 4,2 km, de 412 m a 448 m"), no los puntos.
struct ProfileChart: View {
    let samples: [ProfileSample]
    let display: UnitDisplay
    var height: CGFloat = 64

    @Environment(\.palette) private var palette

    struct Point: Identifiable {
        let id: Int
        /// km o mi.
        let x: Double
        /// m o ft.
        let y: Double
        /// Tramo (serie) al que pertenece.
        let segment: String
    }

    var body: some View {
        let points = ProfileChart.points(samples, units: display.units)
        let isolated = ProfileChart.isolatedPoints(points)
        let yDomain = ProfileChart.yDomain(points)
        let xMax = max(points.last?.x ?? 0, 0.1)
        return Chart {
            ForEach(points) { point in
                LineMark(
                    x: .value("distance", point.x),
                    y: .value("altitude", point.y),
                    series: .value("segment", point.segment)
                )
                .foregroundStyle(palette.positive)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
            }
            // Un tramo de una sola muestra no tiene línea: se marca con un punto.
            ForEach(isolated) { point in
                PointMark(
                    x: .value("distance", point.x),
                    y: .value("altitude", point.y)
                )
                .foregroundStyle(palette.positive)
                .symbolSize(12)
            }
        }
        .chartXScale(domain: 0...xMax)
        .chartYScale(domain: yDomain)
        // Ejes legibles: etiquetas en `textSecondary` (no el gris por defecto de Charts) y
        // rejilla `hairline`. En X, `.aligned` mantiene la primera y la última etiqueta dentro
        // del área (antes la última se cortaba en el borde). La unidad de Y va arriba y en
        // horizontal (en vertical, a la izquierda, quedaba girada y recortada).
        .chartXAxis {
            AxisMarks(preset: .aligned, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(palette.hairline)
                AxisValueLabel {
                    Text(verbatim: axisNumber(value.as(Double.self) ?? 0, decimals: xMax < 10 ? 1 : 0))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                AxisGridLine()
                    .foregroundStyle(palette.hairline)
                AxisValueLabel {
                    Text(verbatim: axisNumber(value.as(Double.self) ?? 0, decimals: 0))
                        .foregroundStyle(palette.textSecondary)
                }
            }
        }
        .chartXAxisLabel(position: .bottom, alignment: .trailing) {
            Text(verbatim: display.units == .metric ? "km" : "mi")
                .foregroundStyle(palette.textSecondary)
        }
        .chartYAxisLabel(position: .top, alignment: .leading) {
            Text(verbatim: display.units == .metric ? "m" : "ft")
                .foregroundStyle(palette.textSecondary)
        }
        .frame(height: height)
        .transaction { transaction in
            transaction.animation = nil
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.profileSection)
        .accessibilityValue(ProfileChart.spokenSummary(samples, display: display))
    }

    /// Número de eje con el separador decimal del idioma.
    private func axisNumber(_ value: Double, decimals: Int) -> String {
        guard value.isFinite else {
            return ""
        }
        if decimals == 0 {
            return String(Int(value.rounded()))
        }
        let tenths = Int((abs(value) * 10).rounded())
        let sign = value < 0 && tenths > 0 ? "-" : ""
        return sign + String(tenths / 10) + display.lang.decimalSeparator + String(tenths % 10)
    }

    // MARK: - Datos

    static func points(_ samples: [ProfileSample], units: UnitSystem) -> [Point] {
        let xFactor = units == .metric ? 1.0 / 1000.0 : 1.0 / UnitFormatter.metersPerMile
        let yFactor = units == .metric ? 1.0 : UnitFormatter.feetPerMeter
        var segment = 0
        var result: [Point] = []
        result.reserveCapacity(samples.count)
        for (index, sample) in samples.enumerated() {
            guard sample.d.isFinite, sample.alt.isFinite else {
                continue
            }
            if sample.gapBefore && index > 0 {
                segment += 1
            }
            result.append(Point(id: index, x: sample.d * xFactor, y: sample.alt * yFactor, segment: "s\(segment)"))
        }
        return result
    }

    /// Muestras que son el único punto de su tramo.
    static func isolatedPoints(_ points: [Point]) -> [Point] {
        var counts: [String: Int] = [:]
        for point in points {
            counts[point.segment, default: 0] += 1
        }
        return points.filter { counts[$0.segment] == 1 }
    }

    /// Dominio de altitud con margen (nunca desde 0: el relieve se vería plano).
    static func yDomain(_ points: [Point]) -> ClosedRange<Double> {
        guard let low = points.map({ $0.y }).min(), let high = points.map({ $0.y }).max() else {
            return 0...10
        }
        let pad = max(5, (high - low) * 0.1)
        return (low - pad)...(high + pad)
    }

    // MARK: - Resumen textual

    /// "perfil de 4,2 km, de 412 m a 448 m"; con menos de 2 muestras, "aún no hay perfil".
    static func summary(_ samples: [ProfileSample], display: UnitDisplay) -> String {
        guard let parts = summaryParts(samples) else {
            return L10n.profileEmpty
        }
        return L10n.profileSummary(
            distance: display.distance(parts.distance),
            low: display.elevation(parts.low),
            high: display.elevation(parts.high)
        )
    }

    static func spokenSummary(_ samples: [ProfileSample], display: UnitDisplay) -> String {
        guard let parts = summaryParts(samples) else {
            return L10n.profileEmpty
        }
        return L10n.profileSummary(
            distance: display.spokenDistance(parts.distance),
            low: display.spokenElevation(parts.low),
            high: display.spokenElevation(parts.high)
        )
    }

    private static func summaryParts(_ samples: [ProfileSample]) -> (distance: Double, low: Double, high: Double)? {
        let valid = samples.filter { $0.d.isFinite && $0.alt.isFinite }
        guard valid.count >= 2, let last = valid.last,
              let low = valid.map({ $0.alt }).min(), let high = valid.map({ $0.alt }).max() else {
            return nil
        }
        return (last.d, low, high)
    }
}

/// Bloque de perfil: gráfica + resumen visible, o el texto de "sin perfil".
struct ProfileBlock: View {
    let samples: [ProfileSample]
    let display: UnitDisplay
    var height: CGFloat = 64
    var emptyText: String = L10n.profileEmpty

    @Environment(\.palette) private var palette

    var body: some View {
        VStack(alignment: .leading, spacing: Spacing.xs) {
            if samples.count >= 2 {
                ProfileChart(samples: samples, display: display, height: height)
                Text(ProfileChart.summary(samples, display: display))
                    .typeStyle(.detail)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityHidden(true)
            } else {
                StatusLine(symbol: Icon.profile, text: emptyText)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
