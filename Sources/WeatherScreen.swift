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
                    ContentUnavailableView("Météo additionnelle",
                        systemImage: "cloud.sun.rain",
                        description: Text("Ajoute un plan de vol pour voir vents en altitude, PIREPs et AIRMETs/SIGMETs."))
                } else {
                    List {
                        if !windsAloft.isEmpty {
                            Section("Vents en altitude") {
                                ForEach(windsAloft.sorted { $0.altitude < $1.altitude }) { w in
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("\(w.icao) • \(w.altitude) ft")
                                                .font(.caption)
                                                .foregroundStyle(Theme.textSecondary)
                                            Text(windText(w))
                                                .font(.system(.body, design: .monospaced))
                                                .foregroundStyle(Theme.textPrimary)
                                        }
                                        Spacer()
                                        if let temp = w.temperature {
                                            Text("\(temp)°C")
                                                .font(.caption.monospacedDigit())
                                                .foregroundStyle(temp < 0 ? .blue : .orange)
                                        }
                                    }
                                }
                            }
                        }

                        if !pireps.isEmpty {
                            Section("PIREPs (rapports pilotes)") {
                                ForEach(pireps) { p in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            if let icao = p.icao {
                                                Text(icao).font(.caption).foregroundStyle(Theme.accent)
                                            }
                                            if let alt = p.altitudeFt {
                                                Text("FL\(alt/100)").font(.caption).foregroundStyle(Theme.textSecondary)
                                            }
                                            if let ac = p.aircraftType {
                                                Text(ac).font(.caption).foregroundStyle(Theme.textTertiary)
                                            }
                                            Spacer()
                                            Text(p.reportTime.formatted(date: .omitted, time: .shortened))
                                                .font(.caption2).foregroundStyle(Theme.textTertiary)
                                        }
                                        Text(p.rawText).font(.caption).foregroundStyle(Theme.textPrimary)
                                        if let turb = p.turbulence, !turb.isEmpty {
                                            Label("Turb: \(turb)", systemImage: "wind")
                                                .font(.caption2).foregroundStyle(.orange)
                                        }
                                        if let ice = p.icing, !ice.isEmpty {
                                            Label("Givrage: \(ice)", systemImage: "snowflake")
                                                .font(.caption2).foregroundStyle(.blue)
                                        }
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }

                        if !airSigmets.isEmpty {
                            Section("AIRMETs / SIGMETs / G-AIRMETs") {
                                ForEach(airSigmets) { a in
                                    VStack(alignment: .leading, spacing: 4) {
                                        HStack {
                                            Text(a.type).font(.caption.bold())
                                                .padding(.horizontal, 6).padding(.vertical, 2)
                                                .background(typeColor(a.type), in: Capsule())
                                                .foregroundStyle(.white)
                                            Text(a.hazard).font(.caption).foregroundStyle(Theme.accent)
                                            if let sev = a.severity {
                                                Text(sev).font(.caption.bold()).foregroundStyle(.red)
                                            }
                                            Spacer()
                                            if let from = a.validFrom, let to = a.validTo {
                                                Text("\(from.formatted(date: .omitted, time: .shortened)) – \(to.formatted(date: .omitted, time: .shortened))")
                                                    .font(.caption2).foregroundStyle(Theme.textTertiary)
                                            }
                                        }
                                        if let from = a.altitudeFrom, let to = a.altitudeTo {
                                            Text("\(from) – \(to) ft MSL").font(.caption2).foregroundStyle(Theme.textSecondary)
                                        }
                                        Text(a.rawText).font(.caption).foregroundStyle(Theme.textPrimary)
                                    }
                                    .padding(.vertical, 2)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Météo Avancée")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }
            }
            .task { load() }
            .onChange(of: model.directTo) { _ in load() }
            .alert("Erreur", isPresented: .constant(error != nil)) {
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

    private func windText(_ w: WindsAloft) -> String {
        let dir = w.direction.map { "\($0)°" } ?? "VRB"
        return "\(dir) \(w.speed) kt"
    }

    private func typeColor(_ type: String) -> Color {
        switch type {
        case "SIGMET": return .red
        case "G-AIRMET": return .orange
        default: return .blue
        }
    }
}