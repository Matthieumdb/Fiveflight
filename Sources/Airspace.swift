import Foundation
import CoreLocation

/// Codable wrapper for CLLocationCoordinate2D
struct Coordinate2D: Codable, Hashable, Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// Airspace classification matching FAA/ICAO standards
enum AirspaceClass: String, Codable, CaseIterable, Identifiable {
    case A = "A"
    case B = "B"
    case C = "C"
    case D = "D"
    case E = "E"
    case G = "G"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .A: return "Class A"
        case .B: return "Class B"
        case .C: return "Class C"
        case .D: return "Class D"
        case .E: return "Class E"
        case .G: return "Class G"
        }
    }

    var color: String {
        switch self {
        case .A: return "#8B0000"      // Dark red
        case .B: return "#0044CC"      // Blue
        case .C: return "#0066CC"      // Light blue
        case .D: return "#0088AA"      // Teal
        case .E: return "#AA8800"      // Amber
        case .G: return "#555555"      // Gray
        }
    }

    var requiresATC: Bool {
        self != .G && self != .E
    }

    var vfrAllowed: Bool {
        self != .A
    }

    /// Minimum visibility for VFR (statute miles)
    var vfrMinVisibility: Int {
        switch self {
        case .A: return 0 // IFR only
        case .B: return 3
        case .C: return 3
        case .D: return 3
        case .E: return 3 // Below 10,000 MSL
        case .G: return 1 // Day, 3 at night
        }
    }

    /// Cloud clearance for VFR
    var vfrCloudClearance: String {
        switch self {
        case .A: return "N/A"
        case .B: return "Clear of clouds"
        case .C: return "500 ft below, 1000 ft above, 2000 ft horizontal"
        case .D: return "500 ft below, 1000 ft above, 2000 ft horizontal"
        case .E: return "500 ft below, 1000 ft above, 2000 ft horizontal"
        case .G: return "Clear of clouds (day), 500/1000/2000 (night)"
        }
    }
}

/// Special Use Airspace types
enum SUAType: String, Codable, CaseIterable, Identifiable {
    case moa = "MOA"
    case restricted = "RESTRICTED"
    case prohibited = "PROHIBITED"
    case warning = "WARNING"
    case alert = "ALERT"
    case cfa = "CFA" // Controlled Firing Area
    case tf = "TFR" // Temporary Flight Restriction
    case nationalSecurity = "NATIONAL_SECURITY"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .moa: return "MOA"
        case .restricted: return "Restricted"
        case .prohibited: return "Prohibited"
        case .warning: return "Warning Area"
        case .alert: return "Alert Area"
        case .cfa: return "CFA"
        case .tf: return "TFR"
        case .nationalSecurity: return "Nat'l Security"
        }
    }

    var color: String {
        switch self {
        case .moa: return "#FF6B35"        // Orange
        case .restricted: return "#CC0000" // Red
        case .prohibited: return "#8B0000" // Dark red
        case .warning: return "#FF8800"    // Orange-red
        case .alert: return "#FFAA00"      // Yellow-orange
        case .cfa: return "#FFCC00"        // Yellow
        case .tf: return "#FF0088"         // Magenta
        case .nationalSecurity: return "#AA00FF" // Purple
        }
    }

    var requiresPermission: Bool {
        switch self {
        case .restricted, .prohibited, .tf, .nationalSecurity: return true
        case .moa, .warning, .alert, .cfa: return false
        }
    }
}

/// Unified airspace representation
struct Airspace: Identifiable, Codable, Hashable {
    let id: String
    let name: String
    let type: AirspaceType
    let polygons: [[Coordinate2D]] // Multiple rings (outer + holes)
    let floor: Int // feet MSL
    let ceiling: Int // feet MSL
    let controllingAgency: String?
    let frequency: String?
    var isActive: Bool = true
    var schedule: String?

    enum AirspaceType: Codable, Hashable {
        case classAirspace(AirspaceClass)
        case sua(SUAType)
        case airway(String) // Victor/Jet route designator
        case classESurface // Class E surface area

        var displayName: String {
            switch self {
            case .classAirspace(let c): return c.displayName
            case .sua(let s): return s.displayName
            case .airway(let s): return "Airway \(s)"
            case .classESurface: return "Class E Surface"
            }
        }

        var color: String {
            switch self {
            case .classAirspace(let c): return c.color
            case .sua(let s): return s.color
            case .airway: return "#008844"
            case .classESurface: return "#00AA66"
            }
        }

