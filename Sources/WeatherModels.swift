import Foundation
import CoreLocation
import SwiftUI

// MARK: - Flight Category

enum FlightCategory: String, Codable, CaseIterable, Identifiable {
    case vfr = "VFR"
    case mvfr = "MVFR"
    case ifr = "IFR"
    case lifr = "LIFR"
    case unknown = "UNKNOWN"

    var id: String { rawValue }

    var displayName: String { rawValue }

    var color: Color {
        switch self {
        case .vfr: return ColorToken.vfr
        case .mvfr: return ColorToken.mvfr
        case .ifr: return ColorToken.ifr
        case .lifr: return ColorToken.lifr
        case .unknown: return ColorToken.textTertiary
        }
    }

    static func from(visibility: Double, ceiling: Int) -> FlightCategory {
        if visibility < 1 || ceiling < 500 { return .lifr }
        if visibility < 3 || ceiling < 1000 { return .ifr }
        if visibility < 5 || ceiling < 3000 { return .mvfr }
        return .vfr
    }
}

// MARK: - METAR

struct METAR: Identifiable, Codable, Hashable {
    let id = UUID()
    let station: String
    let rawText: String
    let observationTime: Date
    let flightCategory: FlightCategory
    let decoded: METARDecoded?

    // Computed properties for display
    var temperature: Int? { decoded?.temperature }
    var dewpoint: Int? { decoded?.dewpoint }
    var windDirection: Int? { decoded?.windDirection }
    var windSpeed: Int? { decoded?.windSpeed }
    var windGust: Int? { decoded?.windGust }
    var visibility: Double? { decoded?.visibility }
    var altimeter: Double? { decoded?.altimeter }
    var ceiling: Int? { decoded?.ceiling }

    init(from response: METARResponse) {
        self.station = response.icaoId
        self.rawText = response.rawOb
        self.observationTime = ISO8601DateFormatter().date(from: response.reportTime) ?? Date()

        // Parse flight category
        if let cat = response.flightCategory, let fc = FlightCategory(rawValue: cat.uppercased()) {
            self.flightCategory = fc
        } else if let visStr = response.visib, let vis = Double(visStr),
                  let ceilStr = response.clouds?.first?.base, let ceil = Int(ceilStr) {
            self.flightCategory = FlightCategory.from(visibility: vis, ceiling: ceil)
        } else {
            self.flightCategory = .unknown
        }

        // Build decoded data
        var decodedData = METARDecoded()

        if let tempStr = response.temp, let temp = Int(tempStr) {
            decodedData.temperature = temp
        }
        if let dewpStr = response.dewp, let dewp = Int(dewpStr) {
            decodedData.dewpoint = dewp
        }
        if let wdirStr = response.wdir, let wdir = Int(wdirStr) {
            decodedData.windDirection = wdir
        }
        if let wspdStr = response.wspd, let wspd = Int(wspdStr) {
            decodedData.windSpeed = wspd
        }
        if let visStr = response.visib, let vis = Double(visStr) {
            decodedData.visibility = vis
        }
        if let altimStr = response.altim, let altim = Double(altimStr) {
            decodedData.altimeter = altim / 100.0 // Convert to inHg
        }
        if let clouds = response.clouds, let first = clouds.first,
           let base = Int(first.base) {
            decodedData.ceiling = base
        }

        // Build wind string
        if let dir = decodedData.windDirection, let spd = decodedData.windSpeed {
            decodedData.wind = "\(dir)° @ \(spd)kt"
            if let gust = decodedData.windGust {
                decodedData.wind += "G\(gust)"
            }
        }

        // Build visibility string
        if let vis = decodedData.visibility {
            if vis >= 10 { decodedData.visibilityStr = "10+" } else { decodedData.visibilityStr = String(format: "%.1f", vis) }
        }

        // Build ceiling string
        if let ceil = decodedData.ceiling {
            decodedData.ceilingStr = "\(ceil) ft"
        }

        // Build temperature string
        if let temp = decodedData.temperature, let dewp = decodedData.dewpoint {
            decodedData.temperatureStr = "\(temp)/\(dewp)°C"
        } else if let temp = decodedData.temperature {
            decodedData.temperatureStr = "\(temp)°C"
        }

        // Build altimeter string
        if let altim = decodedData.altimeter {
            decodedData.altimeterStr = String(format: "%.2f", altim)
        }

        self.decoded = decodedData.isEmpty ? nil : decodedData
    }

