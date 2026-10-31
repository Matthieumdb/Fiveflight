import SwiftUI
import MapKit
import CoreLocation

struct MapScreen: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var model: AppModel

    @State private var nearest: [Airport] = []
    @State private var categories: [String: String] = [:]   // ICAO -> flight category
    @State private var selected: Airport?

    @State private var waypoints: [Airport] = []
    @State private var fromText = ""
    @State private var toText = ""
    @State private var routeError: String?
    @State private var groundSpeed = 110.0
    @State private var fuelBurn = 8.0
    @State private var logged = false

    @State private var showSectional = true
    @State private var showWeather = false
    @State private var showPlan = false

    @State private var region = MKCoordinateRegion(
        center: .init(latitude: 27.5, longitude: -80.4),
        span: .init(latitudeDelta: 1.2, longitudeDelta: 1.2))
    @State private var regionVersion = 0

    private let types: Set<String> = ["small_airport", "medium_airport", "large_airport"]

    var body: some View {
        VStack(spacing: 0) {
            routeBar
            ZStack(alignment: .topTrailing) {
                VFRMapView(showSectional: showSectional, showWeather: showWeather,
                           nearest: nearest, waypoints: waypoints, categories: categories,
                           region: region, regionVersion: regionVersion,
                           onSelect: { selected = $0 })
                    .ignoresSafeArea(edges: .horizontal)
                    .overlay(alignment: .bottom) {
                        Text("Démo — ne pas utiliser pour la navigation réelle")
                            .font(.system(size: 10))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(.regularMaterial, in: Capsule())
                            .padding(.bottom, 6)
                    }
                    .overlay(alignment: .bottomLeading) { if !categories.isEmpty { legend } }
                layerControls.padding(10)
            }
            .frame(maxHeight: .infinity)
            list
        }
        .onAppear(perform: recompute)
        .onChange(of: location.coordinate?.latitude) { recompute() }
        .onChange(of: model.directTo) { handleDirectTo() }
        .sheet(item: $selected) { a in
            AirportDetailView(airport: a,
                              runways: store.runways(for: a),
                              frequencies: store.frequencies(for: a))
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showPlan) {
            FlightPlanSheet(waypoints: $waypoints, groundSpeed: $groundSpeed, fuelBurn: $fuelBurn)
                .presentationDetents([.medium, .large])
        }
    }

    // MARK: - Layer controls

    private var layerControls: some View {
        VStack(spacing: Theme.mapControlGap) {
            layerButton(on: $showSectional, systemImage: "map.fill", label: "Carte VFR")
            layerButton(on: $showWeather, systemImage: "cloud.rain.fill", label: "Météo radar")
        }
    }

    private func layerButton(on: Binding<Bool>, systemImage: String, label: String) -> some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { on.wrappedValue.toggle() }
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 18))
                .frame(width: Theme.tapTarget, height: Theme.tapTarget)
                .foregroundStyle(on.wrappedValue ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
                .background(on.wrappedValue ? AnyShapeStyle(Color.accentColor)
                                            : AnyShapeStyle(.regularMaterial),
                            in: RoundedRectangle(cornerRadius: Theme.corner))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(.quaternary))
                .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        }
        .accessibilityLabel(label)
        .accessibilityAddTraits(on.wrappedValue ? .isSelected : [])
    }

    // MARK: - Route bar

    private var routeBar: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                field("De", text: $fromText)
                Image(systemName: "arrow.right").foregroundStyle(.secondary)
                field("À", text: $toText)
                Button("Tracer") { makeRoute() }.buttonStyle(.borderedProminent).controlSize(.small)
                if !waypoints.isEmpty {
                    Button { clearRoute() } label: { Image(systemName: "xmark.circle.fill") }.tint(.secondary)
                }
            }
            if waypoints.count >= 2 {
                routeInfo
                flightComputer
            } else if let routeError {
                Text(routeError).font(.caption).foregroundStyle(.red)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
        .background(Theme.bgElevated)
        .overlay(alignment: .bottom) { Rectangle().fill(Theme.stroke).frame(height: 1) }
    }

    private func field(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            .textInputAutocapitalization(.characters).autocorrectionDisabled()
            .textFieldStyle(.roundedBorder).frame(width: 78).onSubmit { makeRoute() }
    }

    private var totalNM: Double {
        guard waypoints.count >= 2 else { return 0 }
        return zip(waypoints, waypoints.dropFirst())
            .reduce(0) { $0 + Haversine.nauticalMiles($1.0.coordinate, $1.1.coordinate) }
    }

    private var routeInfo: some View {
        Button { showPlan = true } label: {
            HStack {
                Text("\(waypoints.map(\.id).joined(separator: " → "))  ·  \(Int(totalNM.rounded())) NM")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .lineLimit(2)
                Spacer()
                Image(systemName: "list.bullet.rectangle").font(.caption)
            }
            .contentShape(Rectangle())
        }
        .tint(Theme.textPrimary)
    }

    private var flightComputer: some View {
        let hours = groundSpeed > 0 ? totalNM / groundSpeed : 0
        let mins = Int((hours * 60).rounded())
        let ete = "\(mins / 60)h\(String(format: "%02d", mins % 60))"
        let fuel = hours * fuelBurn
        return VStack(spacing: 4) {
            HStack {
                Text("GS \(Int(groundSpeed)) kt").font(.caption.monospacedDigit())
                Stepper("", value: $groundSpeed, in: 40...500, step: 5).labelsHidden()
                Spacer()
                Text("\(Int(fuelBurn)) gph").font(.caption.monospacedDigit())
                Stepper("", value: $fuelBurn, in: 1...100, step: 1).labelsHidden()
            }
            HStack {
                Text("ETE \(ete)  ·  \(String(format: "%.1f", fuel)) gal")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                Spacer()
                Button {
                    model.logFlight(from: waypoints.first!.id, to: waypoints.last!.id,
                                    nm: Int(totalNM.rounded()), eteMinutes: mins)
                    logged = true
                } label: { Label(logged ? "Enregistré" : "Carnet",
                                 systemImage: logged ? "checkmark" : "book") }
                .buttonStyle(.bordered).controlSize(.small).disabled(logged)
            }
        }
    }

    // MARK: - List

    private var list: some View {
        List(nearest) { a in
            row(a)
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
                .listRowInsets(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .frame(height: 196)
    }

    private func row(_ a: Airport) -> some View {
        HStack(spacing: 12) {
            Circle().fill(dotColor(a)).frame(width: 10, height: 10)
                .shadow(color: dotColor(a).opacity(0.7), radius: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.id).font(.headline).foregroundStyle(Theme.textPrimary)
                Text(a.name).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
            }
            Spacer()
            if let c = location.coordinate {
                Text("\(Int(a.distanceNM(to: c).rounded())) NM")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.textSecondary)
            }
            Button { addWaypoint(a) } label: {
                Image(systemName: "plus.circle.fill").font(.title3)
            }
            .buttonStyle(.borderless).tint(Theme.accent)
        }
        .padding(.vertical, 11).padding(.horizontal, 14)
        .card(radius: Theme.cornerSmall)
        .contentShape(Rectangle())
        .onTapGesture { selected = a }
    }

    // MARK: - Actions

    private func makeRoute() {
        guard let f = store.airport(fromText), let t = store.airport(toText) else {
            routeError = "Code inconnu (ex : KFPR, KMIA)"; waypoints = []; return
        }
        routeError = nil; logged = false
        waypoints = [f, t]
        fit(waypoints.map(\.coordinate))
    }

    private func addWaypoint(_ a: Airport) {
        logged = false
        if waypoints.isEmpty, let dep = nearest.first, dep.id != a.id {
            waypoints = [dep, a]
            fromText = dep.id
        } else if waypoints.last?.id != a.id {
            waypoints.append(a)
        }
        toText = waypoints.last?.id ?? ""
        fit(waypoints.map(\.coordinate))
    }

    private func clearRoute() {
        waypoints = []; routeError = nil; fromText = ""; toText = ""; logged = false
        fitNearby()
    }

    /// "Direct to" from a detail sheet: route from the nearest field to the chosen airport.
    private func handleDirectTo() {
        guard let id = model.directTo, let dest = store.airport(id) else { return }
        model.directTo = nil
        logged = false
        if let dep = nearest.first, dep.id != dest.id {
            waypoints = [dep, dest]; fromText = dep.id
        } else {
            waypoints = [dest]
        }
        toText = dest.id
        fit(waypoints.map(\.coordinate))
    }

    // MARK: - Helpers

    private func recompute() {
        guard store.ready, let c = location.coordinate else { return }
        nearest = store.nearest(to: c, limit: 10, matching: types)
        if fromText.isEmpty, let f = nearest.first { fromText = f.id }
        if waypoints.isEmpty { fitNearby() }
        let ids = nearest.map(\.id)
        Task { categories = await WeatherService.categories(for: ids) }
    }

    /// Dot colour: live flight category when the field reports weather, else by size.
    private func dotColor(_ a: Airport) -> Color {
        if let cat = categories[a.id] { return Theme.category(cat) }
        return tint(for: a.type)
    }

    private var legend: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(["VFR", "MVFR", "IFR", "LIFR"], id: \.self) { c in
                HStack(spacing: 6) {
                    Circle().fill(Theme.category(c)).frame(width: 9, height: 9)
                    Text(c).font(.caption.monospaced()).foregroundStyle(Theme.textSecondary)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Theme.stroke))
        .padding(10)
    }

    private func fitNearby() {
        guard let c = location.coordinate else { return }
        fit([c] + nearest.prefix(5).map(\.coordinate))
    }

    private func fit(_ coords: [CLLocationCoordinate2D]) {
        guard let first = coords.first else { return }
        var minLat = first.latitude, maxLat = first.latitude
        var minLon = first.longitude, maxLon = first.longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        region = MKCoordinateRegion(
            center: .init(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
            span: .init(latitudeDelta: max((maxLat - minLat) * 1.4, 0.2),
                        longitudeDelta: max((maxLon - minLon) * 1.4, 0.2)))
        regionVersion += 1
    }

    private func tint(for type: String) -> Color {
        switch type {
        case "large_airport":  return Theme.accent
        case "medium_airport": return Color(.sRGB, red: 0.28, green: 0.80, blue: 0.75)
        default:               return Theme.textTertiary
        }
    }
}
