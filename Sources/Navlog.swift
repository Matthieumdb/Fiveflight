import Foundation
import CoreLocation

/// One row of the navigation log, ForeFlight style: a straight segment of the (possibly detoured) route.
struct NavLogLeg: Identifiable, Hashable {
    let id = UUID()
    let from: String
    let to: String
    let distanceNM: Double
    /// Distance still to fly after this leg.
    let remainingNM: Double
    let trueCourse: Int
    let magneticCourse: Int
    /// Wind correction angle, degrees (+ = right).
    let wca: Int
    let magneticHeading: Int
    let altitude: Int
    let windDirection: Int?
    let windSpeed: Int?
    let temperature: Int?
    let tas: Double
    let groundSpeed: Double
    let minutes: Double
    /// Time since departure at the end of the leg.
    let cumulativeMinutes: Double
    /// Estimated time over the leg's end point.
    let eta: Date
    let fuelGallons: Double
    /// Fuel left at the end of the leg; nil when no fuel load was entered.
    let fuelRemaining: Double?
    /// FD station and period the wind came from, e.g. "MLB 12 h".
    let windSource: String?

    /// Head (+) or tail (−) wind component, kt.
    var headwind: Int? {
        guard let d = windDirection, let s = windSpeed else { return nil }
        let angle = Double(d - trueCourse) * .pi / 180
        return Int((Double(s) * cos(angle)).rounded())
    }
}

/// One stretch of route between two named points, as drawn on the map.
struct NavlogSegment: Hashable {
    let from: String
    let to: String
    let points: [CLLocationCoordinate2D]

    static func == (a: NavlogSegment, b: NavlogSegment) -> Bool {
        a.from == b.from && a.to == b.to && a.points.count == b.points.count
            && zip(a.points, b.points).allSatisfy { $0.latitude == $1.latitude && $0.longitude == $1.longitude }
    }
    func hash(into h: inout Hasher) {
        h.combine(from); h.combine(to); h.combine(points.count)
        for p in points { h.combine(p.latitude); h.combine(p.longitude) }
    }
}

/// Climb and descent performance of the aircraft flown.
struct VerticalPerformance: Hashable {
    var climbTAS: Double
    var climbFPM: Double
    var climbBurn: Double
    var descentTAS: Double
    var descentFPM: Double

    init(climbTAS: Double, climbFPM: Double, climbBurn: Double, descentTAS: Double, descentFPM: Double) {
        self.climbTAS = climbTAS; self.climbFPM = climbFPM; self.climbBurn = climbBurn
        self.descentTAS = descentTAS; self.descentFPM = descentFPM
    }

    init(_ a: AircraftProfile) {
        self.init(climbTAS: a.climbSpeed, climbFPM: a.climbRate, climbBurn: a.climbBurn,
                  descentTAS: a.descentSpeed, descentFPM: a.descentRate)
    }
}

/// Top of climb and top of descent along the route.
struct VerticalProfile: Hashable {
    /// Distance from departure to the top of climb, NM.
    let tocNM: Double
    /// Distance before the destination where the descent starts, NM.
    let todNM: Double
    let climbMinutes: Double
    let descentMinutes: Double
    /// Pattern altitude reached at the end of the descent (destination elevation + 1000 ft).
    let patternAltitude: Int

    /// Climb from the departure elevation, descent to 1000 ft above the destination. When the route is
    /// too short to reach cruise, both are shortened in proportion.
    static func make(totalNM: Double, cruiseAlt: Int, departureElevation: Int, arrivalElevation: Int,
                     perf: VerticalPerformance) -> VerticalProfile {
        let climbFt = Double(max(0, cruiseAlt - departureElevation))
        let pattern = arrivalElevation + 1000
        let descentFt = Double(max(0, cruiseAlt - pattern))
        var climbMin = perf.climbFPM > 0 ? climbFt / perf.climbFPM : 0
        var descentMin = perf.descentFPM > 0 ? descentFt / perf.descentFPM : 0
        var toc = perf.climbTAS * climbMin / 60
        var tod = perf.descentTAS * descentMin / 60
        if toc + tod > totalNM, toc + tod > 0 {
            let k = totalNM / (toc + tod)
            toc *= k; tod *= k; climbMin *= k; descentMin *= k
        }
        return VerticalProfile(tocNM: toc, todNM: tod, climbMinutes: climbMin, descentMinutes: descentMin,
                               patternAltitude: pattern)
    }
}

