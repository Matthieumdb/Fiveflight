import SwiftUI
import CoreLocation

// MARK: - Map chrome (ForeFlight Maps view)
//
// Charcoal toolbar across the top: map selector (base chart + overlays), map settings, FPL (route
// editor), then search, nearest and centre-on-ownship. The route editor docks under the toolbar with
// the route as editable text and its action buttons; the instrument panel sits under it; navlog and
// vertical profile open as a drawer at the bottom.

enum MapDrawer: String, Identifiable {
    case navlog, profile
    var id: String { rawValue }
}

struct FFMapToolbar: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var locationManager: LocationManager
    @Binding var showLayers: Bool
    @Binding var showRouteEditor: Bool
    @Binding var showNearby: Bool
    @Binding var showSettings: Bool
    @Binding var showSearch: Bool

    private var chartTitle: String {
        if !model.showSectional { return model.showSatellite ? "Satellite" : "Plan" }
        return MapChart(rawValue: model.mapChart)?.label ?? "Carte"
    }

    var body: some View {
        HStack(spacing: 8) {
            FFBarButton(title: chartTitle, icon: "square.3.layers.3d.down.right", active: showLayers) {
                toggle(.layers)
            }
            FFBarButton(title: nil, icon: "gearshape") { showSettings = true }
            FFBarButton(title: "FPL", icon: nil, active: showRouteEditor) {
                toggle(.route)
            }
            Spacer(minLength: 0)
            FFBarButton(title: nil, icon: "magnifyingglass") { showSearch = true }
            FFBarButton(title: nil, icon: "list.bullet.indent", active: showNearby) {
                toggle(.nearby)
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
    }

    private enum Panel { case layers, route, nearby }

    /// One panel at a time, as in ForeFlight.
    private func toggle(_ panel: Panel) {
        let wasOpen: Bool
        switch panel {
        case .layers: wasOpen = showLayers
        case .route: wasOpen = showRouteEditor
        case .nearby: wasOpen = showNearby
        }
        withAnimation(AnimationToken.spring) {
            showLayers = panel == .layers && !wasOpen
            showRouteEditor = panel == .route && !wasOpen
            showNearby = panel == .nearby && !wasOpen
        }
    }
}

// MARK: - Map selector

/// ForeFlight map selector: base maps as a row of tiles, overlays as a checked list.
struct MapLayerSelector: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    private enum Base: String, CaseIterable, Identifiable {
        case sectional, tac, ifrLow, ifrHigh, street, satellite
        var id: String { rawValue }
        var title: String {
            switch self {
            case .sectional: return "Sectional"
            case .tac: return "TAC"
            case .ifrLow: return "IFR bas"
            case .ifrHigh: return "IFR haut"
            case .street: return "Plan"
            case .satellite: return "Satellite"
            }
        }
        var icon: String {
            switch self {
            case .sectional: return "map"
            case .tac: return "map.circle"
            case .ifrLow: return "point.3.connected.trianglepath.dotted"
            case .ifrHigh: return "point.3.filled.connected.trianglepath.dotted"
            case .street: return "car"
            case .satellite: return "globe.americas"
            }
        }
        var chart: MapChart? {
            switch self {
            case .sectional: return .sectional
            case .tac: return .terminal
            case .ifrLow: return .ifrLow
            case .ifrHigh: return .ifrHigh
            case .street, .satellite: return nil
            }
        }
    }

    private var current: Base {
        guard model.showSectional else { return model.showSatellite ? .satellite : .street }
        switch MapChart(rawValue: model.mapChart) {
        case .terminal: return .tac
        case .ifrLow: return .ifrLow
        case .ifrHigh: return .ifrHigh
        default: return .sectional
        }
    }

    private func select(_ base: Base) {
        if let chart = base.chart {
            model.mapChart = chart.rawValue
            model.showSectional = true
        } else {
            model.showSectional = false
            model.showSatellite = base == .satellite
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            FFHeader("CARTE DE BASE")
                .padding(.horizontal, 12).padding(.top, 10)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Base.allCases) { base in
                        Button { select(base) } label: {
                            VStack(spacing: 4) {
                                Image(systemName: base.icon).font(.system(size: 20))
                                    .frame(width: 64, height: 44)
                                    .background(current == base ? FF.accent : FF.barSecondary,
                                                in: RoundedRectangle(cornerRadius: 6))
                                Text(base.title).font(.custom("Barlow-SemiBold", size: 11, relativeTo: .body))
                            }
                            .foregroundStyle(current == base ? ColorToken.textOnBrand : ColorToken.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 12).padding(.vertical, 8)
            }
            Divider().overlay(ColorToken.borderDefault)
            FFHeader("SURCOUCHES")
                .padding(.horizontal, 12).padding(.top, 10).padding(.bottom, 4)
            ScrollView {
                VStack(spacing: 0) {
                    overlayRow("Radar (NEXRAD)", "cloud.rain", $model.showRadar)
                    overlayRow("Radar ADS-B (FIS-B)", "dot.radiowaves.up.forward", $model.showFISBRadar)
                    overlayRow("Satellite infrarouge", "cloud.fill", $model.showIR)
                    overlayRow("Foudre", "bolt.fill", $model.showLightning)
                    overlayRow("Espaces aériens et TFR", "shield.lefthalf.filled", $model.showAirspace)
                    overlayRow("Imagerie satellite sous la carte", "globe.americas.fill", $model.showSatellite)
                    overlayRow("Anneau de plané", "circle.dashed", $model.showGlideRing)
                    overlayRow("Panneau d'instruments", "gauge.with.dots.needle.33percent", $model.showInstruments)
                }
            }
            .frame(maxHeight: 300)
        }
        .padding(.bottom, 6)
        .background(FF.bar.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .shadow(color: ColorToken.shadowMedium, radius: 12, y: 4)
        .frame(maxWidth: 420)
        .padding(.horizontal, 8)
        .padding(.top, 4)
    }

    private func overlayRow(_ title: String, _ icon: String, _ isOn: Binding<Bool>) -> some View {
        Button { isOn.wrappedValue.toggle() } label: {
            HStack(spacing: 10) {
                Image(systemName: icon).frame(width: 22).foregroundStyle(isOn.wrappedValue ? FF.accent : FF.label)
                Text(title).foregroundStyle(ColorToken.textPrimary)
                Spacer()
                if isOn.wrappedValue {
                    Image(systemName: "checkmark").font(.system(size: 14, weight: .bold)).foregroundStyle(FF.accent)
                }
            }
            .font(.system(size: 15))
            .padding(.horizontal, 12)
            .frame(height: 40)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Map settings

/// ForeFlight map settings (gear): receivers, offline data, alerts and the glide ring.
struct MapSettingsSheet: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var airspace = AirspaceDataManager.shared
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Toggle("Annonces vocales", isOn: $model.voiceAlerts)
                    Toggle("Anneau de plané", isOn: $model.showGlideRing)
                    Stepper(value: $model.glideRatio, in: 5...20, step: 0.5) {
                        HStack {
                            Text("Finesse")
                            Spacer()
                            Text(String(format: "%.1f:1", model.glideRatio)).foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Toggle("Panneau d'instruments", isOn: $model.showInstruments)
                } header: { FFHeader("Vol") }

                ADSBSection()

                Section {
                    Button {
                        Task { await airspace.refresh() }
                    } label: {
                        HStack {
                            Text("Mettre à jour espaces aériens et TFR")
                            Spacer()
                            if airspace.isLoading { ProgressView() }
                        }
                    }
                    .disabled(airspace.isLoading)
                    if let last = airspace.lastUpdate {
                        HStack {
                            Text("Dernière mise à jour")
                            Spacer()
                            Text(last.frDateTime).foregroundStyle(.secondary)
                        }
                    }
                } header: { FFHeader("Données") }

                OfflineChartsSection()
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Réglages de la carte")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() } } }
        }
    }
}

// MARK: - Route editor

/// ForeFlight route editor: the route as text (identifiers separated by spaces), action buttons,
/// then the Dist · ETE · ETA · Carb strip.
struct RouteEditorPanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var routingEngine: RoutingEngine
    @Binding var drawer: MapDrawer?
    @State private var text = ""
    @State private var unknown: [String] = []
    @FocusState private var editing: Bool

    private static let vfrAltitudes = [1500, 2500, 3500, 4500, 5500, 6500, 7500, 8500, 9500, 10500, 11500, 12500]

    private var routeString: String { model.waypoints.map(\.id).joined(separator: " ") }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                TextField("Route", text: $text,
                          prompt: Text("Départ, points, destination").foregroundColor(Color(white: 0.42)))
                    .font(.system(size: 15, weight: .semibold, design: .monospaced))
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .focused($editing)
                    .submitLabel(.done)
                    .onSubmit(apply)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(Color.white, in: RoundedRectangle(cornerRadius: 6))
                    .foregroundStyle(.black)
                if editing {
                    FFBarButton(title: "OK", icon: nil, active: true) { apply() }
                }
            }
            .padding(.horizontal, 10)
            .padding(.top, 8)

            if !unknown.isEmpty {
                Text("Inconnu : " + unknown.joined(separator: ", "))
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ColorToken.danger)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }

            // One row that fits an iPhone: altitude, routing, navlog, profile, then the rest in a menu.
            HStack(spacing: 6) {
                Menu {
                    ForEach(Self.vfrAltitudes, id: \.self) { alt in
                        Button {
                            model.cruiseAlt = alt
                        } label: {
                            if alt == model.cruiseAlt { Label("\(alt) ft", systemImage: "checkmark") } else { Text("\(alt) ft") }
                        }
                    }
                } label: {
                    barLabel("\(model.cruiseAlt) ft")
                }
                Menu {
                    Picker("Routage", selection: $routingEngine.currentMode) {
                        ForEach(RoutingEngine.RoutingMode.allCases) { Label($0.rawValue, systemImage: $0.icon).tag($0) }
                    }
                } label: {
                    barLabel(routingEngine.currentMode.rawValue)
                }
                FFBarButton(title: "Navlog", icon: nil, active: drawer == .navlog) { toggle(.navlog) }
                FFBarButton(title: "Profil", icon: nil, active: drawer == .profile) { toggle(.profile) }
                Spacer(minLength: 0)
                Menu {
                    Button("Enregistrer", systemImage: "square.and.arrow.down") { model.savePlan() }
                    Button("Inverser", systemImage: "arrow.left.arrow.right") { model.waypoints.reverse() }
                    Button("Ouvrir dans Vols", systemImage: "airplane.departure") { FFRouter.shared.tab = .flights }
                    Button("Effacer la route", systemImage: "trash", role: .destructive) {
                        model.clearFlightPlan()
                        drawer = nil
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(ColorToken.textPrimary)
                        .frame(width: 36, height: 30)
                        .background(FF.barSecondary, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            .lineLimit(1)
            .padding(.horizontal, 10)
            .padding(.vertical, 6)

            if model.waypoints.count >= 2 {
                RouteInfoBar(showChips: false)
            }
        }
        .background(FF.bar)
        .onAppear { text = routeString }
        .onChange(of: routeString) { _, new in
            if !editing { text = new }
        }
    }

    private func barLabel(_ title: String) -> some View {
        HStack(spacing: 3) {
            Text(title).font(.custom("Barlow-SemiBold", size: 14, relativeTo: .body)).lineLimit(1)
            Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold))
        }
        .foregroundStyle(ColorToken.textPrimary)
        .padding(.horizontal, 8)
        .frame(height: 30)
        .background(FF.barSecondary, in: RoundedRectangle(cornerRadius: 6))
    }

    private func toggle(_ d: MapDrawer) {
        withAnimation(AnimationToken.spring) { drawer = drawer == d ? nil : d }
    }

    /// Parses the route text: each identifier is an airport, navaid, fix or user point.
    private func apply() {
        editing = false
        let tokens = text.uppercased()
            .split(whereSeparator: { $0 == " " || $0 == "," || $0 == "-" || $0 == "\n" })
            .map(String.init)
        var points: [Airport] = []
        var missing: [String] = []
        for token in tokens {
            if token == AppModel.gpsWaypointID, let gps = model.waypoints.first(where: { $0.id == token }) {
                points.append(gps)
            } else if let p = model.resolveWaypoint(token, store: store) {
                if !points.contains(where: { $0.id == p.id }) { points.append(p) }
            } else {
                missing.append(token)
            }
        }
        unknown = missing
        model.waypoints = points
        text = routeString
    }
}

