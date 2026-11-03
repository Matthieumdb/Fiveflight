import SwiftUI
import CoreLocation

// MARK: - Altitude advisor (ForeFlight "Profile / altitude" picker)

/// Time and fuel at each VFR cruising altitude allowed for the route's course (14 CFR 91.159),
/// with the FD winds at the planned departure time. Tap a row to fly it.
struct AltitudeAdvisorSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var weather: WeatherService

    struct Option: Identifiable {
        let altitude: Int
        let minutes: Double
        let fuel: Double
        let headwind: Int
        var id: Int { altitude }
    }

    /// Magnetic course from departure to destination.
    private var magneticCourse: Double? {
        guard let a = model.waypoints.first, let b = model.waypoints.last, model.waypoints.count >= 2 else { return nil }
        let tc = Double(Haversine.trueCourse(a.coordinate, b.coordinate))
        let mc = (tc - Navlog.magneticVariation(at: Haversine.midpoint(a.coordinate, b.coordinate)))
            .truncatingRemainder(dividingBy: 360)
        return mc < 0 ? mc + 360 : mc
    }

    /// 2,500 ft (below the hemispheric rule) plus the odd/even thousands + 500 for the course.
    static func candidates(magneticCourse: Double) -> [Int] {
        let east = magneticCourse < 180
        return [2500] + (east ? [3500, 5500, 7500, 9500] : [4500, 6500, 8500, 10500])
    }

    /// Highest obstacle within 1 NM of the route (FAA DOF, Florida).
    private var highestObstacle: Int? {
        TerrainProfile.obstacles(along: model.routePath).map(\.0.amslFt).max()
    }

    private var options: [Option] {
        guard let mc = magneticCourse else { return [] }
        let segments = model.navlogSegments
        let cached = weather.windsByPeriod.values.flatMap { $0 }
        let winds = cached.isEmpty ? weather.windsAloft : cached
        let vertical = model.selectedAircraft.map(VerticalPerformance.init)
        return Self.candidates(magneticCourse: mc).compactMap { alt in
            let legs = Navlog.build(segments: segments, tas: model.cruiseGS, altitude: alt, fuelBurn: model.fuelBurn,
                                    winds: winds, departure: model.departureTime, vertical: vertical,
                                    departureElevation: model.waypoints.first?.elevationFt ?? 0,
                                    arrivalElevation: model.waypoints.last?.elevationFt ?? 0)
            guard !legs.isEmpty else { return nil }
            let total = legs.reduce(0) { $0 + $1.distanceNM }
            let head = total > 0 ? legs.reduce(0.0) { $0 + Double($1.headwind ?? 0) * $1.distanceNM } / total : 0
            return Option(altitude: alt, minutes: legs.reduce(0) { $0 + $1.minutes },
                          fuel: legs.reduce(0) { $0 + $1.fuelGallons }, headwind: Int(head.rounded()))
        }
    }

    var body: some View {
        let opts = options
        let best = opts.min { $0.minutes < $1.minutes }?.altitude
        let obstacle = highestObstacle
        Section {
            if opts.isEmpty {
                Text("Ajoutez un départ et une destination.").foregroundStyle(.secondary)
            }
            ForEach(opts) { o in
                Button { model.cruiseAlt = o.altitude } label: {
                    HStack {
                        Text("\(o.altitude) ft").font(TypographyToken.monoMedium).frame(width: 82, alignment: .leading)
                        Text(ffDuration(o.minutes)).monospacedDigit().frame(width: 62, alignment: .trailing)
                        Text(String(format: "%.1f gal", o.fuel)).monospacedDigit().frame(width: 70, alignment: .trailing)
                        Text(o.headwind == 0 ? "0" : (o.headwind > 0 ? "−\(o.headwind) kt" : "+\(-o.headwind) kt"))
                            .monospacedDigit()
                            .foregroundStyle(o.headwind > 0 ? ColorToken.warning : ColorToken.success)
                            .frame(maxWidth: .infinity, alignment: .trailing)
                        if let obstacle, o.altitude < obstacle + 500 {
                            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ColorToken.danger)
                        } else if o.altitude == model.cruiseAlt {
                            Image(systemName: "checkmark").foregroundStyle(FF.accent)
                        } else if o.altitude == best {
                            Image(systemName: "star.fill").foregroundStyle(ColorToken.warning)
                        } else {
                            Image(systemName: "checkmark").hidden()
                        }
                    }
                    .font(.subheadline)
                }
                .tint(.primary)
            }
        } header: { FFHeader("Choix de l'altitude") } footer: {
            if let mc = magneticCourse {
                Text("Route magnétique \(Int(mc.rounded()))° : altitudes \(mc < 180 ? "impaires" : "paires") + 500 ft au-dessus de 3 000 ft sol (91.159). "
                     + "Vent moyen −face / +arrière. ★ la plus rapide."
                     + (obstacle.map { " Obstacle le plus haut à 1 NM de la route : \($0) ft." } ?? ""))
            }
        }
    }
}

