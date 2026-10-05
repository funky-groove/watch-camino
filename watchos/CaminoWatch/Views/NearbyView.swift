import SwiftUI
import CaminoCore
import CaminoDesign

/// Destino «Lugares» (V1.1 §A, §J): lugares de los datos ordenados por distancia en línea
/// recta a la última ubicación conocida, con filtro mínimo (todos / agua / alojamiento) y la
/// calidad de esa ubicación siempre a la vista. Datos de demostración identificados.
struct NearbyView: View {
    let waterOnly: Bool

    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @State private var filter: PlaceFilter

    init(waterOnly: Bool) {
        self.waterOnly = waterOnly
        _filter = State(initialValue: waterOnly ? .water : .all)
    }

    var body: some View {
        // La antigüedad de la ubicación cambia con el tiempo: se recalcula cada 15 s (sin animación).
        TimelineView(.periodic(from: Date(), by: 15)) { context in
            content(now: context.date)
        }
        .navigationTitle(L10n.placesTitle)
        .onAppear {
            // Sin etapa en curso: una sola lectura, sin seguimiento continuo.
            if model.activeSession == nil {
                model.refreshLocationOnce()
            }
        }
    }

    private func content(now: Date) -> some View {
        let quality = model.locationQuality(at: now)
        let items = model.nearby(filter: filter)
        let denied = model.locationPermission == .denied
        let hasFix = NearbyLocationLine.hasFix(quality)
        let display = model.display

        return ScrollView {
            LazyVStack(alignment: .leading, spacing: Spacing.s) {
                filterPicker

                ForEach(NearbyLocationLine.lines(quality: quality, permission: model.locationPermission)) { line in
                    NearbyLocationStatus(line: line)
                }

                if !hasFix {
                    Text(denied ? L10n.nearbyNoLocationDenied : L10n.nearbyNoLocation)
                        .typeStyle(.body)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if !denied {
                        Button {
                            model.refreshLocationOnce()
                        } label: {
                            HStack(spacing: Spacing.xs) {
                                IconView(name: Icon.location)
                                Text(L10n.nearbyRetry)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }
                        .buttonStyle(SecondaryButtonStyle())
                    }
                } else if items.isEmpty {
                    Text(emptyText)
                        .typeStyle(.body)
                        .foregroundStyle(palette.textPrimary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(items, id: \.poi.id) { item in
                        NavigationLink(value: Route.poi(id: item.poi.id)) {
                            NearbyPoiRow(item: item, approximate: quality.isApproximate, display: display)
                        }
                        .buttonStyle(RowButtonStyle())
                    }
                }

                Text(L10n.nearbyDemoNote)
                    .typeStyle(.detail)
                    .foregroundStyle(palette.textSecondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Spacing.s)
            }
        }
    }

    /// Filtro mínimo (una fila nativa que abre la lista de opciones; ocupa poco en 40 mm).
    private var filterPicker: some View {
        Picker(selection: $filter) {
            ForEach(PlaceFilter.allCases, id: \.self) { option in
                Label(NearbyView.title(option), systemImage: NearbyView.symbol(option))
                    .tag(option)
            }
        } label: {
            Text(L10n.placesFilterLabel)
        }
        .pickerStyle(.navigationLink)
        .frame(minHeight: Target.minimumHeight)
    }

    static func title(_ filter: PlaceFilter) -> String {
        switch filter {
        case .all:
            return L10n.placesFilterAll
        case .water:
            return L10n.placesFilterWater
        case .shelter:
            return L10n.placesFilterShelter
        }
    }

    static func symbol(_ filter: PlaceFilter) -> String {
        switch filter {
        case .all:
            return Icon.places
        case .water:
            return Icon.category(.water)
        case .shelter:
            return Icon.category(.shelter)
        }
    }

    private var emptyText: String {
        let inStage = model.activeSession != nil
        switch filter {
        case .water:
            return inStage ? L10n.nearbyEmptyWaterStage : L10n.nearbyEmptyWaterAny
        case .shelter:
            return inStage ? L10n.placesEmptyShelterStage : L10n.placesEmptyShelterAny
        case .all:
            return inStage ? L10n.nearbyEmptyAllStage : L10n.nearbyEmptyAllAny
        }
    }
}

/// Fila de «Lugares»: icono de categoría, nombre (varias líneas si hace falta) y
/// "categoría · distancia en línea recta" con cifras monoespaciadas.
private struct NearbyPoiRow: View {
    let item: PoiAlert
    let approximate: Bool
    let display: UnitDisplay

    @Environment(\.palette) private var palette

    var body: some View {
        let category = PoiText.category(item.poi.category)
        let distance = PoiText.straightLine(item.distanceMeters, approximate: approximate, display)
        let spokenDistance = PoiText.spokenStraightLine(item.distanceMeters, approximate: approximate, display)

        return HStack(alignment: .center, spacing: Spacing.s) {
            IconView(name: Icon.category(item.poi.category))
            VStack(alignment: .leading, spacing: 0) {
                Text(item.poi.name)
                    .typeStyle(.body)
                    .foregroundStyle(palette.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(category + " · " + distance)
                    .font(TypeStyle.detail.font.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
            Image(systemName: Icon.chevron)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(palette.textSecondary)
                .accessibilityHidden(true)
        }
        .padding(.vertical, Spacing.s)
        .frame(maxWidth: .infinity, minHeight: Target.minimumHeight, alignment: .leading)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(item.poi.name)
        .accessibilityValue(category + ", " + spokenDistance)
    }
}

/// Muestra una `NearbyLocationLine` con su lectura para VoiceOver.
struct NearbyLocationStatus: View {
    let line: NearbyLocationLine

    var body: some View {
        StatusLine(symbol: line.symbol, text: line.text, tone: line.tone)
            .accessibilityLabel(line.spoken)
    }
}

/// Línea de estado de la ubicación ("ubicación ±15 m · hace 2 min"), compartida por
/// "Cerca" y la ficha de lugar. Texto visible + variante hablada; el color nunca va solo.
struct NearbyLocationLine: Identifiable {
    let id: String
    let symbol: String
    let text: String
    let spoken: String
    let tone: StatusLine.Tone

    /// Una línea por la calidad y, si el permiso está denegado y aún queda una posición
    /// antigua, otra crítica con el permiso.
    static func lines(quality: LocationQuality, permission: LocationPermission) -> [NearbyLocationLine] {
        var result: [NearbyLocationLine] = []
        if hasFix(quality) || permission != .denied {
            result.append(of(quality))
        }
        if permission == .denied {
            result.append(denied)
        }
        return result
    }

    /// Si hay alguna posición (aunque sea imprecisa o antigua).
    static func hasFix(_ quality: LocationQuality) -> Bool {
        switch quality {
        case .none:
            return false
        case .good, .imprecise, .stale:
            return true
        }
    }

    static var denied: NearbyLocationLine {
        return NearbyLocationLine(
            id: "denied",
            symbol: Icon.locationOff,
            text: L10n.nearbyLocationDenied,
            spoken: L10n.nearbyLocationDenied,
            tone: .critical
        )
    }

    static func of(_ quality: LocationQuality) -> NearbyLocationLine {
        switch quality {
        case .none:
            return NearbyLocationLine(
                id: "quality",
                symbol: Icon.location,
                text: L10n.nearbyLocationSearching,
                spoken: L10n.nearbyLocationSearching,
                tone: .neutral
            )
        case .good(let accuracy, let age):
            let meters = roundedMeters(accuracy)
            return NearbyLocationLine(
                id: "quality",
                symbol: Icon.location,
                text: L10n.nearbyLocationAccuracy(meters) + " · " + ageText(age),
                spoken: L10n.nearbySpokenAccuracy(meters) + ", " + spokenAge(age),
                tone: .neutral
            )
        case .imprecise(let accuracy, _):
            let meters = roundedMeters(accuracy)
            return NearbyLocationLine(
                id: "quality",
                symbol: Icon.warning,
                text: L10n.nearbyLocationImprecise(meters),
                spoken: L10n.nearbySpokenImprecise(meters),
                tone: .warning
            )
        case .stale(_, let age):
            return NearbyLocationLine(
                id: "quality",
                symbol: Icon.time,
                text: L10n.nearbyLocationStale + ", " + ageText(age),
                spoken: L10n.nearbyLocationStale + ", " + spokenAge(age),
                tone: .warning
            )
        }
    }

    private static func roundedMeters(_ accuracy: Double) -> Int {
        guard accuracy.isFinite, accuracy > 0 else {
            return 0
        }
        return Int(min(accuracy, 1.0e6).rounded())
    }

    static func ageText(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes < 1 {
            return L10n.nearbyAgeNow
        }
        if minutes < 60 {
            return L10n.nearbyAgeMinutes(minutes)
        }
        return L10n.nearbyAgeHours(minutes / 60)
    }

    static func spokenAge(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes < 1 {
            return L10n.nearbySpokenAgeNow
        }
        if minutes < 60 {
            return L10n.nearbySpokenAgo(L10n.spokenMinutes(minutes))
        }
        return L10n.nearbySpokenAgo(L10n.spokenHours(minutes / 60))
    }
}

#if DEBUG
#Preview("negro · datos de demostración") {
    NavigationStack {
        NearbyView(waterOnly: true)
            .themed(.negro)
    }
    .environmentObject(AppModel())
    .environmentObject(ThemeStore())
}

#Preview("perla · datos de demostración") {
    NavigationStack {
        NearbyView(waterOnly: false)
            .themed(.perla)
    }
    .environmentObject(AppModel())
    .environmentObject(ThemeStore())
}
#endif
