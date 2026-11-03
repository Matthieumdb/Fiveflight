import SwiftUI
import Charts
import CoreLocation

/// FAA Digital Obstacle File, Florida, 200 ft AGL and up (bundled, rebuilt by scripts/build_obstacles.py).
struct Obstacle: Hashable {
    let coordinate: CLLocationCoordinate2D
    let amslFt: Int
    let aglFt: Int

    static func == (a: Obstacle, b: Obstacle) -> Bool {
        a.coordinate.latitude == b.coordinate.latitude && a.coordinate.longitude == b.coordinate.longitude && a.amslFt == b.amslFt
    }
    func hash(into h: inout Hasher) { h.combine(coordinate.latitude); h.combine(coordinate.longitude) }

    static let all: [Obstacle] = {
        guard let url = Bundle.main.url(forResource: "obstacles_fl", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let rows = try? JSONDecoder().decode([[Double]].self, from: data) else { return [] }
        return rows.filter { $0.count == 4 }.map {
            Obstacle(coordinate: .init(latitude: $0[0], longitude: $0[1]), amslFt: Int($0[2]), aglFt: Int($0[3]))
        }
    }()
}

/// Ground elevation along a route (Open-Meteo elevation API, free, no key) and what sits under it.
enum TerrainProfile {
    struct Sample: Identifiable {
        let id: Int
        let distanceNM: Double
        let groundFt: Double
    }
    struct Band: Identifiable {
        let id = UUID()
        let name: String
        let startNM, endNM: Double
        let floor, ceiling: Int
        let color: Color
    }

    /// Up to 100 points evenly spaced along `path`.
    static func points(along path: [CLLocationCoordinate2D], count: Int = 100) -> [(CLLocationCoordinate2D, Double)] {
        guard path.count >= 2 else { return [] }
        var cumulative = [0.0]
        for i in 1..<path.count { cumulative.append(cumulative[i - 1] + Haversine.nauticalMiles(path[i - 1], path[i])) }
        let total = cumulative.last!
        guard total > 0 else { return [] }
        return (0..<count).map { k in
            let d = total * Double(k) / Double(count - 1)
            let i = max(1, cumulative.firstIndex { $0 >= d } ?? path.count - 1)
            let segment = cumulative[i] - cumulative[i - 1]
            let t = segment > 0 ? (d - cumulative[i - 1]) / segment : 0
            let a = path[i - 1], b = path[i]
            return (CLLocationCoordinate2D(latitude: a.latitude + (b.latitude - a.latitude) * t,
                                           longitude: a.longitude + (b.longitude - a.longitude) * t), d)
        }
    }

    static func samples(along path: [CLLocationCoordinate2D]) async -> [Sample] {
        let pts = points(along: path)
        guard !pts.isEmpty else { return [] }
        let lats = pts.map { String(format: "%.4f", $0.0.latitude) }.joined(separator: ",")
        let lons = pts.map { String(format: "%.4f", $0.0.longitude) }.joined(separator: ",")
        struct Response: Decodable { let elevation: [Double] }
        guard let url = URL(string: "https://api.open-meteo.com/v1/elevation?latitude=\(lats)&longitude=\(lons)"),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let r = try? JSONDecoder().decode(Response.self, from: data), r.elevation.count == pts.count else { return [] }
        return pts.indices.map { Sample(id: $0, distanceNM: pts[$0].1, groundFt: max(0, r.elevation[$0]) * 3.28084) }
    }

    /// Obstacles within 1 NM of the route, with their distance along it.
    static func obstacles(along path: [CLLocationCoordinate2D]) -> [(Obstacle, Double)] {
        let pts = points(along: path, count: 200)
        guard !pts.isEmpty else { return [] }
        let lats = pts.map(\.0.latitude), lons = pts.map(\.0.longitude)
        let pad = 0.02
        let box = (lats.min()! - pad, lats.max()! + pad, lons.min()! - pad, lons.max()! + pad)
        return Obstacle.all.compactMap { o in
            let c = o.coordinate
            guard c.latitude >= box.0, c.latitude <= box.1, c.longitude >= box.2, c.longitude <= box.3 else { return nil }
            let nearest = pts.min { Haversine.nauticalMiles($0.0, c) < Haversine.nauticalMiles($1.0, c) }!
            return Haversine.nauticalMiles(nearest.0, c) <= 1 ? (o, nearest.1) : nil
        }
    }