/// Wind triangle and navlog built from the FAA winds aloft (FD) forecast.
enum Navlog {
    /// Builds the log flown at `tas` and `altitude`, departing at `departure`.
    /// Each leg takes its wind from the FD period (6/12/24 h) whose "FOR USE" window covers the leg's mid time.
    /// Without wind data the ground speed is the true airspeed.
    /// With `vertical`, the stretch before the top of climb is flown at the climb speed and burn, and the
    /// stretch after the top of descent at the descent speed (burn = 70 % of cruise).
    static func build(segments: [NavlogSegment], tas: Double, altitude: Int, fuelBurn: Double,
                      winds: [WindsAloft], departure: Date = .now, fuelOnBoard: Double = 0,
                      vertical: VerticalPerformance? = nil, departureElevation: Int = 0,
                      arrivalElevation: Int = 0) -> [NavLogLeg] {
        guard tas > 0 else { return [] }
        // Flatten into straight pieces first so the remaining distance is known.
        var pieces: [(from: String, to: String, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D, nm: Double)] = []
        for seg in segments {
            let points = seg.points
            guard points.count >= 2 else { continue }
            var detour = 0
            for i in 1..<points.count {
                let a = points[i - 1], b = points[i]
                let nm = Haversine.nauticalMiles(a, b)
                guard nm > 0.05 else { continue }
                let last = i == points.count - 1
                let fromName = i == 1 ? seg.from : "DET\(detour)"
                if !last { detour += 1 }
                pieces.append((fromName, last ? seg.to : "DET\(detour)", a, b, nm))
            }
        }
        let total = pieces.reduce(0) { $0 + $1.nm }
        let profile = vertical.map {
            VerticalProfile.make(totalNM: total, cruiseAlt: altitude, departureElevation: departureElevation,
                                 arrivalElevation: arrivalElevation, perf: $0)
        }
        var flown = 0.0, elapsed = 0.0, burned = 0.0
        var rows: [NavLogLeg] = []
        for p in pieces {
            let tc = Double(Haversine.trueCourse(p.a, p.b))
            let mid = Haversine.midpoint(p.a, p.b)
            let variation = magneticVariation(at: mid)
            // First guess of the leg's mid time at TAS, refined once the ground speed is known.
            let guessMid = departure.addingTimeInterval((elapsed + p.nm / tas * 30) * 60)
            let set = windSet(for: guessMid, from: winds)
            let w = wind(at: mid, altitude: altitude, winds: set.winds)
            let windFrom = Double(w?.direction ?? 0), windSpeed = Double(w?.speed ?? 0)
            let (wca, gs) = solve(trueCourse: tc, tas: tas, windFrom: windFrom, windSpeed: windSpeed)
            var minutes = p.nm / gs * 60
            var fuel = minutes / 60 * fuelBurn
            if let v = vertical, let profile {
                func overlap(_ lo: Double, _ hi: Double) -> Double { max(0, min(flown + p.nm, hi) - max(flown, lo)) }
                let climbNM = overlap(0, profile.tocNM)
                let descentNM = overlap(total - profile.todNM, total)
                let cruiseNM = max(0, p.nm - climbNM - descentNM)
                let gsClimb = solve(trueCourse: tc, tas: max(30, v.climbTAS), windFrom: windFrom, windSpeed: windSpeed).gs
                let gsDescent = solve(trueCourse: tc, tas: max(30, v.descentTAS), windFrom: windFrom, windSpeed: windSpeed).gs
                let mClimb = climbNM / gsClimb * 60, mDescent = descentNM / gsDescent * 60, mCruise = cruiseNM / gs * 60
                minutes = mClimb + mCruise + mDescent
                fuel = (mClimb * v.climbBurn + mCruise * fuelBurn + mDescent * fuelBurn * 0.7) / 60
            }
            flown += p.nm; elapsed += minutes
            burned += fuel
            let station = nearestStation(mid, set.winds)
            rows.append(NavLogLeg(
                from: p.from, to: p.to,
                distanceNM: p.nm,
                remainingNM: max(0, total - flown),
                trueCourse: Int(tc.rounded()) % 360,
                magneticCourse: Int(normalize(tc - variation).rounded()) % 360,
                wca: Int(wca.rounded()),
                magneticHeading: Int(normalize(tc + wca - variation).rounded()) % 360,
                altitude: altitude,
                windDirection: w?.direction,
                windSpeed: w?.speed,
                temperature: temperature(at: mid, altitude: altitude, winds: set.winds),
                tas: tas,
                groundSpeed: minutes > 0 ? p.nm / minutes * 60 : gs,
                minutes: minutes,
                cumulativeMinutes: elapsed,
                eta: departure.addingTimeInterval(elapsed * 60),
                fuelGallons: fuel,
                fuelRemaining: fuelOnBoard > 0 ? fuelOnBoard - burned : nil,
                windSource: station.map { "\($0.station)" + (set.period.map { " \($0) h" } ?? "") }
            ))
        }
        return rows
    }

