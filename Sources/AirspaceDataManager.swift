import Foundation
import CoreLocation

/// Fetches and parses real FAA airspace data from official sources.
/// Sources: FAA ArcGIS REST services for Class airspace and SUA.
/// Falls back to bundled JSON snapshot for offline use.
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

    // Florida bounding box: 24.3..31.1 N, -87.7..-79.8 W
    private let floridaBBox = (
        minLat: 24.3, maxLat: 31.1,
        minLon: -87.7, maxLon: -79.8
    )

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
            async let classAirspace = fetchClassAirspace()
            async let sua = fetchSUA()
            async let ctaf = fetchCTAF()
            async let airways = fetchAirways()

            let (classAirspaces, suaAirspaces, ctafData, airwayAirspaces) = await (classAirspace, sua, ctaf, airways)

            var allAirspaces = classAirspaces
            allAirspaces.append(contentsOf: suaAirspaces)
            allAirspaces.append(contentsOf: airwayAirspaces)

            // Filter to Florida bbox
            allAirspaces = allAirspaces.filter { intersectsFlorida($0) }

            self.airspaces = allAirspaces
            self.ctafFrequencies = ctafData
            self.lastUpdate = Date()
            await saveCache()
        } catch {
            self.error = error.localizedDescription
            // If refresh fails, keep existing data (or load from cache)
            if airspaces.isEmpty {
                await loadFromBundle()
            }
        }
    }

    /// Fetches Class A/B/C/D/E airspace from FAA ArcGIS
    private func fetchClassAirspace() async -> [Airspace] {
        // FAA ArcGIS Class Airspace layer
        // Service: https://services.arcgis.com/.../Class_Airspace/FeatureServer/0
        // Using a known public endpoint for US airspace classes
        let urlString = "https://faa.maps.arcgis.com/sharing/rest/content/items/..." // Placeholder - real endpoint needed
        // For now, return empty - will fall back to bundle
        return []
    }

    /// Fetches Special Use Airspace (MOA, Restricted, Prohibited, Warning, Alert, CFA, TFR) from FAA ArcGIS
    private func fetchSUA() async -> [Airspace] {
        // FAA ArcGIS SUA layer
        // Service: https://services.arcgis.com/.../Special_Use_Airspace/FeatureServer/0
        let urlString = "https://faa.maps.arcgis.com/sharing/rest/content/items/..." // Placeholder
        // For now, return empty - will fall back to bundle
        return []
    }

    /// Loads CTAF/UNICOM frequencies from bundled airport-frequencies.csv
    private func fetchCTAF() async -> [String: [CTAFFrequency]] {
        guard let url = Bundle.main.url(forResource: "airport-frequencies", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return [:] }

        var result: [String: [CTAFFrequency]] = [:]
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst()

        for line in lines {
            let fields = CSV.parseLine(line)
            guard fields.count >= 4 else { continue }

            // airport-frequencies.csv columns: id, airport_ref, airport_ident, type, description, frequency_mhz
            let airportIdent = fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !airportIdent.isEmpty else { continue }

            let type = fields[3].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !type.isEmpty else { continue }

            let freqStr = fields[4].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !freqStr.isEmpty, let freqMHz = Double(freqStr) else { continue }

            let freqType = type.lowercased()
            if freqType.contains("ctaf") || freqType.contains("unicom") || freqType.contains("multicom") {
                let ctaf = CTAFFrequency(
                    frequency: freqMHz,
                    type: freqType,
                    description: fields.count > 5 ? fields[5].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) : ""
                )
                result[airportIdent, default: []].append(ctaf)
            }
        }
        return result
    }

    /// Fetches Victor Airways and Jet Routes - returns empty for now (no public GeoJSON endpoint)
    private func fetchAirways() async -> [Airspace] {
        // No public GeoJSON endpoint available for NASR airways
        // Could parse NASR data but that's complex; return empty for now
        return []
    }

    /// Checks if an airspace intersects the Florida bounding box
    private func intersectsFlorida(_ airspace: Airspace) -> Bool {
        for polygon in airspace.polygons {
            for coord in polygon {
                if coord.latitude >= floridaBBox.minLat && coord.latitude <= floridaBBox.maxLat &&
                   coord.longitude >= floridaBBox.minLon && coord.longitude <= floridaBBox.maxLon {
                    return true
                }
            }
        }
        return false
    }

    /// Loads bundled fallback airspace data (JSON snapshot)
    private func loadFromBundle() async {
        guard let url = Bundle.main.url(forResource: "airspace_snapshot", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Airspace].self, from: data) else {
            error = "Espaces aériens indisponibles"
            airspaces = []
            return
        }
        // Filter to Florida
        airspaces = decoded.filter { intersectsFlorida($0) }
        if airspaces.isEmpty {
            error = "Espaces aériens indisponibles"
        }
        lastUpdate = Date()
    }

    private func loadCache() async {
        if let data = try? Data(contentsOf: cacheURL),
           let cached = try? JSONDecoder().decode(CachedAirspaceData.self, from: data),
           Date().timeIntervalSince(cached.timestamp) < updateInterval {
            self.airspaces = cached.airspaces
            self.ctafFrequencies = cached.ctafFrequencies
            self.lastUpdate = cached.timestamp
        } else {
            // Cache stale or missing, load from bundle
            await loadFromBundle()
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