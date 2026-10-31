import Foundation

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

/// Winds aloft forecast at a given altitude.
struct WindsAloft: Sendable, Identifiable {
    let id = UUID()
    let icao: String
    let altitude: Int          // feet MSL
    let direction: Int?        // degrees true, nil = VRB
    let speed: Int             // knots
    let temperature: Int?      // Celsius
}

/// Pilot Report (PIREP).
struct Pirep: Sendable, Identifiable {
    let id = UUID()
    let icao: String?          // nearest airport
    let latitude: Double?
    let longitude: Double?
    let altitudeFt: Int?       // MSL
    let aircraftType: String?
    let reportTime: Date
    let rawText: String
    let turbulence: String?    // NONE, LGT, MOD, SEV
    let icing: String?         // NONE, TRACE, LGT, MOD, SEV
}

/// AIRMET/SIGMET advisory.
struct AirSigmet: Sendable, Identifiable {
    let id = UUID()
    let type: String           // AIRMET, SIGMET, G-AIRMET
    let hazard: String         // IFR, MTN OBSCN, TURB, ICE, etc.
    let severity: String?      // MOD, SEV
    let altitudeFrom: Int?     // feet MSL
    let altitudeTo: Int?       // feet MSL
    let rawText: String
    let validFrom: Date?
    let validTo: Date?
    let affectedArea: String?  // FIR/region identifier
}

/// Fetches METAR/TAF from aviationweather.gov (NOAA, free, no key).
enum WeatherService {
    static func fetch(icao: String) async -> AirportWeather? {
        async let m = metar(icao)
        async let t = taf(icao)
        let (metar, taf) = await (m, t)
        guard metar != nil || taf != nil else { return nil }
        return AirportWeather(
            fltCat: metar?.fltCat,
            rawMetar: metar?.rawOb,
            rawTaf: taf,
            windText: metar.flatMap(windText),
            visib: metar?.visib.map { "\($0.string) SM" },
            altimInHg: metar?.altim.map { String(format: "%.2f inHg", $0 * 0.0295300) },
            tempC: metar?.temp.map { Int($0.rounded()) },
            dewpC: metar?.dewp.map { Int($0.rounded()) },
            windDirDeg: metar?.wdir.flatMap { Int($0.string) },
            windSpdKt: metar?.wspd.map { Int($0.rounded()) },
            obsTime: metar?.obsTime.map { Date(timeIntervalSince1970: $0) })
    }

    /// Flight category per ICAO, in one batched request. Airports without a
    /// reporting station simply won't appear in the result.
    static func categories(for icaos: [String]) async -> [String: String] {
        let ids = icaos.prefix(40).joined(separator: ",")
        guard !ids.isEmpty,
              let arr = await get("https://aviationweather.gov/api/data/metar?ids=\(ids)&format=json",
                                  as: [MetarDTO].self) else { return [:] }
        var out: [String: String] = [:]
        for m in arr { if let id = m.icaoId, let cat = m.fltCat { out[id] = cat } }
        return out
    }

    /// Winds aloft forecast for a list of stations.
    static func windsAloft(for icaos: [String]) async -> [WindsAloft] {
        let ids = icaos.prefix(20).joined(separator: ",")
        guard !ids.isEmpty,
              let arr = await get("https://aviationweather.gov/api/data/wind?ids=\(ids)&format=json",
                                  as: [WindDTO].self) else { return [] }
        var out: [WindsAloft] = []
        for w in arr {
            guard let icao = w.icaoId else { continue }
            // wind levels are nested; typical structure: fcst array of {level, drct, spdr, tmpc}
            if let fcsts = w.fcst {
                for f in fcsts {
                    if let level = f.level, let spd = f.spdr {
                        out.append(WindsAloft(
                            icao: icao,
                            altitude: level,
                            direction: f.drct.flatMap { Int($0.string) },
                            speed: Int(spd.rounded()),
                            temperature: f.tmpc.map { Int($0.rounded()) }
                        ))
                    }
                }
            }
        }
        return out
    }

    /// PIREPs near a coordinate (lat/lon) within radius NM.
    static func pireps(lat: Double, lon: Double, radiusNM: Int = 100) async -> [Pirep] {
        // aviationweather.gov doesn't support geographic query directly; fetch all recent and filter
        let url = "https://aviationweather.gov/api/data/pirep?format=json&age=2"
        guard let arr = await get(url, as: [PirepDTO].self) else { return [] }
        var out: [Pirep] = []
        for p in arr {
            guard let plat = p.lat, let plon = p.lon else { continue }
            let dist = haversineNM(lat1: lat, lon1: lon, lat2: plat, lon2: plon)
            if dist <= Double(radiusNM) {
                out.append(Pirep(
                    icao: nil,
                    latitude: plat,
                    longitude: plon,
                    altitudeFt: p.alt.flatMap { Int($0.string) },
                    aircraftType: p.aircraft,
                    reportTime: Date(timeIntervalSince1970: p.obsTime ?? 0),
                    rawText: p.rawOb ?? "",
                    turbulence: p.turb,
                    icing: p.ice
                ))
            }
        }
        return out
    }

