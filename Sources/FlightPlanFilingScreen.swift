import SwiftUI

struct FlightPlanFilingScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var plan = ICAOFlightPlan()
    @State private var routeWeather: RouteWeather?
    @State private var loadingWx = false
    @State private var showShare = false
    @State private var exportText = ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Aéronef") {
                    TextField("Type (ex: C172)", text: $plan.aircraftType)
                        .textInputAutocapitalization(.characters)
                    Picker("Catégorie turbulence", selection: $plan.wakeCategory) {
                        Text("L (Light)").tag("L")
                        Text("M (Medium)").tag("M")
                        Text("H (Heavy)").tag("H")
                        Text("J (Super)").tag("J")
                    }
                    TextField("Vitesse croisière (kt)", text: $plan.cruiseSpeed)
                        .keyboardType(.numberPad)
                }

                Section("Route") {
                    TextField("Départ (ICAO)", text: $plan.departure)
                        .textInputAutocapitalization(.characters)
                    TextField("Arrivée (ICAO)", text: $plan.destination)
                        .textInputAutocapitalization(.characters)
                    TextField("Altitude (ft ou FL)", text: $plan.cruiseAltitude)
                        .textInputAutocapitalization(.characters)
                    TextField("Route (ex: KFPR DCT KMIA)", text: $plan.route)
                        .textInputAutocapitalization(.characters)
                    TextField("Alternate (ICAO)", text: $plan.alternate)
                        .textInputAutocapitalization(.characters)
                }

                Section("Temps & Carburant") {
                    TextField("EET total (HHMM)", text: $plan.totalEET)
                        .keyboardType(.numberPad)
                    TextField("Endurance (HHMM)", text: $plan.endurance)
                        .keyboardType(.numberPad)
                    Stepper("Personnes à bord: \(plan.personsOnBoard)", value: $plan.personsOnBoard, in: 1...10)
                    TextField("Remarques", text: $plan.remarks)
                }

                if let wx = routeWeather {
                    Section("Météo sur la route") {
                        if let worst = wx.worstCategory {
                            HStack {
                                Text("Pire catégorie")
                                Spacer()
                                Text(worst).bold().foregroundStyle(fltColor(worst))
                            }
                        }
                        ForEach(wx.waypoints) { p in
                            if let cat = p.category {
                                HStack {
                                    Text(p.icao).monospaced()
                                    Spacer()
                                    Text(cat).foregroundStyle(fltColor(cat))
                                    if let w = p.wind { Text(w).font(.caption).foregroundStyle(.secondary) }
                                }
                            }
                        }
                    }
                }

                Section {
                    Button { loadRouteWeather() } label: {
                        Label("Charger météo route", systemImage: "cloud.sun")
                    }.disabled(loadingWx)

                    Button { shareICAO() } label: {
                        Label("Partager plan ICAO", systemImage: "square.and.arrow.up")
                    }

                    Button { shareGPX() } label: {
                        Label("Exporter GPX", systemImage: "doc.text")
                    }

                    Button { shareFPL() } label: {
                        Label("Exporter FPL", systemImage: "doc.plaintext")
                    }
                }
            }
            .navigationTitle("Plan de vol ICAO")
            .sheet(isPresented: $showShare) {
                ShareSheet(activityItems: [exportText])
            }
        }
    }

    private func loadRouteWeather() {
        loadingWx = true
        Task {
            let wx = await RouteWeatherService.fetch(for: model.logbook.isEmpty ? [] : [])
            routeWeather = wx
            loadingWx = false
        }
    }

    private func shareICAO() {
        exportText = plan.icaoString
        showShare = true
    }

    private func shareGPX() {
        exportText = GPXExport.export(waypoints: [], route: [])
        showShare = true
    }

    private func shareFPL() {
        exportText = FPLExport.export(plan: plan)
        showShare = true
    }

    private func fltColor(_ cat: String) -> Color {
        switch cat {
        case "VFR": return .green
        case "MVFR": return .blue
        case "IFR": return .red
        case "LIFR": return .purple
        default: return .gray
        }
    }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }
    func updateUIViewController(_ vc: UIActivityViewController, context: Context) {}
}