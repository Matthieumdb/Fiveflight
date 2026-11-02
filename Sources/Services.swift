import Foundation
import CoreLocation
import Combine

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

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 10
        manager.headingFilter = 5
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

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
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

    // MARK: - METAR

    func fetchMETAR(for station: String) async -> METAR? {
        let urlString = "\(baseURL)/metar?ids=\(station)&format=json&taf=false&hours=2"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode([METARResponse].self, from: data)
            if let metarResponse = response.first {
                let metar = METAR(from: metarResponse)
                metars[station] = metar
                return metar
            }
        } catch {
            print("METAR fetch error for \(station): \(error)")
        }
        return nil
    }

    func fetchMETARs(for stations: [String]) async {
        let ids = stations.joined(separator: ",")
        let urlString = "\(baseURL)/metar?ids=\(ids)&format=json&taf=false&hours=2"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode([METARResponse].self, from: data)
            for metarResponse in response {
                let metar = METAR(from: metarResponse)
                metars[metar.station] = metar
            }
        } catch {
            print("Batch METAR fetch error: \(error)")
        }
    }

    // MARK: - TAF

    func fetchTAF(for station: String) async -> TAF? {
        let urlString = "\(baseURL)/taf?ids=\(station)&format=json&hours=24"
        guard let url = URL(string: urlString) else { return nil }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode([TAFResponse].self, from: data)
            if let tafResponse = response.first {
                let taf = TAF(from: tafResponse)
                tafs[station] = taf
                return taf
            }
        } catch {
            print("TAF fetch error for \(station): \(error)")
        }
        return nil
    }

    func fetchTAFs(for stations: [String]) async {
        let ids = stations.joined(separator: ",")
        let urlString = "\(baseURL)/taf?ids=\(ids)&format=json&hours=24"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode([TAFResponse].self, from: data)
            for tafResponse in response {
                let taf = TAF(from: tafResponse)
                tafs[taf.station] = taf
            }
        } catch {
            print("Batch TAF fetch error: \(error)")
        }
    }

    // MARK: - Winds Aloft

    func fetchWindsAloft() async {
        isLoading = true
        defer { isLoading = false }

        let urlString = "\(baseURL)/wind?format=json"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode([WindsAloftResponse].self, from: data)
            windsAloft = response.compactMap { WindsAloft(from: $0) }
        } catch {
            print("Winds aloft fetch error: \(error)")
        }
    }

    // MARK: - PIREPs

    func fetchPIREPs() async {
        isLoading = true
        defer { isLoading = false }

        let urlString = "\(baseURL)/pirep?format=json&hours=2"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode([PIREPResponse].self, from: data)
            pireps = response.compactMap { PIREP(from: $0) }
        } catch {
            print("PIREP fetch error: \(error)")
        }
    }

    // MARK: - AIRMETs/SIGMETs

    func fetchAIRMETs() async {
        isLoading = true
        defer { isLoading = false }

        let urlString = "\(baseURL)/airsigmet?format=json&hours=6"
        guard let url = URL(string: urlString) else { return }

        do {
            let (data, _) = try await session.data(from: url)
            let response = try JSONDecoder().decode([AirSigmetResponse].self, from: data)
            airsigmets = response.compactMap { AirSigmet(from: $0) }
        } catch {
            print("AIRMET/SIGMET fetch error: \(error)")
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
        let ids = icaos.prefix(40).joined(separator: ",")
        guard !ids.isEmpty else { return [:] }

        let urlString = "https://aviationweather.gov/api/data/metar?ids=\(ids)&format=json"
        guard let url = URL(string: urlString) else { return [:] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode([MetarDTO].self, from: data)
            var out: [String: String] = [:]
            for m in response {
                if let id = m.icaoId, let cat = m.fltCat {
                    out[id] = cat
                }
            }
            return out
        } catch {
            print("Categories fetch error: \(error)")
            return [:]
        }
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
