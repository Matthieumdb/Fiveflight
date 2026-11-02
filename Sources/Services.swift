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

    private let manager = CLLocationManager()
    private var lastLocation: CLLocation?

    private override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.headingFilter = 5
        // In flight, never let iOS pause GPS updates; foreground use only (no UIBackgroundModes).
        manager.activityType = .airborne
        manager.pausesLocationUpdatesAutomatically = false
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
        isUpdating = false
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
        let urlString = "\(baseURL)/metar?ids=\(station)&format=json"
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
        let urlString = "\(baseURL)/metar?ids=\(ids)&format=json"
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

    /// Last fetch time per station, so the map can ask often without hammering aviationweather.gov.
    private var lastMetarFetch: [String: Date] = [:]

    /// Fetches METARs for the stations currently on the map (stale > 5 min only, batches of 50),
    /// which feeds the VFR/MVFR/IFR/LIFR marker colours.
    func refreshMETARs(forVisible stations: [String]) async {
        let now = Date()
        let stale = stations.filter { now.timeIntervalSince(lastMetarFetch[$0] ?? .distantPast) > 300 }
        guard !stale.isEmpty else { return }
        for id in stale { lastMetarFetch[id] = now }
        for chunk in stale.chunked(into: 50) {
            if Task.isCancelled { return }
            await fetchMETARs(for: chunk)
        }
    }

    // MARK: - TAF

    func fetchTAF(for station: String) async -> TAF? {
        let urlString = "\(baseURL)/taf?ids=\(station)&format=json"
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
        let urlString = "\(baseURL)/taf?ids=\(ids)&format=json"
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

        // FD winds/temps are a text product (no JSON); region "mia" covers Florida.
        guard let url = URL(string: "\(baseURL)/windtemp?region=mia&level=low&fcst=06") else { return }
        let text: String? = await fetchWithRetry(url: url) { data in
            String(decoding: data, as: UTF8.self)
        }
        if let text {
            let parsed = WindsAloftParser.parse(text)
            if !parsed.isEmpty { windsAloft = parsed }
        }
    }

    // MARK: - PIREPs

    func fetchPIREPs() async {
        isLoading = true
        defer { isLoading = false }

        let bbox = "\(FloridaArea.minLat),\(FloridaArea.minLon),\(FloridaArea.maxLat),\(FloridaArea.maxLon)"
        guard let url = URL(string: "\(baseURL)/pirep?format=json&age=3&bbox=\(bbox)") else { return }

        let result: [PIREPResponse]? = await fetchWithRetry(url: url) { data in
            try JSONDecoder().decode([PIREPResponse].self, from: data)
        }
        if let result {
            pireps = result
                .filter { FloridaArea.contains(lat: $0.lat, lon: $0.lon) }
                .map { PIREP(from: $0) }
                .sorted { $0.time > $1.time }
        }
    }

    // MARK: - AIRMETs/SIGMETs

    func fetchAIRMETs() async {
        isLoading = true
        defer { isLoading = false }

        guard let sigURL = URL(string: "\(baseURL)/airsigmet?format=json"),
              let gURL = URL(string: "\(baseURL)/gairmet?format=json") else { return }

        async let sigmets: [AirSigmetResponse]? = fetchWithRetry(url: sigURL) { data in
            try JSONDecoder().decode([AirSigmetResponse].self, from: data)
        }
        async let gairmets: [GAirmetResponse]? = fetchWithRetry(url: gURL) { data in
            try JSONDecoder().decode([GAirmetResponse].self, from: data)
        }
        let (s, g) = await (sigmets, gairmets)
        guard s != nil || g != nil else { return }
        airsigmets = Self.floridaAdvisories(sigmets: s ?? [], gairmets: g ?? [])
    }

    /// SIGMETs and current G-AIRMET areas that touch Florida, most severe first.
    nonisolated static func floridaAdvisories(sigmets: [AirSigmetResponse], gairmets: [GAirmetResponse]) -> [AirSigmet] {
        let sig = sigmets
            .filter { FloridaArea.overlaps($0.coords ?? []) }
            .map { AirSigmet(from: $0) }
        // G-AIRMETs come as snapshots (+0 h, +3 h, …): keep the earliest snapshot, areas only.
        let firstHour = gairmets.compactMap(\.forecastHour).min()
        let air = gairmets
            .filter { $0.forecastHour == firstHour && ($0.geometryType ?? "AREA") == "AREA" }
            .filter { FloridaArea.overlaps($0.coords ?? []) }
            .map { AirSigmet(gairmet: $0) }
        return sig + air
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

// MARK: - Response Models (aviationweather.gov Data API, format=json)
//
// These mirror the real payloads (see Tests/Fixtures, captured from the live API):
// numbers are numbers, times are epoch seconds, and a few fields mix types
// (wdir is 120 or "VRB", visib is 3 or "10+"/"6+").

/// A JSON scalar that may be a number or a string.
struct FlexValue: Codable, Hashable {
    let string: String

    init(_ string: String) { self.string = string }

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let d = try? c.decode(Double.self) {
            string = d == d.rounded() ? String(Int(d)) : String(d)
        } else if let s = try? c.decode(String.self) {
            string = s
        } else {
            string = ""
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(string)
    }

    /// Numeric value: "10+" → 10, "1/2" → 0.5, "1 1/2" → 1.5, "VRB" → nil.
    var number: Double? {
        let s = string.trimmingCharacters(in: CharacterSet(charactersIn: "+PM "))
        if let d = Double(s) { return d }
        var total = 0.0
        for part in s.split(separator: " ") {
            let f = part.split(separator: "/")
            if f.count == 2, let n = Double(f[0]), let d = Double(f[1]), d != 0 {
                total += n / d
            } else if let whole = Double(part) {
                total += whole
            } else {
                return nil
            }
        }
        return s.isEmpty ? nil : total
    }
}

struct METARResponse: Codable {
    let icaoId: String
    let obsTime: Double?
    let rawOb: String
    let temp: Double?
    let dewp: Double?
    let wdir: FlexValue?
    let wspd: Double?
    let wgst: Double?
    let visib: FlexValue?
    let altim: Double?        // hPa
    let clouds: [CloudLayer]?
    let fltCat: String?
    let wxString: String?

    struct CloudLayer: Codable {
        let cover: String
        let base: Double?
    }
}

struct TAFResponse: Codable {
    let icaoId: String
    let issueTime: String?
    let validTimeFrom: Double
    let validTimeTo: Double
    let rawTAF: String
    let fcsts: [TAFPeriod]?

    struct TAFPeriod: Codable {
        let timeFrom: Double
        let timeTo: Double
        let fcstChange: String?
        let probability: Double?
        let wdir: FlexValue?
        let wspd: Double?
        let wgst: Double?
        let visib: FlexValue?
        let wxString: String?
        let clouds: [METARResponse.CloudLayer]?
    }
}

struct PIREPResponse: Codable {
    let obsTime: Double?
    let acType: String?
    let lat: Double
    let lon: Double
    let fltLvl: Double?
    let pirepType: String?
    let rawOb: String
    let tbInt1: String?
    let tbType1: String?
    let icgInt1: String?
    let icgType1: String?
    let wxString: String?
}

struct AirSigmetResponse: Codable {
    let icaoId: String?
    let seriesId: String?
    let airSigmetType: String?
    let hazard: String?
    let severity: Double?
    let validTimeFrom: Double?
    let validTimeTo: Double?
    let altitudeLow1: Double?
    let altitudeHi1: Double?
    let rawAirSigmet: String?
    let coords: [Coord]?

    struct Coord: Codable {
        let lat: FlexValue
        let lon: FlexValue
    }
}

/// Graphical AIRMET (the format the US actually issues AIRMETs in).
struct GAirmetResponse: Codable {
    let tag: String?
    let forecastHour: Double?
    let validTime: String?
    let hazard: String?
    let geometryType: String?
    let severity: String?
    let top: FlexValue?
    let base: FlexValue?
    let issueTime: Double?
    let expireTime: Double?
    let coords: [AirSigmetResponse.Coord]?
}

// MARK: - Florida filter

enum FloridaArea {
    static let minLat = 24.3, maxLat = 31.1, minLon = -87.7, maxLon = -79.8

    static func contains(lat: Double, lon: Double) -> Bool {
        lat >= minLat && lat <= maxLat && lon >= minLon && lon <= maxLon
    }

    /// True when the bounding box of `coords` overlaps Florida.
    static func overlaps(_ coords: [AirSigmetResponse.Coord]) -> Bool {
        let pts = coords.compactMap { c -> (Double, Double)? in
            guard let la = c.lat.number, let lo = c.lon.number else { return nil }
            return (la, lo)
        }
        guard let laMin = pts.map(\.0).min(), let laMax = pts.map(\.0).max(),
              let loMin = pts.map(\.1).min(), let loMax = pts.map(\.1).max() else { return false }
        return laMax >= minLat && laMin <= maxLat && loMax >= minLon && loMin <= maxLon
    }
}

// MARK: - Winds aloft (FD text product)

/// Parses the FB/FD winds-and-temperatures text from `/api/data/windtemp`.
enum WindsAloftParser {
    /// FD stations covering Florida, with their positions.
    static let floridaStations: [String: (Double, Double)] = [
        "JAX": (30.49, -81.69), "TLH": (30.40, -84.35), "PFN": (30.21, -85.68),
        "PIE": (27.91, -82.69), "MLB": (28.10, -80.65), "MIA": (25.79, -80.29),
        "EYW": (24.56, -81.76)
    ]

    static func parse(_ text: String, stations: [String: (Double, Double)] = floridaStations,
                      maxAltitude: Int = 18000) -> [WindsAloft] {
        let lines = text.components(separatedBy: .newlines)
        guard let header = lines.first(where: { $0.hasPrefix("FT") }) else { return [] }
        let valid = lines.first { $0.hasPrefix("VALID") }?
            .split(separator: " ").dropFirst().first.map(String.init) ?? ""

        // Each altitude column ends where its header label ends (fields are right-aligned).
        var columns: [(altitude: Int, end: Int)] = []
        let chars = Array(header)
        var i = 2
        while i < chars.count {
            if chars[i].isNumber {
                var j = i
                while j < chars.count, chars[j].isNumber { j += 1 }
                if let alt = Int(String(chars[i..<j])) { columns.append((alt, j)) }
                i = j
            } else {
                i += 1
            }
        }

        var result: [WindsAloft] = []
        for line in lines {
            let row = Array(line)
            guard row.count >= 3 else { continue }
            let id = String(row[0..<3])
            guard let pos = stations[id] else { continue }
            var levels: [WindsAloftLevel] = []
            var start = 3
            for col in columns {
                defer { start = col.end }
                guard col.altitude <= maxAltitude else { continue }
                let end = min(col.end, row.count)
                guard start < end else { continue }
                let field = String(row[start..<end]).trimmingCharacters(in: .whitespaces)
                if let level = decode(field, altitude: col.altitude) { levels.append(level) }
            }
            guard !levels.isEmpty else { continue }
            result.append(WindsAloft(station: id, latitude: pos.0, longitude: pos.1,
                                     validTime: valid, levels: levels))
        }
        return result
    }

    /// "1311+15" → 130° 11 kt +15 °C; "9900" → light and variable; "7315" → 230° 115 kt;
    /// "266537" → temperature -37 (no sign above 24 000 ft means negative).
    static func decode(_ field: String, altitude: Int) -> WindsAloftLevel? {
        guard field.count >= 4, let dd = Int(field.prefix(2)), let ss = Int(field.dropFirst(2).prefix(2)) else {
            return nil
        }
        var direction = dd * 10
        var speed = ss
        if dd == 99 && ss == 0 {
            direction = 0; speed = 0
        } else if dd > 36 {
            direction = (dd - 50) * 10
            speed += 100
        }
        var temperature: Int?
        let rest = field.dropFirst(4)
        if !rest.isEmpty {
            if let t = Int(rest) {
                temperature = rest.hasPrefix("+") || rest.hasPrefix("-") ? t : -t
            }
        }
        return WindsAloftLevel(altitude: altitude, direction: direction, speed: speed, temperature: temperature)
    }
}
