import SwiftUI
import CaminoCore
import CaminoDesign

/// Ficha breve de un lugar: categoría, nombre, distancia actual con su calidad y si ya
/// se avisó en la etapa. Sin mapa ni navegación paso a paso.
struct PoiDetailView: View {
    let poiId: String

    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 15)) { context in
            ScrollView {
                VStack(alignment: .leading, spacing: Spacing.s) {
                    if let poi = model.poi(id: poiId) {
                        details(poi, now: context.date)
                    } else {
                        notFound
                    }
                }
            }
        }
        .navigationTitle(L10n.poiTitle)
        .onAppear {
            // Sin etapa en curso: una sola lectura para la distancia actual.
            if model.activeSession == nil {
                model.refreshLocationOnce()
            }
        }
    }

    @ViewBuilder
    private func details(_ poi: Poi, now: Date) -> some View {
        let quality = model.locationQuality(at: now)
        let approximate = quality.isApproximate
        let meters = model.distance(to: poi)
        let category = PoiText.category(poi.category)

        HStack(alignment: .firstTextBaseline, spacing: Spacing.xs) {
            IconView(name: Icon.category(poi.category), color: palette.textSecondary)
            Text(category)
                .typeStyle(.detail)
                .foregroundStyle(palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)

        Text(poi.name)
            .typeStyle(.title)
            .foregroundStyle(palette.textPrimary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityAddTraits(.isHeader)

        Card {
            MetricView(
                label: L10n.poiDistance,
                value: meters.map { PoiText.distance($0, approximate: approximate) },
                spokenValue: meters.map { PoiText.spokenDistance($0, approximate: approximate) },
                size: .hero,
                emptyText: L10n.poiNoLocation
            )
            ForEach(NearbyLocationLine.lines(quality: quality, permission: model.locationPermission)) { line in
                NearbyLocationStatus(line: line)
            }
        }

        if model.wasAlerted(poi.id) {
            StatusLine(symbol: Icon.alert, text: L10n.poiAlerted)
        }

        Text(L10n.nearbyDemoNote)
            .typeStyle(.detail)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, Spacing.s)
    }

    private var notFound: some View {
        VStack(alignment: .leading, spacing: Spacing.s) {
            StatusLine(symbol: Icon.warning, text: L10n.poiNotFound, tone: .warning)
                .accessibilityAddTraits(.isHeader)
            Text(L10n.poiNotFoundExplain)
                .typeStyle(.body)
                .foregroundStyle(palette.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

#if DEBUG
#Preview("negro · datos de demostración") {
    NavigationStack {
        // "p01": Fuente de Barbadelo, de shared/fixtures/pois.json (datos de demostración).
        PoiDetailView(poiId: "p01")
            .themed(.negro)
    }
    .environmentObject(AppModel())
    .environmentObject(ThemeStore())
}

#Preview("perla · lugar no encontrado") {
    NavigationStack {
        PoiDetailView(poiId: "id-antiguo")
            .themed(.perla)
    }
    .environmentObject(AppModel())
    .environmentObject(ThemeStore())
}
#endif
