import Foundation
import MapKit
import CoreLocation
import SwiftUI

struct LogEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var from: String
    var to: String
    var nm: Int
    var eteMinutes: Int
}

struct AircraftProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    let name: String
    let type: String
    let cruiseSpeed: Double
    let fuelBurn: Double
    let capacityGal: Double

    var enduranceHours: Double {
        guard fuelBurn > 0 else { return 0 }
        return capacityGal / fuelBurn
    }

    static let defaultProfiles: [AircraftProfile] = [
        AircraftProfile(name: "Cessna 172S", type: "C172", cruiseSpeed: 122, fuelBurn: 8.5, capacityGal: 53),
        AircraftProfile(name: "Piper PA-28-180", type: "PA28", cruiseSpeed: 124, fuelBurn: 9.0, capacityGal: 48),
        AircraftProfile(name: "Cirrus SR22T", type: "SR22", cruiseSpeed: 183, fuelBurn: 14.0, capacityGal: 81),
        AircraftProfile(name: "Diamond DA40", type: "DA40", cruiseSpeed: 130, fuelBurn: 7.5, capacityGal: 40),
    ]
}

struct ChecklistItem: Codable, Identifiable {
    var id = UUID()
    var text: String
    var done = false
}

struct Checklist: Codable, Identifiable {
    var id = UUID()
    var name: String
    var items: [ChecklistItem]
}

/// App-wide persisted state: favourites, logbook, checklists. Saved to UserDefaults.
@MainActor
final class AppModel: ObservableObject {
    @Published var favorites: Set<String> = []
    @Published var logbook: [LogEntry] = []
    @Published var checklists: [Checklist] = []
    @Published var recents: [String] = []   // recently viewed ICAOs, most recent first
    @Published var directTo: String?   // ICAO requested as route destination from a detail sheet

    func markViewed(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > 15 { recents = Array(recents.prefix(15)) }
        defaults.set(recents, forKey: "recents")
    }

    // Flight plan
    @Published var waypoints: [Airport] = []
    @Published var legs: [RouteLeg] = []
    @Published var cruiseAlt: Int = 5500 { didSet { defaults.set(cruiseAlt, forKey: "cruiseAlt") } }

