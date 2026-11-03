import Foundation
import MapKit
import CoreLocation
import SwiftUI

struct LogEntry: Codable, Identifiable, Equatable {
    var id = UUID()
    var date: Date
    var from: String
    var to: String
    var nm: Int
    var eteMinutes: Int
    // Added in 1.0.45 (optional so older logbooks still decode).
    var aircraft: String?
    var landingsDay: Int?
    var landingsNight: Int?
    var remarks: String?
    /// Flown GPS track, downsampled, for replay and GPX/KML export.
    var track: [Coordinate2D]?
}

/// A flight plan kept for later: name and waypoint idents.
struct SavedPlan: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var waypointIDs: [String]
}

struct AircraftProfile: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var type: String
    var cruiseSpeed: Double
    var fuelBurn: Double
    var capacityGal: Double
    /// Weight & balance envelope (lb, inches aft of datum), copied to the W&B calculator on selection.
    var maxWeight: Double = 2550
    var cgForward: Double = 82
    var cgAft: Double = 88
    /// Loading stations (empty weight, seats, fuel, baggage) with their arms.
    var stations: [WeightBalanceItem] = []

    /// C172S-like stations, used when a profile has none.
    static func stations(empty: Double, emptyArm: Double, front: Double, rear: Double, fuel: Double, baggage: Double) -> [WeightBalanceItem] {
        [WeightBalanceItem(name: "Empty Weight", weight: empty, arm: emptyArm),
         WeightBalanceItem(name: "Pilot", weight: 180, arm: front),
         WeightBalanceItem(name: "Passenger", weight: 0, arm: front),
         WeightBalanceItem(name: "Rear seats", weight: 0, arm: rear),
         WeightBalanceItem(name: "Fuel (gal)", weight: 0, arm: fuel),
         WeightBalanceItem(name: "Baggage", weight: 0, arm: baggage)]
    }

    var enduranceHours: Double {
        guard fuelBurn > 0 else { return 0 }
        return capacityGal / fuelBurn
    }

    static let defaultProfiles: [AircraftProfile] = [
        AircraftProfile(name: "Cessna 172S", type: "C172", cruiseSpeed: 122, fuelBurn: 8.5, capacityGal: 53,
                        maxWeight: 2550, cgForward: 35, cgAft: 47.3,
                        stations: stations(empty: 1680, emptyArm: 40.6, front: 37, rear: 73, fuel: 48, baggage: 95)),
        AircraftProfile(name: "Piper PA-28-180", type: "PA28", cruiseSpeed: 124, fuelBurn: 9.0, capacityGal: 48,
                        maxWeight: 2400, cgForward: 84, cgAft: 95.9,
                        stations: stations(empty: 1400, emptyArm: 86, front: 80.5, rear: 118.1, fuel: 95, baggage: 142.8)),
        AircraftProfile(name: "Cirrus SR22T", type: "SR22", cruiseSpeed: 183, fuelBurn: 14.0, capacityGal: 81,
                        maxWeight: 3600, cgForward: 139.1, cgAft: 148.1,
                        stations: stations(empty: 2350, emptyArm: 139, front: 143.5, rear: 180, fuel: 154.9, baggage: 208)),
        AircraftProfile(name: "Diamond DA40", type: "DA40", cruiseSpeed: 130, fuelBurn: 7.5, capacityGal: 40,
                        maxWeight: 2646, cgForward: 94.5, cgAft: 98.4,
                        stations: stations(empty: 1750, emptyArm: 96, front: 90.6, rear: 128, fuel: 103.5, baggage: 153.1)),
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

    func markViewed(_ id: String) {
        recents.removeAll { $0 == id }
        recents.insert(id, at: 0)
        if recents.count > 15 { recents = Array(recents.prefix(15)) }
        defaults.set(recents, forKey: "recents")
    }

    // Flight plan
    @Published var waypoints: [Airport] = [] { didSet { routedDistanceNM = nil; navlog = []; routePath = waypoints.map(\.coordinate) } }
    /// Length of the computed route (with airspace detours); straight-line legs until it is known.
    @Published var routedDistanceNM: Double?
    /// Wind-corrected log of the computed route; empty until the route is calculated.
    @Published var navlog: [NavLogLeg] = []
    /// Computed route (with detours); straight legs until it is calculated.
    @Published var routePath: [CLLocationCoordinate2D] = []
    @Published var legs: [RouteLeg] = []
    @Published var cruiseAlt: Int = 5500 { didSet { defaults.set(cruiseAlt, forKey: "cruiseAlt") } }

    // Map state
    /// Last map region. Deliberately *not* @Published: the map reports a new region at the end of
    /// every pan, and publishing it re-rendered every screen observing AppModel. Saved with a 1 s debounce.
    var mapRegion = AppModel.homeRegion {
        didSet {
            mapRegionSaveTask?.cancel()
            mapRegionSaveTask = Task {
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second debounce
                if !Task.isCancelled {
                    await MainActor.run { saveMapRegion() }
                }
            }
        }
    }

    /// Home base KFPR (Fort Pierce, FL), used for the first launch and as a fallback position.
    static let homeCoordinate = CLLocationCoordinate2D(latitude: 27.4975, longitude: -80.3726)
    static let homeRegion = MKCoordinateRegion(
        center: homeCoordinate,
        span: MKCoordinateSpan(latitudeDelta: 1.2, longitudeDelta: 1.2)
    )

    @Published var userLocation: CLLocationCoordinate2D? { didSet { recordTrack() } }
    /// Flown track (breadcrumb): a point each time the aircraft has moved 100 m or more.
    @Published private(set) var track: [CLLocationCoordinate2D] = []

    private func recordTrack() {
        guard let c = userLocation else { return }
        if let last = track.last,
           CLLocation(latitude: last.latitude, longitude: last.longitude)
               .distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude)) < 100 { return }
        track.append(c)
        if track.count > 20_000 { track.removeFirst(track.count - 20_000) }
    }

    func clearTrack() { track.removeAll() }
    @Published var showUserLocation = true
    @Published var followUser = false

    private var mapRegionSaveTask: Task<Void, Never>?

    /// Bumped whenever code (not the user's finger) moves the map, so VFRMapView applies `mapRegion`.
    @Published private(set) var mapRegionVersion = 0

    /// Recentres the map (GPS button, search result, Direct To).
    func moveMap(to center: CLLocationCoordinate2D, span: Double = 0.5) {
        mapRegion = MKCoordinateRegion(center: center,
                                       span: MKCoordinateSpan(latitudeDelta: span, longitudeDelta: span))
        mapRegionVersion += 1
    }

    // Map layer visibility (persisted)
    @Published var showSectional: Bool = true { didSet { defaults.set(showSectional, forKey: "showSectional") } }
    @Published var showRadar: Bool = false { didSet { defaults.set(showRadar, forKey: "showRadar") } }
    @Published var mapChart: String = MapChart.sectional.rawValue { didSet { defaults.set(mapChart, forKey: "mapChart") } }
    @Published var showSatellite: Bool = false { didSet { defaults.set(showSatellite, forKey: "showSatellite") } }
    /// GOES infrared cloud imagery over the map.
    @Published var showIR: Bool = false { didSet { defaults.set(showIR, forKey: "showIR") } }
    /// Listen for a GDL 90 ADS-B receiver (Stratux, Sentry…) on UDP 4000.
    @Published var adsbEnabled: Bool = false {
        didSet {
            defaults.set(adsbEnabled, forKey: "adsbEnabled")
            if adsbEnabled { ADSBReceiver.shared.start() } else { ADSBReceiver.shared.stop() }
        }
    }
    @Published var showAirspace: Bool = true { didSet { defaults.set(showAirspace, forKey: "showAirspace") } }

    // Appearance (persisted): 0 = System, 1 = Light, 2 = Dark
    @Published var appearanceMode: Int = 0 { didSet { defaults.set(appearanceMode, forKey: "appearanceMode") } }

    // UI state
    @Published var selectedAirport: Airport?
    @Published var selectedAircraft: AircraftProfile? {
        didSet { defaults.set(selectedAircraft?.id.uuidString, forKey: "selectedAircraft") }
    }
    @Published var aircraftProfiles: [AircraftProfile] = AircraftProfile.defaultProfiles {
        didSet { defaults.set(try? JSONEncoder().encode(aircraftProfiles), forKey: "aircraftProfiles") }
    }

    // Aircraft profile (persisted, shared by the flight computer and plan)
    @Published var nightMode = false { didSet { defaults.set(nightMode, forKey: "nightMode") } }
    @Published var cruiseGS = 110.0 { didSet { saveProfile() } }
    @Published var fuelBurn = 8.0    { didSet { saveProfile() } }
    @Published var reserveMin = 45.0 { didSet { saveProfile() } }
    /// Fuel loaded before departure (gal); 0 = not entered, no fuel alert.
    @Published var fuelOnBoard = 0.0 { didSet { defaults.set(fuelOnBoard, forKey: "fuelOnBoard") } }
    /// Show the GPS instrument strip even on the ground.
    @Published var showInstruments = false { didSet { defaults.set(showInstruments, forKey: "showInstruments") } }

    private let defaults: UserDefaults

    static let shared = AppModel()

    /// `defaults` is injectable so tests don't share (and race with) the running app's storage.
    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        load()
    }

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

    /// Direct To: replaces the plan with "current GPS position → airport" (just the airport without a fix).
    func directTo(_ airport: Airport) {
        var plan: [Airport] = []
        if let here = userLocation {
            plan.append(Airport(id: Self.gpsWaypointID, name: "Position actuelle", type: "gps",
                                icao: nil, iata: nil, municipality: nil, elevationFt: nil, coordinate: here))
        }
        plan.append(airport)
        waypoints = plan
        Haptics.success()
    }

    static let gpsWaypointID = "GPS"

    func clearFlightPlan() {
        waypoints.removeAll()
        legs.removeAll()
        Haptics.success()
    }

    func selectAircraft(_ aircraft: AircraftProfile) {
        selectedAircraft = aircraft
        cruiseGS = aircraft.cruiseSpeed
        fuelBurn = aircraft.fuelBurn
        // The W&B calculator reads its limits from here when it opens.
        struct Limits: Codable { let maxWeight, cgForward, cgAft: Double }
        defaults.set(try? JSONEncoder().encode(Limits(maxWeight: aircraft.maxWeight, cgForward: aircraft.cgForward,
                                                     cgAft: aircraft.cgAft)), forKey: "wb.limits")
        if !aircraft.stations.isEmpty { defaults.set(try? JSONEncoder().encode(aircraft.stations), forKey: "wb.items") }
        Haptics.tap()
    }

    // Logbook
    /// Logs the flight with the aircraft, one day landing and the GPS track. When the GPS saw the takeoff,
    /// the real flight time replaces the planned ETE.
    func logFlight(from: String, to: String, nm: Int, eteMinutes: Int) {
        let step = max(1, track.count / 2000)
        let flown = FlightMonitor.shared.airborneSince.map { Int(Date.now.timeIntervalSince($0) / 60) }.flatMap { $0 >= 5 ? $0 : nil }
        logbook.insert(LogEntry(date: .now, from: from, to: to, nm: nm, eteMinutes: flown ?? eteMinutes,
                                aircraft: selectedAircraft?.name, landingsDay: 1, landingsNight: 0, remarks: nil,
                                track: track.isEmpty ? nil : stride(from: 0, to: track.count, by: step).map { Coordinate2D(track[$0]) }),
                        at: 0)
        Haptics.success()
        save()
    }
    func updateLog(_ entry: LogEntry) {
        guard let i = logbook.firstIndex(where: { $0.id == entry.id }) else { return }
        logbook[i] = entry
        save()
    }

    // Saved plans
    @Published var savedPlans: [SavedPlan] = [] {
        didSet { defaults.set(try? JSONEncoder().encode(savedPlans), forKey: "savedPlans") }
    }
    func savePlan() {
        let ids = waypoints.map(\.id).filter { $0 != Self.gpsWaypointID }
        guard ids.count >= 2 else { return }
        savedPlans.insert(SavedPlan(name: ids.joined(separator: " → "), waypointIDs: ids), at: 0)
        Haptics.success()
    }

    // Pilot currency (dates stored as seconds since 1970; 0 = not entered)
    @Published var medicalExpiry: Double = 0 { didSet { defaults.set(medicalExpiry, forKey: "medicalExpiry") } }
    @Published var flightReviewDate: Double = 0 { didSet { defaults.set(flightReviewDate, forKey: "flightReviewDate") } }
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
        if let d = defaults.data(forKey: "aircraftProfiles"),
           let v = try? JSONDecoder().decode([AircraftProfile].self, from: d), !v.isEmpty { aircraftProfiles = v }
        let selectedID = defaults.string(forKey: "selectedAircraft")
        if let d = defaults.data(forKey: "savedPlans"),
           let v = try? JSONDecoder().decode([SavedPlan].self, from: d) { savedPlans = v }
        medicalExpiry = defaults.double(forKey: "medicalExpiry")
        flightReviewDate = defaults.double(forKey: "flightReviewDate")
        selectedAircraft = aircraftProfiles.first { $0.id.uuidString == selectedID }
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
        // Load map layer settings
        showSectional = defaults.object(forKey: "showSectional") as? Bool ?? true
        showRadar = defaults.object(forKey: "showRadar") as? Bool ?? false
        mapChart = defaults.string(forKey: "mapChart") ?? MapChart.sectional.rawValue
        showSatellite = defaults.bool(forKey: "showSatellite")
        showIR = defaults.bool(forKey: "showIR")
        adsbEnabled = defaults.bool(forKey: "adsbEnabled")
        fuelOnBoard = defaults.double(forKey: "fuelOnBoard")
        showInstruments = defaults.bool(forKey: "showInstruments")
        showAirspace = defaults.object(forKey: "showAirspace") as? Bool ?? true
        appearanceMode = defaults.object(forKey: "appearanceMode") as? Int ?? 0
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
        if let routedDistanceNM { return routedDistanceNM }
        var total = 0.0
        for i in 1..<waypoints.count {
            total += waypoints[i-1].distanceNM(to: waypoints[i].coordinate)
        }
        return total
    }

    /// Wind-corrected when the navlog is available, else distance / true airspeed.
    var totalTimeMinutes: Double {
        if !navlog.isEmpty { return navlog.reduce(0) { $0 + $1.minutes } }
        guard totalDistanceNM > 0 && cruiseGS > 0 else { return 0 }
        return (totalDistanceNM / cruiseGS) * 60
    }

    var formattedTotalTime: String {
        guard totalTimeMinutes > 0 else { return "—" }
        let totalMinutes = Int(totalTimeMinutes)
        let h = totalMinutes / 60
        let m = totalMinutes % 60
        return h > 0 ? "\(h)h \(m)min" : "\(m)min"
    }

    var totalFuelGallons: Double {
        guard fuelBurn > 0 && totalTimeMinutes > 0 else { return 0 }
        return (totalTimeMinutes + reserveMin) / 60.0 * fuelBurn
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
