import Foundation
import CoreLocation

/// Routing engine for VFR flight planning
/// Supports direct routing and controlled airspace avoidance
@MainActor
final class RoutingEngine: ObservableObject {
    static let shared = RoutingEngine()

    enum RoutingMode: String, CaseIterable, Identifiable {
        case direct = "Direct"
        case avoidControlled = "Avoid Controlled Airspace"
        case avoidAllSUA = "Avoid All SUA"

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
            case .direct: return "Great circle route between waypoints"
            case .avoidControlled: return "Route around Class B/C/D/E surface areas"
            case .avoidAllSUA: return "Avoid MOAs, Restricted, Prohibited, TFRs"
            }
        }
    }

    @Published var currentMode: RoutingMode = .direct
    @Published var isCalculating = false
    @Published var lastRoute: RouteResult?
    @Published var error: String?

    private let gridResolution: Double = 0.1 // degrees (~6 NM at mid-latitudes)
    private let maxAltitude = 17500 // VFR max
    private let minAltitude = 500  // AGL buffer

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

        lastRoute = result
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

        // A* pathfinding to avoid airspace
        let path = await findPathAStar(
            start: from,
            goal: to,
            altitude: altitude,
            mode: mode,
            airspaces: airspaces
        )

        var totalDist = 0.0
        var totalTime = 0.0
        var totalFuel = 0.0
        var previous = path[0]
        var allWarnings: [LegAirspaceWarning] = []

        for i in 1..<path.count {
            let current = path[i]
            let dist = Haversine.nauticalMiles(previous, current)
            let course = Haversine.trueCourse(previous, current)
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

    /// A* pathfinding on a grid to avoid controlled airspace
    private func findPathAStar(
        start: CLLocationCoordinate2D,
        goal: CLLocationCoordinate2D,
        altitude: Int,
        mode: RoutingMode,
        airspaces: [Airspace]
    ) async -> [CLLocationCoordinate2D] {
        // Build a grid around the route corridor
        let bounds = calculateBounds(start: start, goal: goal, padding: 2.0) // 2 degree padding
        let grid = buildGrid(bounds: bounds, altitude: altitude, mode: mode, airspaces: airspaces)

        let startNode = gridNode(for: start, in: bounds)
        let goalNode = gridNode(for: goal, in: bounds)

        // A* algorithm
        var openSet: [GridNode] = [startNode]
        var cameFrom: [GridNode: GridNode] = [:]
        var gScore: [GridNode: Double] = [startNode: 0]
        var fScore: [GridNode: Double] = [startNode: heuristic(startNode, goalNode)]

        var openSetQueue = PriorityQueue<GridNode> { $0.fScore < $1.fScore }
        openSetQueue.enqueue(startNode)

        var iterations = 0
        let maxIterations = 10000

        while !openSetQueue.isEmpty && iterations < maxIterations {
            iterations += 1
            guard let current = openSetQueue.dequeue() else { break }

            if current == goalNode {
                return reconstructPath(cameFrom: cameFrom, current: current, bounds: bounds)
            }

            for neighbor in neighbors(of: current, in: grid, bounds: bounds) {
                let tentativeGScore = (gScore[current] ?? .infinity) + distance(current, neighbor, bounds: bounds)

                if tentativeGScore < (gScore[neighbor] ?? .infinity) {
                    cameFrom[neighbor] = current
                    gScore[neighbor] = tentativeGScore
                    fScore[neighbor] = tentativeGScore + heuristic(neighbor, goalNode)

                    if !openSetQueue.contains(neighbor) {
                        openSetQueue.enqueue(neighbor)
                    }
                }
            }
        }

        // Fallback to direct if no path found
        return [start, goal]
    }

    // MARK: - Grid System

    private struct GridBounds {
        let minLat, maxLat: Double
        let minLon, maxLon: Double
        let rows, cols: Int
    }

    private struct GridNode: Hashable, Equatable {
        let row, col: Int
        var fScore: Double = 0

        static func == (lhs: GridNode, rhs: GridNode) -> Bool {
            lhs.row == rhs.row && lhs.col == rhs.col
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(row)
            hasher.combine(col)
        }
    }

    private func calculateBounds(start: CLLocationCoordinate2D, goal: CLLocationCoordinate2D, padding: Double) -> GridBounds {
        let minLat = min(start.latitude, goal.latitude) - padding
        let maxLat = max(start.latitude, goal.latitude) + padding
        let minLon = min(start.longitude, goal.longitude) - padding
        let maxLon = max(start.longitude, goal.longitude) + padding

        let rows = Int((maxLat - minLat) / gridResolution) + 1
        let cols = Int((maxLon - minLon) / gridResolution) + 1

        return GridBounds(minLat: minLat, maxLat: maxLat, minLon: minLon, maxLon: maxLon, rows: rows, cols: cols)
    }

    private func buildGrid(bounds: GridBounds, altitude: Int, mode: RoutingMode, airspaces: [Airspace]) -> [[Bool]] {
        var grid = Array(repeating: Array(repeating: true, count: bounds.cols), count: bounds.rows)

        for row in 0..<bounds.rows {
            for col in 0..<bounds.cols {
                let lat = bounds.minLat + Double(row) * gridResolution
                let lon = bounds.minLon + Double(col) * gridResolution
                let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)

                // Check if this grid cell is in forbidden airspace
                let forbidden = airspaces.contains { airspace in
                    guard airspace.isActive else { return false }
                    guard altitude >= airspace.floor && altitude <= airspace.ceiling else { return false }

                    switch mode {
                    case .direct:
                        return false
                    case .avoidControlled:
                        // Avoid Class B, C, D, E surface
                        if case .classAirspace(let cls) = airspace.type {
                            return cls.requiresATC
                        }
                        if case .classESurface = airspace.type {
                            return true
                        }
                        return false
                    case .avoidAllSUA:
                        // Avoid all SUA that requires permission + controlled
                        if case .classAirspace(let cls) = airspace.type {
                            return cls.requiresATC
                        }
                        if case .sua(let sua) = airspace.type {
                            return sua.requiresPermission
                        }
                        if case .classESurface = airspace.type {
                            return true
                        }
                        return false
                    }
                }

                grid[row][col] = !forbidden
            }
        }

        return grid
    }

    private func gridNode(for coordinate: CLLocationCoordinate2D, in bounds: GridBounds) -> GridNode {
        let row = Int((coordinate.latitude - bounds.minLat) / gridResolution)
        let col = Int((coordinate.longitude - bounds.minLon) / gridResolution)
        return GridNode(row: max(0, min(bounds.rows - 1, row)), col: max(0, min(bounds.cols - 1, col)))
    }

    private func coordinate(for node: GridNode, in bounds: GridBounds) -> CLLocationCoordinate2D {
        let lat = bounds.minLat + Double(node.row) * gridResolution
        let lon = bounds.minLon + Double(node.col) * gridResolution
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }

    private func neighbors(of node: GridNode, in grid: [[Bool]], bounds: GridBounds) -> [GridNode] {
        var result: [GridNode] = []
        let directions = [
            (-1, 0), (1, 0), (0, -1), (0, 1),  // Cardinal
            (-1, -1), (-1, 1), (1, -1), (1, 1)  // Diagonal
        ]

        for (dr, dc) in directions {
            let nr = node.row + dr
            let nc = node.col + dc

            guard nr >= 0 && nr < bounds.rows && nc >= 0 && nc < bounds.cols else { continue }
            guard grid[nr][nc] else { continue } // Blocked

            result.append(GridNode(row: nr, col: nc))
        }
        return result
    }

    private func distance(_ a: GridNode, _ b: GridNode, bounds: GridBounds) -> Double {
        let coordA = coordinate(for: a, in: bounds)
        let coordB = coordinate(for: b, in: bounds)
        return Haversine.nauticalMiles(coordA, coordB)
    }

    private func heuristic(_ a: GridNode, _ b: GridNode) -> Double {
        // Euclidean distance in grid space * approximate NM per grid
        let dr = Double(a.row - b.row)
        let dc = Double(a.col - b.col)
        return sqrt(dr * dr + dc * dc) * gridResolution * 60.0 // Rough NM
    }

    private func reconstructPath(cameFrom: [GridNode: GridNode], current: GridNode, bounds: GridBounds) -> [CLLocationCoordinate2D] {
        var path: [GridNode] = [current]
        var node = current

        while let parent = cameFrom[node] {
            path.append(parent)
            node = parent
        }

        return path.reversed().map { coordinate(for: $0, in: bounds) }
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
    let id = UUID()
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
    let id = UUID()
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
    let id = UUID()
    let airspace: Airspace
    let type: AirspaceWarningType
}

struct AirspaceWarning: Identifiable {
    let id = UUID()
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

// Simple priority queue for A*
struct PriorityQueue<T> {
    private var elements: [T] = []
    private let comparator: (T, T) -> Bool

    init(comparator: @escaping (T, T) -> Bool) {
        self.comparator = comparator
    }

    mutating func enqueue(_ element: T) {
        elements.append(element)
        elements.sort(by: comparator)
    }

    mutating func dequeue() -> T? {
        guard !elements.isEmpty else { return nil }
        return elements.removeFirst()
    }

    var isEmpty: Bool { elements.isEmpty }

    func contains(_ element: T) -> Bool where T: Equatable {
        elements.contains(element)
    }
}
