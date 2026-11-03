import SwiftUI
import MapKit
import CoreLocation

/// Main map screen - ForeFlight inspired dark theme with side panels
struct MapScreen: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var airspaceManager: AirspaceDataManager
    @EnvironmentObject private var routingEngine: RoutingEngine
    @EnvironmentObject private var weatherService: WeatherService
    @EnvironmentObject private var locationManager: LocationManager

    @State private var showFlightPlanPanel = false
    @State private var showLayersPanel = false
    @State private var showNearbyPanel = false
    @State private var showSearch = false
    @State private var showNearest = false
    @ObservedObject private var adsb = ADSBReceiver.shared
    /// Radar loop: index in `VFRMapView.radarFrames` (last = live), animating while `radarPlaying`.
    @State private var radarFrame = VFRMapView.radarFrames.count - 1
    @State private var radarPlaying = false

    private var weatherLayers: [String] {
        (model.showIR ? ["goes-east-ir-4km-900913"] : [])
            + (model.showRadar ? ["nexrad-n0q-900913" + VFRMapView.radarFrames[radarFrame]] : [])
    }
    @State private var selectedAirport: Airport?
    @State private var routePolyline: [CLLocationCoordinate2D] = []
    @State private var routeWarnings: [RouteWarning] = []
    @State private var visibleAirports: [Airport] = []
    @State private var visibleNavaids: [Airport] = []
    @State private var pressedPoint: PressedPoint?
    @State private var selectedWaypoint: Airport?
    @ObservedObject private var monitor = FlightMonitor.shared

    private var glideRadius: Double? {
        model.showGlideRing ? monitor.glideRangeNM : nil
    }

    private var activeAirspaces: [Airspace] {
        airspaceManager.allAirspaces.filter { $0.isActive }
    }

    /// US stations among the airports on screen, for the METAR-driven marker colours.
    private var metarStations: [String] {
        visibleAirports
            .filter { $0.type != "heliport" && $0.id.count == 4 && ($0.id.hasPrefix("K") || $0.id.hasPrefix("P")) }
            .prefix(100)
            .map(\.id)
            .sorted()
    }

    /// Split out of the button label so the type checker stays fast.
    private var radarButtonTitle: String {
        guard radarPlaying else { return "Animer radar" }
        let minutesAgo: Int = 10 * (VFRMapView.radarFrames.count - 1 - radarFrame)
        return "-\(minutesAgo) min"
    }

    /// The map itself, split out of `body` so the type checker stays fast in Release builds.
    private var mapLayer: some View {
            VFRMapView(
                showSectional: model.showSectional,
                nearest: visibleAirports,
                waypoints: model.waypoints,
                route: routePolyline,
                track: model.track,
                categories: weatherService.categories,
                userCoord: model.userLocation,
                region: model.mapRegion,
                regionVersion: model.mapRegionVersion,
                onSelect: { airport in
                    if airport.isAirport {
                        selectedAirport = airport
                        model.selectedAirport = airport
                    } else {
                        selectedWaypoint = airport
                    }
                },
                onRegionChange: { region in
                    model.mapRegion = region
                    visibleAirports = Self.airportsToShow(store.airports, in: region)
                    visibleNavaids = Self.navaidsToShow(in: region)
                },
                airspaces: activeAirspaces,
                showAirspace: model.showAirspace,
                showTFRs: model.showAirspace,
                chart: model.mapChart,
                satellite: model.showSatellite,
                weatherLayers: weatherLayers,
                traffic: adsb.traffic,
                navaids: visibleNavaids,
                glideRadiusNM: glideRadius,
                onLongPress: { coord in pressedPoint = PressedPoint(coordinate: coord) },
                onMoveWaypoint: { id, coord in model.moveWaypoint(id: id, to: coord) }
            )
            .ignoresSafeArea()
    }

    var body: some View {
        ZStack(alignment: .top) {
            // MARK: - Full Screen Map (VFRMapView with MKTileOverlay)
            mapLayer

            // MARK: - Top Bar
            TopMapBar(
                showFlightPlanPanel: $showFlightPlanPanel,
                showLayersPanel: $showLayersPanel,
                showNearbyPanel: $showNearbyPanel,
                showSearch: $showSearch
            )
            .zIndex(20)   // ForeFlight: the toolbar stays on top of the panels it opens

            // MARK: - Side Panels
            if showFlightPlanPanel {
                FlightPlanSidePanel(
                    isPresented: $showFlightPlanPanel,
                    routePolyline: $routePolyline,
                    routeWarnings: $routeWarnings
                )
                .padding(.top, 48)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(10)
            }

            if showLayersPanel {
                LayersSidePanel(isPresented: $showLayersPanel)
                    .padding(.top, 48)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(10)
            }

            if showNearbyPanel {
                NearbySidePanel(isPresented: $showNearbyPanel)
                    .padding(.top, 48)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(10)
            }

            // MARK: - Radar loop control
            if model.showRadar {
                HStack {
                    Spacer()
                    Button {
                        radarPlaying.toggle()
                        if !radarPlaying { radarFrame = VFRMapView.radarFrames.count - 1 }
                    } label: {
                        Label(radarButtonTitle, systemImage: radarPlaying ? "stop.fill" : "play.fill")
                            .font(TypographyToken.labelSmall)
                            .padding(.horizontal, SpacingToken.space3)
                            .padding(.vertical, SpacingToken.space2)
                            .background(.black.opacity(0.7), in: Capsule())
                            .foregroundStyle(.white)
                    }
                }
                .padding(.top, 150)
                .padding(.trailing, SpacingToken.space3)
                .zIndex(4)
            }

            // MARK: - GPS instruments (in flight, or on demand)
            if model.showInstruments || locationManager.speed > FlightMonitor.airborneSpeed {
                VStack {
                    Spacer()
                    InstrumentStrip(showNearest: $showNearest)
                        .padding(.horizontal, SpacingToken.space3)
                        .padding(.bottom, 8)
                }
                .zIndex(5)
            }
        }
        .sheet(isPresented: $showNearest) { NearestSheet() }
        .modifier(MapPointActions(pressedPoint: $pressedPoint, selectedWaypoint: $selectedWaypoint))
        .task(id: radarPlaying) {
            while radarPlaying, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 900_000_000)
                radarFrame = (radarFrame + 1) % VFRMapView.radarFrames.count
            }
        }
        .animation(AnimationToken.transition, value: showFlightPlanPanel)
        .animation(AnimationToken.transition, value: showLayersPanel)
        .animation(AnimationToken.transition, value: showNearbyPanel)
        // A real sheet: swipe down or "Done" closes it (it used to be an overlay that could not be dismissed).
        .sheet(item: $selectedAirport) { airport in
            AirportDetailSheet(airport: airport, store: store)
                .environmentObject(model)
                .environmentObject(weatherService)
        }
        .sheet(isPresented: $showSearch) {
            SearchSheet(nearest: store.nearest(to: model.userLocation ?? AppModel.homeCoordinate, limit: 20)) { airport in
                showSearch = false
                model.markViewed(airport.id)
                model.moveMap(to: airport.coordinate, span: 0.3)
                // Open the airport card once the search sheet has finished closing.
                Task {
                    try? await Task.sleep(nanoseconds: 450_000_000)
                    selectedAirport = airport
                }
            }
        }
        .onAppear {
            visibleAirports = Self.airportsToShow(store.airports, in: model.mapRegion)
            visibleNavaids = Self.navaidsToShow(in: model.mapRegion)
            Task { await calculateAndUpdateRoute() }
        }
        .onChange(of: model.waypoints) { _, _ in
            Task { await calculateAndUpdateRoute() }
        }
        .onChange(of: routingEngine.currentMode) { _, _ in
            Task { await calculateAndUpdateRoute() }
        }
        .onChange(of: model.cruiseAlt) { _, _ in
            Task { await calculateAndUpdateRoute() }
        }
        .onChange(of: model.cruiseGS) { _, _ in
            Task { await calculateAndUpdateRoute() }
        }
        .onChange(of: model.fuelBurn) { _, _ in
            Task { await calculateAndUpdateRoute() }
        }
        .onChange(of: airspaceManager.allAirspaces.count) { _, _ in
            Task { await calculateAndUpdateRoute() } // data arrived after the plan (launch, TFR refresh)
        }
        .task(id: metarStations) {
            // Debounce: wait until the map has settled, then colour markers by flight category.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await weatherService.refreshMETARs(forVisible: metarStations)
        }
    }

    // MARK: - Helpers

    /// VORs and VFR waypoints below ~90 NM of span, fixes too below ~35 NM.
    nonisolated static func navaidsToShow(in region: MKCoordinateRegion) -> [Airport] {
        let maxDelta = max(region.span.latitudeDelta, region.span.longitudeDelta)
        guard maxDelta < 1.5 else { return [] }
        let types: Set<String> = maxDelta < 0.6 ? ["vor", "ndb", "vfr_wp", "fix"] : ["vor", "vfr_wp"]
        let latHalf = region.span.latitudeDelta * 0.6, lonHalf = region.span.longitudeDelta * 0.6
        return NavaidStore.inRegion(minLat: region.center.latitude - latHalf, maxLat: region.center.latitude + latHalf,
                                    minLon: region.center.longitude - lonHalf, maxLon: region.center.longitude + lonHalf,
                                    types: types, limit: 150)
    }

    /// Airports worth drawing for `region`: only those inside the visible area (plus a margin),
    /// smaller types only when zoomed in, capped so MapKit never gets thousands of annotations.
    nonisolated static func airportsToShow(_ all: [Airport], in region: MKCoordinateRegion, limit: Int = 300) -> [Airport] {
        let latHalf = region.span.latitudeDelta * 0.6
        let lonHalf = region.span.longitudeDelta * 0.6
        let minLat = region.center.latitude - latHalf, maxLat = region.center.latitude + latHalf
        let minLon = region.center.longitude - lonHalf, maxLon = region.center.longitude + lonHalf
        let maxDelta = max(region.span.latitudeDelta, region.span.longitudeDelta)

        let allowed: Set<String>
        if maxDelta > 6 {
            allowed = ["large_airport", "medium_airport"]
        } else if maxDelta > 0.5 {
            allowed = ["large_airport", "medium_airport", "small_airport"]
        } else {
            allowed = ["large_airport", "medium_airport", "small_airport", "seaplane_base", "heliport"]
        }
        let rank = ["large_airport": 0, "medium_airport": 1, "small_airport": 2, "seaplane_base": 3, "heliport": 4]

        return all
            .filter { a in
                allowed.contains(a.type)
                    && a.coordinate.latitude >= minLat && a.coordinate.latitude <= maxLat
                    && a.coordinate.longitude >= minLon && a.coordinate.longitude <= maxLon
            }
            .sorted { (rank[$0.type] ?? 9, $0.id) < (rank[$1.type] ?? 9, $1.id) }
            .prefix(limit)
            .map { $0 }
    }

    private func calculateAndUpdateRoute() async {
        guard model.waypoints.count >= 2 else {
            routePolyline = []
            routeWarnings = []
            return
        }

        let planned = model.waypoints
        if let result = await routingEngine.calculateRoute(
            waypoints: planned,
            cruiseAltitude: model.cruiseAlt,
            mode: routingEngine.currentMode,
            airspaces: airspaceManager.allAirspaces
        ) {
            // Plan, mode or altitude changed meanwhile: a newer calculation will land.
            guard model.waypoints.map(\.id) == planned.map(\.id), result.mode == routingEngine.currentMode,
                  result.cruiseAltitude == model.cruiseAlt else { return }
            routePolyline = result.legs.flatMap { $0.waypoints }
            model.routedDistanceNM = result.totalDistanceNM
            model.routePath = routePolyline
            // The navlog follows the routed path (rebuilt in RootView when the segments change).
            model.routeSegments = result.legs.map { NavlogSegment(from: $0.from, to: $0.to, points: $0.waypoints) }
            routeWarnings = result.airspaceWarnings.map { warning in
                RouteWarning(
                    legIndex: warning.legIndex,
                    airspaceName: warning.airspace.name,
                    type: warning.type,
                    message: warning.type.description
                )
            }
        }
    }
}