// MARK: - Bottom drawer

/// Navlog or vertical profile under the map, with a charcoal title bar.
struct MapBottomDrawer: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var airspaceManager: AirspaceDataManager
    @Binding var drawer: MapDrawer?

    var body: some View {
        if let current = drawer {
            VStack(spacing: 0) {
                HStack {
                    Text(current == .navlog ? "NAVLOG" : "PROFIL VERTICAL")
                        .font(.custom("BarlowCondensed-SemiBold", size: 13, relativeTo: .footnote))
                        .tracking(0.8)
                        .foregroundStyle(ColorToken.brandSecondary)
                    Spacer()
                    Button {
                        withAnimation(AnimationToken.spring) { drawer = nil }
                    } label: {
                        Image(systemName: "xmark").font(.system(size: 13, weight: .bold)).foregroundStyle(ColorToken.textPrimary)
                    }
                }
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(FF.bar)
                Group {
                    switch current {
                    case .navlog:
                        NavlogTable()
                    case .profile:
                        VerticalProfileView(path: model.routePath, cruiseAlt: model.cruiseAlt,
                                            airspaces: airspaceManager.allAirspaces,
                                            vertical: model.verticalProfile, departureElevation: model.waypoints.first?.elevationFt ?? 0)
                            .padding(8)
                    }
                }
                .frame(height: 280)
                .frame(maxWidth: .infinity)
                .clipped()
                .background(Color(.systemBackground))
            }
            .transition(.move(edge: .bottom))
        }
    }
}
