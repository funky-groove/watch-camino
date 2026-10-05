import SwiftUI
import CaminoCore
import CaminoDesign

/// Ficha breve de un lugar (V1.1 §J): categoría, nombre, distancia actual EN LÍNEA RECTA
/// (no hay rutas) con su calidad, si ya se avisó en la etapa y «Llamar» sólo si el lugar
/// tiene un teléfono válido. Sin mapa ni navegación paso a paso. Datos locales: no requiere
/// conexión.
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
        let display = model.display

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
                label: L10n.poiDistanceStraight,
                value: meters.map { PoiText.distance($0, approximate: approximate, display) },
                spokenValue: meters.map { PoiText.spokenDistance($0, approximate: approximate, display) },
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

        // «Llamar» sólo con teléfono válido (E.164 o 9 dígitos españoles). Los datos actuales
        // no traen teléfonos, así que hoy no aparece. No es una llamada de emergencia.
        if poi.telURL != nil {
            Button {
                model.callPlace(poi)
            } label: {
                HStack(spacing: Spacing.xs) {
                    IconView(name: Icon.phone)
                    Text(L10n.poiCall)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .buttonStyle(SecondaryButtonStyle())
            .accessibilityLabel(L10n.poiCall + ", " + poi.name)
            .accessibilityHint(L10n.poiCallHint)
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
