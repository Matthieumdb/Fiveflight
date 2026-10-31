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