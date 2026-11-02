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

    @State private var regionVersion = 0
    @State private var showFlightPlanPanel = false
    @State private var showLayersPanel = false
    @State private var showNearbyPanel = false
    @State private var showSearch = false
    @State private var selectedAirport: Airport?
    @State private var routePolyline: [CLLocationCoordinate2D] = []
    @State private var routeWarnings: [RouteWarning] = []
    @State private var visibleAirports: [Airport] = []
    @State private var lastFilterSpan: MKCoordinateSpan?
    @State private var lastMaxDelta: Double = 0

    // Computed properties to avoid re-filtering on every render
    private var activeAirspaces: [Airspace] {
        airspaceManager.airspaces.filter { $0.isActive }
    }

    private var currentMaxDelta: Double {
        max(model.mapRegion.span.latitudeDelta, model.mapRegion.span.longitudeDelta)
    }

    var body: some View {
        ZStack(alignment: .top) {
            // MARK: - Full Screen Map (VFRMapView with MKTileOverlay)
            VFRMapView(
                showSectional: model.showSectional,
                showWeather: model.showRadar,
                nearest: visibleAirports,
                waypoints: model.waypoints,
                categories: weatherService.categories,
                userCoord: model.userLocation,
                region: model.mapRegion,
                regionVersion: regionVersion,
                onSelect: { airport in
                    withAnimation(AnimationToken.fast) {
                        selectedAirport = airport
                        model.selectedAirport = airport
                    }
                },
                onRegionChange: { region in
                    model.mapRegion = region
                },
                airspaces: activeAirspaces,
                showAirspace: model.showAirspace,
                showTFRs: model.showTFRs
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

            // MARK: - Airport Detail Sheet
            if let airport = selectedAirport {
                AirportDetailSheet(airport: airport, store: store)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(20)
            }
        }
        .animation(AnimationToken.transition, value: showFlightPlanPanel)
        .animation(AnimationToken.transition, value: showLayersPanel)
        .animation(AnimationToken.transition, value: showNearbyPanel)
        .animation(AnimationToken.transition, value: selectedAirport)
        .sheet(isPresented: $showSearch) {
            SearchSheet(nearest: store.nearest(to: model.userLocation ?? CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795), limit: 20))
        }
        .onAppear {
            Task {
                await calculateAndUpdateRoute()
            }
            // Initial airport filtering
            visibleAirports = store.airports.filter { shouldShowAirport($0, span: model.mapRegion.span) }
            lastFilterSpan = model.mapRegion.span
        }
        .onChange(of: model.waypoints) { _, _ in
            Task { await calculateAndUpdateRoute() }
        }
        .onChange(of: routingEngine.currentMode) { _, _ in
            Task { await calculateAndUpdateRoute() }
        }
        .onChange(of: currentMaxDelta) { oldMax, newMax in
            // Only re-filter when zoom level changes significantly (not on pan)
            if abs(oldMax - newMax) > 0.1 || lastFilterSpan == nil {
                lastMaxDelta = newMax
                lastFilterSpan = model.mapRegion.span
                visibleAirports = store.airports.filter { shouldShowAirport($0, span: model.mapRegion.span) }
            }
        }
    }

    // MARK: - Helpers

    private func shouldShowAirport(_ airport: Airport, span: MKCoordinateSpan) -> Bool {
        let maxDelta = max(span.latitudeDelta, span.longitudeDelta)

        // Show major airports always, smaller ones when zoomed in
        if airport.type == "large_airport" || airport.type == "medium_airport" {
            return true
        }
        return maxDelta < 2.0 // Show small airports when zoomed in
    }

    private func calculateAndUpdateRoute() async {
        guard model.waypoints.count >= 2 else {
            routePolyline = []
            routeWarnings = []
            return
        }

        if let result = await routingEngine.calculateRoute(
            waypoints: model.waypoints,
            cruiseAltitude: model.cruiseAlt,
            mode: routingEngine.currentMode,
            airspaces: airspaceManager.airspaces
        ) {
            routePolyline = result.legs.flatMap { $0.waypoints }
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
                    if let loc = model.userLocation {
                        withAnimation(AnimationToken.map) {
                            model.mapRegion.center = loc
                            model.mapRegion.span = MKCoordinateSpan(latitudeDelta: 0.5, longitudeDelta: 0.5)
                        }
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

    var body: some View {
        HStack(spacing: SpacingToken.space6) {
            // Origin → Destination
            HStack(spacing: SpacingToken.space2) {
                Text(model.waypoints.first?.id ?? "—")
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ColorToken.textTertiary)
                Text(model.waypoints.last?.id ?? "—")
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
            }

            Divider().frame(height: 20)

            // Distance
            HStack(spacing: SpacingToken.space1) {
                Image(systemName: "point.topleft.down.curvedto.point.bottomright.forward")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ColorToken.textTertiary)
                Text(String(format: "%.0f NM", model.totalDistanceNM))
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
            }

            Divider().frame(height: 20)

            // Time
            HStack(spacing: SpacingToken.space1) {
                Image(systemName: "clock")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ColorToken.textTertiary)
                Text(model.formattedTotalTime)
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
            }

            Divider().frame(height: 20)

            // Fuel
            HStack(spacing: SpacingToken.space1) {
                Image(systemName: "fuelpump")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(ColorToken.textTertiary)
                Text(String(format: "%.1f gal", model.totalFuelGallons))
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
            }

            Spacer()

            // Routing mode badge
            HStack(spacing: SpacingToken.space1) {
                Image(systemName: routingEngine.currentMode.icon)
                    .font(.system(size: 11, weight: .medium))
                Text(routingEngine.currentMode.rawValue)
                    .font(TypographyToken.labelXSmall)
            }
            .foregroundStyle(ColorToken.brandPrimary)
            .padding(.horizontal, SpacingToken.space2)
            .padding(.vertical, SpacingToken.space1)
            .background(ColorToken.brandPrimary.opacity(0.1), in: Capsule())
        }
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