    /// Airspace crossed by the route, as distance bands with their vertical limits.
    static func bands(along path: [CLLocationCoordinate2D], airspaces: [Airspace]) -> [Band] {
        let pts = points(along: path, count: 200)
        var out: [Band] = []
        for a in airspaces where a.isActive && a.type.needsAlert {
            let rings = a.polygons.map { $0.map(\.clCoordinate) }
            var start: Double?
            for (p, d) in pts {
                let inside = rings.contains { Airspace.pointInPolygonStatic(p, polygon: $0) }
                if inside, start == nil { start = d }
                if !inside, let s = start {
                    out.append(Band(name: a.name, startNM: s, endNM: d, floor: a.floor, ceiling: min(a.ceiling, 18000), color: color(a)))
                    start = nil
                }
            }
            if let s = start, let last = pts.last {
                out.append(Band(name: a.name, startNM: s, endNM: last.1, floor: a.floor, ceiling: min(a.ceiling, 18000), color: color(a)))
            }
        }
        return out
    }

    private static func color(_ a: Airspace) -> Color {
        switch a.type {
        case .classAirspace(let c): return c == .B ? ColorToken.classB : c == .C ? ColorToken.classC : ColorToken.classD
        case .sua(let s): return s == .tf ? ColorToken.tfr : s == .moa ? ColorToken.moa : ColorToken.restricted
        default: return ColorToken.classESurface
        }
    }
}

// MARK: - View

/// Vertical profile: terrain, obstacles, airspace and the cruise altitude along the planned route.
struct VerticalProfileView: View {
    let path: [CLLocationCoordinate2D]
    let cruiseAlt: Int
    let airspaces: [Airspace]

    @State private var samples: [TerrainProfile.Sample] = []
    @State private var obstacles: [(Obstacle, Double)] = []
    @State private var bands: [TerrainProfile.Band] = []

    private var highest: Double {
        max(samples.map(\.groundFt).max() ?? 0, Double(obstacles.map(\.0.amslFt).max() ?? 0))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space2) {
            if samples.isEmpty {
                HStack { ProgressView(); Text("Relief en cours de chargement…").foregroundStyle(ColorToken.textTertiary) }
            } else {
                let clearance = Double(cruiseAlt) - highest
                Label(String(format: "Point le plus haut : %.0f ft · marge %.0f ft", highest, clearance),
                      systemImage: clearance < 1000 ? "exclamationmark.triangle.fill" : "mountain.2")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(clearance < 1000 ? ColorToken.danger : ColorToken.textSecondary)
                Chart {
                    ForEach(bands) { b in
                        RectangleMark(xStart: .value("Début", b.startNM), xEnd: .value("Fin", b.endNM),
                                      yStart: .value("Plancher", b.floor), yEnd: .value("Plafond", b.ceiling))
                            .foregroundStyle(b.color.opacity(0.18))
                    }
                    ForEach(samples) { s in
                        AreaMark(x: .value("NM", s.distanceNM), y: .value("Sol", s.groundFt))
                            .foregroundStyle(Color.brown.opacity(0.6))
                    }
                    ForEach(obstacles.indices, id: \.self) { i in
                        RuleMark(x: .value("NM", obstacles[i].1),
                                 yStart: .value("Base", obstacles[i].0.amslFt - obstacles[i].0.aglFt),
                                 yEnd: .value("Sommet", obstacles[i].0.amslFt))
                            .foregroundStyle(ColorToken.danger)
                    }
                    RuleMark(y: .value("Croisière", cruiseAlt))
                        .foregroundStyle(ColorToken.brandPrimary)
                        .lineStyle(StrokeStyle(lineWidth: 2, dash: [6, 4]))
                }
                .chartYScale(domain: 0...max(Double(cruiseAlt) * 1.4, highest + 1000))
                .chartXAxisLabel("NM")
                .chartYAxisLabel("ft MSL")
                .frame(height: 200)
                if !bands.isEmpty {
                    Text(Set(bands.map(\.name)).sorted().joined(separator: " · "))
                        .font(TypographyToken.labelXSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                }
            }
        }
        .task(id: path.map(\.latitude) + [Double(cruiseAlt)]) {
            obstacles = TerrainProfile.obstacles(along: path)
            bands = TerrainProfile.bands(along: path, airspaces: airspaces)
            samples = await TerrainProfile.samples(along: path)
        }
    }
}
