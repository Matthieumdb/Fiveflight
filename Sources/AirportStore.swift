import Foundation
import CoreLocation

/// Loads the US-only OurAirports datasets off the main thread and publishes
/// a real-time loading progress (0…1) plus a `ready` flag.
/// A weekly background refresh from ourairports.com keeps a filtered copy in Application Support.
@MainActor
final class AirportStore: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var ready = false

    private(set) var airports: [Airport] = []
    private var byId: [String: Airport] = [:]
    private var byIata: [String: Airport] = [:]
    private var runwaysByIdent: [String: [Runway]] = [:]
    private var freqsByIdent: [String: [Frequency]] = [:]

    func runways(for airport: Airport) -> [Runway] { runwaysByIdent[airport.id] ?? [] }
    func frequencies(for airport: Airport) -> [Frequency] { freqsByIdent[airport.id] ?? [] }

    /// Look up an airport by its identifier (ICAO), case-insensitive.
    func airport(_ ident: String) -> Airport? { byId[ident.uppercased()] }

    /// Look up an airport by IATA code, case-insensitive.
    func airport(iata: String) -> Airport? { byIata[iata.uppercased()] }

    func load() async {
        guard !ready else { return }
        await loadCSVs()
        // Weekly refresh from ourairports.com, entirely off the main thread.
        Task.detached(priority: .background) { [weak self] in
            guard let fresh = await AirportDataRefresher.refreshIfNeeded() else { return }
            await self?.apply(parsed: fresh)
        }
    }

    /// Parses the US-only CSVs (downloaded copy if any, else the bundle) off the main thread.
    private func loadCSVs() async {
        let (stream, cont) = AsyncStream<Double>.makeStream()
        let task = Task.detached(priority: .userInitiated) { () -> Parsed in
            defer { cont.finish() }
            return Parser.parseAll { cont.yield($0) }
        }
        for await p in stream { progress = p }
        let parsed = await task.value
        apply(parsed: parsed)
        progress = 1
        ready = true
    }

    private func apply(parsed: Parsed) {
        airports = parsed.airports
        byId = Dictionary(parsed.airports.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Build IATA index, handling duplicates by preferring larger airports
        byIata = [:]
        let typeOrder = ["large_airport": 0, "medium_airport": 1, "small_airport": 2, "heliport": 3]
        let sortedByType = parsed.airports.sorted { (typeOrder[$0.type] ?? 99) < (typeOrder[$1.type] ?? 99) }
        for airport in sortedByType {
            if let iata = airport.iata?.uppercased(), !iata.isEmpty, byIata[iata] == nil {
                byIata[iata] = airport
            }
        }

        runwaysByIdent = parsed.runways
        freqsByIdent = parsed.freqs
    }

    /// The `limit` closest airports to `c`, nearest first.
    func nearest(to c: CLLocationCoordinate2D, limit: Int = 10,
                 matching types: Set<String>? = nil) -> [Airport] {
        var pool = airports
        if let types { pool = pool.filter { types.contains($0.type) } }
        return pool
            .map { ($0, $0.distanceNM(to: c)) }
            .sorted { $0.1 < $1.1 }
            .prefix(limit)
            .map { $0.0 }
    }
}

struct Parsed: Sendable {
    var airports: [Airport]
    var runways: [String: [Runway]]
    var freqs: [String: [Frequency]]
}

/// Pure parsing, safe to run off-actor. Reports fractional progress across all files.
enum Parser {
    enum Col { static let ident = 1, type = 2, name = 3, lat = 4, lon = 5,
                          elev = 6, country = 8, municipality = 10, icao = 12, iata = 13 }

    /// Prefers the copy downloaded by `AirportDataRefresher`, falls back to the bundle.
    private static func lines(_ name: String) -> [Substring] {
        let downloaded = AirportDataRefresher.directory.appendingPathComponent("\(name).csv")
        let url = FileManager.default.fileExists(atPath: downloaded.path)
            ? downloaded : Bundle.main.url(forResource: name, withExtension: "csv")
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
        return Array(text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst())
    }

