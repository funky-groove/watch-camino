import SwiftUI
import CaminoCore
import CaminoDesign

/// Pantalla de emergencia. Se abre con un toque en «SOS» y se cierra con el botón atrás
/// del sistema (la pantalla anterior se conserva tal cual, con su desplazamiento).
///
/// - Acción principal: «Llamar al 112». Entrega `tel:112` al sistema, que pide confirmación;
///   sin confirmación propia, cuenta atrás ni pulsación prolongada.
/// - Mensajes honestos: la app sólo sabe que pidió la llamada, nunca que se conectó.
/// - Ubicación: la que ya hay (no pide permiso ni espera al GPS); no se envía a ningún sitio.
/// - No pausa ni finaliza el trayecto. Funciona sin sesión y sin backend.
struct SOSView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.palette) private var palette
    @State private var result: DialResult?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Spacing.s) {
                Button {
                    result = model.requestEmergencyCall()
                } label: {
                    HStack(spacing: Spacing.xs) {
                        IconView(name: Icon.phone)
                        Text(L10n.sosCall)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .buttonStyle(EmergencyCallButtonStyle())
                .accessibilityHint(L10n.sosCallHint)

                if let result = result {
                    resultLine(result)
                }

                detailText(L10n.sosScope)

                if model.usesSimulatedDialer {
                    DemoBadge()
                    detailText(L10n.sosDemoNote)
                }

                SectionLabel(text: L10n.sosLocationSection)
                    .padding(.top, Spacing.s)
                // La antigüedad cambia con el tiempo: se recalcula cada 15 s (sin animación).
                TimelineView(.periodic(from: Date(), by: 15)) { context in
                    locationBlock(model.emergencyLocation(at: context.date))
                }
                detailText(L10n.sosLocationNotSent)

                Hairline()
                    .padding(.top, Spacing.s)
                SectionLabel(text: L10n.sosNativeSection)
                StatusLine(symbol: Icon.info, text: L10n.sosNativeHelp)
                StatusLine(symbol: Icon.satellite, text: L10n.sosSatellite)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .navigationTitle(L10n.sosTitle)
        .onAppear {
            // Sólo si el permiso ya está concedido; nunca se pide desde aquí.
            model.refreshLocationIfAuthorized()
        }
    }

    // MARK: - Resultado de la petición

    private func resultLine(_ result: DialResult) -> some View {
        switch result {
        case .handedToSystem:
            // Con el marcador simulado (DEMO) no se ha pedido nada al sistema.
            if model.usesSimulatedDialer {
                return StatusLine(symbol: Icon.info, text: L10n.sosSimulated)
            }
            return StatusLine(symbol: Icon.phone, text: L10n.sosHandedToSystem)
        case .failed:
            return StatusLine(symbol: Icon.warning, text: L10n.sosFailed, tone: .critical)
        }
    }

    // MARK: - Ubicación

    @ViewBuilder
    private func locationBlock(_ summary: EmergencyLocationSummary) -> some View {
        VStack(alignment: .leading, spacing: Spacing.xxs) {
            statusText(summary)
            if let lat = summary.latitude, let lon = summary.longitude {
                coordinates(lat: lat, lon: lon, summary: summary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func statusText(_ summary: EmergencyLocationSummary) -> some View {
        let text: String
        let tone: StatusLine.Tone
        let symbol: String
        switch summary.status {
        case .current:
            text = L10n.sosLocationCurrent
            tone = .neutral
            symbol = Icon.location
        case .lastKnown:
            text = L10n.sosLocationLastKnown
            tone = .neutral
            symbol = Icon.time
        case .stale:
            text = L10n.sosLocationStale
            tone = .warning
            symbol = Icon.time
        case .noSignal:
            text = L10n.sosLocationNoSignal
            tone = .warning
            symbol = Icon.locationOff
        case .permissionDenied:
            text = L10n.sosLocationDenied
            tone = .warning
            symbol = Icon.locationOff
        }
        return VStack(alignment: .leading, spacing: Spacing.xxs) {
            StatusLine(symbol: symbol, text: text, tone: tone)
            // Queda una posición anterior pero ya no hay permiso: también se dice.
            if summary.permissionDenied && summary.status != .permissionDenied {
                StatusLine(symbol: Icon.locationOff, text: L10n.sosLocationDenied, tone: .warning)
            }
        }
    }

    /// "42.78080° N" / "7.41410° O" en cifras grandes y "±8 m · hace 2 min" debajo.
    private func coordinates(
        lat: EmergencyCoordinate,
        lon: EmergencyCoordinate,
        summary: EmergencyLocationSummary
    ) -> some View {
        let latText = lat.degrees + "° " + L10n.sosHemisphereLetter(lat.hemisphere)
        let lonText = lon.degrees + "° " + L10n.sosHemisphereLetter(lon.hemisphere)
        var details: [String] = []
        var spokenDetails: [String] = []
        if let accuracy = summary.accuracyMeters {
            details.append(L10n.sosAccuracy(accuracy))
            spokenDetails.append(L10n.sosSpokenAccuracy(accuracy))
        }
        if let age = summary.ageSeconds {
            details.append(SOSView.ageText(age))
            spokenDetails.append(SOSView.spokenAge(age))
        }
        let spoken = L10n.sosLatitude + " " + lat.degrees + " " + L10n.sosHemisphereSpoken(lat.hemisphere)
            + ", " + L10n.sosLongitude + " " + lon.degrees + " " + L10n.sosHemisphereSpoken(lon.hemisphere)
        let detailLine = details.joined(separator: " · ")
        return VStack(alignment: .leading, spacing: 0) {
            Text(verbatim: latText)
                .typeStyle(.metric)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(verbatim: lonText)
                .typeStyle(.metric)
                .foregroundStyle(palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if !detailLine.isEmpty {
                Text(verbatim: detailLine)
                    .font(TypeStyle.detail.font.monospacedDigit())
                    .foregroundStyle(palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(spoken)
        .accessibilityValue(spokenDetails.joined(separator: ", "))
    }

    private static func ageText(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes < 1 {
            return L10n.nearbyAgeNow
        }
        if minutes < 60 {
            return L10n.nearbyAgeMinutes(minutes)
        }
        return L10n.nearbyAgeHours(minutes / 60)
    }

    private static func spokenAge(_ seconds: Int) -> String {
        let minutes = max(0, seconds) / 60
        if minutes < 1 {
            return L10n.nearbySpokenAgeNow
        }
        if minutes < 60 {
            return L10n.nearbySpokenAgo(L10n.spokenMinutes(minutes))
        }
        return L10n.nearbySpokenAgo(L10n.spokenHours(minutes / 60))
    }

    private func detailText(_ text: String) -> some View {
        Text(text)
            .typeStyle(.detail)
            .foregroundStyle(palette.textSecondary)
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }
}

#if DEBUG
// Datos de demostración. Los previews usan el marcador del entorno: no se pulsa nada.
#Preview("negro · datos de demostración") {
    NavigationStack {
        SOSView()
            .themed(.negro)
    }
    .environmentObject(AppModel())
}

#Preview("perla · datos de demostración") {
    NavigationStack {
        SOSView()
            .themed(.perla)
    }
    .environmentObject(AppModel())
}
#endif
