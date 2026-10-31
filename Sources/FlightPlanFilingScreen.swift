import SwiftUI

struct FlightPlanFilingScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var plan = ICAOFlightPlan()
    @State private var routeWeather: RouteWeather?
    @State private var loadingWx = false
    @State private var showShare = false
    @State private var exportText = ""
    @State private var activeTab = 0

    var body: some View {
        NavigationStack {
            Form {
                Section("Aéronef") {
                    ProfileTextField(
                        title: "Type",
                        text: $plan.aircraftType,
                        placeholder: "C172",
                        systemImage: "airplane",
                        capitalization: .characters
                    )

                    Picker("Catégorie turbulence", selection: $plan.wakeCategory) {
                        Text("L (Light)").tag("L")
                        Text("M (Medium)").tag("M")
                        Text("H (Heavy)").tag("H")
                        Text("J (Super)").tag("J")
                    }

                    ProfileTextField(
                        title: "Vitesse croisière",
                        text: $plan.cruiseSpeed,
                        placeholder: "110",
                        systemImage: "speedometer",
                        keyboard: .numberPad
                    )
                }

                Section("Route") {
                    ProfileTextField(
                        title: "Départ",
                        text: $plan.departure,
                        placeholder: "KFPR",
                        systemImage: "airplane.departure",
                        capitalization: .characters
                    )

                    ProfileTextField(
                        title: "Arrivée",
                        text: $plan.destination,
                        placeholder: "KMIA",
                        systemImage: "airplane.arrival",
                        capitalization: .characters
                    )

                    ProfileTextField(
                        title: "Altitude",
                        text: $plan.cruiseAltitude,
                        placeholder: "5000",
                        systemImage: "altitude",
                        capitalization: .characters
                    )

                    ProfileTextField(
                        title: "Route",
                        text: $plan.route,
                        placeholder: "KFPR DCT KMIA",
                        systemImage: "point.topleft.down.curvedto.point.bottomright.forward",
                        capitalization: .characters
                    )

                    ProfileTextField(
                        title: "Alternate",
                        text: $plan.alternate,
                        placeholder: "KTPA",
                        systemImage: "airplane.circle",
                        capitalization: .characters
                    )
                }

                Section("Temps & Carburant") {
                    ProfileTextField(
                        title: "EET total",
                        text: $plan.totalEET,
                        placeholder: "0230",
                        systemImage: "clock",
                        keyboard: .numberPad
                    )

                    ProfileTextField(
                        title: "Endurance",
                        text: $plan.endurance,
                        placeholder: "0400",
                        systemImage: "fuelpump",
                        keyboard: .numberPad
                    )

                    Stepper("Personnes à bord: \(plan.personsOnBoard)", value: $plan.personsOnBoard, in: 1...10)
                        .padding(.vertical, Theme.spacingXS)

                    ProfileTextField(
                        title: "Remarques",
                        text: $plan.remarks,
                        placeholder: "RMK/...",
                        systemImage: "note.text"
                    )
                }

                if let wx = routeWeather {
                    Section("Météo sur la route") {
                        if let worst = wx.worstCategory {
                            HStack {
                                Label("Pire catégorie", systemImage: "exclamationmark.triangle.fill")
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text(worst)
                                    .font(.headline.monospacedDigit())
                                    .foregroundStyle(Theme.category(worst))
                            }
                            .padding(.vertical, Theme.spacingXS)
                        }

                        ForEach(wx.waypoints) { point in
                            if let cat = point.category {
                                HStack {
                                    Text(point.icao)
                                        .font(.subheadline.monospaced())
                                        .foregroundStyle(Theme.textPrimary)
                                    Spacer()
                                    Text(cat)
                                        .font(.subheadline.weight(.medium))
                                        .foregroundStyle(Theme.category(cat))
                                    if let wind = point.wind {
                                        Text(wind)
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(Theme.textSecondary)
                                    }
                                }
                                .padding(.vertical, Theme.spacingXS)
                            }
                        }
                    }
                }

                Section {
                    Button { loadRouteWeather() } label: {
                        Label {
                            Text("Charger météo route")
                        } icon: {
                            if loadingWx {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "cloud.sun")
                            }
                        }
                    }
                    .disabled(loadingWx)

                    Divider()

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
}

struct ProfileTextField: View {
    let title: String
    @Binding var text: String
    let placeholder: String
    let systemImage: String
    var capitalization: TextInputAutocapitalization = .never
    var keyboard: UIKeyboardType = .default

    var body: some View {
        LabeledContent {
            TextField(placeholder, text: $text)
                .textInputAutocapitalization(capitalization)
                .keyboardType(keyboard)
                .multilineTextAlignment(.trailing)
                .font(.subheadline.monospacedDigit())
        } label: {
            Label(title, systemImage: systemImage)
                .foregroundStyle(Theme.textPrimary)
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