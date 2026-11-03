import Foundation
import CoreLocation

/// Routing engine for VFR flight planning
/// Supports direct routing and controlled airspace avoidance
@MainActor
final class RoutingEngine: ObservableObject {
    static let shared = RoutingEngine()

    enum RoutingMode: String, CaseIterable, Identifiable {
        case direct = "Direct"
        case avoidControlled = "Éviter B/C/D"
        case avoidAllSUA = "Éviter tout"

        var id: String { rawValue }

        var icon: String {
            switch self {
            case .direct: return "arrow.up.right"
            case .avoidControlled: return "shield.lefthalf.filled"
            case .avoidAllSUA: return "shield.fill"
            }
        }

        var description: String {
            switch self {
            case .direct: return "Ligne droite entre les points"
            case .avoidControlled: return "Contourne les Class B, C, D et E surface"
            case .avoidAllSUA: return "Contourne aussi R, P, MOA, zones d'alerte et TFR"
            }
        }
    }

    @Published var currentMode: RoutingMode = .direct
    @Published var isCalculating = false
    @Published var lastRoute: RouteResult?
    @Published var error: String?

    private init() {}

    /// Calculates a route between waypoints
    func calculateRoute(
        waypoints: [Airport],
        cruiseAltitude: Int,
        mode: RoutingMode,
        airspaces: [Airspace]
    ) async -> RouteResult? {
        guard waypoints.count >= 2 else { return nil }

        isCalculating = true
        error = nil
        defer { isCalculating = false }

        var allLegs: [RouteLeg] = []
        var totalNM = 0.0
        var totalTime = 0.0
        var airspaceWarnings: [AirspaceWarning] = []

        for i in 0..<waypoints.count - 1 {
            let from = waypoints[i]
            let to = waypoints[i + 1]

            let leg = await calculateLeg(
                from: from.coordinate,
                to: to.coordinate,
                fromIdent: from.id,
                toIdent: to.id,
                altitude: cruiseAltitude,
                mode: mode,
                airspaces: airspaces
            )

            allLegs.append(leg)
            totalNM += leg.distanceNM
            totalTime += leg.timeMinutes

            // Collect airspace warnings
            for warning in leg.airspaceWarnings {
                airspaceWarnings.append(AirspaceWarning(
                    legIndex: i,
                    airspace: warning.airspace,
                    type: warning.type
                ))
            }
        }

        let result = RouteResult(
            legs: allLegs,
            totalDistanceNM: totalNM,
            totalTimeMinutes: totalTime,
            airspaceWarnings: airspaceWarnings,
            mode: mode,
            cruiseAltitude: cruiseAltitude,
            generatedAt: Date()
        )

        if mode == currentMode { lastRoute = result } // a stale calculation must not overwrite the summary
        return result
    }

    /// Calculates a single leg using A* pathfinding
    private func calculateLeg(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        fromIdent: String,
        toIdent: String,
        altitude: Int,
        mode: RoutingMode,
        airspaces: [Airspace]
    ) async -> RouteLeg {
        let directDistance = Haversine.nauticalMiles(from, to)
        let directCourse = Haversine.trueCourse(from, to)

        // For direct mode, just return straight line
        if mode == .direct {
            let warnings = checkAirspaceIntersections(
                from: from, to: to, altitude: altitude, airspaces: airspaces
            )
            return RouteLeg(
                from: fromIdent,
                to: toIdent,
                waypoints: [from, to],
                distanceNM: directDistance,
                trueCourse: directCourse,
                timeMinutes: directDistance / 120.0 * 60, // Assume 120 kt
                fuelGallons: directDistance / 120.0 * 10, // Assume 10 gal/h
                airspaceWarnings: warnings,
                mode: mode
            )
        }

        // Grid A* around the blocking airspaces, then straightened.
        let blockers = Self.blockingRings(airspaces, from: from, to: to, altitude: altitude, mode: mode)
        let path = await Task.detached(priority: .userInitiated) {
            Self.findPath(start: from, goal: to, blockers: blockers)
        }.value

        var totalDist = 0.0
        var totalTime = 0.0
        var totalFuel = 0.0
        var previous = path[0]
        var allWarnings: [LegAirspaceWarning] = []

        for i in 1..<path.count {
            let current = path[i]
            let dist = Haversine.nauticalMiles(previous, current)
            totalDist += dist
            totalTime += dist / 120.0 * 60
            totalFuel += dist / 120.0 * 10

            let warnings = checkAirspaceIntersections(
                from: previous, to: current, altitude: altitude, airspaces: airspaces
            )
            allWarnings.append(contentsOf: warnings)

            previous = current
        }

        return RouteLeg(
            from: fromIdent,
            to: toIdent,
            waypoints: path,
            distanceNM: totalDist,
            trueCourse: directCourse, // Overall course
            timeMinutes: totalTime,
            fuelGallons: totalFuel,
            airspaceWarnings: allWarnings,
            mode: mode
        )
    }