    init(station: String, rawText: String, observationTime: Date, flightCategory: FlightCategory, decoded: METARDecoded?) {
        self.station = station
        self.rawText = rawText
        self.observationTime = observationTime
        self.flightCategory = flightCategory
        self.decoded = decoded
    }
}

struct METARDecoded: Codable, Hashable {
    var temperature: Int?
    var dewpoint: Int?
    var windDirection: Int?
    var windSpeed: Int?
    var windGust: Int?
    var visibility: Double?
    var altimeter: Double?
    var ceiling: Int?

    // Display strings
    var wind: String = ""
    var visibilityStr: String = ""
    var ceilingStr: String = ""
    var temperatureStr: String = ""
    var altimeterStr: String = ""

    var isEmpty: Bool {
        temperature == nil && dewpoint == nil && windDirection == nil && windSpeed == nil &&
        visibility == nil && altimeter == nil && ceiling == nil
    }
}

// MARK: - TAF

struct TAF: Identifiable, Codable, Hashable {
    let id = UUID()
    let station: String
    let rawText: String
    let issueTime: Date
    let validFrom: Date
    let validTo: Date
    let forecasts: [TAFForecast]

    init(from response: TAFResponse) {
        self.station = response.icaoId
        self.rawText = response.rawTAF
        self.issueTime = ISO8601DateFormatter().date(from: response.issueTime) ?? Date()
        self.validFrom = ISO8601DateFormatter().date(from: response.validTimeFrom) ?? Date()
        self.validTo = ISO8601DateFormatter().date(from: response.validTimeTo) ?? Date()

        self.forecasts = response.forecast?.compactMap { TAFForecast(from: $0) } ?? []
    }

    init(station: String, rawText: String, issueTime: Date, validFrom: Date, validTo: Date, forecasts: [TAFForecast]) {
        self.station = station
        self.rawText = rawText
        self.issueTime = issueTime
        self.validFrom = validFrom
        self.validTo = validTo
        self.forecasts = forecasts
    }
}

struct TAFForecast: Identifiable, Codable, Hashable {
    let id = UUID()
    let from: Date
    let to: Date
    let windDirection: Int?
    let windSpeed: Int?
    let visibility: Double?
    let weather: String?
    var clouds: [TAFCloudLayer] = []

    init(from response: TAFResponse.TAFPeriod) {
        self.from = ISO8601DateFormatter().date(from: response.fcstTimeFrom) ?? Date()
        self.to = ISO8601DateFormatter().date(from: response.fcstTimeTo) ?? Date()
        self.windDirection = response.windDir.flatMap { Int($0) }
        self.windSpeed = response.windSpeed.flatMap { Int($0) }
        self.visibility = response.visib.flatMap { Double($0) }
        self.weather = response.wxString

        if let clouds = response.clouds {
            self.clouds = clouds.compactMap { TAFCloudLayer(from: $0) }
        }
    }
}

struct TAFCloudLayer: Codable, Hashable {
    let cover: String
    let base: Int

    init?(from response: METARResponse.CloudLayer) {
        guard let base = Int(response.base) else { return nil }
        self.cover = response.cover
        self.base = base
    }
}

// MARK: - Winds Aloft

struct WindsAloft: Identifiable, Codable, Hashable {
    let id = UUID()
    let station: String
    let latitude: Double
    let longitude: Double
    let validTime: String
    let levels: [WindsAloftLevel]

    init(from response: WindsAloftResponse) {
        self.station = response.station
        self.latitude = response.latitude
        self.longitude = response.longitude
        self.validTime = response.time
        self.levels = response.winds.compactMap { WindsAloftLevel(from: $0) }
    }
}

