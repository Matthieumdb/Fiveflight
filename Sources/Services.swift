import Foundation
import CoreLocation
import Combine

// MARK: - Array Extensions

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        guard size > 0 else { return [] }
        return stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Location Manager

@MainActor
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    static let shared = LocationManager()

    @Published var location: CLLocationCoordinate2D?
    @Published var heading: Double = 0
    @Published var speed: Double = 0
    @Published var altitude: Double = 0
    @Published var accuracy: Double = 0
    @Published var authorizationStatus: CLAuthorizationStatus = .notDetermined
    @Published var isUpdating = false
    @Published var isBackgroundModeEnabled = false

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?
    private var isSignificantChangeMonitoring = false

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.headingFilter = 5
        manager.pausesLocationUpdatesAutomatically = true
        manager.allowsBackgroundLocationUpdates = false // Set to true when background mode enabled
        authorizationStatus = manager.authorizationStatus
    }

    func start() {
        guard !isUpdating else { return }

        switch authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways:
            startUpdating()
        case .denied, .restricted:
            // Could show alert to open settings
            break
        @unknown default:
            break
        }
    }

    func stop() {
        manager.stopUpdatingLocation()
        manager.stopUpdatingHeading()
        if isSignificantChangeMonitoring {
            manager.stopMonitoringSignificantLocationChanges()
            isSignificantChangeMonitoring = false
        }
        isUpdating = false
    }

    func enableBackgroundMode(_ enabled: Bool) {
        guard isBackgroundModeEnabled != enabled else { return }
        isBackgroundModeEnabled = enabled

        if enabled {
            manager.allowsBackgroundLocationUpdates = true
            // Start significant change monitoring for background updates
            if !isSignificantChangeMonitoring {
                manager.startMonitoringSignificantLocationChanges()
                isSignificantChangeMonitoring = true
            }
        } else {
            manager.allowsBackgroundLocationUpdates = false
            if isSignificantChangeMonitoring {
                manager.stopMonitoringSignificantLocationChanges()
                isSignificantChangeMonitoring = false
            }
        }
    }

    private func startUpdating() {
        manager.startUpdatingLocation()
        manager.startUpdatingHeading()
        isUpdating = true
    }

    // MARK: - CLLocationManagerDelegate

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways {
                startUpdating()
            }
        }
    }

    nonisolated private func handleLocations(_ locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            self.location = location.coordinate
            self.altitude = location.altitude
            self.accuracy = location.horizontalAccuracy
            self.speed = max(0, location.speed) * 1.94384 // m/s to knots

            if let last = self.lastLocation {
                // Calculate track
                let course = Haversine.trueCourse(last.coordinate, location.coordinate)
                self.heading = Double(course)
            }
            self.lastLocation = location
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        handleLocations(locations)
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        Task { @MainActor in
            if newHeading.headingAccuracy > 0 {
                self.heading = newHeading.trueHeading > 0 ? newHeading.trueHeading : newHeading.magneticHeading
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error.localizedDescription)")
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation], isSignificantChange: Bool) {
        // Called for significant location changes (background mode)
        handleLocations(locations)
    }
}

// MARK: - Weather Service

@MainActor
final class WeatherService: ObservableObject {
    static let shared = WeatherService()

    @Published var metars: [String: METAR] = [:]
    @Published var tafs: [String: TAF] = [:]
    @Published var windsAloft: [WindsAloft] = []
    @Published var pireps: [PIREP] = []
    @Published var airsigmets: [AirSigmet] = []
    @Published var isLoading = false
    @Published var error: String?

    /// Flight categories from currently cached METARs (for map markers).
    var categories: [String: String] {
        metars.mapValues { $0.flightCategory.rawValue }
    }

    private let baseURL = "https://aviationweather.gov/api/data"
    private let session = URLSession.shared
    private var cancellables = Set<AnyCancellable>()

    private init() {}

    // MARK: - Retry Helper

    private func fetchWithRetry<T: Decodable>(
        url: URL,
        decode: @escaping (Data) throws -> T,
        maxRetries: Int = 2,
        baseDelay: TimeInterval = 1.0
    ) async -> T? {
        var lastError: Error?

        for attempt in 0...maxRetries {
            do {
                let (data, response) = try await session.data(from: url)

                // Check for HTTP errors
                if let httpResponse = response as? HTTPURLResponse,
                   httpResponse.statusCode >= 400 {
                    throw URLError(.badServerResponse)
                }

                return try decode(data)
            } catch {
                lastError = error
                if attempt < maxRetries {
                    let delay = baseDelay * pow(2.0, Double(attempt))
                    try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                }
            }
        }

        if let error = lastError {
            print("Fetch failed after retries: \(error)")
        }
        return nil
    }

    // MARK: - METAR

