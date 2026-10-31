import SwiftUI
import MapKit
import CoreLocation
import WidgetKit

// Shared types for widget data
private struct AirportSummary: Codable {
    let id: String
    let name: String
    let nm: Int
    let category: String?
}
private struct RouteSummary: Codable {
    let from: String
    let to: String
    let totalNM: Int
    let ete: String
    let fuel: Double
}
private struct WeatherSummary: Codable {
    let station: String
    let category: String
    let wind: String
    let visib: String
}

struct MapScreen: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var model: AppModel

    @State private var nearest: [Airport] = []
    @State private var categories: [String: String] = [:]
    @State private var selectedAirport: Airport?
    @State private var waypoints: [Airport] = []
    @State private var fromText = ""
    @State private var toText = ""
    @State private var routeError: String?
    @State private var logged = false

    @State private var showSectional = true
    @State private var showWeather = false
    @State private var showPlan = false
    @State private var showSearch = false

    @State private var region = MKCoordinateRegion(
        center: .init(latitude: 27.5, longitude: -80.4),
        span: .init(latitudeDelta: 1.2, longitudeDelta: 1.2))
    @State private var regionVersion = 0

    private let airportTypes: Set<String> = ["small_airport", "medium_airport", "large_airport"]

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            VStack(spacing: 0) {
                RouteBarView(
                    waypoints: $waypoints,
                    fromText: $fromText,
                    toText: $toText,
                    routeError: $routeError,
                    logged: $logged,
                    onMakeRoute: makeRoute,
                    onClearRoute: clearRoute
                )

                ZStack(alignment: .topTrailing) {
                    VFRMapView(
                        showSectional: showSectional,
                        showWeather: showWeather,
                        nearest: nearest,
                        waypoints: waypoints,
                        categories: categories,
                        userCoord: location.coordinate,
                        region: region,
                        regionVersion: regionVersion,
                        onSelect: { selectedAirport = $0 }
                    )
                    .ignoresSafeArea(edges: .horizontal)
                    .overlay(alignment: .bottom) {
                        disclaimerLabel
                    }
                    .overlay(alignment: .bottomLeading) {
                        MapLegendView(categories: categories)
                    }

                    LayerControlsView(
                        showSectional: $showSectional,
                        showWeather: $showWeather,
                        onRecenter: recenterMap,
                        onSearch: { showSearch = true }
                    )
                    .padding(Theme.pad)
                }
                .frame(maxHeight: .infinity)

                NearbyAirportsListView(
                    nearest: nearest,
                    categories: categories,
                    onSelect: { selectedAirport = $0 },
                    onAddWaypoint: addWaypoint
                )
            }
        }
        .onAppear(perform: recompute)
        .onChange(of: location.coordinate?.latitude) { _, _ in recompute() }
        .onChange(of: model.directTo) { _, _ in handleDirectTo() }
        .sheet(item: $selectedAirport) { airport in
            AirportDetailSheet(airport: airport, store: store)
        }
        .sheet(isPresented: $showPlan) {
            FlightPlanSheet(waypoints: $waypoints)
                .presentationDetents([.medium, .large])
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(nearest: nearest)
        }
    }

    private var disclaimerLabel: some View {
        Text("Démo — ne pas utiliser pour la navigation réelle")
            .font(.system(size: 10))
            .foregroundStyle(Theme.textTertiary)
            .padding(.horizontal, Theme.spacingS)
            .padding(.vertical, Theme.spacingXS)
            .background(.regularMaterial, in: Capsule())
            .padding(.bottom, Theme.spacingS)
    }

    // MARK: - Actions

    private func makeRoute() {
        guard let from = store.airport(fromText), let to = store.airport(toText) else {
            routeError = "Code inconnu (ex: KFPR, KMIA)"
            waypoints = []
            return
        }
        routeError = nil
        logged = false
        waypoints = [from, to]
        fromText = from.id
        toText = to.id
        fit(waypoints.map(\.coordinate))
    }

    private func addWaypoint(_ airport: Airport) {
        logged = false
        Haptics.tap()

        if waypoints.isEmpty, let dep = nearest.first, dep.id != airport.id {
            waypoints = [dep, airport]
            fromText = dep.id
        } else if waypoints.last?.id != airport.id {
            waypoints.append(airport)
        }
        toText = waypoints.last?.id ?? ""
        fit(waypoints.map(\.coordinate))
    }

    private func clearRoute() {
        waypoints = []
        routeError = nil
        fromText = ""
        toText = ""
        logged = false
        fitNearby()
    }

    private func handleDirectTo() {
        guard let id = model.directTo, let dest = store.airport(id) else { return }
        model.directTo = nil
        logged = false

        if let dep = nearest.first, dep.id != dest.id {
            waypoints = [dep, dest]
            fromText = dep.id
        } else {
            waypoints = [dest]
        }
        toText = dest.id
        fit(waypoints.map(\.coordinate))
    }

    private func recenterMap() {
        if waypoints.count >= 2 {
            fit(waypoints.map(\.coordinate))
        } else {
            fitNearby()
        }
    }

    // MARK: - Helpers

    private func recompute() {
        guard store.ready, let coord = location.coordinate else { return }

        nearest = store.nearest(to: coord, limit: 10, matching: airportTypes)

        if fromText.isEmpty, let first = nearest.first {
            fromText = first.id
        }

        if waypoints.isEmpty {
            fitNearby()
        }

        let ids = nearest.map(\.id)
        Task {
            categories = await WeatherService.categories(for: ids)
            writeWidgetData()
        }
    }

    private func writeWidgetData() {
        let shared = UserDefaults(suiteName: "group.com.example.efb.fiveflight")!
        let encoder = JSONEncoder()

        // Nearest airports
        let summaries = nearest.prefix(5).map { airport in
            AirportSummary(
                id: airport.id,
                name: airport.name,
                nm: Int(airport.distanceNM(to: location.coordinate!).rounded()),
                category: categories[airport.id]
            )
        }
        shared.set(try? encoder.encode(summaries), forKey: "widget.nearest")

        // Active route
        if waypoints.count >= 2 {
            let totalNM = zip(waypoints, waypoints.dropFirst())
                .reduce(0) { $0 + Haversine.nauticalMiles($1.0.coordinate, $1.1.coordinate) }
            let hours = model.cruiseGS > 0 ? totalNM / model.cruiseGS : 0
            let mins = Int((hours * 60).rounded())
            let ete = "\(mins / 60)h\(String(format: "%02d", mins % 60))"
            let fuel = hours * model.fuelBurn + model.reserveMin / 60 * model.fuelBurn

            let route = RouteSummary(
                from: waypoints.first!.id,
                to: waypoints.last!.id,
                totalNM: Int(totalNM.rounded()),
                ete: ete,
                fuel: fuel
            )
            shared.set(try? encoder.encode(route), forKey: "widget.route")
        } else {
            shared.removeObject(forKey: "widget.route")
        }

        // Weather for first nearest
        if let first = nearest.first, let cat = categories[first.id] {
            let wx = WeatherSummary(station: first.id, category: cat, wind: "—", visib: "—")
            shared.set(try? encoder.encode(wx), forKey: "widget.weather")
        }

        WidgetCenter.shared.reloadAllTimelines()
    }

    private func fitNearby() {
        guard let coord = location.coordinate else { return }
        fit([coord] + nearest.prefix(5).map(\.coordinate))
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
            center: .init(
                latitude: (minLat + maxLat) / 2,
                longitude: (minLon + maxLon) / 2
            ),
            span: .init(
                latitudeDelta: max((maxLat - minLat) * 1.4, 0.2),
                longitudeDelta: max((maxLon - minLon) * 1.4, 0.2)
            )
        )
        regionVersion += 1
    }
}

struct AirportDetailSheet: View {
    let airport: Airport
    let store: AirportStore

    var body: some View {
        NavigationStack {
            AirportDetailView(
                airport: airport,
                runways: store.runways(for: airport),
                frequencies: store.frequencies(for: airport)
            )
        }
        .presentationDetents([.medium, .large])
    }
}