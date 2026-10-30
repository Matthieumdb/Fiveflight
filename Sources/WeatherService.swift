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