    static func parseAll(progress: @Sendable (Double) -> Void) -> Parsed {
        let aptLines = lines("airports")
        let rwyLines = lines("runways")
        let frqLines = lines("airport-frequencies")
        let total = max(1, aptLines.count + rwyLines.count + frqLines.count)
        var done = 0
        func tick() { done += 1; if done % 3000 == 0 { progress(Double(done) / Double(total)) } }

        var airports: [Airport] = []; airports.reserveCapacity(aptLines.count)
        for line in aptLines {
            tick()
            let f = CSV.parseLine(line)
            guard f.count > Col.iata,
                  f[Col.country] == "US",          // US-only (user flies only in the US)
                  f[Col.type] != "closed",
                  let lat = Double(f[Col.lat]), let lon = Double(f[Col.lon]),
                  lat != 0 || lon != 0 else { continue }
            func opt(_ s: String) -> String? { s.isEmpty ? nil : s }
            airports.append(Airport(
                id: f[Col.ident], name: f[Col.name], type: f[Col.type],
                icao: opt(f[Col.icao]), iata: opt(f[Col.iata]),
                municipality: opt(f[Col.municipality]), elevationFt: Int(f[Col.elev]),
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
        }

        var runways: [String: [Runway]] = [:]
        for line in rwyLines {
            tick()
            let f = CSV.parseLine(line)
            guard f.count > 14 else { continue }
            runways[f[2], default: []].append(Runway(
                leIdent: f[8], heIdent: f[14], lengthFt: Int(f[3]), widthFt: Int(f[4]),
                surface: f[5].isEmpty ? nil : f[5], lighted: f[6] == "1", closed: f[7] == "1",
                leHeadingT: f.count > 12 ? Double(f[12]) : nil, heHeadingT: f.count > 18 ? Double(f[18]) : nil,
                leLat: Double(f[9]), leLon: Double(f[10]),
                heLat: f.count > 16 ? Double(f[15]) : nil, heLon: f.count > 16 ? Double(f[16]) : nil))
        }

        var freqs: [String: [Frequency]] = [:]
        for line in frqLines {
            tick()
            let f = CSV.parseLine(line)
            guard f.count > 5 else { continue }
            freqs[f[2], default: []].append(Frequency(type: f[3], description: f[4], mhz: f[5]))
        }

        progress(1)
        return Parsed(airports: airports, runways: runways, freqs: freqs)
    }
}
/// Downloads fresh OurAirports CSVs at most once a week, keeps only US (non-closed) airports
/// and their runways/frequencies, and stores them in Application Support. Never runs on the main actor.
enum AirportDataRefresher {
    static let directory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Fiveflight/airports", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    private static let refreshKey = "lastAirportsRefresh"
    private static let base = "https://ourairports.com/data/"

    static func refreshIfNeeded() async -> Parsed? {
        let last = UserDefaults.standard.object(forKey: refreshKey) as? Date ?? .distantPast
        guard Date().timeIntervalSince(last) > 7 * 24 * 3600 else { return nil }

        var texts: [String: String] = [:]
        for name in ["airports", "runways", "airport-frequencies"] {
            guard let url = URL(string: base + name + ".csv"),
                  let (data, response) = try? await URLSession.shared.data(from: url),
                  (response as? HTTPURLResponse)?.statusCode == 200,
                  let text = String(data: data, encoding: .utf8) else { return nil }
            texts[name] = text
        }
        guard let filtered = filterUS(texts) else { return nil }
        for (name, text) in filtered {
            try? text.write(to: directory.appendingPathComponent("\(name).csv"), atomically: true, encoding: .utf8)
        }
        UserDefaults.standard.set(Date(), forKey: refreshKey)
        return Parser.parseAll { _ in }
    }

    /// Keeps header + US non-closed airports, and runways/frequencies of those airports.
    static func filterUS(_ texts: [String: String]) -> [String: String]? {
        guard let apt = texts["airports"], let rwy = texts["runways"], let frq = texts["airport-frequencies"] else { return nil }
        var idents = Set<String>()
        var aptOut: [Substring] = []
        for (i, line) in apt.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
            if i == 0 { aptOut.append(line); continue }
            let f = CSV.parseLine(line)
            guard f.count > Parser.Col.country, f[Parser.Col.country] == "US", f[Parser.Col.type] != "closed" else { continue }
            idents.insert(f[Parser.Col.ident])
            aptOut.append(line)
        }
        guard idents.count > 1000 else { return nil }   // sanity check: never replace good data with a broken download
        func keep(_ text: String) -> String {
            var out: [Substring] = []
            for (i, line) in text.split(separator: "\n", omittingEmptySubsequences: true).enumerated() {
                if i == 0 { out.append(line); continue }
                let f = CSV.parseLine(line)
                if f.count > 2, idents.contains(f[2]) { out.append(line) }
            }
            return out.joined(separator: "\n") + "\n"
        }
        return ["airports": aptOut.joined(separator: "\n") + "\n", "runways": keep(rwy), "airport-frequencies": keep(frq)]
    }
}