struct WindsAloftLevel: Identifiable, Codable, Hashable {
    let id = UUID()
    let altitude: Int
    let direction: Int
    let speed: Int
    let temperature: Int?

    init(from response: WindsAloftResponse.WindLevel) {
        self.altitude = response.altitude
        self.direction = response.direction
        self.speed = response.speed
        self.temperature = response.temperature
    }
}

// MARK: - PIREP

struct PIREP: Identifiable, Codable, Hashable {
    let id = UUID()
    let location: String
    let time: Date
    let latitude: Double
    let longitude: Double
    let elevation: Int?
    let aircraftType: String
    let rawText: String
    let elements: [PIREPElement]

    init(from response: PIREPResponse) {
        self.location = response.icaoId
        self.time = ISO8601DateFormatter().date(from: response.obsTime) ?? Date()
        self.latitude = response.latitude
        self.longitude = response.longitude
        self.elevation = Int(response.elev ?? "0")
        self.aircraftType = response.aircraftType ?? "UNKNOWN"
        self.rawText = response.rawOb
        self.elements = response.elements?.compactMap { PIREPElement(from: $0) } ?? []
    }
}

struct PIREPElement: Identifiable, Codable, Hashable {
    let id = UUID()
    let type: String
    let value: String
    let severity: String?

    init(from response: PIREPResponse.PIREPElementResponse) {
        self.type = response.type
        self.value = response.value
        self.severity = response.severity
    }

    var severityColor: Color {
        switch severity?.uppercased() {
        case "SEVERE", "EXTREME": return ColorToken.lifr
        case "MODERATE": return ColorToken.ifr
        case "LIGHT": return ColorToken.mvfr
        case "TRACE": return ColorToken.vfr
        default: return ColorToken.textPrimary
        }
    }
}

// MARK: - AIRMET/SIGMET (AirSigmet)

struct AirSigmet: Identifiable, Codable, Hashable {
    let id = UUID()
    let type: String // "AIRMET", "SIGMET", "CONVECTIVE SIGMET"
    let hazard: String // "ICE", "TURB", "IFR", "MTN OBSCN", "CONVECTION", etc.
    let severity: String
    let validFrom: Date
    let validTo: Date
    let rawText: String
    let issuingOffice: String
    let sequence: String

    init(from response: AirSigmetResponse) {
        self.type = response.type
        self.hazard = response.hazard
        self.severity = response.severity
        self.validFrom = ISO8601DateFormatter().date(from: response.validTimeFrom) ?? Date()
        self.validTo = ISO8601DateFormatter().date(from: response.validTimeTo) ?? Date()
        self.rawText = response.rawAirSigmet
        self.issuingOffice = response.icaoId
        self.sequence = response.sequence
    }

    var isConvective: Bool {
        type.uppercased().contains("CONVECTIVE")
    }

    var isSigmet: Bool {
        type.uppercased().contains("SIGMET") && !isConvective
    }

    var isAirmet: Bool {
        type.uppercased() == "AIRMET"
    }

    var displayType: String {
        if isConvective { return "CONVECTIVE SIGMET" }
        if isSigmet { return "SIGMET" }
        return "AIRMET"
    }

    var hazardColor: Color {
        switch hazard.uppercased() {
        case "CONVECTION", "TS", "TCU": return ColorToken.lifr
        case "SEVERE TURB", "EXTREME TURB": return ColorToken.lifr
        case "TURB", "TURBULENCE": return ColorToken.ifr
        case "ICE", "ICING", "SEVERE ICE": return ColorToken.mvfr
        case "IFR", "LOW IFR", "LIFR": return ColorToken.ifr
        case "MTN OBSCN", "MOUNTAIN OBSCURATION": return ColorToken.mvfr
        default: return ColorToken.brandPrimary
        }
    }

    var validTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return "\(formatter.string(from: validFrom))–\(formatter.string(from: validTo))Z"
    }
}
