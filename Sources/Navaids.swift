import Foundation
import CoreLocation

/// Non-airport waypoints: VOR/NDB (OurAirports), FAA fixes and VFR waypoints (FAA ADDS), bundled for
/// Florida by scripts/build_navaids.py, plus the pilot's own points (stored in AppModel).
/// They reuse `Airport` so the plan, routing, navlog and map treat every waypoint the same way.
enum NavaidStore {
    static let all: [Airport] = {
        guard let url = Bundle.main.url(forResource: "navaids", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let list = try? JSONDecoder().decode([Airport].self, from: data) else { return [] }
        return list
    }()

    private static let byID: [String: Airport] = {
        var d: [String: Airport] = [:]
        // A VOR wins over a fix with the same ident.
        for a in all where d[a.id] == nil || a.type == "vor" { d[a.id] = a }
        return d
    }()

    static func find(_ ident: String) -> Airport? { byID[ident.uppercased()] }

    static func search(_ q: String, limit: Int = 30) -> [Airport] {
        let q = q.uppercased()
        guard !q.isEmpty else { return [] }
        let hits = all.filter { $0.id.hasPrefix(q) || $0.name.uppercased().contains(q) }
        return Array(hits.sorted { ($0.id == q ? 0 : 1, $0.id) < ($1.id == q ? 0 : 1, $1.id) }.prefix(limit))
    }

    static func nearest(to c: CLLocationCoordinate2D, limit: Int = 10, types: Set<String> = ["vor", "ndb"]) -> [Airport] {
        Array(all.filter { types.contains($0.type) }
            .sorted { $0.distanceNM(to: c) < $1.distanceNM(to: c) }
            .prefix(limit))
    }

    /// Navaids/fixes inside a map region, capped (shown on the map only when zoomed in).
    static func inRegion(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double,
                         types: Set<String>, limit: Int) -> [Airport] {
        var out: [Airport] = []
        for a in all where types.contains(a.type)
            && a.coordinate.latitude >= minLat && a.coordinate.latitude <= maxLat
            && a.coordinate.longitude >= minLon && a.coordinate.longitude <= maxLon {
            out.append(a)
            if out.count >= limit { break }
        }
        return out
    }
}

extension Airport {
    static let waypointTypes: Set<String> = ["vor", "ndb", "fix", "vfr_wp", "user", "gps"]

    /// True for a real airport/heliport/seaplane base (has an airport card, METAR, NOTAM).
    var isAirport: Bool { !Airport.waypointTypes.contains(type) }

    var kindLabel: String {
        switch type {
        case "vor": return "VOR"
        case "ndb": return "NDB"
        case "fix": return "Fix"
        case "vfr_wp": return "Point VFR"
        case "user": return "Point perso"
        case "gps": return "Position GPS"
        default: return "Aéroport"
        }
    }

    var symbolName: String {
        switch type {
        case "vor": return "hexagon"
        case "ndb": return "circle.dotted"
        case "fix": return "triangle"
        case "vfr_wp": return "flag.fill"
        case "user": return "mappin"
        case "gps": return "location.fill"
        default: return "airplane.circle.fill"
        }
    }

    /// "27°29.9'N 080°22.4'W", the coordinate style used on charts.
    var coordinateText: String {
        func dm(_ v: Double, _ pos: String, _ neg: String, _ width: Int) -> String {
            let a = abs(v), d = Int(a), m = (a - Double(d)) * 60
            return String(format: "%0\(width)d°%04.1f'%@", d, m, v >= 0 ? pos : neg)
        }
        return dm(coordinate.latitude, "N", "S", 2) + " " + dm(coordinate.longitude, "E", "W", 3)
    }

    /// ICAO flight-plan form of a point: ident for airports/navaids/fixes, "2730N08022W" for a user point.
    var flightPlanToken: String {
        guard type == "user" || type == "gps" else { return id }
        let lat = abs(coordinate.latitude), lon = abs(coordinate.longitude)
        return String(format: "%02d%02d%@%03d%02d%@",
                      Int(lat), Int((lat - Double(Int(lat))) * 60), coordinate.latitude >= 0 ? "N" : "S",
                      Int(lon), Int((lon - Double(Int(lon))) * 60), coordinate.longitude >= 0 ? "E" : "W")
    }
}
