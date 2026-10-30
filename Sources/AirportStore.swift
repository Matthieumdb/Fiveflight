import Foundation
import CoreLocation

/// Loads the bundled OurAirports datasets off the main thread and publishes
/// a real-time loading progress (0…1) plus a `ready` flag.
@MainActor
final class AirportStore: ObservableObject {
    @Published private(set) var progress: Double = 0
    @Published private(set) var ready = false

    private(set) var airports: [Airport] = []
    private var byId: [String: Airport] = [:]
    private var runwaysByIdent: [String: [Runway]] = [:]
    private var freqsByIdent: [String: [Frequency]] = [:]

    func runways(for airport: Airport) -> [Runway] { runwaysByIdent[airport.id] ?? [] }
    func frequencies(for airport: Airport) -> [Frequency] { freqsByIdent[airport.id] ?? [] }

    /// Look up an airport by its identifier (ICAO), case-insensitive.
    func airport(_ ident: String) -> Airport? { byId[ident.uppercased()] }

    func load() async {
        guard !ready else { return }
        let (stream, cont) = AsyncStream<Double>.makeStream()
        let task = Task.detached(priority: .userInitiated) { () -> Parsed in
            defer { cont.finish() }
            return Parser.parseAll { cont.yield($0) }
        }
        // Each step maps to real parsed rows; we reveal them at a watchable pace
        // (the parse itself runs ahead in the detached task and buffers its ticks).
        for await p in stream {
            progress = p
            try? await Task.sleep(for: .milliseconds(45))
        }
        let parsed = await task.value
        airports = parsed.airports
        byId = Dictionary(parsed.airports.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        runwaysByIdent = parsed.runways
        freqsByIdent = parsed.freqs
        progress = 1
        ready = true
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
    private enum Col { static let ident = 1, type = 2, name = 3, lat = 4, lon = 5,
                              elev = 6, country = 8, municipality = 10, icao = 12, iata = 13 }

    private static func lines(_ name: String) -> [Substring] {
        guard let url = Bundle.main.url(forResource: name, withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [] }
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
                surface: f[5].isEmpty ? nil : f[5], lighted: f[6] == "1", closed: f[7] == "1"))
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