    // Map state
    @Published var mapRegion = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795),
        span: MKCoordinateSpan(latitudeDelta: 10, longitudeDelta: 10)
    ) { didSet { saveMapRegion() } }
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var showUserLocation = true
    @Published var followUser = false

    // Map layer visibility (persisted)
    @AppStorage("showSectional") var showSectional: Bool = true
    @AppStorage("showRadar") var showRadar: Bool = false
    @AppStorage("showAirspace") var showAirspace: Bool = true
    @AppStorage("showTFRs") var showTFRs: Bool = true
    @AppStorage("showWindsAloft") var showWindsAloft: Bool = true
    @AppStorage("showPIREPs") var showPIREPs: Bool = true
    @AppStorage("showAIRMETs") var showAIRMETs: Bool = true
    @AppStorage("showAirways") var showAirways: Bool = true

    // Appearance (persisted): 0 = System, 1 = Light, 2 = Dark
    @AppStorage("appearanceMode") var appearanceMode: Int = 0

    // UI state
    @Published var selectedAirport: Airport?
    @Published var selectedAircraft: AircraftProfile?
    @Published var aircraftProfiles: [AircraftProfile] = AircraftProfile.defaultProfiles

    // Aircraft profile (persisted, shared by the flight computer and plan)
    @Published var nightMode = false { didSet { defaults.set(nightMode, forKey: "nightMode") } }
    @Published var cruiseGS = 110.0 { didSet { saveProfile() } }
    @Published var fuelBurn = 8.0    { didSet { saveProfile() } }
    @Published var reserveMin = 45.0 { didSet { saveProfile() } }

    private let defaults = UserDefaults.standard

    static let shared = AppModel()

    init() { load() }

    // Favorites
    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        Haptics.tap()
        save()
    }

    // Flight plan
    func addWaypoint(_ airport: Airport) {
        guard !waypoints.contains(where: { $0.id == airport.id }) else { return }
        waypoints.append(airport)
        Haptics.tap()
    }

    func clearFlightPlan() {
        waypoints.removeAll()
        legs.removeAll()
        Haptics.success()
    }

    func selectAircraft(_ aircraft: AircraftProfile) {
        selectedAircraft = aircraft
        cruiseGS = aircraft.cruiseSpeed
        fuelBurn = aircraft.fuelBurn
        Haptics.tap()
    }

    // Logbook
    func logFlight(from: String, to: String, nm: Int, eteMinutes: Int) {
        logbook.insert(LogEntry(date: .now, from: from, to: to, nm: nm, eteMinutes: eteMinutes), at: 0)
        Haptics.success()
        save()
    }
    func deleteLog(_ offsets: IndexSet) { logbook.remove(atOffsets: offsets); save() }

    // Checklists
    func toggle(_ item: ChecklistItem, in list: Checklist) {
        guard let li = checklists.firstIndex(where: { $0.id == list.id }),
              let ii = checklists[li].items.firstIndex(where: { $0.id == item.id }) else { return }
        checklists[li].items[ii].done.toggle()
        Haptics.tap()
        save()
    }
    func reset(_ list: Checklist) {
        guard let li = checklists.firstIndex(where: { $0.id == list.id }) else { return }
        for i in checklists[li].items.indices { checklists[li].items[i].done = false }
        save()
    }

    // Persistence
    private func load() {
        if let d = defaults.data(forKey: "favorites"),
           let v = try? JSONDecoder().decode(Set<String>.self, from: d) { favorites = v }
        if let d = defaults.data(forKey: "logbook"),
           let v = try? JSONDecoder().decode([LogEntry].self, from: d) { logbook = v }
        if let d = defaults.data(forKey: "checklists"),
           let v = try? JSONDecoder().decode([Checklist].self, from: d) { checklists = v }
        if checklists.isEmpty { checklists = Self.defaultChecklists }
        recents = defaults.stringArray(forKey: "recents") ?? []
        nightMode = defaults.bool(forKey: "nightMode")
        if defaults.object(forKey: "cruiseGS") != nil { cruiseGS = defaults.double(forKey: "cruiseGS") }
        if defaults.object(forKey: "fuelBurn") != nil { fuelBurn = defaults.double(forKey: "fuelBurn") }
        if defaults.object(forKey: "reserveMin") != nil { reserveMin = defaults.double(forKey: "reserveMin") }
        if defaults.object(forKey: "cruiseAlt") != nil { cruiseAlt = defaults.integer(forKey: "cruiseAlt") }
        if let data = defaults.data(forKey: "mapRegion"),
           let region = try? JSONDecoder().decode(MKCoordinateRegionCodable.self, from: data) {
            mapRegion = region.region
        }
    }

    private func saveMapRegion() {
        if let data = try? JSONEncoder().encode(MKCoordinateRegionCodable(mapRegion)) {
            defaults.set(data, forKey: "mapRegion")
        }
    }

    private func saveProfile() {
        defaults.set(cruiseGS, forKey: "cruiseGS")
        defaults.set(fuelBurn, forKey: "fuelBurn")
        defaults.set(reserveMin, forKey: "reserveMin")
    }
    private func save() {
        let e = JSONEncoder()
        defaults.set(try? e.encode(favorites), forKey: "favorites")
        defaults.set(try? e.encode(logbook), forKey: "logbook")
        defaults.set(try? e.encode(checklists), forKey: "checklists")
    }

    static let defaultChecklists: [Checklist] = [
        Checklist(name: "Prévol", items: [
            "Documents à bord", "Essence & huile vérifiées", "Surfaces & gouvernes",
            "Pneus & freins", "Pitot / prises statiques", "Feux & gyrophare"
        ].map { ChecklistItem(text: $0) }),
        Checklist(name: "Avant décollage", items: [
            "Harnais & portes", "Volets réglés", "Trim décollage",
            "Instruments moteur dans le vert", "Magnétos testées", "Transpondeur ALT"
        ].map { ChecklistItem(text: $0) }),
        Checklist(name: "Après atterrissage", items: [
            "Volets rentrés", "Transpondeur STBY", "Feux inutiles éteints", "Réchauffage carbu froid"
        ].map { ChecklistItem(text: $0) })
    ]

    // Computed properties for flight plan
    var totalDistanceNM: Double {
        guard waypoints.count >= 2 else { return 0 }
        var total = 0.0
        for i in 1..<waypoints.count {
            total += waypoints[i-1].distanceNM(to: waypoints[i].coordinate)
        }
        return total
    }

    var totalTimeMinutes: Double {
        guard totalDistanceNM > 0 && cruiseGS > 0 else { return 0 }
        return (totalDistanceNM / cruiseGS) * 60
    }

    var formattedTotalTime: String {
        guard totalDistanceNM > 0 && cruiseGS > 0 else { return "—" }
        let hours = totalDistanceNM / cruiseGS
        let totalMinutes = Int(hours * 60)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
    }

    var totalFuelGallons: Double {
        guard fuelBurn > 0 && totalDistanceNM > 0 && cruiseGS > 0 else { return 0 }
        let hours = totalDistanceNM / cruiseGS
        return hours * fuelBurn + (reserveMin / 60.0 * fuelBurn)
    }
}

/// Codable wrapper for MKCoordinateRegion
struct MKCoordinateRegionCodable: Codable {
    let center: CLLocationCoordinate2DCodable
    let span: MKCoordinateSpanCodable

    var region: MKCoordinateRegion {
        MKCoordinateRegion(center: center.coordinate, span: span.span)
    }

    init(_ region: MKCoordinateRegion) {
        self.center = CLLocationCoordinate2DCodable(region.center)
        self.span = MKCoordinateSpanCodable(region.span)
    }
}

struct CLLocationCoordinate2DCodable: Codable {
    let latitude: Double
    let longitude: Double
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: latitude, longitude: longitude) }
    init(_ coordinate: CLLocationCoordinate2D) { self.latitude = coordinate.latitude; self.longitude = coordinate.longitude }
}

struct MKCoordinateSpanCodable: Codable {
    let latitudeDelta: Double
    let longitudeDelta: Double
    var span: MKCoordinateSpan { MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta) }
    init(_ span: MKCoordinateSpan) { self.latitudeDelta = span.latitudeDelta; self.longitudeDelta = span.longitudeDelta }
}
