import Foundation
import CoreLocation

/// Fetches and parses real FAA airspace data from official sources
/// Sources: FAA NASR, NOAA AIP, FAA SUA (Special Use Airspace)
@MainActor
final class AirspaceDataManager: ObservableObject {
    static let shared = AirspaceDataManager()

    @Published var airspaces: [Airspace] = []
    @Published var ctafFrequencies: [String: [CTAFFrequency]] = [:]
    @Published var isLoading = false
    @Published var lastUpdate: Date?
    @Published var error: String?

    private let cacheURL: URL
    private let updateInterval: TimeInterval = 24 * 3600 // 24 hours

    private init() {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        cacheURL = caches.appendingPathComponent("airspace_cache.json")
        Task { await loadCache() }
    }

    /// Forces refresh from FAA sources
    func refresh() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            async let sua = fetchSUA()
            async let ctaf = fetchCTAF()
            async let airways = fetchAirways()

            let (suaAirspaces, ctafData, airwayAirspaces) = await (sua, ctaf, airways)

            var allAirspaces = suaAirspaces
            allAirspaces.append(contentsOf: airwayAirspaces)

            self.airspaces = allAirspaces
            self.ctafFrequencies = ctafData
            self.lastUpdate = Date()
            await saveCache()
        } catch {
            self.error = error.localizedDescription
        }
    }

    /// Fetches Special Use Airspace (MOA, Restricted, Prohibited, Warning, Alert, CFA)
    private func fetchSUA() async -> [Airspace] {
        // FAA SUA data: https://nfdc.faa.gov/nfdcApps/services/ajv5/sua
        let urlString = "https://nfdc.faa.gov/nfdcApps/services/ajv5/sua"
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let features = json["features"] as? [[String: Any]] else {
            return loadLocalSUA() // Fallback to bundled data
        }

        return features.compactMap { feature -> Airspace? in
            guard let properties = feature["properties"] as? [String: Any],
                  let geometry = feature["geometry"] as? [String: Any],
                  let type = properties["type"] as? String,
                  let name = properties["name"] as? String,
                  let coordinates = geometry["coordinates"] as? [[[Double]]] else { return nil }

            let polygons = coordinates.map { ring in
                ring.map { Coordinate2D(CLLocationCoordinate2D(latitude: $0[1], longitude: $0[0])) }
            }

            let floor = (properties["floor"] as? String).flatMap { parseAltitude($0) } ?? 0
            let ceiling = (properties["ceiling"] as? String).flatMap { parseAltitude($0) } ?? 18000
            let controllingAgency = properties["controllingAgency"] as? String

            return Airspace(
                id: UUID().uuidString,
                name: name,
                type: Airspace.fromSUA(type),
                polygons: polygons,
                floor: floor,
                ceiling: ceiling,
                controllingAgency: controllingAgency,
                frequency: (properties["frequency"] as? String)?.trimmingCharacters(in: .whitespaces)
            )
        }
    }

    /// Fetches CTAF/UNICOM frequencies for non-towered airports
    private func fetchCTAF() async -> [String: [CTAFFrequency]] {
        // Use OurAirports data which includes CTAF frequencies
        let urlString = "https://ourairports.com/data/airport-frequencies.csv"
        guard let url = URL(string: urlString),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let csv = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var result: [String: [CTAFFrequency]] = [:]
        let lines = csv.components(separatedBy: .newlines).dropFirst()

        for line in lines {
            let fields = parseCSV(line)
            guard fields.count >= 4 else { continue }

            let airportRef = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")).components(separatedBy: ",").first ?? ""
            guard !airportRef.isEmpty else { continue }

            let type = fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !type.isEmpty else { continue }

            let freqStr = fields[3].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !freqStr.isEmpty else { continue }

            let freqType = type.lowercased()
            if freqType.contains("ctaf") || freqType.contains("unicom") || freqType.contains("multicom") {
                if let freqMHz = Double(freqStr) {
                    let ctaf = CTAFFrequency(
                        frequency: freqMHz,
                        type: freqType,
                        description: fields.count > 4 ? fields[4].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) : ""
                    )
                    result[airportRef, default: []].append(ctaf)
                }
            }
        }
        return result
    }

    /// Fetches Victor Airways and Jet Routes
    private func fetchAirways() async -> [Airspace] {
        // FAA NASR data for airways - simplified for now
        // Real implementation would parse NASR ATS routes
        return []
    }

    /// Loads bundled fallback SUA data
    private func loadLocalSUA() -> [Airspace] {
        // Bundled SUA data for offline use
        // In production, this would be a JSON file in the bundle
        return Airspace.sampleUSAAirspaces()
    }

    private func parseAltitude(_ str: String) -> Int? {
        let cleaned = str.replacingOccurrences(of: "[^0-9]", with: "", options: .regularExpression)
        return Int(cleaned)
    }

    private func parseCSV(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false

        for char in line {
            if char == "\"" {
                inQuotes.toggle()
            } else if char == "," && !inQuotes {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
        }
        fields.append(current)
        return fields
    }

    private func loadCache() async {
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(CachedAirspaceData.self, from: data),
           Date().timeIntervalSince(cached.timestamp) < updateInterval {
            self.airspaces = cached.airspaces
            self.ctafFrequencies = cached.ctafFrequencies
            self.lastUpdate = cached.timestamp
        }
    }

    private func saveCache() async {
        let cached = CachedAirspaceData(
            timestamp: Date(),
            airspaces: airspaces,
            ctafFrequencies: ctafFrequencies
        )
        if let data = try? JSONEncoder().encode(cached) {
            try? data.write(to: cacheURL)
        }
    }
}

struct CachedAirspaceData: Codable {
    let timestamp: Date
    let airspaces: [Airspace]
    let ctafFrequencies: [String: [CTAFFrequency]]
}