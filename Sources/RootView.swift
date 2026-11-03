import SwiftUI
import UIKit

struct RootView: View {
    // Single source of truth: the instances created once in FiveflightApp.
    // (RootView used to create its own copies, so Settings changed a different AppModel than the one the app read.)
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var model: AppModel

    @EnvironmentObject private var weather: WeatherService
    /// ForeFlight layout: Airports, Maps, Flights, Imagery (weather), More. Opens on the map.
    @State private var tab = 1

    var body: some View {
        ZStack {
            if store.ready {
                TabView(selection: $tab) {
                    AirportsScreen()
                        .tabItem { Label("Aéroports", systemImage: "airplane.circle") }
                        .tag(0)
                    MapScreen()
                        .tabItem { Label("Cartes", systemImage: "map") }
                        .tag(1)
                    FlightPlanScreen()
                        .tabItem { Label("Vols", systemImage: "airplane.departure") }
                        .tag(2)
                    WeatherScreen()
                        .tabItem { Label("Météo", systemImage: "cloud.sun") }
                        .tag(3)
                    MoreScreen()
                        .tabItem { Label("Plus", systemImage: "ellipsis") }
                        .tag(4)
                }
                .tint(FF.accent)
            } else {
                LoadingView(progress: store.progress)
            }
        }
        // One navlog for the whole app: rebuilt when the plan, performance or departure time changes.
        .task(id: model.navlogInputs) {
            await model.refreshNavlog(weather: weather)
        }
        .colorMultiply(model.nightMode ? Color(red: 1.0, green: 0.30, blue: 0.30) : .white)
        .animation(.easeInOut, value: model.nightMode)
        .onReceive(location.$location) { coordinate in
            // Feed the GPS fix to the map, nearest-airport lists and widget.
            if let coordinate {
                model.userLocation = coordinate
                FlightMonitor.shared.update(position: coordinate, groundSpeed: location.speed, course: location.course,
                                            altitudeFt: Int(location.altitude * 3.28084), model: model,
                                            airspaces: AirspaceDataManager.shared.allAirspaces, store: store)
            }
        }
        .task {
            location.start()
            await store.load()
        }
    }
}

/// Secondary tools, grouped like the system "More" pattern but with a single navigation stack.
struct MoreScreen: View {
    var body: some View {
        NavigationStack {
            List {
                Section {
                    NavigationLink { FavoritesScreen() } label: { Label("Favoris", systemImage: "star.fill") }
                    NavigationLink { AircraftScreen() } label: { Label("Avions", systemImage: "airplane") }
                    NavigationLink { LogbookScreen() } label: { Label("Carnet de vol", systemImage: "book.fill") }
                    NavigationLink { ChecklistScreen() } label: { Label("Checklists", systemImage: "checklist") }
                    NavigationLink { CalculatorsScreen() } label: { Label("Calculateurs", systemImage: "function") }
                }
                Section {
                    NavigationLink { AirspaceScreen() } label: { Label("Espaces aériens & SUA", systemImage: "shield.lefthalf.filled") }
                }
                Section {
                    NavigationLink { SettingsScreen() } label: { Label("Réglages", systemImage: "gearshape.fill") }
                }
            }
            .navigationTitle("Plus")
        }
    }
}

struct LoadingView: View {
    let progress: Double
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Theme.accentGradient)
                        .frame(width: 96, height: 96)
                        .shadow(color: Theme.accent.opacity(0.6), radius: 24)
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 6) {
                    Text("FIVEFLIGHT").font(.title3.weight(.heavy)).tracking(4)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Base aéronautique").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear).tint(Theme.accent)
                    .frame(width: 220)
                Text("\(Int(progress * 100)) %")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText()).animation(.default, value: progress)
            }
        }
    }
}