    // MARK: - Avoidance

    /// A polygon ring to keep out of, with its bounding box for fast rejection.
    struct Blocker: Sendable {
        let ring: [CLLocationCoordinate2D]
        let minLat, maxLat, minLon, maxLon: Double

        init(_ ring: [CLLocationCoordinate2D]) {
            self.ring = ring
            minLat = ring.map(\.latitude).min() ?? 0; maxLat = ring.map(\.latitude).max() ?? 0
            minLon = ring.map(\.longitude).min() ?? 0; maxLon = ring.map(\.longitude).max() ?? 0
        }

        func contains(_ p: CLLocationCoordinate2D) -> Bool {
            p.latitude >= minLat && p.latitude <= maxLat && p.longitude >= minLon && p.longitude <= maxLon
                && Airspace.pointInPolygonStatic(p, polygon: ring)
        }

        func crosses(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
            guard max(a.latitude, b.latitude) >= minLat, min(a.latitude, b.latitude) <= maxLat,
                  max(a.longitude, b.longitude) >= minLon, min(a.longitude, b.longitude) <= maxLon else { return false }
            return Airspace.segmentIntersectsPolygonInternal(a, b, polygon: ring)
        }
    }

    /// Rings the leg must stay out of. Any part of a Class B/C/D (or E surface, or permission-only SUA)
    /// whose floor is at or below the cruise altitude is avoided laterally: the aircraft would be inside
    /// it in cruise, climb or descent. The airspace around the departure or destination is exempt
    /// (all its shelves, which share its name): you have to fly through it.
    static func blockingRings(_ airspaces: [Airspace], from: CLLocationCoordinate2D, to: CLLocationCoordinate2D,
                              altitude: Int, mode: RoutingMode) -> [Blocker] {
        let candidates = airspaces.filter { airspace in
            guard airspace.isActive, airspace.floor <= altitude else { return false }
            switch (mode, airspace.type) {
            case (.direct, _): return false
            case (_, .classAirspace(let cls)): return cls.requiresATC
            case (_, .classESurface): return true
            case (.avoidAllSUA, .sua): return true
            default: return false
            }
        }
        let rings = candidates.map { a in (a.name, a.polygons.map { Blocker($0.map(\.clCoordinate)) }) }
        let exempt = Set(rings.filter { $0.1.contains { $0.contains(from) || $0.contains(to) } }.map(\.0))
        return rings.filter { !exempt.contains($0.0) }.flatMap(\.1)
    }