// MARK: - Top Map Bar

struct TopMapBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var locationManager: LocationManager
    @Binding var showFlightPlanPanel: Bool
    @Binding var showLayersPanel: Bool
    @Binding var showNearbyPanel: Bool
    @Binding var showSearch: Bool

    private var chartLabel: String {
        MapChart(rawValue: model.mapChart)?.label ?? "Carte"
    }

    /// ForeFlight map toolbar: one charcoal bar with the layer selector, FPL and the map tools.
    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                FFBarButton(title: chartLabel, icon: "chevron.down", active: showLayersPanel) {
                    withAnimation(AnimationToken.spring) { showLayersPanel.toggle() }
                    showFlightPlanPanel = false
                    showNearbyPanel = false
                }
                FFBarButton(title: "FPL", icon: nil, active: showFlightPlanPanel) {
                    withAnimation(AnimationToken.spring) { showFlightPlanPanel.toggle() }
                    showLayersPanel = false
                    showNearbyPanel = false
                }
                Spacer(minLength: 0)
                FFBarButton(title: nil, icon: "magnifyingglass") { showSearch = true }
                FFBarButton(title: "Proches", icon: nil, active: showNearbyPanel) {
                    withAnimation(AnimationToken.spring) { showNearbyPanel.toggle() }
                    showFlightPlanPanel = false
                    showLayersPanel = false
                }
                FFBarButton(title: nil, icon: model.followUser ? "location.fill" : "location", active: model.followUser) {
                    if let loc = model.userLocation ?? locationManager.location {
                        model.moveMap(to: loc)
                    } else {
                        locationManager.start()
                    }
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(FF.bar.ignoresSafeArea(edges: .top))

            if model.waypoints.count >= 2 {
                RouteInfoBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

/// ForeFlight route strip under the toolbar: the route string, then Dist · ETE · ETA · Carb.
struct RouteInfoBar: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(Array(model.waypoints.enumerated()), id: \.element.id) { i, w in
                        Text(w.id)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(i == 0 || i == model.waypoints.count - 1 ? FF.accent : FF.magenta.opacity(0.85),
                                        in: RoundedRectangle(cornerRadius: 4))
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
            }
            .background(FF.barSecondary)
            FFDataStrip(items: [
                ("Dist", String(format: "%.0f nm", model.totalDistanceNM)),
                ("ETE", ffDuration(model.totalTimeMinutes)),
                ("ETA", model.arrivalTime.formatted(date: .omitted, time: .shortened)),
                ("Carb", String(format: "%.1f gal", model.totalFuelGallons))
            ])
        }
    }
}

