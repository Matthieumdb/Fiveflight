import Foundation
import SwiftUI
import CoreLocation
import MapKit

/// Central app state - single source of truth
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    // MARK: - Flight Plan
    @Published var waypoints: [Airport] = []
    @Published var cruiseAlt: Int = 5500
    @Published var cruiseGS: Double = 120
    @Published var fuelBurn: Double = 10
    @Published var reserveMin: Int = 30

    // MARK: - Map State
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
        span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
    )
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var showUserLocation = true
    @Published var followUser = false

    // MARK: - Layer Visibility
    @Published var showSectional = true
    @Published var showRadar = false
    @Published var showAirspace = true
    @Published var showAirways = false
    @Published var showTFRs = true
    @Published var showWindsAloft = false
    @Published var showPIREPs = false
    @Published var showAIRMETs = false

    // MARK: - UI State
    @Published var selectedAirport: Airport?
    @Published var showingAirportDetail = false
    @Published var showingSearch = false
    @Published var showingFlightPlan = false
    @Published var showingCalculators = false
    @Published var showingChecklist = false
    @Published var showingLogbook = false
    @Published var showingSettings = false
    @Published var showingWeather = false
    @Published var showingAirspace = false
    @Published var showingNearby = false

    // MARK: - Persistence
    @Published var favorites: Set<String> = []
    @Published var recents: [String] = []
    @Published var aircraftProfiles: [AircraftProfile] = []
    @Published var selectedAircraft: AircraftProfile?

    // MARK: - Data
    @Published var lastWeatherUpdate: Date?
    @Published var lastAirspaceUpdate: Date?

    private let defaults = UserDefaults.standard
    private let favoritesKey = "favorites"
    private let recentsKey = "recents"
    private let aircraftKey = "aircraftProfiles"

    private init() {
        loadPersistence()
        setupDefaultAircraft()
    }

    // MARK: - Flight Plan Management

    func addWaypoint(_ airport: Airport) {
        // Avoid duplicates
        if !waypoints.contains(where: { $0.id == airport.id }) {
            waypoints.append(airport)
            addToRecents(airport.id)
        }
    }

    func insertWaypoint(_ airport: Airport, at index: Int) {
        if !waypoints.contains(where: { $0.id == airport.id }) {
            waypoints.insert(airport, at: index)
            addToRecents(airport.id)
        }
    }

    func removeWaypoint(_ airport: Airport) {
        waypoints.removeAll { $0.id == airport.id }
    }

    func removeWaypoint(at index: Int) {
        guard index >= 0 && index < waypoints.count else { return }
        waypoints.remove(at: index)
    }

    func clearFlightPlan() {
        waypoints.removeAll()
    }

    func reverseFlightPlan() {
        waypoints.reverse()
    }

    // MARK: - Computed Flight Plan Data

    var legs: [FlightLeg] {
        guard waypoints.count >= 2 else { return [] }
        return zip(waypoints, waypoints.dropFirst()).enumerated().map { index, pair in
            let (from, to) = pair
            let distance = Haversine.nauticalMiles(from.coordinate, to.coordinate)
            let course = Haversine.trueCourse(from.coordinate, to.coordinate)
            let time = cruiseGS > 0 ? distance / cruiseGS * 60 : 0
            let fuel = cruiseGS > 0 ? distance / cruiseGS * fuelBurn : 0
            return FlightLeg(
                index: index,
                from: from,
                to: to,
                distanceNM: distance,
                trueCourse: course,
                timeMinutes: time,
                fuelGallons: fuel
            )
        }
    }

    var totalDistanceNM: Double {
        legs.reduce(0) { $0 + $1.distanceNM }
    }

    var totalTimeMinutes: Double {
        legs.reduce(0) { $0 + $1.timeMinutes }
    }

    var totalFuelGallons: Double {
        let enroute = legs.reduce(0) { $0 + $1.fuelGallons }
        let reserve = Double(reserveMin) / 60.0 * fuelBurn
        return enroute + reserve
    }

    var formattedTotalTime: String {
        let m = Int(totalTimeMinutes.rounded())
        return m >= 60 ? "\(m/60)h\(String(format: "%02d", m%60))m" : "\(m)m"
    }

    // MARK: - Favorites

    func toggleFavorite(_ ident: String) {
        if favorites.contains(ident) {
            favorites.remove(ident)
        } else {
            favorites.insert(ident)
        }
        savePersistence()
    }

    func isFavorite(_ ident: String) -> Bool {
        favorites.contains(ident)
    }

    // MARK: - Recents

    private func addToRecents(_ ident: String) {
        recents.removeAll { $0 == ident }
        recents.insert(ident, at: 0)
        if recents.count > 20 { recents = Array(recents.prefix(20)) }
        savePersistence()
    }

    // MARK: - Aircraft Profiles

    private func setupDefaultAircraft() {
        if aircraftProfiles.isEmpty {
            aircraftProfiles = [
                AircraftProfile(
                    name: "Cessna 172S",
                    type: "C172",
                    cruiseSpeed: 120,
                    fuelBurn: 10,
                    usableFuel: 53,
                    maxWeight: 2550,
                    emptyWeight: 1650,
                    cgForward: 35,
                    cgAft: 47
                ),
                AircraftProfile(
                    name: "Piper PA-28-181",
                    type: "P28A",
                    cruiseSpeed: 115,
                    fuelBurn: 9.5,
                    usableFuel: 48,
                    maxWeight: 2550,
                    emptyWeight: 1600,
                    cgForward: 35,
                    cgAft: 47
                ),
                AircraftProfile(
                    name: "Cirrus SR22",
                    type: "SR22",
                    cruiseSpeed: 180,
                    fuelBurn: 14,
                    usableFuel: 81,
                    maxWeight: 3400,
                    emptyWeight: 2300,
                    cgForward: 35,
                    cgAft: 47
                )
            ]
            selectedAircraft = aircraftProfiles.first
            savePersistence()
        }
    }

    func selectAircraft(_ aircraft: AircraftProfile) {
        selectedAircraft = aircraft
        cruiseGS = aircraft.cruiseSpeed
        fuelBurn = aircraft.fuelBurn
        savePersistence()
    }

    // MARK: - Logbook

    func logFlight(from: String, to: String, nm: Int, eteMinutes: Int) {
        let entry = LogbookEntry(
            date: Date(),
            from: from,
            to: to,
            distanceNM: nm,
            eteMinutes: eteMinutes,
            aircraft: selectedAircraft?.name ?? "Unknown",
            conditions: "VFR"
        )
        // Would save to persistent store
        print("Logged flight: \(entry)")
    }

    // MARK: - Persistence

    private func loadPersistence() {
        favorites = Set(defaults.stringArray(forKey: favoritesKey) ?? [])
        recents = defaults.stringArray(forKey: recentsKey) ?? []

        if let data = defaults.data(forKey: aircraftKey),
           let decoded = try? JSONDecoder().decode([AircraftProfile].self, from: data) {
            aircraftProfiles = decoded
            selectedAircraft = decoded.first
        }
    }

    private func savePersistence() {
        defaults.set(Array(favorites), forKey: favoritesKey)
        defaults.set(recents, forKey: recentsKey)
        if let data = try? JSONEncoder().encode(aircraftProfiles) {
            defaults.set(data, forKey: aircraftKey)
        }
    }
}

