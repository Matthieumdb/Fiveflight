import SwiftUI

// MARK: - Root View
// Uses custom bottom tab bar (ForeFlight style) instead of system TabView

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var airspaceManager: AirspaceDataManager
    @EnvironmentObject private var weatherService: WeatherService

    @State private var selectedTab: MainTab = .map

    enum MainTab: String, CaseIterable {
        case map = "map"
        case flightPlan = "list.bullet"
        case weather = "cloud.sun"
        case airspace = "airplane.departure"
        case more = "ellipsis"

        var title: String {
            switch self {
            case .map: return "Map"
            case .flightPlan: return "Flights"
            case .weather: return "Wx"
            case .airspace: return "Airspace"
            case .more: return "More"
            }
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            // Main content - no system TabView
            Group {
                switch selectedTab {
                case .map:
                    MapScreen()
                case .flightPlan:
                    FlightPlanTabView()
                case .weather:
                    WeatherScreen()
                case .airspace:
                    AirspaceScreen()
                case .more:
                    MoreTabView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            // Custom Bottom Tab Bar (single source of truth)
            CustomTabBar(selectedTab: $selectedTab)
                .padding(.bottom, 0) // Respects safe area automatically
        }
        .ignoresSafeArea(.container, edges: .bottom) // Allow bar to extend to bottom
        .background(ColorToken.surfaceBase)
        .onAppear {
            Task {
                await store.loadData()
                await airspaceManager.refresh()
            }
        }
    }
}

// MARK: - Custom Tab Bar (ForeFlight-style)

struct CustomTabBar: View {
    @Binding var selectedTab: RootView.MainTab
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: 0) {
            ForEach(RootView.MainTab.allCases, id: \.self) { tab in
                TabBarButton(
                    icon: tab.rawValue,
                    label: tab.title,
                    isSelected: selectedTab == tab,
                    badge: badgeForTab(tab)
                ) {
                    withAnimation(AnimationToken.tabSwitch) {
                        // Close side panels when switching main tabs
                        if selectedTab == .map && tab != .map {
                            model.showingAirportDetail = false
                            model.showingWeather = false
                            model.showingAirspace = false
                            model.showingCalculators = false
                            model.showingSettings = false
                        }
                        selectedTab = tab
                    }
                }
            }
        }
        .padding(.horizontal, SpacingToken.space2)
        .padding(.top, SpacingToken.space3)
        .padding(.bottom, SpacingToken.space2)
        .background(
            LinearGradient.bottomBarGradient
                .ignoresSafeArea(edges: .bottom)
        )
        .overlay(
            Rectangle()
                .fill(ColorToken.borderDefault)
                .frame(height: 0.5),
            alignment: .top
        )
        .shadow(ShadowToken.bottomBar)
    }

    private func badgeForTab(_ tab: RootView.MainTab) -> String? {
        switch tab {
        case .flightPlan:
            return model.waypoints.isEmpty ? nil : "\(model.waypoints.count)"
        default:
            return nil
        }
    }
}

struct TabBarButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    var badge: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SpacingToken.space0) {
                ZStack(alignment: .topTrailing) {
                    Image(systemName: icon)
                        .font(.system(size: 22, weight: .medium))
                        .foregroundStyle(isSelected ? ColorToken.brandPrimary : ColorToken.textTertiary)
                        .symbolVariant(isSelected ? .fill : .none)

                    if let badge = badge {
                        Text(badge)
                            .font(TypographyToken.labelXSmall)
                            .foregroundStyle(ColorToken.textOnBrand)
                            .frame(minWidth: 16, minHeight: 16)
                            .background(ColorToken.danger, in: Capsule())
                            .offset(x: 8, y: -8)
                    }
                }
                .frame(height: 24)

                Text(label)
                    .font(TypographyToken.labelXSmall)
                    .foregroundStyle(isSelected ? ColorToken.brandPrimary : ColorToken.textTertiary)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Flight Plan Tab View

struct FlightPlanTabView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            FlightPlanListView()
                .environmentObject(model)
        }
    }
}