    func fetchMETAR(for station: String) async -> METAR? {
        let urlString = "\(baseURL)/metar?ids=\(station)&format=json&taf=false&hours=2"
        guard let url = URL(string: urlString) else { return nil }

        let result: [METARResponse]? = await fetchWithRetry(url: url) { data in
            try JSONDecoder().decode([METARResponse].self, from: data)
        }

        if let metarResponse = result?.first {
            let metar = METAR(from: metarResponse)
            metars[station] = metar
            return metar
        }
        return nil
    }

    func fetchMETARs(for stations: [String]) async {
        let ids = stations.joined(separator: ",")
        let urlString = "\(baseURL)/metar?ids=\(ids)&format=json&taf=false&hours=2"
        guard let url = URL(string: urlString) else { return }

        let result: [METARResponse]? = await fetchWithRetry(url: url) { data in
            try JSONDecoder().decode([METARResponse].self, from: data)
        }

        if let response = result {
            for metarResponse in response {
                let metar = METAR(from: metarResponse)
                metars[metar.station] = metar
            }
        }
    }

    // MARK: - TAF

    func fetchTAF(for station: String) async -> TAF? {
        let urlString = "\(baseURL)/taf?ids=\(station)&format=json&hours=24"
        guard let url = URL(string: urlString) else { return nil }

        let result: [TAFResponse]? = await fetchWithRetry(url: url) { data in
            try JSONDecoder().decode([TAFResponse].self, from: data)
        }

        if let tafResponse = result?.first {
            let taf = TAF(from: tafResponse)
            tafs[station] = taf
            return taf
        }
        return nil
    }

    func fetchTAFs(for stations: [String]) async {
        let ids = stations.joined(separator: ",")
        let urlString = "\(baseURL)/taf?ids=\(ids)&format=json&hours=24"
        guard let url = URL(string: urlString) else { return }

        let result: [TAFResponse]? = await fetchWithRetry(url: url) { data in
            try JSONDecoder().decode([TAFResponse].self, from: data)
        }

        if let response = result {
            for tafResponse in response {
                let taf = TAF(from: tafResponse)
                tafs[taf.station] = taf
            }
        }
    }

    // MARK: - Winds Aloft

    func fetchWindsAloft() async {
        isLoading = true
        defer { isLoading = false }

        let urlString = "\(baseURL)/wind?format=json"
        guard let url = URL(string: urlString) else { return }

        let result: [WindsAloftResponse]? = await fetchWithRetry(url: url) { data in
            try JSONDecoder().decode([WindsAloftResponse].self, from: data)
        }

        if let response = result {
            windsAloft = response.compactMap { WindsAloft(from: $0) }
        }
    }

    // MARK: - PIREPs

    func fetchPIREPs() async {
        isLoading = true
        defer { isLoading = false }

        let urlString = "\(baseURL)/pirep?format=json&hours=2"
        guard let url = URL(string: urlString) else { return }

        let result: [PIREPResponse]? = await fetchWithRetry(url: url) { data in
            try JSONDecoder().decode([PIREPResponse].self, from: data)
        }

        if let response = result {
            pireps = response.compactMap { PIREP(from: $0) }
        }
    }

    // MARK: - AIRMETs/SIGMETs

    func fetchAIRMETs() async {
        isLoading = true
        defer { isLoading = false }

        let urlString = "\(baseURL)/airsigmet?format=json&hours=6"
        guard let url = URL(string: urlString) else { return }

        let result: [AirSigmetResponse]? = await fetchWithRetry(url: url) { data in
            try JSONDecoder().decode([AirSigmetResponse].self, from: data)
        }

        if let response = result {
            airsigmets = response.compactMap { AirSigmet(from: $0) }
        }
    }

    // MARK: - Refresh All

    func refreshAll(for stations: [String]) async {
        async let metars = fetchMETARs(for: stations)
        async let tafs = fetchTAFs(for: stations)
        async let winds = fetchWindsAloft()
        async let pireps = fetchPIREPs()
        async let airsigmets = fetchAIRMETs()

        _ = await (metars, tafs, winds, pireps, airsigmets)
    }

    // MARK: - Static Convenience Methods (for backward compatibility)

    /// Fetches METAR/TAF for a single airport, returning a simplified AirportWeather struct.
    static func fetch(icao: String) async -> AirportWeather? {
        async let metarResult = shared.fetchMETAR(for: icao)
        async let tafResult = shared.fetchTAF(for: icao)
        let (metar, taf) = await (metarResult, tafResult)
        guard metar != nil || taf != nil else { return nil }

        return AirportWeather(
            fltCat: metar?.flightCategory.rawValue,
            rawMetar: metar?.rawText,
            rawTaf: taf?.rawText,
            windText: metar.flatMap { windText(from: $0) },
            visib: metar?.visibility.map { "\($0) SM" },
            altimInHg: metar?.altimeter.map { String(format: "%.2f inHg", $0) },
            tempC: metar?.temperature,
            dewpC: metar?.dewpoint,
            windDirDeg: metar?.windDirection,
            windSpdKt: metar?.windSpeed,
            obsTime: metar?.observationTime
        )
    }