    /// AIRMETs, SIGMETs, and G-AIRMETs for a region (CONUS, AK, HI, etc.).
    static func airSigmets(region: String = "CONUS") async -> [AirSigmet] {
        var out: [AirSigmet] = []
        // AIRMETs
        if let airmets = await get("https://aviationweather.gov/api/data/airmet?format=json&region=\(region)",
                                    as: [AirSigmetDTO].self) {
            for a in airmets {
                out.append(AirSigmet(
                    type: "AIRMET",
                    hazard: a.hazard ?? "",
                    severity: a.severity,
                    altitudeFrom: a.altFrom.flatMap { Int($0.string) },
                    altitudeTo: a.altTo.flatMap { Int($0.string) },
                    rawText: a.rawText ?? "",
                    validFrom: a.validTimeFrom.map { Date(timeIntervalSince1970: $0) },
                    validTo: a.validTimeTo.map { Date(timeIntervalSince1970: $0) },
                    affectedArea: a.region
                ))
            }
        }
        // SIGMETs
        if let sigmets = await get("https://aviationweather.gov/api/data/sigmet?format=json&region=\(region)",
                                    as: [AirSigmetDTO].self) {
            for s in sigmets {
                out.append(AirSigmet(
                    type: "SIGMET",
                    hazard: s.hazard ?? "",
                    severity: s.severity,
                    altitudeFrom: s.altFrom.flatMap { Int($0.string) },
                    altitudeTo: s.altTo.flatMap { Int($0.string) },
                    rawText: s.rawText ?? "",
                    validFrom: s.validTimeFrom.map { Date(timeIntervalSince1970: $0) },
                    validTo: s.validTimeTo.map { Date(timeIntervalSince1970: $0) },
                    affectedArea: s.region
                ))
            }
        }
        // G-AIRMETs
        if let gAirmets = await get("https://aviationweather.gov/api/data/gairmet?format=json&region=\(region)",
                                     as: [AirSigmetDTO].self) {
            for g in gAirmets {
                out.append(AirSigmet(
                    type: "G-AIRMET",
                    hazard: g.hazard ?? "",
                    severity: g.severity,
                    altitudeFrom: g.altFrom.flatMap { Int($0.string) },
                    altitudeTo: g.altTo.flatMap { Int($0.string) },
                    rawText: g.rawText ?? "",
                    validFrom: g.validTimeFrom.map { Date(timeIntervalSince1970: $0) },
                    validTo: g.validTimeTo.map { Date(timeIntervalSince1970: $0) },
                    affectedArea: g.region
                ))
            }
        }
        return out
    }

    private static func windText(_ m: MetarDTO) -> String? {
        guard let dir = m.wdir?.string else { return nil }
        let spd = m.wspd.map { Int($0.rounded()) } ?? 0
        let base = dir == "VRB" ? "VRB \(spd) kt" : "\(dir)° \(spd) kt"
        if let g = m.wgst, g > 0 { return base + " raf. \(Int(g.rounded()))" }
        return base
    }

    private static func metar(_ icao: String) async -> MetarDTO? {
        await get("https://aviationweather.gov/api/data/metar?ids=\(icao)&format=json",
                  as: [MetarDTO].self)?.first
    }

    private static func taf(_ icao: String) async -> String? {
        await get("https://aviationweather.gov/api/data/taf?ids=\(icao)&format=json",
                  as: [TafDTO].self)?.first?.rawTAF
    }

    private static func get<T: Decodable>(_ urlString: String, as: T.Type) async -> T? {
        guard let url = URL(string: urlString) else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(T.self, from: data)
        } catch { return nil }
    }

    /// Haversine distance in nautical miles.
    private static func haversineNM(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let R = 3440.065 // Earth radius in NM
        let dLat = (lat2 - lat1) * .pi / 180
        let dLon = (lon2 - lon1) * .pi / 180
        let a = sin(dLat/2)*sin(dLat/2) + cos(lat1*.pi/180)*cos(lat2*.pi/180)*sin(dLon/2)*sin(dLon/2)
        return 2 * R * asin(sqrt(a))
    }
}

// MARK: - DTOs (aviationweather.gov sends wdir/visib as String or number)

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

private struct TafDTO: Decodable { let rawTAF: String? }

private struct WindDTO: Decodable {
    let icaoId: String?
    let fcst: [WindLevelDTO]?
}

private struct WindLevelDTO: Decodable {
    let level: Int?        // altitude in feet MSL
    let drct: Flex?
    let spdr: Double?      // speed in knots
    let tmpc: Double?      // temperature in Celsius
}

private struct PirepDTO: Decodable {
    let icaoId: String?
    let lat: Double?
    let lon: Double?
    let alt: Flex?
    let aircraft: String?
    let obsTime: Double?
    let rawOb: String?
    let turb: String?
    let ice: String?
}

private struct AirSigmetDTO: Decodable {
    let hazard: String?
    let severity: String?
    let altFrom: Flex?
    let altTo: Flex?
    let rawText: String?
    let validTimeFrom: Double?
    let validTimeTo: Double?
    let region: String?
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
