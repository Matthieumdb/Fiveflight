import SwiftUI
import CoreLocation

// MARK: - Flights (ForeFlight "Flights" view: Edit · Navlog · Briefing)

struct FlightPlanScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore
    @State private var showSearch = false
    @State private var showSavedPlans = false
    @State private var page: Page = .edit

    enum Page: String, CaseIterable, Identifiable {
        case edit = "Modifier", navlog = "Navlog", briefing = "Briefing"
        var id: String { rawValue }
    }

    private var exportPoints: [FlightExport.Point] {
        model.waypoints.map { FlightExport.Point(name: $0.id, coordinate: $0.coordinate) }
    }

    private var title: String {
        guard let a = model.waypoints.first else { return "Vols" }
        guard model.waypoints.count >= 2, let b = model.waypoints.last else { return a.id }
        return "\(a.id) → \(b.id)"
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if model.waypoints.count >= 2 {
                    FlightSummaryStrip()
                    Picker("Page", selection: $page) {
                        ForEach(Page.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(FF.bar)
                }
                switch (model.waypoints.isEmpty, page) {
                case (true, _):
                    ContentUnavailableView {
                        Label("Aucun vol", systemImage: "airplane.departure")
                    } description: {
                        Text("Ajoutez un départ et une destination, ou tracez la route sur la carte.")
                    } actions: {
                        Button("Ajouter un aéroport") { showSearch = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                case (false, .edit):
                    FlightEditPage(showSearch: $showSearch)
                case (false, .navlog):
                    NavlogTable()
                case (false, .briefing):
                    RouteBriefingScreen(embedded: true)
                }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Menu {
                        Button("Enregistrer ce vol", systemImage: "square.and.arrow.down") { model.savePlan() }
                            .disabled(model.waypoints.count < 2)
                        Button("Vols enregistrés", systemImage: "folder") { showSavedPlans = true }
                        if model.waypoints.count >= 2 {
                            let name = model.waypoints.map(\.id).joined(separator: "-")
                            if let gpx = FlightExport.gpx(name: name, route: exportPoints, track: model.track) {
                                ShareLink("Exporter en GPX", item: gpx)
                            }
                            if let kml = FlightExport.kml(name: name, route: exportPoints, track: model.track) {
                                ShareLink("Exporter en KML", item: kml)
                            }
                            ShareLink("Partager le navlog", item: NavlogText.make(model: model))
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                    }
                }
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if model.waypoints.count >= 2 {
                        Button("Carte") { showOnMap() }
                    }
                    Button { showSearch = true } label: { Image(systemName: "plus") }
                }
            }
            .sheet(isPresented: $showSavedPlans) { SavedPlansSheet() }
            .sheet(isPresented: $showSearch) {
                SearchSheet(nearest: store.nearest(to: model.userLocation ?? AppModel.homeCoordinate, limit: 20), onSelect: { airport in
                    model.addWaypoint(airport)
                })
            }
        }
    }
}

extension FlightPlanScreen {
    /// ForeFlight "Send to Maps": frame the whole route on the map tab.
    fileprivate func showOnMap() {
        let lats = model.waypoints.map(\.coordinate.latitude), lons = model.waypoints.map(\.coordinate.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(), let minLon = lons.min(), let maxLon = lons.max() else { return }
        model.moveMap(to: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                      span: max(maxLat - minLat, maxLon - minLon) * 1.4 + 0.2)
        FFRouter.shared.tab = .maps
    }
}

/// Distance · ETE · ETA · fuel · wind, on the charcoal bar under the title (ForeFlight flight summary).
struct FlightSummaryStrip: View {
    @EnvironmentObject private var model: AppModel

    private var windText: String {
        let legs = model.navlog
        guard model.navlogHasWinds, !legs.isEmpty else { return "—" }
        let total = legs.reduce(0) { $0 + $1.distanceNM }
        guard total > 0 else { return "—" }
        // Average head (−) / tail (+) component weighted by distance, as ForeFlight's "Wind" box.
        let avg = legs.reduce(0.0) { $0 + Double($1.headwind ?? 0) * $1.distanceNM } / total
        let v = Int(avg.rounded())
        return v == 0 ? "0" : (v > 0 ? "-\(v)" : "+\(-v)")
    }

    var body: some View {
        FFDataStrip(items: [
            ("Dist", String(format: "%.0f nm", model.totalDistanceNM)),
            ("ETE", ffDuration(model.totalTimeMinutes)),
            ("ETA", model.arrivalTime.formatted(date: .omitted, time: .shortened)),
            ("Carb", String(format: "%.1f", model.totalFuelGallons)),
            ("Vent", windText)
        ])
    }
}

/// "Modifier": route, aircraft, departure time, performance, profile.
private struct FlightEditPage: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var routingEngine: RoutingEngine
    @EnvironmentObject private var airspaceManager: AirspaceDataManager
    @Binding var showSearch: Bool

