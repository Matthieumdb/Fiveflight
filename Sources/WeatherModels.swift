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
    var id = UUID()
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
        self.observationTime = response.obsTime.map { Date(timeIntervalSince1970: $0) } ?? Date()

        let visibility = response.visib?.number
        let ceiling = Self.ceiling(of: response.clouds ?? [])

        // aviationweather.gov computes the category itself (fltCat); fall back to vis/ceiling.
        if let cat = response.fltCat, let fc = FlightCategory(rawValue: cat.uppercased()) {
            self.flightCategory = fc
        } else if let vis = visibility {
            self.flightCategory = FlightCategory.from(visibility: vis, ceiling: ceiling ?? 99_999)
        } else {
            self.flightCategory = .unknown
        }

        var d = METARDecoded()
        d.temperature = response.temp.map { Int($0.rounded()) }
        d.dewpoint = response.dewp.map { Int($0.rounded()) }
        d.windDirection = response.wdir?.number.map { Int($0) }
        d.windSpeed = response.wspd.map { Int($0) }
        d.windGust = response.wgst.map { Int($0) }
        d.visibility = visibility
        d.altimeter = response.altim.map { $0 / 33.8639 } // hPa → inHg
        d.ceiling = ceiling

        if let spd = d.windSpeed {
            if spd == 0 {
                d.wind = "Calme"
            } else {
                let dir = d.windDirection.map { String(format: "%03d°", $0) } ?? "VRB"
                d.wind = "\(dir) @ \(spd)kt" + (d.windGust.map { "G\($0)" } ?? "")
            }
        }
        if let vis = d.visibility {
            d.visibilityStr = (vis >= 10 ? "10+" : String(format: vis == vis.rounded() ? "%.0f" : "%.1f", vis)) + " SM"
        }
        if let ceil = d.ceiling { d.ceilingStr = "\(ceil) ft" }
        if let t = d.temperature, let dp = d.dewpoint {
            d.temperatureStr = "\(t)/\(dp)°C"
        } else if let t = d.temperature {
            d.temperatureStr = "\(t)°C"
        }
        if let altim = d.altimeter { d.altimeterStr = String(format: "%.2f", altim) }

        self.decoded = d.isEmpty ? nil : d
    }

    /// Ceiling = lowest broken, overcast or obscured layer.
    static func ceiling(of clouds: [METARResponse.CloudLayer]) -> Int? {
        clouds
            .filter { ["BKN", "OVC", "OVX", "VV"].contains($0.cover.uppercased()) }
            .compactMap { $0.base.map { Int($0) } }
            .min()
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
    var id = UUID()
    let station: String
    let rawText: String
    let issueTime: Date
    let validFrom: Date
    let validTo: Date
    let forecasts: [TAFForecast]

    init(from response: TAFResponse) {
        self.station = response.icaoId
        self.rawText = response.rawTAF
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let validFrom = Date(timeIntervalSince1970: response.validTimeFrom)
        self.validFrom = validFrom
        self.validTo = Date(timeIntervalSince1970: response.validTimeTo)
        self.issueTime = response.issueTime.flatMap { iso.date(from: $0) } ?? validFrom
        self.forecasts = response.fcsts?.map { TAFForecast(from: $0) } ?? []
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
    var id = UUID()
    let from: Date
    let to: Date
    let windDirection: Int?
    let windSpeed: Int?
    let visibility: Double?
    let weather: String?
    var clouds: [TAFCloudLayer] = []

    init(from response: TAFResponse.TAFPeriod) {
        self.from = Date(timeIntervalSince1970: response.timeFrom)
        self.to = Date(timeIntervalSince1970: response.timeTo)
        self.windDirection = response.wdir?.number.map { Int($0) }
        self.windSpeed = response.wspd.map { Int($0) }
        self.visibility = response.visib?.number
        self.weather = response.wxString
        self.clouds = response.clouds?.compactMap { TAFCloudLayer(from: $0) } ?? []
    }
}

struct TAFCloudLayer: Codable, Hashable {
    let cover: String
    let base: Int

    init?(from response: METARResponse.CloudLayer) {
        guard let base = response.base else { return nil }
        self.cover = response.cover
        self.base = Int(base)
    }
}

// MARK: - Winds Aloft

struct WindsAloft: Identifiable, Codable, Hashable {
    var id = UUID()
    let station: String
    let latitude: Double
    let longitude: Double
    let validTime: String
    let levels: [WindsAloftLevel]
    /// "FOR USE hhmm-hhmmZ" window of the FD product, when it could be read.
    var useFrom: Date?
    var useTo: Date?

    init(station: String, latitude: Double, longitude: Double, validTime: String, levels: [WindsAloftLevel],
         useFrom: Date? = nil, useTo: Date? = nil) {
        self.station = station
        self.latitude = latitude
        self.longitude = longitude
        self.validTime = validTime
        self.levels = levels
        self.useFrom = useFrom
        self.useTo = useTo
    }
}

struct WindsAloftLevel: Identifiable, Codable, Hashable {
    var id = UUID()
    let altitude: Int
    let direction: Int
    let speed: Int
    let temperature: Int?

    init(altitude: Int, direction: Int, speed: Int, temperature: Int?) {
        self.altitude = altitude
        self.direction = direction
        self.speed = speed
        self.temperature = temperature
    }
}

// MARK: - PIREP

struct PIREP: Identifiable, Codable, Hashable {
    var id = UUID()
    let location: String
    let time: Date
    let latitude: Double
    let longitude: Double
    let elevation: Int?
    let aircraftType: String
    let rawText: String
    let elements: [PIREPElement]

    init(from response: PIREPResponse) {
        // rawOb starts with the reporting location: "ORL UA /OV ORL270001/TM 2016/..."
        self.location = response.rawOb.split(separator: " ").first.map(String.init) ?? "—"
        self.time = response.obsTime.map { Date(timeIntervalSince1970: $0) } ?? Date()
        self.latitude = response.lat
        self.longitude = response.lon
        let altitude = response.fltLvl.map { Int($0) * 100 }
        self.elevation = altitude
        self.aircraftType = response.acType.flatMap { $0.isEmpty ? nil : $0 } ?? "—"
        self.rawText = response.rawOb

        var elements: [PIREPElement] = []
        if let alt = altitude, alt > 0 {
            elements.append(PIREPElement(type: "Altitude", value: "\(alt) ft", severity: nil))
        }
        if let tb = response.tbInt1, !tb.isEmpty {
            let value = [tb, response.tbType1 ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            elements.append(PIREPElement(type: "Turbulence", value: value, severity: PIREPElement.severity(tb)))
        }
        if let ic = response.icgInt1, !ic.isEmpty {
            let value = [ic, response.icgType1 ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
            elements.append(PIREPElement(type: "Givrage", value: value, severity: PIREPElement.severity(ic)))
        }
        if let wx = response.wxString, !wx.isEmpty {
            elements.append(PIREPElement(type: "Temps", value: wx, severity: nil))
        }
        self.elements = elements
    }

    var isUrgent: Bool { rawText.contains(" UUA ") }
}

struct PIREPElement: Identifiable, Codable, Hashable {
    var id = UUID()
    let type: String
    let value: String
    let severity: String?

    init(type: String, value: String, severity: String?) {
        self.type = type
        self.value = value
        self.severity = severity
    }

    /// "LGT" / "MOD-SEV" / "NEG" → the severity names used for colours.
    static func severity(_ intensity: String) -> String? {
        let s = intensity.uppercased()
        if s.hasPrefix("NEG") { return nil }
        if s.contains("EXTRM") { return "EXTREME" }
        if s.contains("SEV") { return "SEVERE" }
        if s.contains("MOD") { return "MODERATE" }
        if s.contains("LGT") { return "LIGHT" }
        if s.contains("TRC") { return "TRACE" }
        return nil
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
    var id = UUID()
    let type: String // "AIRMET", "SIGMET", "CONVECTIVE SIGMET"
    let hazard: String // "ICE", "TURB", "IFR", "MTN OBSCN", "CONVECTION", etc.
    let severity: String
    let validFrom: Date
    let validTo: Date
    let rawText: String
    let issuingOffice: String
    let sequence: String
    /// Polygon of the advisory (for the route briefing); nil when unknown.
    var area: [Coordinate2D]?

    init(type: String, hazard: String, severity: String, validFrom: Date, validTo: Date,
         rawText: String, issuingOffice: String, sequence: String) {
        self.type = type
        self.hazard = hazard
        self.severity = severity
        self.validFrom = validFrom
        self.validTo = validTo
        self.rawText = rawText
        self.issuingOffice = issuingOffice
        self.sequence = sequence
    }

    init(from response: AirSigmetResponse) {
        let hazard = response.hazard ?? "—"
        let type = response.airSigmetType ?? "SIGMET"
        self.type = hazard.uppercased() == "CONVECTIVE" ? "CONVECTIVE SIGMET" : type
        self.hazard = hazard
        self.severity = response.severity.map { String(Int($0)) } ?? ""
        self.validFrom = Date(timeIntervalSince1970: response.validTimeFrom ?? 0)
        self.validTo = Date(timeIntervalSince1970: response.validTimeTo ?? 0)
        self.rawText = response.rawAirSigmet ?? ""
        self.issuingOffice = response.icaoId ?? ""
        self.sequence = response.seriesId ?? ""
        self.area = Self.polygon(response.coords)
    }

    static func polygon(_ coords: [AirSigmetResponse.Coord]?) -> [Coordinate2D]? {
        let pts = (coords ?? []).compactMap { c -> Coordinate2D? in
            guard let la = c.lat.number, let lo = c.lon.number else { return nil }
            return Coordinate2D(CLLocationCoordinate2D(latitude: la, longitude: lo))
        }
        return pts.count >= 3 ? pts : nil
    }

    /// A G-AIRMET area (IFR, MT_OBSC, TURB-LO, ICE, SFC_WND, LLWS…).
    init(gairmet g: GAirmetResponse) {
        let hazard = g.hazard ?? "—"
        let layers = [g.base?.string, g.top?.string].compactMap { $0 }.filter { !$0.isEmpty }
        self.type = "AIRMET"
        self.hazard = hazard
        self.severity = g.severity ?? ""
        self.validFrom = Date(timeIntervalSince1970: g.issueTime ?? 0)
        self.validTo = Date(timeIntervalSince1970: g.expireTime ?? 0)
        self.rawText = "G-AIRMET \(hazard)" + (layers.isEmpty ? "" : " \(layers.joined(separator: "–"))")
            + (g.forecastHour.map { " · +\(Int($0)) h" } ?? "")
        self.issuingOffice = "KKCI"
        self.sequence = g.tag ?? ""
        self.area = Self.polygon(g.coords)
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
        case "CONVECTION", "CONVECTIVE", "TS", "TCU": return ColorToken.lifr
        case "SEVERE TURB", "EXTREME TURB": return ColorToken.lifr
        case "TURB", "TURBULENCE", "TURB-LO", "TURB-HI", "LLWS": return ColorToken.ifr
        case "ICE", "ICING", "SEVERE ICE": return ColorToken.mvfr
        case "IFR", "LOW IFR", "LIFR": return ColorToken.ifr
        case "MTN OBSCN", "MT_OBSC", "MOUNTAIN OBSCURATION": return ColorToken.mvfr
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
