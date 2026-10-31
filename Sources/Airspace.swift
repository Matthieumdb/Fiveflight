import Foundation
import CoreLocation

// MARK: - Airspace Data (simplified US airspace)

struct Airspace: Identifiable, Codable {
    let id = UUID()
    let name: String
    let type: AirspaceType
    let floor: Int?     // ft MSL, nil = surface
    let ceiling: Int?   // ft MSL, nil = unlimited
    let geometry: AirspaceGeometry
}

enum AirspaceType: String, Codable {
    case classA = "CLASS_A"
    case classB = "CLASS_B"
    case classC = "CLASS_C"
    case classD = "CLASS_D"
    case classE = "CLASS_E"
    case classG = "CLASS_G"
    case moa = "MOA"
    case restricted = "RESTRICTED"
    case prohibited = "PROHIBITED"
    case warning = "WARNING"
    case alert = "ALERT"
    case cfa = "CFA"
    case tfr = "TFR"
    case other = "OTHER"
}

struct Coordinate2D: Codable, Equatable {
    let latitude: Double
    let longitude: Double

    init(_ coord: CLLocationCoordinate2D) {
        self.latitude = coord.latitude
        self.longitude = coord.longitude
    }

    var clCoordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

enum AirspaceGeometry: Codable {
    case circle(center: Coordinate2D, radiusNM: Double)
    case polygon([Coordinate2D])
    case complex(String) // GeoJSON reference
}

// Sample airspace data for Florida (major ones)
let floridaAirspaces: [Airspace] = [
    // Class B - Miami
    Airspace(name: "Miami Class B", type: .classB, floor: 0, ceiling: 10000,
             geometry: .circle(center: Coordinate2D(CLLocationCoordinate2D(latitude: 25.7907, longitude: -80.2906)), radiusNM: 30)),
    // Class B - Orlando
    Airspace(name: "Orlando Class B", type: .classB, floor: 0, ceiling: 10000,
             geometry: .circle(center: Coordinate2D(CLLocationCoordinate2D(latitude: 28.4312, longitude: -81.3081)), radiusNM: 30)),
    // Class B - Tampa
    Airspace(name: "Tampa Class B", type: .classB, floor: 0, ceiling: 10000,
             geometry: .circle(center: Coordinate2D(CLLocationCoordinate2D(latitude: 27.9755, longitude: -82.5332)), radiusNM: 30)),
    // Class C - Jacksonville
    Airspace(name: "Jacksonville Class C", type: .classC, floor: 0, ceiling: 4100,
             geometry: .circle(center: Coordinate2D(CLLocationCoordinate2D(latitude: 30.4941, longitude: -81.6879)), radiusNM: 10)),
    // Class C - Fort Lauderdale
    Airspace(name: "Fort Lauderdale Class C", type: .classC, floor: 0, ceiling: 4100,
             geometry: .circle(center: Coordinate2D(CLLocationCoordinate2D(latitude: 26.0726, longitude: -80.1527)), radiusNM: 10)),
    // Class C - Palm Beach
    Airspace(name: "Palm Beach Class C", type: .classC, floor: 0, ceiling: 4100,
             geometry: .circle(center: Coordinate2D(CLLocationCoordinate2D(latitude: 26.6847, longitude: -80.0956)), radiusNM: 10)),
    // MOA - Avon Park
    Airspace(name: "Avon Park MOA", type: .moa, floor: 500, ceiling: 18000,
             geometry: .circle(center: Coordinate2D(CLLocationCoordinate2D(latitude: 27.5833, longitude: -81.3333)), radiusNM: 25)),
    // Restricted - Eglin
    Airspace(name: "R-2915 Eglin", type: .restricted, floor: 0, ceiling: 50000,
             geometry: .circle(center: Coordinate2D(CLLocationCoordinate2D(latitude: 30.4833, longitude: -86.5167)), radiusNM: 30)),
]

extension Airspace {
    func contains(_ coordinate: CLLocationCoordinate2D, altitude: Int) -> Bool {
        guard let ceiling = ceiling, altitude <= ceiling else { return false }
        if let floor = floor, altitude < floor { return false }

        switch geometry {
        case .circle(let center, let radius):
            let dist = Haversine.nauticalMiles(coordinate, center.clCoordinate)
            return dist <= radius
        case .polygon(let coords):
            return pointInPolygon(coordinate, polygon: coords.map { $0.clCoordinate })
        case .complex:
            return false // Would need GeoJSON parser
        }
    }

    private func pointInPolygon(_ point: CLLocationCoordinate2D, polygon: [CLLocationCoordinate2D]) -> Bool {
        var inside = false
        var j = polygon.count - 1
        for i in 0..<polygon.count {
            let pi = polygon[i], pj = polygon[j]
            if ((pi.latitude > point.latitude) != (pj.latitude > point.latitude)) &&
               (point.longitude < (pj.longitude - pi.longitude) * (point.latitude - pi.latitude) / (pj.latitude - pi.latitude) + pi.longitude) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }

    var color: String {
        switch type {
        case .classA: return "#FF0000"
        case .classB: return "#0000FF"
        case .classC: return "#FF8C00"
        case .classD: return "#00BFFF"
        case .classE: return "#9932CC"
        case .moa: return "#FF69B4"
        case .restricted, .prohibited: return "#DC143C"
        case .tfr: return "#FF0000"
        default: return "#808080"
        }
    }
}

// MARK: - Terrain/Obstacle (simplified)

struct Obstacle: Identifiable, Codable {
    let id = UUID()
    let coordinate: Coordinate2D
    let elevationFt: Int
    let heightFt: Int  // above ground
    let type: String   // tower, building, terrain, etc.
    var topElevation: Int { elevationFt + heightFt }

    var clCoordinate: CLLocationCoordinate2D { coordinate.clCoordinate }
}

// Sample major obstacles in Florida
let floridaObstacles: [Obstacle] = [
    Obstacle(coordinate: Coordinate2D(CLLocationCoordinate2D(latitude: 25.7617, longitude: -80.1918)), elevationFt: 10, heightFt: 1000, type: "tower"), // Miami
    Obstacle(coordinate: Coordinate2D(CLLocationCoordinate2D(latitude: 28.5383, longitude: -81.3792)), elevationFt: 100, heightFt: 500, type: "tower"), // Orlando
]

// MARK: - Airspace Checker

struct AirspaceChecker {
    static func check(coordinate: CLLocationCoordinate2D, altitude: Int) -> [Airspace] {
        floridaAirspaces.filter { $0.contains(coordinate, altitude: altitude) }
    }

    static func checkRoute(_ route: [Airport], altitude: Int) -> [(Airport, [Airspace])] {
        route.map { ($0, check(coordinate: $0.coordinate, altitude: altitude)) }
    }

    static func checkObstacles(_ route: [Airport], altitude: Int, bufferNM: Double = 5) -> [Obstacle] {
        floridaObstacles.filter { obs in
            route.contains { apt in
                Haversine.nauticalMiles(apt.coordinate, obs.clCoordinate) <= bufferNM
            } && obs.topElevation >= altitude - 500
        }
    }
}