        var requiresATC: Bool {
            switch self {
            case .classAirspace(let c): return c.requiresATC
            case .sua(let s): return s.requiresPermission
            case .airway: return false
            case .classESurface: return true
            }
        }
    }

    static func fromSUA(_ type: String) -> AirspaceType {
        if let sua = SUAType(rawValue: type.uppercased()) {
            return .sua(sua)
        }
        if let classType = AirspaceClass(rawValue: type.uppercased()) {
            return .classAirspace(classType)
        }
        return .sua(.moa) // default
    }

    /// Checks if a coordinate at given altitude is inside this airspace
    func contains(_ coordinate: CLLocationCoordinate2D, altitude: Int) -> Bool {
        guard altitude >= floor && altitude <= ceiling else { return false }
        guard isActive else { return false }

        // Point in polygon test for each ring
        for ring in polygons {
            if pointInPolygon(coordinate, polygon: ring.map(\.clCoordinate)) {
                return true
            }
        }
        return false
    }

    /// Gets all airspaces containing a coordinate at altitude
    static func containing(_ coordinate: CLLocationCoordinate2D, altitude: Int, from airspaces: [Airspace]) -> [Airspace] {
        airspaces.filter { $0.contains(coordinate, altitude: altitude) }
    }

    /// Gets airspaces intersecting a route segment
    static func intersecting(_ from: CLLocationCoordinate2D, _ to: CLLocationCoordinate2D, altitude: Int, from airspaces: [Airspace]) -> [Airspace] {
        airspaces.filter { airspace in
            guard airspace.isActive else { return false }
            guard altitude >= airspace.floor && altitude <= airspace.ceiling else { return false }

            for ring in airspace.polygons {
                if segmentIntersectsPolygon(from, to, polygon: ring) {
                    return true
                }
            }
            return false
        }
    }