// MARK: - Map Markers

struct AirportMapMarker: View {
    let airport: Airport
    let isSelected: Bool

    var body: some View {
        ZStack {
            // Outer ring
            Circle()
                .fill(markerColor)
                .frame(width: isSelected ? 28 : 20, height: isSelected ? 28 : 20)
                .shadow(ShadowToken.medium)

            // Inner dot
            Circle()
                .fill(ColorToken.textOnBrand)
                .frame(width: isSelected ? 14 : 10, height: isSelected ? 14 : 10)

            // Type indicator
            Image(systemName: airportIcon)
                .font(.system(size: isSelected ? 12 : 9, weight: .bold))
                .foregroundStyle(ColorToken.textOnBrand)
        }
        .scaleEffect(isSelected ? 1.2 : 1.0)
        .animation(AnimationToken.springFast, value: isSelected)
    }

    private var markerColor: Color {
        switch airport.type {
        case "large_airport": return ColorToken.brandPrimary
        case "medium_airport": return ColorToken.info
        case "small_airport": return ColorToken.success
        case "heliport": return ColorToken.warning
        default: return ColorToken.textTertiary
        }
    }

    private var airportIcon: String {
        switch airport.type {
        case "large_airport": return "airplane"
        case "medium_airport": return "airplane"
        case "small_airport": return "airplane"
        case "heliport": return "helmet"
        default: return "circle"
        }
    }
}

