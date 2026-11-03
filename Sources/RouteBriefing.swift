import SwiftUI
import CoreLocation

/// What the route briefing works out from the plan: weather stations along the route,
/// TFRs / airspace crossed and advisories touching the corridor.
struct BriefingStation: Identifiable {
    let airport: Airport
    let alongNM: Double
    let offNM: Double
    let rank: Int
    var id: String { airport.id }
}

enum RouteBriefing {
    /// The path densified to a point every ~2 NM (for corridor tests).
    static func samples(_ path: [CLLocationCoordinate2D], stepNM: Double = 2) -> [CLLocationCoordinate2D] {
        guard path.count >= 2 else { return path }
        var out: [CLLocationCoordinate2D] = [path[0]]
        for i in 1..<path.count {
            let a = path[i - 1], b = path[i]
            let n = max(1, Int(Haversine.nauticalMiles(a, b) / stepNM))
            for k in 1...n { out.append(Haversine.interpolate(a, b, fraction: Double(k) / Double(n))) }
        }
        return out
    }

    /// METAR-capable airports within `corridorNM` of the route, in route order (departure and destination included).
    static func stations(along path: [CLLocationCoordinate2D], airports: [Airport], plan: [Airport],
                         corridorNM: Double = 10, limit: Int = 12) -> [BriefingStation] {
        let pts = samples(path)
        guard pts.count >= 2 else { return [] }
        let margin = corridorNM / 60 + 0.05
        let minLat = pts.map(\.latitude).min()! - margin, maxLat = pts.map(\.latitude).max()! + margin
        let minLon = pts.map(\.longitude).min()! - margin * 1.2, maxLon = pts.map(\.longitude).max()! + margin * 1.2
        var along: [Double] = [0]
        for i in 1..<pts.count { along.append(along[i - 1] + Haversine.nauticalMiles(pts[i - 1], pts[i])) }
        let planIDs = Set(plan.filter(\.isAirport).map(\.id))
        let types: Set<String> = ["large_airport", "medium_airport", "small_airport"]
        var hits: [BriefingStation] = []
        for a in airports {
            let c = a.coordinate
            guard c.latitude >= minLat, c.latitude <= maxLat, c.longitude >= minLon, c.longitude <= maxLon else { continue }
            let inPlan = planIDs.contains(a.id)
            guard inPlan || (types.contains(a.type) && a.id.count == 4 && a.id.hasPrefix("K")) else { continue }
            var best = Double.infinity, idx = 0
            for (i, p) in pts.enumerated() {
                let d = Haversine.nauticalMiles(c, p)
                if d < best { best = d; idx = i }
            }
            guard inPlan || best <= corridorNM else { continue }
            let rank = inPlan ? 0 : a.type == "large_airport" ? 1 : a.type == "medium_airport" ? 2 : 3
            hits.append(BriefingStation(airport: a, alongNM: along[idx], offNM: best, rank: rank))
        }
        let kept = hits.sorted { ($0.rank, $0.offNM) < ($1.rank, $1.offNM) }.prefix(limit)
        return kept.sorted { $0.alongNM < $1.alongNM }
    }

    static func crosses(_ polygon: [Coordinate2D], path: [CLLocationCoordinate2D]) -> Bool {
        guard polygon.count >= 3, path.count >= 2 else { return false }
        for i in 1..<path.count where Airspace.segmentIntersectsPolygon(path[i - 1], path[i], polygon: polygon) { return true }
        return false
    }

    /// Airspace whose polygon the route crosses, optionally filtered on the cruise altitude.
    static func airspacesCrossed(_ airspaces: [Airspace], path: [CLLocationCoordinate2D], altitude: Int?) -> [Airspace] {
        airspaces.filter { a in
            if let altitude, altitude < a.floor - 300 || altitude > a.ceiling { return false }
            return a.polygons.contains { crosses($0, path: path) }
        }
    }

    static func advisories(_ list: [AirSigmet], path: [CLLocationCoordinate2D]) -> [AirSigmet] {
        list.filter { adv in adv.area.map { crosses($0, path: path) } ?? false }
    }

    static func worst(_ cats: [FlightCategory]) -> FlightCategory {
        let order: [FlightCategory] = [.lifr, .ifr, .mvfr, .vfr]
        return order.first { cats.contains($0) } ?? .unknown
    }
}