    /// Legacy entry point (routing engine legs).
    static func build(legs: [RouteLeg], tas: Double, altitude: Int, fuelBurn: Double,
                      winds: [WindsAloft]) -> [NavLogLeg] {
        build(segments: legs.map { NavlogSegment(from: $0.from, to: $0.to, points: $0.waypoints) },
              tas: tas, altitude: altitude, fuelBurn: fuelBurn, winds: winds)
    }

    /// The FD stations to use at `time`: those of the product whose FOR USE window covers it,
    /// else the closest window; products without a window are used as they are.
    static func windSet(for time: Date, from winds: [WindsAloft]) -> (winds: [WindsAloft], period: Int?) {
        let windowed = winds.filter { $0.useFrom != nil && $0.useTo != nil }
        guard !windowed.isEmpty else { return (winds, nil) }
        func distance(_ w: WindsAloft) -> TimeInterval {
            guard let f = w.useFrom, let t = w.useTo else { return .infinity }
            if time < f { return f.timeIntervalSince(time) }
            if time >= t { return time.timeIntervalSince(t) }
            return 0
        }
        guard let best = windowed.min(by: { distance($0) < distance($1) }), let from = best.useFrom else { return (winds, nil) }
        let chosen = windowed.filter { $0.useFrom == from && $0.useTo == best.useTo }
        // Period ≈ hours between the data time (VALID) and the window's middle.
        let period: Int? = {
            guard let to = best.useTo else { return nil }
            let span = to.timeIntervalSince(from) / 3600
            return span <= 8 ? 6 : (span <= 10 ? 12 : 24)
        }()
        return (chosen, period)
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

    private static func nearestStation(_ point: CLLocationCoordinate2D, _ winds: [WindsAloft]) -> WindsAloft? {
        winds.min {
            Haversine.nauticalMiles(point, CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude))
                < Haversine.nauticalMiles(point, CLLocationCoordinate2D(latitude: $1.latitude, longitude: $1.longitude))
        }
    }

    /// Wind at `altitude` from the nearest FB station, interpolated between the two bracketing levels
    /// (as vectors, so 350° and 010° average to 000°, not 180°).
    static func wind(at point: CLLocationCoordinate2D, altitude: Int, winds: [WindsAloft]) -> (direction: Int, speed: Int)? {
        guard let station = nearestStation(point, winds) else { return nil }
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

    /// Temperature (°C) at `altitude`: interpolated between the FD levels that carry one,
    /// or the standard lapse rate (2 °C / 1000 ft) from the nearest level.
    static func temperature(at point: CLLocationCoordinate2D, altitude: Int, winds: [WindsAloft]) -> Int? {
        guard let station = nearestStation(point, winds) else { return nil }
        let levels = station.levels.filter { $0.temperature != nil }.sorted { $0.altitude < $1.altitude }
        guard let first = levels.first, let t0 = first.temperature else { return nil }
        let lower = levels.last { $0.altitude <= altitude }
        let upper = levels.first { $0.altitude >= altitude }
        if let l = lower, let u = upper, let tl = l.temperature, let tu = u.temperature, u.altitude != l.altitude {
            let f = Double(altitude - l.altitude) / Double(u.altitude - l.altitude)
            return Int((Double(tl) + Double(tu - tl) * f).rounded())
        }
        let ref = lower ?? first
        return Int((Double(ref.temperature ?? t0) - Double(altitude - ref.altitude) / 1000 * 2).rounded())
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