struct WaypointMapMarker: View {
    let index: Int
    let airport: Airport

    var body: some View {
        VStack(spacing: 2) {
            ZStack {
                Circle()
                    .fill(ColorToken.brandPrimary)
                    .frame(width: 32, height: 32)
                    .shadow(ShadowToken.medium)

                Text("\(index + 1)")
                    .font(TypographyToken.monoSmall)
                    .foregroundStyle(ColorToken.textOnBrand)
            }

            Text(airport.id)
                .font(TypographyToken.monoXSmall)
                .foregroundStyle(ColorToken.textPrimary)
                .padding(.horizontal, SpacingToken.space2)
                .padding(.vertical, SpacingToken.space0)
                .background(ColorToken.surfaceCard, in: Capsule())
                .overlay(Capsule().stroke(ColorToken.borderDefault, lineWidth: 0.5))
                .shadow(ShadowToken.low)
        }
    }
}

// MARK: - Route Warning

struct RouteWarning: Identifiable {
    var id = UUID()
    let legIndex: Int
    let airspaceName: String
    let type: AirspaceWarningType
    let message: String
}

// MARK: - Long press & waypoint actions

struct PressedPoint: Identifiable {
    let id = UUID()
    let coordinate: CLLocationCoordinate2D
}

/// Long press on the map → create a user waypoint (insert in route, append, Direct To);
/// tap on a navaid/fix/user point → its card.
struct MapPointActions: ViewModifier {
    @EnvironmentObject private var model: AppModel
    @Binding var pressedPoint: PressedPoint?
    @Binding var selectedWaypoint: Airport?

