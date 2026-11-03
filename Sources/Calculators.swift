import Foundation

// MARK: - Weight & Balance

struct WeightBalanceItem: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var weight: Double
    var arm: Double      // inches from datum
    var moment: Double { weight * arm }

    static let emptyName = "Empty Weight"
    /// Names are stored in English (keys shared with older versions); shown in French.
    var displayName: String {
        switch name {
        case Self.emptyName: return "Masse à vide"
        case "Pilot": return "Pilote"
        case "Passenger": return "Passager"
        case "Rear seats": return "Places arrière"
        case "Fuel (gal)": return "Carburant (gal)"
        case "Baggage": return "Bagages"
        case "New Item": return "Autre"
        default: return name
        }
    }
}

@MainActor
final class WeightBalanceModel: ObservableObject {
    @Published var items: [WeightBalanceItem] = [
        WeightBalanceItem(name: "Empty Weight", weight: 1650, arm: 85),
        WeightBalanceItem(name: "Pilot", weight: 180, arm: 85),
        WeightBalanceItem(name: "Passenger", weight: 180, arm: 85),
        WeightBalanceItem(name: "Fuel (gal)", weight: 0, arm: 85),
        WeightBalanceItem(name: "Baggage", weight: 0, arm: 120)
    ] {
        didSet { save() }
    }
    @Published var maxWeight = 2550.0 { didSet { save() } }
    @Published var cgForward = 82.0 { didSet { save() } }
    @Published var cgAft = 88.0 { didSet { save() } }

    private let defaults = UserDefaults.standard

    var totalWeight: Double { items.reduce(0) { $0 + $1.weight } }
    var totalMoment: Double { items.reduce(0) { $0 + $1.moment } }
    var cg: Double { totalWeight > 0 ? totalMoment / totalWeight : 0 }
    var isWithinLimits: Bool { totalWeight <= maxWeight && cg >= cgForward && cg <= cgAft }
    var usefulLoad: Double { maxWeight - (items.first(where: { $0.name == WeightBalanceItem.emptyName })?.weight ?? 0) }

    init() { load() }

    /// Ties the calculator to the aircraft profile: limits always come from it, its stations replace the
    /// loading when the aircraft changed, and the empty weight is never missing or zero.
    func sync(with aircraft: AircraftProfile) {
        maxWeight = aircraft.maxWeight
        cgForward = aircraft.cgForward
        cgAft = aircraft.cgAft
        let key = "wb.aircraftID"
        let stations = aircraft.stations.isEmpty
            ? AircraftProfile.defaultProfiles[0].stations
            : aircraft.stations
        if defaults.string(forKey: key) != aircraft.id.uuidString {
            defaults.set(aircraft.id.uuidString, forKey: key)
            items = stations
            return
        }
        let empty = stations.first { $0.name == WeightBalanceItem.emptyName }
            ?? WeightBalanceItem(name: WeightBalanceItem.emptyName, weight: aircraft.maxWeight * 0.65, arm: (aircraft.cgForward + aircraft.cgAft) / 2)
        if let i = items.firstIndex(where: { $0.name == WeightBalanceItem.emptyName }) {
            if items[i].weight <= 0 { items[i] = empty }
        } else {
            items.insert(empty, at: 0)
        }
    }

    func updateFuel(gallons: Double) {
        if let i = items.firstIndex(where: { $0.name == "Fuel (gal)" }) {
            items[i].weight = gallons * 6.0  // 6 lb/gal avgas
        }
    }

    private func load() {
        if let d = defaults.data(forKey: "wb.items"),
           let v = try? JSONDecoder().decode([WeightBalanceItem].self, from: d) { items = v }
        if let d = defaults.data(forKey: "wb.limits"),
           let v = try? JSONDecoder().decode(Limits.self, from: d) {
            maxWeight = v.maxWeight; cgForward = v.cgForward; cgAft = v.cgAft
        }
    }
    private func save() {
        let e = JSONEncoder()
        defaults.set(try? e.encode(items), forKey: "wb.items")
        defaults.set(try? e.encode(Limits(maxWeight: maxWeight, cgForward: cgForward, cgAft: cgAft)), forKey: "wb.limits")
    }
    private struct Limits: Codable { let maxWeight, cgForward, cgAft: Double }
}

// MARK: - Density Altitude

struct DensityAltitude {
    static func calculate(pressureAltitude: Double, tempC: Double) -> Int {
        // DA = PA + 120 * (OAT - ISA_temp)
        // ISA temp at PA: 15 - 2 * (PA/1000)
        let isaTemp = 15.0 - 2.0 * (pressureAltitude / 1000.0)
        let da = pressureAltitude + 120.0 * (tempC - isaTemp)
        return Int(da.rounded())
    }
    static func pressureAltitude(elevationFt: Int, altimeterInHg: Double) -> Double {
        Double(elevationFt) + (29.92 - altimeterInHg) * 1000.0
    }
}

// MARK: - Crosswind Calculator

struct Crosswind {
    static func components(windDir: Int, windSpeed: Int, runwayHeading: Int) -> (headwind: Int, crosswind: Int, side: String) {
        let diff = abs((windDir - runwayHeading + 180) % 360 - 180)
        let rad = Double(diff) * .pi / 180
        let hw = Int((Double(windSpeed) * cos(rad)).rounded())
        let cw = Int(abs(Double(windSpeed) * sin(rad)).rounded())
        let angle = (windDir - runwayHeading + 360) % 360
        let side = angle < 180 ? "R" : "L"
        return (hw, cw, side)
    }
}

// MARK: - NOTAM (basic)

struct Notam: Identifiable, Codable, Hashable {
    var id = UUID()
    let icao: String
    let text: String
    let start: Date?
    let end: Date?
    var isActive: Bool {
        let now = Date()
        if let s = start, now < s { return false }
        if let e = end, now > e { return false }
        return true
    }
}

enum NotamService {
    static func fetch(for icaos: [String]) async -> [String: [Notam]] {
        var result: [String: [Notam]] = [:]
        // FAA NOTAM API - requires client_id + client_secret (configured in Settings → Keychain)
        // For now, return empty with error indicator
        // TODO: Implement proper Keychain storage and API key configuration
        return [:]
    }
    private struct NotamDTO: Decodable { let text: String; let start: Date?; let end: Date? }
}
