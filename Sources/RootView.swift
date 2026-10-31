import SwiftUI

// MARK: - Root View

struct RootView: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var airspaceManager: AirspaceDataManager
    @EnvironmentObject private var weatherService: WeatherService
    @State private var selectedTab = 0

    private let tabs = [
        (title: "Map", icon: "map"),
        (title: "Flight Plan", icon: "list.bullet"),
        (title: "Weather", icon: "cloud.sun"),
        (title: "Airspace", icon: "airplane.departure"),
        (title: "More", icon: "ellipsis")
    ]

    var body: some View {
        TabView(selection: $selectedTab) {
            // Map Tab
            MapScreen()
                .tabItem {
                    Label(tabs[0].title, systemImage: tabs[0].icon)
                }
                .tag(0)

            // Flight Plan Tab
            FlightPlanTabView()
                .tabItem {
                    Label(tabs[1].title, systemImage: tabs[1].icon)
                }
                .tag(1)

            // Weather Tab
            WeatherScreen()
                .tabItem {
                    Label(tabs[2].title, systemImage: tabs[2].icon)
                }
                .tag(2)

            // Airspace Tab
            AirspaceScreen()
                .tabItem {
                    Label(tabs[3].title, systemImage: tabs[3].icon)
                }
                .tag(3)

            // More Tab
            MoreTabView()
                .tabItem {
                    Label(tabs[4].title, systemImage: tabs[4].icon)
                }
                .tag(4)
        }
        .tint(ColorToken.brandPrimary)
        .onAppear {
            // Load data on launch
            Task {
                await store.loadData()
                await airspaceManager.refresh()
            }
        }
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
    var body: some View {
        TabView {
            FavoritesScreen()
                .tabItem {
                    Label("Favorites", systemImage: "star")
                }

            CalculatorsScreen()
                .tabItem {
                    Label("Calculators", systemImage: "function")
                }

            ChecklistScreen()
                .tabItem {
                    Label("Checklists", systemImage: "checklist")
                }

            LogbookScreen()
                .tabItem {
                    Label("Logbook", systemImage: "book")
                }

            // Settings placeholder
            Text("Settings")
                .font(TypographyToken.bodyLarge)
                .foregroundStyle(ColorToken.textPrimary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(ColorToken.surfaceBase)
                .tabItem {
                    Label("Settings", systemImage: "gear")
                }
        }
    }
}