    /// Flight category per ICAO, in one batched request.
    static func categories(for icaos: [String]) async -> [String: String] {
        // Aviation Weather API supports up to ~100 stations per request; chunk to be safe
        let chunkSize = 80
        var out: [String: String] = [:]

        for chunk in icaos.chunked(into: chunkSize) {
            let ids = chunk.joined(separator: ",")
            guard !ids.isEmpty else { continue }

            let urlString = "https://aviationweather.gov/api/data/metar?ids=\(ids)&format=json"
            guard let url = URL(string: urlString) else { continue }

            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode([MetarDTO].self, from: data)
                for m in response {
                    if let id = m.icaoId, let cat = m.fltCat {
                        out[id] = cat
                    }
                }
            } catch {
                print("Categories fetch error for chunk: \(error)")
            }
        }
        return out
    }

    private static func windText(from metar: METAR) -> String? {
        guard let dir = metar.windDirection, let spd = metar.windSpeed else { return nil }
        let base = "\(dir)° \(spd) kt"
        if let gust = metar.windGust, gust > 0 {
            return base + " raf. \(gust)"
        }
        return base
    }
}

// MARK: - AirportWeather (simplified weather for quick display)

struct AirportWeather: Sendable {
    let fltCat: String?       // VFR / MVFR / IFR / LIFR
    let rawMetar: String?
    let rawTaf: String?
    let windText: String?
    let visib: String?        // statute miles
    let altimInHg: String?    // US altimeter setting
    let tempC: Int?
    let dewpC: Int?
    let windDirDeg: Int?      // nil when variable (VRB)
    let windSpdKt: Int?
    let obsTime: Date?        // observation time (for freshness)

    /// Human relative age, e.g. "il y a 12 min".
    var ageText: String? {
        guard let obsTime else { return nil }
        let mins = Int(max(0, Date().timeIntervalSince(obsTime)) / 60)
        if mins < 1 { return "à l'instant" }
        if mins < 60 { return "il y a \(mins) min" }
        return "il y a \(mins / 60) h \(mins % 60) min"
    }
}

// MARK: - DTOs for static methods (aviationweather.gov sends wdir/visib as String or number)

private struct MetarDTO: Decodable {
    let icaoId: String?
    let rawOb: String?
    let fltCat: String?
    let wdir: Flex?
    let wspd: Double?
    let wgst: Double?
    let visib: Flex?
    let altim: Double?     // hPa
    let temp: Double?
    let dewp: Double?
    let obsTime: Double?    // epoch seconds
}

/// Decodes a field that may arrive as String, Int, or Double into a String.
private struct Flex: Decodable {
    let string: String
    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { string = s }
        else if let i = try? c.decode(Int.self) { string = String(i) }
        else if let d = try? c.decode(Double.self) { string = String(d) }
        else { string = "" }
    }
}

// MARK: - Response Models

struct METARResponse: Codable {
    let icaoId: String
    let reportTime: String
    let rawOb: String
    let temp: String?
    let dewp: String?
    let wspd: String?
    let wdir: String?
    let wgst: String?
    let visib: String?
    let altim: String?
    let clouds: [CloudLayer]?
    let flightCategory: String?
    let wxString: String?

    struct CloudLayer: Codable {
        let cover: String
        let base: String
    }
}

struct TAFResponse: Codable {
    let icaoId: String
    let issueTime: String
    let validTimeFrom: String
    let validTimeTo: String
    let rawTAF: String
    let forecast: [TAFPeriod]?

    struct TAFPeriod: Codable {
        let fcstTimeFrom: String
        let fcstTimeTo: String
        let windDir: String?
        let windSpeed: String?
        let visib: String?
        let wxString: String?
        let clouds: [METARResponse.CloudLayer]?
    }
}

struct WindsAloftResponse: Codable {
    let station: String
    let latitude: Double
    let longitude: Double
    let time: String
    let winds: [WindLevel]

    struct WindLevel: Codable {
        let altitude: Int
        let direction: Int
        let speed: Int
        let temperature: Int?
    }
}

struct PIREPResponse: Codable {
    let rawOb: String
    let icaoId: String
    let obsTime: String
    let latitude: Double
    let longitude: Double
    let elev: String?
    let aircraftType: String?
    let elements: [PIREPElementResponse]?

    struct PIREPElementResponse: Codable {
        let type: String
        let value: String
        let severity: String?
    }
}

struct AirSigmetResponse: Codable {
    let icaoId: String
    let issueTime: String
    let sequence: String
    let type: String
    let hazard: String
    let severity: String
    let validTimeFrom: String
    let validTimeTo: String
    let rawAirSigmet: String
}
