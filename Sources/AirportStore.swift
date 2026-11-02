import Foundation
import CoreLocation

/// Loads the bundled OurAirports datasets off the main thread and publishes
/// a real-time loading progress (0…1) plus a `ready` flag.
/// Supports caching to Application Support and background refresh from ourairports.com (max 1×/7d).
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

        // Try loading from cache first (if newer than bundle)
        if await loadFromCacheIfFresh() {
            progress = 1
            ready = true
            return
        }

        // Fall back to bundle
        await loadFromBundle()

        // Trigger background refresh if needed (non-blocking)
        Task.detached { await self.maybeRefreshFromRemote() }
    }

    private func loadFromBundle() async {
        let (stream, cont) = AsyncStream<Double>.makeStream()
        let task = Task.detached(priority: .userInitiated) { () -> Parsed in
            defer { cont.finish() }
            return Parser.parseAll { cont.yield($0) }
        }
        for await p in stream {
            progress = p
            try? await Task.sleep(for: .milliseconds(45))
        }
        let parsed = await task.value
        apply(parsed: parsed)
        progress = 1
        ready = true
        await saveToCache(parsed)
    }

    private func loadFromCacheIfFresh() async -> Bool {
        let cacheURL = cacheFileURL()
        guard let data = try? Data(contentsOf: cacheURL),
              let cached = try? JSONDecoder().decode(CachedData.self, from: data) else { return false }

        // Check if cache is newer than bundle
        let bundleModDate = bundleModificationDate()
        if cached.timestamp < bundleModDate { return false }

        // Cache is fresh, use it
        apply(parsed: cached.parsed)
        return true
    }

    private func apply(parsed: Parsed) {
        airports = parsed.airports
        byId = Dictionary(parsed.airports.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

        // Build IATA index, handling duplicates by preferring larger airports
        byIata = [:]
        let sortedByType = parsed.airports.sorted { a1, a2 in
            // Prefer large_airport > medium_airport > small_airport > heliport
            let typeOrder = ["large_airport": 0, "medium_airport": 1, "small_airport": 2, "heliport": 3]
            return (typeOrder[a1.type] ?? 99) < (typeOrder[a2.type] ?? 99)
        }
        for airport in sortedByType {
            if let iata = airport.iata?.uppercased(), !iata.isEmpty {
                if byIata[iata] == nil {
                    byIata[iata] = airport
                }
            }
        }

        runwaysByIdent = parsed.runways
        freqsByIdent = parsed.freqs
    }

    private func saveToCache(_ parsed: Parsed) async {
        let cacheURL = cacheFileURL()
        let cached = CachedData(timestamp: Date(), parsed: parsed)
        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: cacheURL)
        }
    }

    private func cacheFileURL() -> URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let dir = appSupport.appendingPathComponent("Fiveflight", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("airports_cache.json")
    }

    private func bundleModificationDate() -> Date {
        guard let url = Bundle.main.url(forResource: "airports", withExtension: "csv"),
              let attrs = try? FileManager.default.attributesOfItem(atPath: url.path),
              let modDate = attrs[.modificationDate] as? Date else { return .distantPast }
        return modDate
    }

    /// Background refresh from ourairports.com (max once per 7 days).
    private func maybeRefreshFromRemote() async {
        let refreshKey = "lastAirportsRefresh"
        let defaults = UserDefaults.standard
        let lastRefresh = defaults.object(forKey: refreshKey) as? Date ?? .distantPast

        // Only refresh if more than 7 days have passed
        guard Date().timeIntervalSince(lastRefresh) > 7 * 24 * 3600 else { return }

        do {
            let urls = [
                "airports": "https://ourairports.com/data/airports.csv",
                "runways": "https://ourairports.com/data/runways.csv",
                "airport-frequencies": "https://ourairports.com/data/airport-frequencies.csv"
            ]

            var downloaded: [String: String] = [:]
            for (name, urlString) in urls {
                guard let url = URL(string: urlString),
                      let (data, _) = try? await URLSession.shared.data(from: url),
                      let text = String(data: data, encoding: .utf8) else { continue }
                downloaded[name] = text
            }

            // Only proceed if we got all three files
            guard downloaded.count == 3 else { return }

            // Parse downloaded data
            let parsed = try await parseDownloaded(downloaded)

            // Save to cache and update UI
            await saveToCache(parsed)
            await MainActor.run {
                self.apply(parsed: parsed)
            }
            defaults.set(Date(), forKey: refreshKey)
        } catch {
            // Silently fail - app continues working with cached/bundle data
        }
    }

    private func parseDownloaded(_ data: [String: String]) async throws -> Parsed {
        return try await Task.detached(priority: .background) { () -> Parsed in
            let aptLines = data["airports"]?.split(separator: "\n", omittingEmptySubsequences: true).dropFirst() ?? []
            let rwyLines = data["runways"]?.split(separator: "\n", omittingEmptySubsequences: true).dropFirst() ?? []
            let frqLines = data["airport-frequencies"]?.split(separator: "\n", omittingEmptySubsequences: true).dropFirst() ?? []

            var airports: [Airport] = []; airports.reserveCapacity(aptLines.count)
            for line in aptLines {
                let f = CSV.parseLine(line)
                guard f.count > Parser.Col.iata,
                      f[Parser.Col.country] == "US",
                      let lat = Double(f[Parser.Col.lat]), let lon = Double(f[Parser.Col.lon]),
                      lat != 0 || lon != 0 else { continue }
                func opt(_ s: String) -> String? { s.isEmpty ? nil : s }
                airports.append(Airport(
                    id: f[Parser.Col.ident], name: f[Parser.Col.name], type: f[Parser.Col.type],
                    icao: opt(f[Parser.Col.icao]), iata: opt(f[Parser.Col.iata]),
                    municipality: opt(f[Parser.Col.municipality]), elevationFt: Int(f[Parser.Col.elev]),
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))
            }

            var runways: [String: [Runway]] = [:]
            for line in rwyLines {
                let f = CSV.parseLine(line)
                guard f.count > 14 else { continue }
                runways[f[2], default: []].append(Runway(
                    leIdent: f[8], heIdent: f[14], lengthFt: Int(f[3]), widthFt: Int(f[4]),
                    surface: f[5].isEmpty ? nil : f[5], lighted: f[6] == "1", closed: f[7] == "1"))
            }

            var freqs: [String: [Frequency]] = [:]
            for line in frqLines {
                let f = CSV.parseLine(line)
                guard f.count > 5 else { continue }
                freqs[f[2], default: []].append(Frequency(type: f[3], description: f[4], mhz: f[5]))
            }

            return Parsed(airports: airports, runways: runways, freqs: freqs)
        }.value
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

struct Parsed: Sendable, Codable {
    var airports: [Airport]
    var runways: [String: [Runway]]
    var freqs: [String: [Frequency]]
}

struct CachedData: Codable {
    let timestamp: Date
    let parsed: Parsed
}

/// Pure parsing, safe to run off-actor. Reports fractional progress across all files.
enum Parser {
    enum Col { static let ident = 1, type = 2, name = 3, lat = 4, lon = 5,
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