// MARK: - Supporting Models

struct FlightLeg: Identifiable {
    let id = UUID()
    let index: Int
    let from: Airport
    let to: Airport
    let distanceNM: Double
    let trueCourse: Int
    let timeMinutes: Double
    let fuelGallons: Double

    var formattedDistance: String { String(format: "%.0f NM", distanceNM) }
    var formattedTime: String {
        let m = Int(timeMinutes.rounded())
        return m >= 60 ? "\(m/60)h\(String(format: "%02d", m%60))m" : "\(m)m"
    }
    var formattedFuel: String { String(format: "%.1f gal", fuelGallons) }
    var courseString: String { String(format: "%03d°", trueCourse) }
}

struct AircraftProfile: Identifiable, Codable, Hashable {
    let id = UUID()
    var name: String
    var type: String
    var cruiseSpeed: Double
    var fuelBurn: Double
    var usableFuel: Double
    var maxWeight: Int
    var emptyWeight: Int
    var cgForward: Int
    var cgAft: Int

    var usefulLoad: Int { maxWeight - emptyWeight }
    var enduranceHours: Double { usableFuel / fuelBurn }
    var rangeNM: Double { enduranceHours * cruiseSpeed }
}

struct LogbookEntry: Identifiable, Codable {
    let id = UUID()
    let date: Date
    let from: String
    let to: String
    let distanceNM: Int
    let eteMinutes: Int
    let aircraft: String
    let conditions: String
}