struct FlightPlanListView: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        List {
            if model.waypoints.isEmpty {
                ContentUnavailableView(
                    "No Route",
                    systemImage: "map",
                    description: Text("Add waypoints to create a flight plan")
                )
                .listRowBackground(ColorToken.surfaceBase)
            } else {
                ForEach(model.waypoints.indices, id: \.self) { index in
                    let airport = model.waypoints[index]
                    HStack {
                        Text("\(index + 1)")
                            .font(TypographyToken.monoMedium)
                            .foregroundStyle(index == 0 ? ColorToken.success : (index == model.waypoints.count - 1 ? ColorToken.danger : ColorToken.brandPrimary))
                            .frame(width: 24)

                        VStack(alignment: .leading) {
                            Text(airport.id)
                                .font(TypographyToken.monoMedium)
                            Text(airport.name)
                                .font(TypographyToken.bodySmall)
                                .foregroundStyle(ColorToken.textSecondary)
                        }

                        Spacer()

                        if index > 0 {
                            let prev = model.waypoints[index - 1]
                            let dist = Haversine.nauticalMiles(prev.coordinate, airport.coordinate)
                            Text("\(Int(dist)) NM")
                                .font(TypographyToken.monoSmall)
                                .foregroundStyle(ColorToken.textTertiary)
                        }
                    }
                    .padding(.vertical, SpacingToken.space1)
                }
                .onDelete { indexSet in
                    for index in indexSet {
                        model.removeWaypoint(at: index)
                    }
                }
                .onMove { indices, newOffset in
                    model.waypoints.move(fromOffsets: indices, toOffset: newOffset)
                }
            }
        }
        .navigationTitle("Flight Plan")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    // Would show airport search
                } label: {
                    Image(systemName: "plus")
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
        }
    }
}

// MARK: - More Tab View

struct MoreTabView: View {
    @State private var moreSelection: MoreTab = .favorites

    enum MoreTab: String, CaseIterable {
        case favorites = "star"
        case calculators = "function"
        case checklists = "checklist"
        case logbook = "book"
        case settings = "gear"

        var title: String {
            switch self {
            case .favorites: return "Favorites"
            case .calculators: return "Calculators"
            case .checklists: return "Checklists"
            case .logbook: return "Logbook"
            case .settings: return "Settings"
            }
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Content
                Group {
                    switch moreSelection {
                    case .favorites:
                        FavoritesScreen()
                    case .calculators:
                        CalculatorsScreen()
                    case .checklists:
                        ChecklistScreen()
                    case .logbook:
                        LogbookScreen()
                    case .settings:
                        SettingsScreen()
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                // More tab picker (segmented control style)
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpacingToken.space2) {
                        ForEach(MoreTab.allCases, id: \.self) { tab in
                            Button {
                                withAnimation(AnimationToken.tabSwitch) { moreSelection = tab }
                            } label: {
                                VStack(spacing: SpacingToken.space1) {
                                    Image(systemName: tab.rawValue)
                                        .font(.system(size: 20, weight: .medium))
                                    Text(tab.title)
                                        .font(TypographyToken.labelXSmall)
                                }
                                .foregroundStyle(moreSelection == tab ? ColorToken.brandPrimary : ColorToken.textTertiary)
                                .padding(.horizontal, SpacingToken.space4)
                                .padding(.vertical, SpacingToken.space2)
                                .background(
                                    moreSelection == tab ? ColorToken.brandPrimary.opacity(0.1) : Color.clear,
                                    in: Capsule()
                                )
                            }
                        }
                    }
                    .padding(.horizontal, SpacingToken.insetMedium)
                }
                .padding(.vertical, SpacingToken.space2)
                .background(ColorToken.surfaceElevated)
            }
        }
        .navigationTitle("More")
        .navigationBarTitleDisplayMode(.large)
    }
}

// MARK: - Settings Screen (placeholder)

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore

    var body: some View {
        List {
            Section {
                HStack {
                    Label("Airport Database", systemImage: "cylinder")
                    Spacer()
                    if store.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text("\(store.airports.count) airports")
                            .foregroundStyle(ColorToken.textSecondary)
                    }
                }

                HStack {
                    Label("Airspace Data", systemImage: "shield")
                    Spacer()
                    if airspaceManager.isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else if let date = airspaceManager.lastUpdate {
                        Text(date.formatted(date: .abbreviated, time: .shortened))
                            .font(TypographyToken.monoSmall)
                            .foregroundStyle(ColorToken.textSecondary)
                    } else {
                        Text("Not loaded")
                            .foregroundStyle(ColorToken.textTertiary)
                    }
                }
            } header: {
                Text("Data")
            }

            Section {
                Toggle("Show User Location", isOn: $model.showUserLocation)
                Toggle("Follow User", isOn: $model.followUser)
            } header: {
                Text("Map")
            }

            Section {
                NavigationLink("Aircraft Profiles") {
                    AircraftProfilesView()
                }
            } header: {
                Text("Aircraft")
            }

            Section {
                Button("Clear All Favorites") {
                    model.favorites.removeAll()
                }
                .foregroundStyle(ColorToken.danger)

                Button("Clear Flight Log") {
                    // Would clear logbook
                }
                .foregroundStyle(ColorToken.danger)
            } header: {
                Text("Danger Zone")
            }
        }
        .navigationTitle("Settings")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ColorToken.surfaceBase)
    }
}