    /// A* on a ~1.8 NM grid; an edge is allowed only if the segment crosses no blocker.
    /// Falls back to the straight line when no path exists.
    nonisolated static func findPath(start: CLLocationCoordinate2D, goal: CLLocationCoordinate2D,
                                     blockers: [Blocker]) -> [CLLocationCoordinate2D] {
        func clear(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Bool {
            !blockers.contains { $0.crosses(a, b) }
        }
        if clear(start, goal) { return [start, goal] }

        let res = 0.03
        let pad = 0.6 + 0.3 * max(abs(start.latitude - goal.latitude), abs(start.longitude - goal.longitude))
        let minLat = min(start.latitude, goal.latitude) - pad, minLon = min(start.longitude, goal.longitude) - pad
        let rows = Int((max(start.latitude, goal.latitude) + pad - minLat) / res) + 1
        let cols = Int((max(start.longitude, goal.longitude) + pad - minLon) / res) + 1
        let cosLat = cos((start.latitude + goal.latitude) / 2 * .pi / 180)

        // Node index rows*cols is the start, rows*cols+1 the goal; the rest are grid points.
        let startID = rows * cols, goalID = startID + 1
        func coord(_ id: Int) -> CLLocationCoordinate2D {
            if id == startID { return start }
            if id == goalID { return goal }
            return CLLocationCoordinate2D(latitude: minLat + Double(id / cols) * res, longitude: minLon + Double(id % cols) * res)
        }
        func cell(_ c: CLLocationCoordinate2D) -> (Int, Int) {
            (Int(((c.latitude - minLat) / res).rounded()), Int(((c.longitude - minLon) / res).rounded()))
        }
        func cost(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
            let dLat = a.latitude - b.latitude, dLon = (a.longitude - b.longitude) * cosLat
            return (dLat * dLat + dLon * dLon).squareRoot()
        }
        // Start/goal connect to grid points up to 2 cells away.
        func near(_ c: CLLocationCoordinate2D) -> [Int] {
            let (r0, c0) = cell(c)
            var ids: [Int] = []
            for r in (r0 - 2)...(r0 + 2) where r >= 0 && r < rows {
                for k in (c0 - 2)...(c0 + 2) where k >= 0 && k < cols { ids.append(r * cols + k) }
            }
            return ids
        }
        let goalNeighbors = Set(near(goal))
        func neighbors(_ id: Int) -> [Int] {
            if id == startID { return near(start) }
            let r = id / cols, k = id % cols
            var out: [Int] = []
            for dr in -1...1 { for dk in -1...1 where dr != 0 || dk != 0 {
                let nr = r + dr, nk = k + dk
                if nr >= 0, nr < rows, nk >= 0, nk < cols { out.append(nr * cols + nk) }
            } }
            if goalNeighbors.contains(id) { out.append(goalID) }
            return out
        }

        var g: [Int: Double] = [startID: 0]
        var cameFrom: [Int: Int] = [:]
        var closed = Set<Int>()
        var heap = MinHeap()
        heap.push(cost(start, goal), startID)
        while let (_, id) = heap.pop() {
            if id == goalID {
                var path = [goalID]
                while let p = cameFrom[path.last!] { path.append(p) }
                return smooth(path.reversed().map(coord), clear: clear)
            }
            guard closed.insert(id).inserted else { continue }
            let here = coord(id)
            for n in neighbors(id) where !closed.contains(n) {
                let there = coord(n)
                guard clear(here, there) else { continue }
                let tentative = g[id]! + cost(here, there)
                if tentative < g[n] ?? .infinity {
                    g[n] = tentative
                    cameFrom[n] = id
                    heap.push(tentative + cost(there, goal), n)
                }
            }
        }
        return [start, goal]
    }

    /// Drops grid zig-zags: from each point, jump to the farthest later point still in clear line of sight.
    nonisolated static func smooth(_ path: [CLLocationCoordinate2D],
                                   clear: (CLLocationCoordinate2D, CLLocationCoordinate2D) -> Bool) -> [CLLocationCoordinate2D] {
        guard path.count > 2 else { return path }
        var out = [path[0]]
        var i = 0
        while i < path.count - 1 {
            var j = path.count - 1
            while j > i + 1 && !clear(path[i], path[j]) { j -= 1 }
            out.append(path[j])
            i = j
        }
        return out
    }

    // MARK: - Airspace Checking

    private func checkAirspaceIntersections(
        from: CLLocationCoordinate2D,
        to: CLLocationCoordinate2D,
        altitude: Int,
        airspaces: [Airspace]
    ) -> [LegAirspaceWarning] {
        airspaces.compactMap { airspace -> LegAirspaceWarning? in
            guard airspace.isActive else { return nil }
            guard altitude >= airspace.floor && altitude <= airspace.ceiling else { return nil }

            var intersects = false
            for ring in airspace.polygons {
                if Airspace.segmentIntersectsPolygon(from, to, polygon: ring) {
                    intersects = true
                    break
                }
            }

            guard intersects else { return nil }

            let type: AirspaceWarningType
            switch airspace.type {
            case .classAirspace(let cls):
                type = cls.requiresATC ? .controlledAirspace : .classE
            case .sua(let sua):
                type = sua.requiresPermission ? .restrictedSUA : .warningSUA
            case .classESurface:
                type = .classE
            case .airway:
                type = .airway
            }

            return LegAirspaceWarning(airspace: airspace, type: type)
        }
    }
}

/// Result of a route calculation
struct RouteResult: Identifiable {
    var id = UUID()
    let legs: [RouteLeg]
    let totalDistanceNM: Double
    let totalTimeMinutes: Double
    let airspaceWarnings: [AirspaceWarning]
    let mode: RoutingEngine.RoutingMode
    let cruiseAltitude: Int
    let generatedAt: Date

    var formattedDistance: String {
        String(format: "%.0f NM", totalDistanceNM)
    }

