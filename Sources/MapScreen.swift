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
    @State private var selectedAirport: Airport?
    @State private var routePolyline: [CLLocationCoordinate2D] = []
    @State private var routeWarnings: [RouteWarning] = []
    @State private var visibleAirports: [Airport] = []

    private var activeAirspaces: [Airspace] {
        airspaceManager.airspaces.filter { $0.isActive }
    }

    /// US stations among the airports on screen, for the METAR-driven marker colours.
    private var metarStations: [String] {
        visibleAirports
            .filter { $0.type != "heliport" && $0.id.count == 4 && ($0.id.hasPrefix("K") || $0.id.hasPrefix("P")) }
            .prefix(100)
            .map(\.id)
            .sorted()
    }

    var body: some View {
        ZStack(alignment: .top) {
            // MARK: - Full Screen Map (VFRMapView with MKTileOverlay)
            VFRMapView(
                showSectional: model.showSectional,
                showWeather: model.showRadar,
                nearest: visibleAirports,
                waypoints: model.waypoints,
                route: routePolyline,
                track: model.track,
                categories: weatherService.categories,
                userCoord: model.userLocation,
                region: model.mapRegion,
                regionVersion: model.mapRegionVersion,
                onSelect: { airport in
                    selectedAirport = airport
                    model.selectedAirport = airport
                },
                onRegionChange: { region in
                    model.mapRegion = region
                    visibleAirports = Self.airportsToShow(store.airports, in: region)
                },
                airspaces: activeAirspaces,
                showAirspace: model.showAirspace
            )
            .ignoresSafeArea()

            // MARK: - Top Bar
            TopMapBar(
                showFlightPlanPanel: $showFlightPlanPanel,
                showLayersPanel: $showLayersPanel,
                showNearbyPanel: $showNearbyPanel,
                showSearch: $showSearch
            )

            // MARK: - Side Panels
            if showFlightPlanPanel {
                FlightPlanSidePanel(
                    isPresented: $showFlightPlanPanel,
                    routePolyline: $routePolyline,
                    routeWarnings: $routeWarnings
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(10)
            }

            if showLayersPanel {
                LayersSidePanel(isPresented: $showLayersPanel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(10)
            }

            if showNearbyPanel {
                NearbySidePanel(isPresented: $showNearbyPanel)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(10)
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
        .task(id: metarStations) {
            // Debounce: wait until the map has settled, then colour markers by flight category.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            guard !Task.isCancelled else { return }
            await weatherService.refreshMETARs(forVisible: metarStations)
        }
    }

    // MARK: - Helpers

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
            airspaces: airspaceManager.airspaces
        ) {
            // Plan, mode or altitude changed meanwhile: a newer calculation will land.
            guard model.waypoints.map(\.id) == planned.map(\.id), result.mode == routingEngine.currentMode,
                  result.cruiseAltitude == model.cruiseAlt else { return }
            routePolyline = result.legs.flatMap { $0.waypoints }
            model.routedDistanceNM = result.totalDistanceNM
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

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: SpacingToken.space3) {
                // Flight plan button
                Button {
                    withAnimation(AnimationToken.spring) { showFlightPlanPanel.toggle() }
                    showLayersPanel = false
                    showNearbyPanel = false
                } label: {
                    Image(systemName: "list.bullet.clipboard")
                        .font(.system(size: 20, weight: .medium))
                }
                .mapControlButton(selected: showFlightPlanPanel)

                Spacer()

                // Search button
                Button { showSearch = true } label: {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .medium))
                }
                .mapControlButton()

                // GPS button
                Button {
                    if let loc = model.userLocation ?? locationManager.location {
                        model.moveMap(to: loc)
                    } else {
                        locationManager.start()
                    }
                } label: {
                    Image(systemName: model.followUser ? "location.fill" : "location")
                        .font(.system(size: 20, weight: .medium))
                }
                .mapControlButton(selected: model.followUser)

                Spacer()

                // Layers button
                Button {
                    withAnimation(AnimationToken.spring) { showLayersPanel.toggle() }
                    showFlightPlanPanel = false
                    showNearbyPanel = false
                } label: {
                    Image(systemName: "square.3.layers.3d")
                        .font(.system(size: 20, weight: .medium))
                }
                .mapControlButton(selected: showLayersPanel)

                // Nearby button
                Button {
                    withAnimation(AnimationToken.spring) { showNearbyPanel.toggle() }
                    showFlightPlanPanel = false
                    showLayersPanel = false
                } label: {
                    Image(systemName: "location.circle")
                        .font(.system(size: 20, weight: .medium))
                }
                .mapControlButton(selected: showNearbyPanel)
            }
            .padding(.horizontal, SpacingToken.insetMedium)
            .padding(.top, SpacingToken.insetMedium)
            .padding(.bottom, SpacingToken.space3)

            // Route info bar
            if !model.waypoints.isEmpty {
                RouteInfoBar()
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .background(
            LinearGradient(
                colors: [ColorToken.surfaceBase.opacity(0.95), ColorToken.surfaceBase.opacity(0.0)],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

struct RouteInfoBar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var routingEngine: RoutingEngine

    /// Compact enough for an iPhone in portrait (the old bar truncated every value to "0…").
    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            Text("\(model.waypoints.first?.id ?? "—")→\(model.waypoints.last?.id ?? "—")")
                .foregroundStyle(ColorToken.textPrimary)
                .layoutPriority(-1)
            Spacer(minLength: 0)
            Text(String(format: "%.0f NM", model.totalDistanceNM)).fixedSize()
            Text(model.formattedTotalTime).fixedSize()
            Label(String(format: "%.1f gal", model.totalFuelGallons), systemImage: "fuelpump")
                .labelStyle(.titleAndIcon).fixedSize()
            Image(systemName: routingEngine.currentMode.icon)
                .foregroundStyle(ColorToken.brandPrimary)
        }
        .font(TypographyToken.monoSmall)
        .foregroundStyle(ColorToken.textPrimary)
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .padding(.horizontal, SpacingToken.insetMedium)
        .padding(.vertical, SpacingToken.space2)
        .background(ColorToken.surfaceElevated, in: RoundedRectangle(cornerRadius: RadiusToken.md))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusToken.md)
                .stroke(ColorToken.borderDefault, lineWidth: 0.5)
        )
        .shadow(ShadowToken.medium)
        .padding(.horizontal, SpacingToken.insetMedium)
        .padding(.bottom, SpacingToken.space3)
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