import SwiftUI

struct AirportDetailView: View {
    let airport: Airport
    let runways: [Runway]
    let frequencies: [Frequency]

    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationManager
    @Environment(\.dismiss) private var dismiss
    @State private var wx: AirportWeather?
    @State private var wxLoading = true

    var body: some View {
        NavigationStack {
            List {
                weatherSection

                Section {
                    Button {
                        model.directTo = airport.id
                        dismiss()
                    } label: {
                        Label("Direct to — mettre au plan", systemImage: "location.north.line.fill")
                    }
                }

                Section {
                    LabeledContent("Identifiant", value: airport.id)
                    if let iata = airport.iata { LabeledContent("IATA", value: iata) }
                    if let m = airport.municipality { LabeledContent("Ville", value: m) }
                    if let e = airport.elevationFt { LabeledContent("Élévation", value: "\(e) ft") }
                    if let c = location.coordinate {
                        let nm = Int(airport.distanceNM(to: c).rounded())
                        let crs = Haversine.trueCourse(c, airport.coordinate)
                        LabeledContent("Depuis ta position",
                                       value: "\(nm) NM · \(String(format: "%03d", crs))°T")
                    }
                    LabeledContent("Type", value: airport.type.replacingOccurrences(of: "_", with: " "))
                }

                Section("Pistes (\(runways.count))") {
                    if runways.isEmpty {
                        Text("Aucune donnée").foregroundStyle(.secondary)
                    }
                    ForEach(runways.filter { !$0.closed }) { r in
                        HStack {
                            Text(r.name).font(.headline.monospaced())
                            Spacer()
                            VStack(alignment: .trailing, spacing: 2) {
                                if let l = r.lengthFt {
                                    Text("\(l) ft").font(.subheadline.monospacedDigit())
                                }
                                Text([r.surface, r.lighted ? "balisée" : nil]
                                        .compactMap { $0 }.joined(separator: " · "))
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                Section("Fréquences (\(frequencies.count))") {
                    if frequencies.isEmpty {
                        Text("Aucune donnée").foregroundStyle(.secondary)
                    }
                    ForEach(frequencies) { f in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(f.type).font(.headline)
                                if !f.description.isEmpty {
                                    Text(f.description).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Text(f.mhz).font(.subheadline.monospacedDigit())
                        }
                    }
                }
            }
            .navigationTitle(airport.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { model.toggleFavorite(airport.id) } label: {
                        Image(systemName: model.isFavorite(airport.id) ? "star.fill" : "star")
                            .foregroundStyle(model.isFavorite(airport.id) ? .yellow : .secondary)
                    }
                }
            }
            .task {
                wx = await WeatherService.fetch(icao: airport.id)
                wxLoading = false
            }
        }
    }

    @ViewBuilder private var weatherSection: some View {
        Section("Météo") {
            if wxLoading {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Chargement METAR/TAF…").foregroundStyle(.secondary)
                }
            } else if let wx {
                if let cat = wx.fltCat {
                    HStack {
                        Text(cat).font(.caption.bold()).foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(fltColor(cat), in: Capsule())
                        Spacer()
                        if let t = wx.tempC, let d = wx.dewpC {
                            Text("\(t)°/\(d)°C").foregroundStyle(.secondary)
                        }
                    }
                    if let age = wx.ageText {
                        Text("Observé \(age)").font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let w = wx.windText { LabeledContent("Vent", value: w) }
                if let v = wx.visib { LabeledContent("Visi", value: v) }
                if let a = wx.altimInHg { LabeledContent("Calage", value: a) }
                if let raw = wx.rawMetar {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("METAR").font(.caption2).foregroundStyle(.secondary)
                        Text(raw).font(.caption.monospaced())
                    }
                }
                if let taf = wx.rawTaf {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("TAF").font(.caption2).foregroundStyle(.secondary)
                        Text(taf).font(.caption.monospaced())
                    }
                }
            } else {
                Text("Météo indisponible").foregroundStyle(.secondary)
            }
        }
    }

    private func fltColor(_ cat: String) -> Color {
        switch cat {
        case "VFR":  return .green
        case "MVFR": return .blue
        case "IFR":  return .red
        case "LIFR": return .purple
        default:     return .gray
        }
    }
}