    var body: some View {
        List {
            Section {
                ForEach(Array(model.waypoints.enumerated()), id: \.element.id) { index, airport in
                    FlightPlanWaypointRow(index: index, airport: airport, totalCount: model.waypoints.count)
                }
                .onDelete { model.waypoints.remove(atOffsets: $0) }
                .onMove { model.waypoints.move(fromOffsets: $0, toOffset: $1) }
                Button { showSearch = true } label: {
                    Label("Ajouter un point", systemImage: "plus.circle.fill")
                }
            } header: {
                HStack {
                    FFHeader("Route")
                    Spacer()
                    EditButton().font(.caption.weight(.semibold))
                }
            }

            Section {
                Picker(selection: Binding(
                    get: { model.selectedAircraft?.id },
                    set: { id in
                        model.selectedAircraft = model.aircraftProfiles.first { $0.id == id }
                        if let a = model.selectedAircraft {
                            model.cruiseGS = a.cruiseSpeed
                            model.fuelBurn = a.fuelBurn
                        }
                    })) {
                    Text("Aucun").tag(UUID?.none)
                    ForEach(model.aircraftProfiles) { a in Text("\(a.name) · \(a.type)").tag(Optional(a.id)) }
                } label: {
                    Label("Avion", systemImage: "airplane")
                }
                Stepper(value: $model.cruiseAlt, in: 500...17500, step: 500) {
                    valueRow("Altitude", "\(model.cruiseAlt) ft", icon: "arrow.up.to.line")
                }
                Stepper(value: $model.cruiseGS, in: 40...500, step: 5) {
                    valueRow("Vitesse propre (TAS)", "\(Int(model.cruiseGS)) kt", icon: "speedometer")
                }
                Stepper(value: $model.fuelBurn, in: 1...100, step: 1) {
                    valueRow("Consommation", "\(Int(model.fuelBurn)) gal/h", icon: "flame")
                }
                Stepper(value: $model.fuelOnBoard, in: 0...300, step: 1) {
                    valueRow("Carburant au départ", model.fuelOnBoard > 0 ? "\(Int(model.fuelOnBoard)) gal" : "—", icon: "fuelpump")
                }
                Stepper(value: $model.reserveMin, in: 0...120, step: 5) {
                    valueRow("Réserve", "\(Int(model.reserveMin)) min", icon: "timer")
                }
            } header: { FFHeader("Avion & performance") }

            Section {
                DatePicker(selection: $model.departureTime) {
                    Label("Départ (ETD)", systemImage: "clock")
                }
                HStack {
                    Label("Arrivée (ETA)", systemImage: "clock.arrow.circlepath")
                    Spacer()
                    Text("\(model.arrivalTime.formatted(date: .omitted, time: .shortened)) · \(model.arrivalTime.zulu)")
                        .font(TypographyToken.monoMedium)
                }
                Button("Partir maintenant") { model.departureTime = .now }
            } header: { FFHeader("Horaires") } footer: {
                Text("Changer l'heure de départ recalcule les vents prévus (FD 6/12/24 h), le navlog, l'ETA et le briefing.")
            }

            if model.waypoints.count >= 2 {
                AltitudeAdvisorSection()

                Section {
                    VerticalProfileView(path: model.routePath, cruiseAlt: model.cruiseAlt,
                                        airspaces: airspaceManager.allAirspaces)
                    if let p = model.verticalProfile {
                        LabeledContent("Fin de montée (TOC)",
                                       value: String(format: "%.0f NM après %@ · %@", p.tocNM, model.waypoints.first?.id ?? "", ffDuration(p.climbMinutes)))
                        LabeledContent("Début de descente (TOD)",
                                       value: String(format: "%.0f NM avant %@ · %@", p.todNM, model.waypoints.last?.id ?? "", ffDuration(p.descentMinutes)))
                    }
                } header: { FFHeader("Profil vertical") } footer: {
                    if model.verticalProfile != nil {
                        Text("Montée et descente selon le profil avion (vitesse, taux, conso), descente jusqu'à 1 000 ft au-dessus de la destination. Le navlog en tient compte.")
                    }
                }

                RouteFrequenciesSection()

                Section {
                    LabeledContent("Mode de route", value: routingEngine.currentMode.rawValue)
                    NavigationLink { VFRFlightPlanFilingScreen() } label: {
                        Label("Plan de vol VFR · dépôt Leidos", systemImage: "paperplane")
                    }
                    Button {
                        model.logFlight(from: model.waypoints.first!.id, to: model.waypoints.last!.id,
                                        nm: Int(model.totalDistanceNM.rounded()),
                                        eteMinutes: Int(model.totalTimeMinutes.rounded()),
                                        departure: model.waypoints.first?.coordinate,
                                        arrival: model.waypoints.last?.coordinate)
                    } label: {
                        Label("Ajouter au carnet de vol", systemImage: "book")
                    }
                    Button(role: .destructive) { model.waypoints.removeAll() } label: {
                        Label("Effacer le vol", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
    }

    private func valueRow(_ title: String, _ value: String, icon: String) -> some View {
        HStack {
            Label(title, systemImage: icon)
            Spacer()
            Text(value).font(TypographyToken.monoMedium)
        }
    }
}

private struct FlightPlanWaypointRow: View {
    let index: Int
    let airport: Airport
    let totalCount: Int

    private var role: String {
        index == 0 ? "DÉP" : (index == totalCount - 1 ? "DEST" : "\(index)")
    }

    var body: some View {
        HStack(spacing: 12) {
            Text(role)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 38, height: 20)
                .background(index == 0 || index == totalCount - 1 ? FF.accent : FF.magenta,
                            in: RoundedRectangle(cornerRadius: 4))
            VStack(alignment: .leading, spacing: 1) {
                Text(airport.id).font(.system(size: 17, weight: .bold))
                Text(airport.name).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// MARK: - Navlog

/// ForeFlight-style navlog: one row per leg with altitude, wind/temp, true & magnetic course,
/// wind correction, magnetic heading, TAS/GS, distance (leg / remaining), time (leg / total), ETA and fuel.
struct NavlogTable: View {
    @EnvironmentObject private var model: AppModel

    private let columns: [(String, CGFloat)] = [
        ("POINT", 74), ("ALT", 46), ("VENT", 62), ("TEMP", 40), ("RV", 40), ("RM", 40), ("WCA", 40), ("CM", 40),
        ("TAS", 40), ("GS", 40), ("DIST", 44), ("REST", 44), ("ETE", 44), ("TOTAL", 46), ("ETA", 50),
        ("CARB", 44), ("RESTE", 48)
    ]

    var body: some View {
        if model.navlog.isEmpty {
            ContentUnavailableView("Navlog vide", systemImage: "tablecells",
                                   description: Text("Ajoutez au moins deux points pour calculer le navlog."))
        } else {
            VStack(spacing: 0) {
                status
                ScrollView([.vertical, .horizontal]) {
                    VStack(spacing: 0) {
                        line(columns.map { Cell($0.0, color: FF.label, bold: true) })
                            .font(.system(size: 10, weight: .bold))
                            .background(FF.bar)
                        line(startCells)
                        ForEach(Array(model.navlog.enumerated()), id: \.element.id) { i, leg in
                            line(cells(leg)).background(i.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.05))
                        }
                        line(totalCells).background(FF.accent.opacity(0.15))
                    }
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .padding(.horizontal, 8)
                }
                legend
            }
        }
    }

    struct Cell {
        let text: String
        var color: Color = .primary
        var bold = false
        init(_ text: String, color: Color = .primary, bold: Bool = false) {
            self.text = text; self.color = color; self.bold = bold
        }
    }

    private func line(_ cells: [Cell]) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(cells.enumerated()), id: \.offset) { i, c in
                Text(c.text)
                    .fontWeight(c.bold ? .bold : nil)
                    .foregroundStyle(c.color)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(width: i < columns.count ? columns[i].1 : 40, alignment: i == 0 ? .leading : .trailing)
            }
        }
        .padding(.vertical, 5)
    }

    private var status: some View {
        HStack(spacing: 6) {
            if model.navlogLoadingWinds {
                ProgressView().controlSize(.mini)
                Text("Téléchargement des vents prévus…")
            } else if model.navlogHasWinds {
                Image(systemName: "wind")
                Text("Vents FD à l'heure de passage · départ \(model.departureTime.formatted(date: .abbreviated, time: .shortened))"
                     + (model.verticalProfile.map { String(format: " · TOC %.0f NM · TOD %.0f NM avant arrivée", $0.tocNM, $0.todNM) } ?? ""))
            } else {
                Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ColorToken.warning)
                Text("Vents en altitude indisponibles : GS = TAS, pas de correction")
            }
            Spacer()
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private var startCells: [Cell] {
        var c = [Cell(model.navlog.first?.from ?? "", bold: true)]
        c += Array(repeating: Cell(""), count: 13)
        c.append(Cell(model.departureTime.zulu))
        c.append(Cell(""))
        c.append(Cell(model.fuelOnBoard > 0 ? String(format: "%.1f", model.fuelOnBoard) : ""))
        return c
    }

    private func cells(_ l: NavLogLeg) -> [Cell] {
        let reserve = model.reserveMin / 60 * model.fuelBurn
        let gsColor: Color = l.groundSpeed < l.tas - 2 ? ColorToken.warning : (l.groundSpeed > l.tas + 2 ? ColorToken.success : .primary)
        return [
            Cell(l.to, bold: true),
            Cell("\(l.altitude / 100)"),
            Cell(l.windDirection.map { d in String(format: "%03d/%02d", d, l.windSpeed ?? 0) } ?? "—"),
            Cell(l.temperature.map { "\($0)" } ?? "—"),
            Cell(String(format: "%03d", l.trueCourse)),
            Cell(String(format: "%03d", l.magneticCourse)),
            Cell(l.wca == 0 ? "0" : (l.wca > 0 ? "R\(l.wca)" : "L\(-l.wca)")),
            Cell(String(format: "%03d", l.magneticHeading), color: FF.magenta, bold: true),
            Cell("\(Int(l.tas))"),
            Cell("\(Int(l.groundSpeed.rounded()))", color: gsColor),
            Cell(String(format: "%.1f", l.distanceNM)),
            Cell(String(format: "%.0f", l.remainingNM)),
            Cell(ffDuration(l.minutes)),
            Cell(ffDuration(l.cumulativeMinutes)),
            Cell(l.eta.zulu),
            Cell(String(format: "%.1f", l.fuelGallons)),
            Cell(l.fuelRemaining.map { String(format: "%.1f", $0) } ?? "—",
                 color: (l.fuelRemaining ?? 999) < reserve ? ColorToken.danger : .primary)
        ]
    }

    private var totalCells: [Cell] {
        let legs = model.navlog
        let dist = legs.reduce(0) { $0 + $1.distanceNM }
        let fuel = legs.reduce(0) { $0 + $1.fuelGallons }
        var c = [Cell("TOTAL", bold: true)]
        c += Array(repeating: Cell(""), count: 9)
        c.append(Cell(String(format: "%.1f", dist), bold: true))
        c += [Cell(""), Cell("")]
        c.append(Cell(ffDuration(model.totalTimeMinutes), bold: true))
        c.append(Cell(model.arrivalTime.zulu, bold: true))
        c.append(Cell(String(format: "%.1f", fuel), bold: true))
        c.append(Cell(legs.last?.fuelRemaining.map { String(format: "%.1f", $0) } ?? "—", bold: true))
        return c
    }

    private var legend: some View {
        Text("RV route vraie · RM route magnétique · WCA correction de vent (R/L) · CM cap magnétique · REST distance restante · CARB carburant du segment (gal) · Réserve \(Int(model.reserveMin)) min")
            .font(.caption2)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Plain-text navlog to share.
enum NavlogText {
    @MainActor
    static func make(model: AppModel) -> String {
        var lines = ["Navlog \(model.waypoints.map(\.id).joined(separator: " → ")) · \(model.cruiseAlt) ft · TAS \(Int(model.cruiseGS)) kt",
                     "Départ \(model.departureTime.formatted(date: .abbreviated, time: .shortened)) (\(model.departureTime.zulu))",
                     "Point     Vent    RV  CM  GS  Dist  ETE   ETA   Carb"]
        for l in model.navlog {
            let wind = l.windDirection.map { String(format: "%03d/%02d", $0, l.windSpeed ?? 0) } ?? "---/--"
            lines.append(String(format: "%@ %@ %03d %03d %3d %5.1f %@ %@ %4.1f",
                                l.to.padding(toLength: 8, withPad: " ", startingAt: 0), wind, l.trueCourse,
                                l.magneticHeading, Int(l.groundSpeed.rounded()), l.distanceNM,
                                ffDuration(l.minutes), l.eta.zulu, l.fuelGallons))
        }
        lines.append("Total \(String(format: "%.0f", model.totalDistanceNM)) NM · ETE \(ffDuration(model.totalTimeMinutes)) · ETA \(model.arrivalTime.zulu)")
        return lines.joined(separator: "\n")
    }
}

/// Saved plans: tap to load, swipe to delete.
private struct SavedPlansSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                if model.savedPlans.isEmpty {
                    Text("Aucun plan enregistré. Menu ⋯ > « Enregistrer ce plan ».").foregroundStyle(ColorToken.textTertiary)
                }
                ForEach(model.savedPlans) { plan in
                    Button(plan.name) {
                        model.waypoints = plan.points ?? plan.waypointIDs.compactMap { model.resolveWaypoint($0, store: store) }
                        dismiss()
                    }
                }
                .onDelete { model.savedPlans.remove(atOffsets: $0) }
            }
            .navigationTitle("Plans enregistrés")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
    }
}