/// Route-wide synthesis: weather (METAR/TAF along the route, AIRMET/SIGMET), TFRs, airspace and NOTAMs.
struct RouteBriefingScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var weather: WeatherService
    @EnvironmentObject private var airspaceManager: AirspaceDataManager

    @State private var departure = Date.now.addingTimeInterval(30 * 60)
    @State private var stations: [BriefingStation] = []
    @State private var notams: [String: [NOTAMService.NOTAM]] = [:]
    @State private var notamFailed: [String] = []
    @State private var loading = false
    @State private var loadedAt: Date?

    private var path: [CLLocationCoordinate2D] {
        model.routePath.count >= 2 ? model.routePath : model.waypoints.map(\.coordinate)
    }
    private var depAirport: Airport? { model.waypoints.first(where: \.isAirport) }
    private var destAirport: Airport? { model.waypoints.last(where: \.isAirport) }
    private var eta: Date { departure.addingTimeInterval(model.totalTimeMinutes * 60) }

    private var tfrs: [Airspace] { RouteBriefing.airspacesCrossed(airspaceManager.tfrs, path: path, altitude: nil) }
    private var crossed: [Airspace] {
        RouteBriefing.airspacesCrossed(airspaceManager.airspaces.filter { $0.isActive && $0.type.needsAlert },
                                       path: path, altitude: model.cruiseAlt)
    }
    private var advisories: [AirSigmet] { RouteBriefing.advisories(weather.airsigmets, path: path) }
    private var categories: [FlightCategory] { stations.compactMap { weather.metars[$0.airport.id]?.flightCategory } }
    private var importantNOTAMs: Int { notams.values.joined().filter(\.isImportant).count }

    private var sunset: Date? {
        guard let dest = destAirport else { return nil }
        return SolarCalculator.sunTimes(for: dest.coordinate, on: eta)?.sunset
    }

    var body: some View {
        List {
            summarySection
            Section {
                DatePicker("Départ", selection: $departure)
                LabeledContent("Arrivée estimée", value: eta.formatted(date: .omitted, time: .shortened))
                if let sunset {
                    LabeledContent("Coucher du soleil (dest.)", value: sunset.formatted(date: .omitted, time: .shortened))
                    if eta > sunset {
                        Label("Arrivée de nuit", systemImage: "moon.stars.fill").foregroundStyle(ColorToken.warning)
                    }
                }
            } header: { Text("Horaires") }

            ForEach([depAirport, destAirport].compactMap { $0 }.uniqued(), id: \.id) { a in
                Section {
                    airportWeather(a)
                } header: {
                    Text(a.id == depAirport?.id ? "Départ · \(a.id)" : "Destination · \(a.id)")
                }
            }

            Section {
                if stations.isEmpty && !loading { Text("Aucune station sur le trajet").foregroundStyle(ColorToken.textTertiary) }
                ForEach(stations) { s in
                    HStack {
                        Text(s.airport.id).font(TypographyToken.monoMedium).frame(width: 56, alignment: .leading)
                        categoryPill(weather.metars[s.airport.id]?.flightCategory)
                        Text(weather.metars[s.airport.id]?.rawText ?? "Pas de METAR")
                            .font(TypographyToken.monoXXSmall).foregroundStyle(ColorToken.textSecondary).lineLimit(2)
                        Spacer(minLength: 4)
                        Text(String(format: "%.0f NM", s.alongNM)).font(TypographyToken.monoXSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                    }
                }
            } header: { Text("Météo le long de la route (±10 NM)") }

            Section {
                if advisories.isEmpty { Text("Aucun AIRMET/SIGMET sur la route").foregroundStyle(ColorToken.textTertiary) }
                ForEach(advisories) { a in
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(a.displayType) · \(a.hazard)").font(TypographyToken.labelMedium).foregroundStyle(a.hazardColor)
                        Text(a.validTime).font(TypographyToken.monoXSmall).foregroundStyle(ColorToken.textTertiary)
                        if !a.rawText.isEmpty { Text(a.rawText).font(TypographyToken.monoXXSmall).lineLimit(4) }
                    }
                }
            } header: { Text("AIRMET / SIGMET") }

            Section {
                if tfrs.isEmpty { Text("Aucune TFR traversée").foregroundStyle(ColorToken.textTertiary) }
                ForEach(tfrs) { t in airspaceRow(t, color: ColorToken.tfr) }
            } header: { Text("TFR") }

            Section {
                if crossed.isEmpty { Text("Aucun espace contrôlé ou SUA à \(model.cruiseAlt) ft").foregroundStyle(ColorToken.textTertiary) }
                ForEach(crossed) { a in airspaceRow(a, color: ColorToken.warning) }
            } header: { Text("Espaces traversés à \(model.cruiseAlt) ft") }

            Section {
                if notams.isEmpty && notamFailed.isEmpty && !loading {
                    Text("Aucun NOTAM chargé").foregroundStyle(ColorToken.textTertiary)
                }
                ForEach(notamLocations, id: \.self) { loc in
                    DisclosureGroup {
                        ForEach(sortedNOTAMs(loc)) { NOTAMRow(notam: $0) }
                    } label: {
                        HStack {
                            Text(loc).font(TypographyToken.monoMedium)
                            Spacer()
                            let list = notams[loc] ?? []
                            let imp = list.filter(\.isImportant).count
                            if imp > 0 { Label("\(imp)", systemImage: "exclamationmark.triangle.fill").foregroundStyle(ColorToken.warning) }
                            Text("\(list.count)").foregroundStyle(ColorToken.textTertiary)
                        }
                    }
                }
                ForEach(notamFailed, id: \.self) { loc in
                    Link("\(loc) : NOTAM indisponibles, ouvrir FAA NOTAM Search", destination: NOTAMService.searchURL(loc))
                }
            } header: { Text("NOTAM") } footer: {
                Text("Sources : aviationweather.gov, tfr.faa.gov, FAA NOTAM Search, FAA ADDS. Ce résumé ne remplace pas un briefing officiel (1800wxbrief.com).")
            }
        }
        .navigationTitle("Briefing de route")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                ShareLink(item: summaryText) { Image(systemName: "square.and.arrow.up") }
            }
        }
        .overlay { if loading && stations.isEmpty { ProgressView("Préparation du briefing…") } }
        .refreshable { await load() }
        .task { await load() }
    }

    // MARK: Sections

    private var summarySection: some View {
        let worst = RouteBriefing.worst(categories)
        let convective = advisories.contains(where: \.isConvective)
        let verdict: (String, Color, String) = {
            if !tfrs.isEmpty { return ("TFR sur la route", ColorToken.danger, "xmark.octagon.fill") }
            if worst == .ifr || worst == .lifr || convective { return ("VFR déconseillé", ColorToken.danger, "cloud.bolt.fill") }
            if worst == .mvfr || !advisories.isEmpty || importantNOTAMs > 0 { return ("VFR avec prudence", ColorToken.warning, "exclamationmark.triangle.fill") }
            if worst == .vfr { return ("VFR favorable", ColorToken.success, "checkmark.seal.fill") }
            return ("Données incomplètes", ColorToken.textTertiary, "questionmark.circle")
        }()
        return Section {
            Label(verdict.0, systemImage: verdict.2).font(TypographyToken.bodyLarge).foregroundStyle(verdict.1)
            HStack(spacing: SpacingToken.space3) {
                badge("Météo", worst == .unknown ? "—" : worst.rawValue, worst.color)
                badge("AIRMET/SIG", "\(advisories.count)", advisories.isEmpty ? ColorToken.success : ColorToken.warning)
                badge("TFR", "\(tfrs.count)", tfrs.isEmpty ? ColorToken.success : ColorToken.danger)
                badge("NOTAM !", "\(importantNOTAMs)", importantNOTAMs == 0 ? ColorToken.success : ColorToken.warning)
            }
            if let loadedAt {
                Text("Mis à jour \(loadedAt.formatted(date: .omitted, time: .shortened))")
                    .font(TypographyToken.labelXSmall).foregroundStyle(ColorToken.textTertiary)
            }
        } header: {
            Text(model.waypoints.map(\.id).joined(separator: " → "))
        }
    }

    @ViewBuilder
    private func airportWeather(_ a: Airport) -> some View {
        if let m = weather.metars[a.id] {
            HStack { categoryPill(m.flightCategory); Text("METAR").font(TypographyToken.labelSmall) }
            Text(m.rawText).font(TypographyToken.monoXSmall).textSelection(.enabled)
        } else {
            Text("Pas de METAR pour \(a.id)").foregroundStyle(ColorToken.textTertiary)
        }
        if let t = weather.tafs[a.id] {
            Text("TAF").font(TypographyToken.labelSmall)
            Text(t.rawText).font(TypographyToken.monoXSmall).textSelection(.enabled)
        }
    }

    private func airspaceRow(_ a: Airspace, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(a.name).font(TypographyToken.labelMedium).foregroundStyle(color)
            Text("\(a.type.displayName) · \(a.floor == 0 ? "SFC" : "\(a.floor) ft") – \(a.ceiling) ft")
                .font(TypographyToken.monoXSmall).foregroundStyle(ColorToken.textSecondary)
            if let status = a.suaStatus() {
                Text(status.label).font(TypographyToken.labelXSmall).foregroundStyle(ColorToken.textTertiary)
            }
        }
    }

    private func badge(_ title: String, _ value: String, _ color: Color) -> some View {
        VStack(spacing: 2) {
            Text(value).font(TypographyToken.monoMedium).foregroundStyle(color)
            Text(title).font(TypographyToken.labelXSmall).foregroundStyle(ColorToken.textTertiary).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    private func categoryPill(_ c: FlightCategory?) -> some View {
        let cat = c ?? .unknown
        return Text(cat == .unknown ? "—" : cat.rawValue)
            .font(TypographyToken.labelXSmall).foregroundStyle(.white)
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background(cat.color, in: Capsule())
    }

    private var notamLocations: [String] {
        let order = stations.map(\.airport.id)
        return notams.keys.sorted { (order.firstIndex(of: $0) ?? 99, $0) < (order.firstIndex(of: $1) ?? 99, $1) }
    }

    private func sortedNOTAMs(_ loc: String) -> [NOTAMService.NOTAM] {
        let list = notams[loc] ?? []
        return list.filter(\.isImportant) + list.filter { !$0.isImportant }
    }

    // MARK: Loading

    private func load() async {
        guard path.count >= 2 else { return }
        loading = true
        defer { loading = false }
        stations = RouteBriefing.stations(along: path, airports: store.airports, plan: model.waypoints)
        let ids = stations.map(\.airport.id)
        async let metars: Void = weather.fetchMETARs(for: ids)
        async let tafs: Void = weather.fetchTAFs(for: ids)
        async let adv: Void = weather.fetchAIRMETs()
        async let tfr: Void = airspaceManager.refreshTFRs()
        _ = await (metars, tafs, adv, tfr)
        // NOTAMs: departure, destination and up to 6 airports en route.
        var locs = [depAirport?.id, destAirport?.id].compactMap { $0 }
        for id in ids where !locs.contains(id) && locs.count < 8 { locs.append(id) }
        let result = await NOTAMService.fetch(locations: locs)
        notams = result.notams
        notamFailed = result.failed
        loadedAt = .now
    }

    /// Plain-text briefing to share (Messages, mail, notes).
    private var summaryText: String {
        var lines = ["Briefing Fiveflight \(model.waypoints.map(\.id).joined(separator: " → "))",
                     "Départ \(departure.formatted(date: .abbreviated, time: .shortened)) · ETE \(model.formattedTotalTime) · \(model.cruiseAlt) ft"]
        for s in stations {
            lines.append("\(s.airport.id): \(weather.metars[s.airport.id]?.rawText ?? "pas de METAR")")
        }
        if let d = destAirport, let t = weather.tafs[d.id] { lines.append("TAF \(t.rawText)") }
        lines.append("AIRMET/SIGMET : " + (advisories.isEmpty ? "aucun" : advisories.map { "\($0.displayType) \($0.hazard)" }.joined(separator: ", ")))
        lines.append("TFR : " + (tfrs.isEmpty ? "aucune" : tfrs.map(\.name).joined(separator: ", ")))
        for loc in notamLocations {
            for n in sortedNOTAMs(loc) where n.isImportant { lines.append("NOTAM \(n.id) \(n.text)") }
        }
        return lines.joined(separator: "\n")
    }
}

extension Array where Element == Airport {
    /// Keeps the first occurrence of each id.
    func uniqued() -> [Airport] {
        var seen = Set<String>()
        return filter { seen.insert($0.id).inserted }
    }
}