    private func pointInPolygon(_ point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        var inside = false
        let count = polygon.count
        guard count >= 3 else { return false }

        var j = count - 1
        for i in 0..<count {
            let pi = polygon[i]
            let pj = polygon[j]

            if ((pi.latitude > point.latitude) != (pj.latitude > point.latitude)) &&
               (point.longitude < (pj.longitude - pi.longitude) * (point.latitude - pi.latitude) / (pj.latitude - pi.latitude) + pi.longitude) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    static func segmentIntersectsPolygon(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, polygon: [Coordinate2D]) -> Bool {
        let clPolygon = polygon.map { $0.clCoordinate }
        return segmentIntersectsPolygonInternal(a, b, polygon: clPolygon)
    }

    private static func segmentIntersectsPolygonInternal(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        let count = polygon.count
        guard count >= 3 else { return false }

        if pointInPolygonStatic(a, polygon: polygon) || pointInPolygonStatic(b, polygon: polygon) {
            return true
        }

        var j = count - 1
        for i in 0..<count {
            if segmentsIntersect(a, b, polygon[j], polygon[i]) {
                return true
            }
            j = i
        }
        return false
    }

    private static func pointInPolygonStatic(_ point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        var inside = false
        let count = polygon.count
        var j = count - 1
        for i in 0..<count {
            let pi = polygon[i]
            let pj = polygon[j]
            if ((pi.latitude > point.latitude) != (pj.latitude > point.latitude)) &&
               (point.longitude < (pj.longitude - pi.longitude) * (point.latitude - pi.latitude) / (pj.latitude - pi.latitude) + pi.longitude) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    private static func segmentsIntersect(_ a1: CLLocationCoordinate2D, _ a2: CLLocationCoordinate2D, _ b1: CLLocationCoordinate2D, _ b2: CLLocationCoordinate2D) -> Bool {
        // Line segment intersection using orientation test
        func orientation(_ p: CLLocationCoordinate2D, _ q: CLLocationCoordinate2D, _ r: CLLocationCoordinate2D) -> Double {
            (q.longitude - p.longitude) * (r.latitude - q.latitude) - (q.latitude - p.latitude) * (r.longitude - q.longitude)
        }

        func onSegment(_ p: CLLocationCoordinate2D, _ q: CLLocationCoordinate2D, _ r: CLLocationCoordinate2D) -> Bool {
            q.longitude <= max(p.longitude, r.longitude) && q.longitude >= min(p.longitude, r.longitude) &&
            q.latitude <= max(p.latitude, r.latitude) && q.latitude >= min(p.latitude, r.latitude)
        }

        let o1 = orientation(a1, a2, b1)
        let o2 = orientation(a1, a2, b2)
        let o3 = orientation(b1, b2, a1)
        let o4 = orientation(b1, b2, a2)

        if o1 * o2 < 0 && o3 * o4 < 0 { return true }
        if o1 == 0 && onSegment(a1, b1, a2) { return true }
        if o2 == 0 && onSegment(a1, b2, a2) { return true }
        if o3 == 0 && onSegment(b1, a1, b2) { return true }
        if o4 == 0 && onSegment(b1, a2, b2) { return true }
        return false
    }

    // Sample data for offline use
    static func sampleUSAAirspaces() -> [Airspace] {
        // Major Class B airspaces (simplified polygons)
        var airspaces: [Airspace] = []

        func coord(_ lat: Double, _ lon: Double) -> Coordinate2D {
            Coordinate2D(CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }

        // KLAX Class B
        airspaces.append(Airspace(
            id: "KBOS_B",
            name: "Boston Class B",
            type: .classAirspace(.B),
            polygons: [[
                coord(42.365, -71.010),
                coord(42.400, -70.950),
                coord(42.340, -70.850),
                coord(42.280, -70.950),
                coord(42.320, -71.050),
                coord(42.365, -71.010)
            ]],
            floor: 0,
            ceiling: 10000,
            controllingAgency: "Boston Approach",
            frequency: "124.4"
        ))

        // KLGA Class B
        airspaces.append(Airspace(
            id: "KLGA_B",
            name: "LaGuardia Class B",
            type: .classAirspace(.B),
            polygons: [[
                coord(40.775, -73.875),
                coord(40.820, -73.820),
                coord(40.750, -73.750),
                coord(40.700, -73.820),
                coord(40.725, -73.900),
                coord(40.775, -73.875)
            ]],
            floor: 0,
            ceiling: 7000,
            controllingAgency: "New York Approach",
            frequency: "120.8"
        ))

        // MOA Example
        airspaces.append(Airspace(
            id: "MOA_CAMEL",
            name: "Camel MOA",
            type: .sua(.moa),
            polygons: [[
                coord(34.5, -117.5),
                coord(35.0, -117.5),
                coord(35.0, -116.5),
                coord(34.5, -116.5),
                coord(34.5, -117.5)
            ]],
            floor: 3000,
            ceiling: 18000,
            controllingAgency: "Edwards Control",
            frequency: "126.3",
            schedule: "Intermittent by NOTAM"
        ))

        // Restricted Area Example
        airspaces.append(Airspace(
            id: "R2508",
            name: "R-2508 Complex",
            type: .sua(.restricted),
            polygons: [[
                coord(35.2, -117.8),
                coord(35.7, -117.8),
                coord(35.7, -116.8),
                coord(35.2, -116.8),
                coord(35.2, -117.8)
            ]],
            floor: 0,
            ceiling: 60000,
            controllingAgency: "Edwards Control",
            frequency: "126.3"
        ))

        // Prohibited Area
        airspaces.append(Airspace(
            id: "P40",
            name: "P-40 Camp David",
            type: .sua(.prohibited),
            polygons: [[
                coord(39.65, -77.47),
                coord(39.70, -77.40),
                coord(39.60, -77.35),
                coord(39.55, -77.42),
                coord(39.65, -77.47)
            ]],
            floor: 0,
            ceiling: 18000,
            controllingAgency: "Washington Control",
            frequency: "121.5"
        ))

        // TFR Example
        airspaces.append(Airspace(
            id: "TFR_DC",
            name: "DC SFRA / FRZ",
            type: .sua(.tf),
            polygons: [[
                coord(38.7, -77.3),
                coord(39.3, -77.3),
                coord(39.3, -76.7),
                coord(38.7, -76.7),
                coord(38.7, -77.3)
            ]],
            floor: 0,
            ceiling: 18000,
            controllingAgency: "Potomac Approach",
            frequency: "121.5",
            schedule: "Continuous"
        ))

        return airspaces
    }
}

/// CTAF/UNICOM frequency info
struct CTAFFrequency: Identifiable, Codable, Hashable {
    let id = UUID()
    let frequency: Double // MHz
    let type: String // "CTAF", "UNICOM", "MULTICOM"
    let description: String

    var displayString: String {
        String(format: "%.2f", frequency)
    }

    var shortType: String {
        switch type.uppercased() {
        case let t where t.contains("CTAF"): return "CTAF"
        case let t where t.contains("UNICOM"): return "UNICOM"
        case let t where t.contains("MULTICOM"): return "MULTICOM"
        default: return type.uppercased()
        }
    }
}