struct AircraftProfilesView: View {
    @EnvironmentObject private var model: AppModel
    @State private var showingAdd = false

    var body: some View {
        List {
            ForEach(model.aircraftProfiles) { aircraft in
                Button {
                    model.selectAircraft(aircraft)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(aircraft.name)
                                .font(TypographyToken.bodyMedium)
                                .foregroundStyle(ColorToken.textPrimary)
                            Text("\(aircraft.type) • \(Int(aircraft.cruiseSpeed)) kt • \(aircraft.fuelBurn, specifier: "%.1f") gph")
                                .font(TypographyToken.bodySmall)
                                .foregroundStyle(ColorToken.textSecondary)
                        }
                        Spacer()
                        if model.selectedAircraft?.id == aircraft.id {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(ColorToken.brandPrimary)
                        }
                    }
                }
                .buttonStyle(.plain)
            }
            .onDelete { indices in
                for index in indices {
                    model.aircraftProfiles.remove(at: index)
                }
            }

            Button {
                showingAdd = true
            } label: {
                Label("Add Aircraft", systemImage: "plus.circle.fill")
                    .foregroundStyle(ColorToken.brandPrimary)
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("Aircraft Profiles")
        .sheet(isPresented: $showingAdd) {
            AddAircraftSheet()
        }
    }
}

struct AddAircraftSheet: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var type = ""
    @State private var cruiseSpeed = 120.0
    @State private var fuelBurn = 10.0
    @State private var usableFuel = 50.0
    @State private var maxWeight = 2550
    @State private var emptyWeight = 1650
    @State private var cgForward = 82
    @State private var cgAft = 88

    var body: some View {
        NavigationStack {
            Form {
                Section("Basic Info") {
                    TextField("Name (e.g. \"C172 N12345\")", text: $name)
                    TextField("Type (e.g. \"Cessna 172\")", text: $type)
                }
                Section("Performance") {
                    HStack {
                        Text("Cruise Speed")
                        Spacer()
                        TextField("KTAS", value: $cruiseSpeed, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Fuel Burn")
                        Spacer()
                        TextField("GPH", value: $fuelBurn, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Usable Fuel")
                        Spacer()
                        TextField("GAL", value: $usableFuel, format: .number)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
                Section("Weight & Balance") {
                    HStack {
                        Text("Max Weight")
                        Spacer()
                        TextField("LBS", value: $maxWeight, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("Empty Weight")
                        Spacer()
                        TextField("LBS", value: $emptyWeight, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("CG Forward Limit")
                        Spacer()
                        TextField("IN", value: $cgForward, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Text("CG Aft Limit")
                        Spacer()
                        TextField("IN", value: $cgAft, format: .number)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }
            .navigationTitle("Add Aircraft")
            .toolbar(content: {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let aircraft = AircraftProfile(
                            name: name,
                            type: type,
                            cruiseSpeed: cruiseSpeed,
                            fuelBurn: fuelBurn,
                            usableFuel: usableFuel,
                            maxWeight: maxWeight,
                            emptyWeight: emptyWeight,
                            cgForward: cgForward,
                            cgAft: cgAft
                        )
                        model.aircraftProfiles.append(aircraft)
                        if model.selectedAircraft == nil {
                            model.selectAircraft(aircraft)
                        }
                        dismiss()
                    }
                    .disabled(name.isEmpty || type.isEmpty)
                }
            })
        }
    }
}


// Need to reference AirspaceDataManager in SettingsScreen
import SwiftUI
@MainActor
private var airspaceManager: AirspaceDataManager { AirspaceDataManager.shared }