    private var showDialog: Binding<Bool> {
        Binding(get: { pressedPoint != nil }, set: { if !$0 { pressedPoint = nil } })
    }

    func body(content: Content) -> some View {
        content
            .confirmationDialog("Nouveau point", isPresented: showDialog, titleVisibility: .visible, presenting: pressedPoint) { p in
                Button("Insérer dans la route") { model.insertIntoRoute(model.makeUserWaypoint(at: p.coordinate)) }
                Button("Ajouter à la fin") { model.addWaypoint(model.makeUserWaypoint(at: p.coordinate)) }
                Button("Direct To") { model.directTo(model.makeUserWaypoint(at: p.coordinate)) }
                Button("Annuler", role: .cancel) {}
            } message: { p in
                Text(Airport(id: "", name: "", type: "user", icao: nil, iata: nil, municipality: nil,
                             elevationFt: nil, coordinate: p.coordinate).coordinateText)
            }
            .sheet(item: $selectedWaypoint) { WaypointSheet(waypoint: $0) }
    }
}

/// Card for a VOR, NDB, fix, VFR waypoint or user point: details and plan actions.
struct WaypointSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationManager
    @Environment(\.dismiss) private var dismiss
    let waypoint: Airport

    private var inPlan: Bool { model.waypoints.contains { $0.id == waypoint.id } }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LabeledContent("Type", value: waypoint.kindLabel)
                    LabeledContent("Coordonnées", value: waypoint.coordinateText)
                    if let here = location.location {
                        LabeledContent("Depuis ma position",
                                       value: String(format: "%03d°V · %.1f NM", Haversine.trueCourse(here, waypoint.coordinate),
                                                     waypoint.distanceNM(to: here)))
                    }
                    if !waypoint.name.isEmpty { Text(waypoint.name).foregroundStyle(ColorToken.textSecondary) }
                }
                Section {
                    if inPlan {
                        Button("Retirer du plan", systemImage: "minus.circle", role: .destructive) {
                            model.removeWaypoint(id: waypoint.id); dismiss()
                        }
                    } else {
                        Button("Insérer dans la route", systemImage: "point.topleft.down.to.point.bottomright.curvepath") {
                            model.insertIntoRoute(waypoint); dismiss()
                        }
                        Button("Ajouter à la fin", systemImage: "plus.circle") { model.addWaypoint(waypoint); dismiss() }
                    }
                    Button("Direct To", systemImage: "location.north.line") { model.directTo(waypoint); dismiss() }
                } footer: {
                    Text("Astuce : sur la carte, maintiens un point de la route puis fais-le glisser pour modifier le trajet.")
                }
                if waypoint.type == "user" {
                    Section {
                        Button("Supprimer ce point perso", systemImage: "trash", role: .destructive) {
                            model.removeWaypoint(id: waypoint.id)
                            model.deleteUserWaypoint(waypoint.id)
                            dismiss()
                        }
                    }
                }
            }
            .navigationTitle(waypoint.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() } } }
        }
        .presentationDetents([.medium, .large])
    }
}
