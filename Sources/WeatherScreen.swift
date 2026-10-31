import SwiftUI

struct WeatherScreen: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    @State private var windsAloft: [WindsAloft] = []
    @State private var pireps: [Pirep] = []
    @State private var airSigmets: [AirSigmet] = []
    @State private var loading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if windsAloft.isEmpty && pireps.isEmpty && airSigmets.isEmpty && !loading {
                    ContentUnavailableView(
                        "Météo additionnelle",
                        systemImage: "cloud.sun.rain",
                        description: Text("Ajoute un plan de vol pour voir vents en altitude, PIREPs et AIRMETs/SIGMETs.")
                    )
                } else {
                    List {
                        if !windsAloft.isEmpty {
                            Section("Vents en altitude") {
                                ForEach(windsAloft.sorted { $0.altitude < $1.altitude }) { w in
                                    WindsAloftRow(wind: w)
                                }
                            }
                        }

                        if !pireps.isEmpty {
                            Section("PIREPs (rapports pilotes)") {
                                ForEach(pireps) { p in
                                    PirepRow(pirep: p)
                                }
                            }
                        }

                        if !airSigmets.isEmpty {
                            Section("AIRMETs / SIGMETs / G-AIRMETs") {
                                ForEach(airSigmets) { a in
                                    AirSigmetRow(airsigmet: a)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Météo Avancée")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { load() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(loading)
                }
            }
            .task { load() }
            .onChange(of: model.directTo) { _, _ in load() }
            .alert("Erreur", isPresented: Binding(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }
    }

    private var waypoints: [Airport] {
        var result: [Airport] = []
        if let d = model.directTo, let a = store.airport(d) { result.append(a) }
        return result
    }

    private func load() {
        let wps = waypoints
        guard !wps.isEmpty else { return }
        loading = true
        error = nil
        Task {
            async let winds = WeatherService.windsAloft(for: wps.map(\.id))
            async let p = WeatherService.pireps(lat: wps.first!.coordinate.latitude, lon: wps.first!.coordinate.longitude)
            async let sig = WeatherService.airSigmets()
            let (w, pir, sigm) = await (winds, p, sig)
            windsAloft = w
            pireps = pir
            airSigmets = sigm
            loading = false
        }
    }
}

struct WindsAloftRow: View {
    let wind: WindsAloft

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(wind.icao) · \(wind.altitude) ft")
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                Text(windText(wind))
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(Theme.textPrimary)
            }
            Spacer()
            if let temp = wind.temperature {
                Text("\(temp)°C")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(temp < 0 ? Theme.accent : Theme.orange)
            }
        }
        .padding(.vertical, Theme.spacingXS)
    }

    private func windText(_ w: WindsAloft) -> String {
        let dir = w.direction.map { "\($0)°" } ?? "VRB"
        return "\(dir) \(w.speed) kt"
    }
}

struct PirepRow: View {
    let pirep: Pirep

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                if let icao = pirep.icao {
                    Text(icao)
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.accent)
                }
                if let alt = pirep.altitudeFt {
                    Text("FL\(alt/100)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
                if let ac = pirep.aircraftType {
                    Text(ac)
                        .font(.caption)
                        .foregroundStyle(Theme.textTertiary)
                }
                Spacer()
                Text(pirep.reportTime.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }

            Text(pirep.rawText)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: Theme.spacingM) {
                if let turb = pirep.turbulence, !turb.isEmpty {
                    Label("Turb: \(turb)", systemImage: "wind")
                        .font(.caption2)
                        .foregroundStyle(Theme.orange)
                }
                if let ice = pirep.icing, !ice.isEmpty {
                    Label("Givrage: \(ice)", systemImage: "snowflake")
                        .font(.caption2)
                        .foregroundStyle(Theme.accent)
                }
            }
        }
        .padding(.vertical, Theme.spacingXS)
    }
}

struct AirSigmetRow: View {
    let airsigmet: AirSigmet

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                Text(airsigmet.type)
                    .font(.caption.weight(.bold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(typeColor(airsigmet.type), in: Capsule())
                    .foregroundStyle(.white)

                Text(airsigmet.hazard)
                    .font(.caption)
                    .foregroundStyle(Theme.accent)

                if let sev = airsigmet.severity {
                    Text(sev)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.red)
                }
                Spacer()
                if let from = airsigmet.validFrom, let to = airsigmet.validTo {
                    Text("\(from.formatted(date: .omitted, time: .shortened)) – \(to.formatted(date: .omitted, time: .shortened))")
                        .font(.caption2)
                        .foregroundStyle(Theme.textTertiary)
                }
            }

            if let from = airsigmet.altitudeFrom, let to = airsigmet.altitudeTo {
                Text("\(from) – \(to) ft MSL")
                    .font(.caption2)
                    .foregroundStyle(Theme.textSecondary)
            }

            Text(airsigmet.rawText)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, Theme.spacingXS)
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "SIGMET": return Theme.red
        case "G-AIRMET": return Theme.orange
        default: return Theme.accent
        }
    }
}