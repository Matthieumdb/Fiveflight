import Foundation
import CoreLocation

// MARK: - Airport Store

@MainActor
final class AirportStore: ObservableObject {
    @Published var airports: [Airport] = []
    @Published var runways: [String: [Runway]] = [:]
    @Published var frequencies: [String: [Frequency]] = [:]
    @Published var isLoading = false
    @Published var loadProgress: Double = 0
    @Published var error: String?

    private let dataLoader = DataLoader()

    func loadData() async {
        guard airports.isEmpty else { return }

        isLoading = true
        error = nil
        defer { isLoading = false }

        do {
            // Load airports
            airports = try await dataLoader.loadAirports { progress in
                self.loadProgress = progress
            }

            // Load runways
            runways = try await dataLoader.loadRunways()

            // Load frequencies
            frequencies = try await dataLoader.loadFrequencies()

            print("Loaded \(airports.count) airports, \(runways.values.reduce(0) { $0 + $1.count }) runways, \(frequencies.values.reduce(0) { $0 + $1.count }) frequencies")
        } catch {
            self.error = error.localizedDescription
            print("Data loading error: \(error)")
        }
    }

    func airport(_ ident: String) -> Airport? {
        airports.first { $0.id == ident }
    }

    func runways(for airport: Airport) -> [Runway] {
        runways[airport.id] ?? []
    }

    func frequencies(for airport: Airport) -> [Frequency] {
        frequencies[airport.id] ?? []
    }

    func nearest(to coordinate: CLLocationCoordinate2D, maxCount: Int = 10) -> [Airport] {
        airports
            .map { ($0, $0.distanceNM(from: coordinate)) }
            .sorted { $0.1 < $1.1 }
            .prefix(maxCount)
            .map { $0.0 }
    }

    func search(_ query: String, limit: Int = 50) -> [Airport] {
        let q = query.uppercased()
        return airports.filter {
            $0.id.uppercased().contains(q) ||
            ($0.iata?.uppercased().contains(q) ?? false) ||
            $0.name.uppercased().contains(q) ||
            ($0.municipality?.uppercased().contains(q) ?? false)
        }
        .prefix(limit)
        .map { $0 }
    }
}

// MARK: - Data Models

struct Airport: Identifiable, Codable, Hashable {
    let id: String
    let iata: String?
    let name: String
    let type: String
    let latitude: Double
    let longitude: Double
    let elevation: Int
    let municipality: String?
    let state: String?
    let country: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func distanceNM(from coordinate: CLLocationCoordinate2D) -> Double {
        Haversine.nauticalMiles(self.coordinate, coordinate)
    }
}

struct Runway: Identifiable, Codable, Hashable {
    let id = UUID()
    let airportIdent: String
    let designation: String
    let length: Int
    let width: Int
    let surface: String
    let lighted: Bool
    let closed: Bool
    let trueHeading: Int
    let magneticHeading: Int
    let leLatitude: Double?
    let leLongitude: Double?
    let heLatitude: Double?
    let heLongitude: Double?
}

struct Frequency: Identifiable, Codable, Hashable {
    let id = UUID()
    let airportIdent: String
    let type: String
    let frequencyMHz: Double
    let description: String

    var displayValue: String {
        String(format: "%.2f", frequencyMHz)
    }

    var typeShort: String {
        let t = type.uppercased()
        if t.contains("CTAF") || t.contains("UNICOM") || t.contains("MULTICOM") { return "CTAF" }
        if t.contains("TOWER") || t.contains("TWR") { return "TWR" }
        if t.contains("GROUND") { return "GND" }
        if t.contains("APPROACH") || t.contains("APP") || t.contains("DEP") { return "APP" }
        if t.contains("CENTER") { return "CTR" }
        if t.contains("ATIS") { return "ATIS" }
        if t.contains("AWOS") || t.contains("ASOS") || t.contains("AWSS") { return "WX" }
        if t.contains("CLEARANCE") { return "CLNC" }
        if t.contains("RADIO") { return "RDO" }
        return String(t.prefix(4))
    }
}

// MARK: - Data Loader

struct DataLoader {
    private let airportsURL = "https://ourairports.com/data/airports.csv"
    private let runwaysURL = "https://ourairports.com/data/runways.csv"
    private let frequenciesURL = "https://ourairports.com/data/airport-frequencies.csv"

