import Foundation

// MARK: - ICAO Flight Plan

struct ICAOFlightPlan: Codable {
    var aircraftType: String = "C172"
    var wakeCategory: String = "L"  // L/M/H/J
    var cruiseSpeed: String = "110"  // kt
    var departure: String = ""
    var departureTime: Date = .now
    var cruiseAltitude: String = "3500"  // ft or FL
    var route: String = ""
    var destination: String = ""
    var totalEET: String = "0130"  // HHMM
    var alternate: String = ""
    var endurance: String = "0400"  // HHMM
    var personsOnBoard: Int = 1
    var remarks: String = "VFR"

    var icaoString: String {
        var lines: [String] = []
        lines.append("(FPL-")
        lines.append("-\(aircraftType)/\(wakeCategory)")
        lines.append("-\(cruiseSpeed)N")  // N = knots
        lines.append("-\(departure.uppercased())")
        lines.append("-\(departureTime.formatted(date: .omitted, time: .standard).replacingOccurrences(of: ":", with: ""))")
        lines.append("-\(cruiseSpeed)N\(cruiseAltitude) \(route.uppercased())")
        lines.append("-\(destination.uppercased()) \(totalEET)")
        if !alternate.isEmpty { lines.append("-\(alternate.uppercased())") }
        lines.append("-\(endurance) \(personsOnBoard) \(remarks.uppercased())")
        lines.append(")")
        return lines.joined()
    }
}

// MARK: - Airspace Info (for flight plan context)

struct AirspaceInfo: Identifiable, Codable {
    let id = UUID()
    let name: String
    let type: String  // Class A/B/C/D/E/G, MOA, Restricted, etc.
    let floor: Int?   // ft MSL
    let ceiling: Int? // ft MSL
    var geometry: String? // GeoJSON or simplified
}

// MARK: - Weather along route

struct RouteWeather: Codable {
    let waypoints: [RouteWxPoint]
    let windsAloft: [WindsAloftPoint]
    var worstCategory: String? {
        waypoints.compactMap { $0.category }.min { order($0) < order($1) }
    }
    private func order(_ cat: String) -> Int {
        switch cat { case "VFR": 4; case "MVFR": 3; case "IFR": 2; case "LIFR": 1; default: 0 }
    }
}

struct RouteWxPoint: Codable, Identifiable {
    let id = UUID()
    let icao: String
    let category: String?
    let wind: String?
    let temp: Int?
}

struct WindsAloftPoint: Codable {
    let icao: String
    let altitude: Int  // ft
    let windDir: Int
    let windSpd: Int
    let temp: Int
}

// MARK: - GPX Export/Import

struct GPXExport {
    static func export(waypoints: [Airport], route: [Airport]) -> String {
        var gpx = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="Fiveflight">
        """
        for w in waypoints {
            gpx += "\n  <wpt lat=\"\(w.coordinate.latitude)\" lon=\"\(w.coordinate.longitude)\"><name>\(w.id)</name><desc>\(w.name)</desc></wpt>"
        }
        if route.count >= 2 {
            gpx += "\n  <rte><name>Flight Plan</name>"
            for w in route {
                gpx += "\n    <rtept lat=\"\(w.coordinate.latitude)\" lon=\"\(w.coordinate.longitude)\"><name>\(w.id)</name></rtept>"
            }
            gpx += "\n  </rte>"
        }
        gpx += "\n</gpx>"
        return gpx
    }
}

struct FPLExport {
    static func export(plan: ICAOFlightPlan) -> String { plan.icaoString }
}

// MARK: - Route Weather Service

enum RouteWeatherService {
    static func fetch(for route: [Airport]) async -> RouteWeather {
        let icaos = route.map(\.id)
        async let cats = WeatherService.categories(for: icaos)
        async let mtrs = fetchMetars(for: icaos)
        let (categories, metars) = await (cats, mtrs)

        var points: [RouteWxPoint] = []
        for apt in route {
            let cat = categories[apt.id]
            let metar = metars[apt.id]
            points.append(RouteWxPoint(
                icao: apt.id,
                category: cat,
                wind: metar?.windText,
                temp: metar?.tempC
            ))
        }
        return RouteWeather(waypoints: points, windsAloft: [])
    }

    private static func fetchMetars(for icaos: [String]) async -> [String: AirportWeather] {
        var result: [String: AirportWeather] = [:]
        for icao in icaos.prefix(10) {
            if let wx = await WeatherService.fetch(icao: icao) { result[icao] = wx }
        }
        return result
    }
}