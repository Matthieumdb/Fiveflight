import Foundation
import CoreLocation

/// One row of the navigation log: a straight segment of the (possibly detoured) route.
struct NavLogLeg: Identifiable, Hashable {
    let id = UUID()
    let from: String
    let to: String
    let distanceNM: Double
    let trueCourse: Int
    let magneticHeading: Int
    let windDirection: Int?
    let windSpeed: Int?
    let groundSpeed: Double
    let minutes: Double
    let fuelGallons: Double
}

/// Wind triangle and navlog built from the FAA winds aloft (FB) forecast.
enum Navlog {
    /// Builds the log for route `legs` (from the RoutingEngine) flown at `tas` and `altitude`.
    /// Without wind data the ground speed is the true airspeed.
    static func build(legs: [RouteLeg], tas: Double, altitude: Int, fuelBurn: Double,
                      winds: [WindsAloft]) -> [NavLogLeg] {
        guard tas > 0 else { return [] }
        var rows: [NavLogLeg] = []
        for leg in legs {
            let points = leg.waypoints
            guard points.count >= 2 else { continue }
            for i in 1..<points.count {
                let a = points[i - 1], b = points[i]
                let nm = Haversine.nauticalMiles(a, b)
                guard nm > 0.05 else { continue }
                let tc = Double(Haversine.trueCourse(a, b))
                let mid = Haversine.midpoint(a, b)
                let w = wind(at: mid, altitude: altitude, winds: winds)
                let (wca, gs) = solve(trueCourse: tc, tas: tas, windFrom: Double(w?.direction ?? 0), windSpeed: Double(w?.speed ?? 0))
                let heading = normalize(tc + wca - magneticVariation(at: mid))
                let minutes = nm / gs * 60
                rows.append(NavLogLeg(
                    from: i == 1 ? leg.from : "Détour \(i - 1)",
                    to: i == points.count - 1 ? leg.to : "Détour \(i)",
                    distanceNM: nm,
                    trueCourse: Int(tc.rounded()) % 360,
                    magneticHeading: Int(heading.rounded()) % 360,
                    windDirection: w?.direction,
                    windSpeed: w?.speed,
                    groundSpeed: gs,
                    minutes: minutes,
                    fuelGallons: minutes / 60 * fuelBurn
                ))
            }
        }
        return rows
    }

    /// Wind correction angle (degrees, + = right) and ground speed. A wind stronger than the aircraft
    /// can fly against gives a floor of 10 kt rather than a negative ground speed.
    static func solve(trueCourse: Double, tas: Double, windFrom: Double, windSpeed: Double) -> (wca: Double, gs: Double) {
        let rad = Double.pi / 180
        let angle = (windFrom - trueCourse) * rad
        let cross = windSpeed * sin(angle)
        let ratio = max(-1, min(1, cross / tas))
        let wca = asin(ratio)
        let gs = tas * cos(wca) - windSpeed * cos(angle)
        return (wca / rad, max(10, gs))
    }

    /// Wind at `altitude` from the nearest FB station, interpolated between the two bracketing levels
    /// (as vectors, so 350° and 010° average to 000°, not 180°).
    static func wind(at point: CLLocationCoordinate2D, altitude: Int, winds: [WindsAloft]) -> (direction: Int, speed: Int)? {
        guard let station = winds.min(by: {
            Haversine.nauticalMiles(point, CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
                < Haversine.nauticalMiles(point, CLLocationCoordinate2D(latitude: $1.latitude, longitude: $1.longitude))
        }) else { return nil }
        let levels = station.levels.sorted { $0.altitude < $1.altitude }
        guard let first = levels.first else { return nil }
        let lower = levels.last { $0.altitude <= altitude } ?? first
        let upper = levels.first { $0.altitude >= altitude } ?? levels.last!
        let t = upper.altitude == lower.altitude ? 0 : Double(altitude - lower.altitude) / Double(upper.altitude - lower.altitude)
        func vector(_ l: WindsAloftLevel) -> (Double, Double) {
            let r = Double(l.direction) * .pi / 180
            return (Double(l.speed) * sin(r), Double(l.speed) * cos(r))
        }
        let (x0, y0) = vector(lower), (x1, y1) = vector(upper)
        let x = x0 + (x1 - x0) * t, y = y0 + (y1 - y0) * t
        let speed = (x * x + y * y).squareRoot()
        let direction = speed < 0.5 ? 0 : normalize(atan2(x, y) * 180 / .pi)
        return (Int(direction.rounded()) % 360, Int(speed.rounded()))
    }

    /// Magnetic variation (east positive) for Florida, 2026.
    /// ponytail: linear fit on longitude (±1.5° vs the World Magnetic Model); swap in WMM if the app leaves Florida.
    static func magneticVariation(at point: CLLocationCoordinate2D) -> Double {
        -2.0 - (point.longitude + 87.2) * 0.75
    }

    private static func normalize(_ degrees: Double) -> Double {
        let d = degrees.truncatingRemainder(dividingBy: 360)
        return d < 0 ? d + 360 : d
    }
}