    func loadAirports(progress: @escaping (Double) -> Void) async throws -> [Airport] {
        guard let url = URL(string: airportsURL),
              let (data, response) = try? await URLSession.shared.data(from: url),
              let httpResponse = response as? HTTPURLResponse,
              httpResponse.statusCode == 200,
              let csv = String(data: data, encoding: .utf8) else {
            throw NSError(domain: "DataLoader", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to download airports"])
        }

        let lines = csv.components(separatedBy: .newlines).dropFirst()
        let total = lines.count
        var airports: [Airport] = []
        airports.reserveCapacity(total)

        for (index, line) in lines.enumerated() {
            if index % 1000 == 0 {
                await MainActor.run { progress(Double(index) / Double(total)) }
            }

            let fields = parseCSV(line)
            guard fields.count >= 14 else { continue }

            let ident = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !ident.isEmpty else { continue }

            // Only US airports
            guard fields[8].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) == "US" else { continue }

            let type = fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard ["large_airport", "medium_airport", "small_airport", "heliport", "seaplane_base"].contains(type) else { continue }

            let latitude = Double(fields[4].trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0
            let longitude = Double(fields[5].trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0
            let elevation = Int(fields[6].trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0

            let iata = fields[13].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let municipality = fields[10].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            let state = fields[9].trimmingCharacters(in: CharacterSet(charactersIn: "\""))

            let airport = Airport(
                id: ident,
                iata: iata.isEmpty ? nil : iata,
                name: fields[3].trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                type: type,
                latitude: latitude,
                longitude: longitude,
                elevation: elevation,
                municipality: municipality.isEmpty ? nil : municipality,
                state: state.isEmpty ? nil : state,
                country: "US"
            )
            airports.append(airport)
        }

        await MainActor.run { progress(1.0) }
        return airports
    }

    func loadRunways() async throws -> [String: [Runway]] {
        guard let url = URL(string: runwaysURL),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let csv = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var result: [String: [Runway]] = [:]
        let lines = csv.components(separatedBy: .newlines).dropFirst()

        for line in lines {
            let fields = parseCSV(line)
            guard fields.count >= 18,
                  let airportIdent = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")).components(separatedBy: ",").first
            else { continue }

            let runway = Runway(
                airportIdent: airportIdent,
                designation: fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                length: Int(fields[3].trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0,
                width: Int(fields[4].trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0,
                surface: fields[5].trimmingCharacters(in: CharacterSet(charactersIn: "\"")),
                lighted: fields[6].trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased() == "yes",
                closed: fields[7].trimmingCharacters(in: CharacterSet(charactersIn: "\"")).lowercased() == "yes",
                trueHeading: Int(fields[8].trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0,
                magneticHeading: Int(fields[9].trimmingCharacters(in: CharacterSet(charactersIn: "\""))) ?? 0,
                leLatitude: Double(fields[10].trimmingCharacters(in: CharacterSet(charactersIn: "\""))),
                leLongitude: Double(fields[11].trimmingCharacters(in: CharacterSet(charactersIn: "\""))),
                heLatitude: Double(fields[12].trimmingCharacters(in: CharacterSet(charactersIn: "\""))),
                heLongitude: Double(fields[13].trimmingCharacters(in: CharacterSet(charactersIn: "\"")))
            )
            result[airportIdent, default: []].append(runway)
        }

        return result
    }

    func loadFrequencies() async throws -> [String: [Frequency]] {
        guard let url = URL(string: frequenciesURL),
              let (data, _) = try? await URLSession.shared.data(from: url),
              let csv = String(data: data, encoding: .utf8) else {
            return [:]
        }

        var result: [String: [Frequency]] = [:]
        let lines = csv.components(separatedBy: .newlines).dropFirst()

        for line in lines {
            let fields = parseCSV(line)
            guard fields.count >= 5 else { continue }

            let airportIdent = fields[1].trimmingCharacters(in: CharacterSet(charactersIn: "\"")).components(separatedBy: ",").first ?? ""
            guard !airportIdent.isEmpty else { continue }

            let type = fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !type.isEmpty else { continue }

            let freqStr = fields[3].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !freqStr.isEmpty else { continue }

            if let freqMHz = Double(freqStr) {
                let freq = Frequency(
                    airportIdent: airportIdent,
                    type: type,
                    frequencyMHz: freqMHz,
                    description: fields.count > 4 ? fields[4].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) : ""
                )
                result[airportIdent, default: []].append(freq)
            }
        }

        return result
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
}