    /// Extra distance flown versus straight legs between the waypoints.
    var detourNM: Double {
        totalDistanceNM - legs.reduce(0) { sum, leg in
            guard let a = leg.waypoints.first, let b = leg.waypoints.last else { return sum }
            return sum + Haversine.nauticalMiles(a, b)
        }
    }

    /// One line telling the pilot what the selected mode did to this route.
    var summary: String {
        if mode == .direct { return mode.description }
        if legs.contains(where: { $0.waypoints.count > 2 }) {
            return String(format: "Détour de %.0f NM pour contourner les espaces", detourNM)
        }
        return "Rien à contourner : la directe est libre"
    }

    var formattedTime: String {
        let h = Int(totalTimeMinutes) / 60
        let m = Int(totalTimeMinutes) % 60
        return h > 0 ? "\(h)h\(String(format: "%02d", m))m" : "\(m)m"
    }

    var totalFuel: Double {
        legs.reduce(0) { $0 + $1.fuelGallons }
    }

    var hasControlledAirspaceWarnings: Bool {
        airspaceWarnings.contains { $0.type == .controlledAirspace }
    }

    var hasRestrictedWarnings: Bool {
        airspaceWarnings.contains { $0.type == .restrictedSUA }
    }
}

/// Individual leg of a route
struct RouteLeg: Identifiable {
    var id = UUID()
    let from: String
    let to: String
    let waypoints: [CLLocationCoordinate2D]
    let distanceNM: Double
    let trueCourse: Int
    let timeMinutes: Double
    let fuelGallons: Double
    let airspaceWarnings: [LegAirspaceWarning]
    let mode: RoutingEngine.RoutingMode

    var formattedDistance: String {
        String(format: "%.0f NM", distanceNM)
    }

    var formattedTime: String {
        let m = Int(timeMinutes.rounded())
        return m >= 60 ? "\(m/60)h\(String(format: "%02d", m%60))m" : "\(m)m"
    }

    var formattedFuel: String {
        String(format: "%.1f gal", fuelGallons)
    }
}

/// Airspace warning for a leg
struct LegAirspaceWarning: Identifiable {
    var id = UUID()
    let airspace: Airspace
    let type: AirspaceWarningType
}

struct AirspaceWarning: Identifiable {
    var id = UUID()
    let legIndex: Int
    let airspace: Airspace
    let type: AirspaceWarningType
}

enum AirspaceWarningType {
    case controlledAirspace  // Class B/C/D
    case classE             // Class E surface
    case restrictedSUA      // Restricted, Prohibited, TFR
    case warningSUA         // MOA, Warning, Alert, CFA
    case airway

    var color: String {
        switch self {
        case .controlledAirspace: return "#0044CC"
        case .classE: return "#AA8800"
        case .restrictedSUA: return "#CC0000"
        case .warningSUA: return "#FF6B35"
        case .airway: return "#008844"
        }
    }

    var icon: String {
        switch self {
        case .controlledAirspace: return "shield.lefthalf.filled"
        case .classE: return "shield"
        case .restrictedSUA: return "exclamationmark.shield.fill"
        case .warningSUA: return "exclamationmark.triangle.fill"
        case .airway: return "arrow.up.and.down"
        }
    }

    var description: String {
        switch self {
        case .controlledAirspace: return "Controlled airspace - ATC clearance required"
        case .classE: return "Class E surface area - ATC comm required"
        case .restrictedSUA: return "Restricted/Prohibited/TFR - Permission required"
        case .warningSUA: return "Caution area - Verify status before entry"
        case .airway: return "Crossing airway - Monitor CTAF"
        }
    }
}

/// Binary min-heap of (priority, node id) for A*.
struct MinHeap {
    private var items: [(Double, Int)] = []

    mutating func push(_ priority: Double, _ id: Int) {
        items.append((priority, id))
        var i = items.count - 1
        while i > 0, items[(i - 1) / 2].0 > items[i].0 { items.swapAt(i, (i - 1) / 2); i = (i - 1) / 2 }
    }

    mutating func pop() -> (Double, Int)? {
        guard !items.isEmpty else { return nil }
        items.swapAt(0, items.count - 1)
        let top = items.removeLast()
        var i = 0
        while true {
            let l = 2 * i + 1, r = l + 1
            var m = i
            if l < items.count, items[l].0 < items[m].0 { m = l }
            if r < items.count, items[r].0 < items[m].0 { m = r }
            if m == i { break }
            items.swapAt(i, m); i = m
        }
        return top
    }
}