// MARK: - ATC frequencies along the route

/// Approach, departure and center frequencies of the airports near the route, in route order:
/// who to call for flight following (Miami Center, Palm Beach, Orlando approach…).
struct RouteFrequenciesSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore

    struct Row: Identifiable, Hashable {
        let name: String
        let mhz: String
        let alongNM: Double
        var id: String { name + mhz }
    }

    static let atcTypes: Set<String> = ["APP", "DEP", "APP/DEP", "CNTR", "CTR", "ARTC", "A/D", "TRSA", "CLASS B", "CLASS C"]

    /// Keeps approach/departure/center entries; "KMIA APP" when the description is only the type.
    static func isATC(_ f: Frequency) -> Bool {
        let t = f.type.uppercased(), d = f.description.uppercased()
        if atcTypes.contains(t) { return true }
        return d.contains("APP") || d.contains("DEP") || d.contains("CNTR") || d.contains("CENTER")
    }

    static func rows(path: [CLLocationCoordinate2D], store: AirportStore, within maxNM: Double = 25) -> [Row] {
        let samples = TerrainProfile.points(along: path, count: 120)
        guard !samples.isEmpty else { return [] }
        let lats = samples.map(\.0.latitude), lons = samples.map(\.0.longitude)
        let pad = maxNM / 60 + 0.1
        var best: [String: Row] = [:]
        for a in store.airports {
            let c = a.coordinate
            guard c.latitude >= lats.min()! - pad, c.latitude <= lats.max()! + pad,
                  c.longitude >= lons.min()! - pad * 1.2, c.longitude <= lons.max()! + pad * 1.2 else { continue }
            let freqs = store.frequencies(for: a).filter(isATC)
            guard !freqs.isEmpty else { continue }
            guard let nearest = samples.min(by: { Haversine.nauticalMiles($0.0, c) < Haversine.nauticalMiles($1.0, c) }),
                  Haversine.nauticalMiles(nearest.0, c) <= maxNM else { continue }
            for f in freqs {
                let desc = f.description.trimmingCharacters(in: .whitespaces)
                let generic = desc.isEmpty || desc.uppercased() == f.type.uppercased()
                let name = generic ? "\(a.id) \(f.type.uppercased())" : desc.capitalized
                let row = Row(name: name, mhz: f.mhz, alongNM: nearest.1)
                let key = name + f.mhz
                if let old = best[key], old.alongNM <= row.alongNM { continue }
                best[key] = row
            }
        }
        return best.values.sorted { $0.alongNM == $1.alongNM ? $0.name < $1.name : $0.alongNM < $1.alongNM }
    }

    @State private var rows: [Row] = []

    var body: some View {
        Section {
            if rows.isEmpty {
                Text("Aucune fréquence d'approche ou de centre à moins de 25 NM de la route.").foregroundStyle(.secondary)
            }
            ForEach(rows) { r in
                HStack {
                    Text(String(format: "%.0f NM", r.alongNM)).font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary).frame(width: 52, alignment: .leading)
                    Text(r.name).lineLimit(2)
                    Spacer()
                    Text(r.mhz).font(TypographyToken.monoMedium).textSelection(.enabled)
                }
            }
        } header: { FFHeader("Fréquences ATC le long de la route") } footer: {
            Text("Approche, départ et centre des aéroports à moins de 25 NM, dans l'ordre de la route : à qui demander le flight following. Données OurAirports, à vérifier sur la carte.")
        }
        .task(id: model.routePath.count + model.waypoints.count) {
            rows = Self.rows(path: model.routePath, store: store)
        }
    }
}
