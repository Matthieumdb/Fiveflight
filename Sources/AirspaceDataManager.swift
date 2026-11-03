import Foundation
import CoreLocation

/// Real FAA airspace for Florida: Class B/C/D, Class E surface areas and Special Use Airspace.
/// Source: FAA Aeronautical Data Delivery Service (ADDS) ArcGIS layers. Offline, the bundled
/// snapshot (generated from the same layers by scripts/build_airspace_snapshot.py) is used.
@MainActor
final class AirspaceDataManager: ObservableObject {
    static let shared = AirspaceDataManager()

    @Published var airspaces: [Airspace] = []
    /// Live TFRs, kept apart from the cached base data (they change by the hour).
    @Published var tfrs: [Airspace] = []
    @Published var ctafFrequencies: [String: [CTAFFrequency]] = [:]
    @Published var isLoading = false
    @Published var lastUpdate: Date?
    @Published var error: String?
    @Published var ctafParseProgress: Double = 0
    @Published var ctafParseError: String?

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
        Task {
            await loadCache()
            await refreshTFRs()
        }
    }

    /// Refreshes from the FAA ADDS layers. Existing data is only replaced by a plausible, non-empty
    /// result: a failed or empty download keeps what is on screen (it used to wipe it and cache the empty list).
    func refresh() async {
        isLoading = true
        error = nil
        defer { isLoading = false }

        async let classAirspace = fetchLayer(FAAAirspaceLayer.classAirspace)
        async let sua = fetchLayer(FAAAirspaceLayer.specialUse)
        async let ctaf = fetchCTAF()
        async let tfr: Void = refreshTFRs()
        let (classResult, suaResult, ctafData, _) = await (classAirspace, sua, ctaf, tfr)

        if !ctafData.isEmpty { ctafFrequencies = ctafData }

        switch (classResult, suaResult) {
        case let (.success(classes), .success(suas)):
            let fresh = (classes + suas).filter { intersectsFlorida($0) }
            guard fresh.count >= 20 else {
                error = "Réponse FAA incomplète (\(fresh.count) espaces) : données précédentes conservées"
                return
            }
            airspaces = fresh
            lastUpdate = Date()
            await saveCache()
        case let (.failure(err), _), let (_, .failure(err)):
            error = "Mise à jour FAA impossible : \(err.localizedDescription). Données précédentes conservées."
            if airspaces.isEmpty { await loadFromBundle() }
        }
    }

    /// Queries one FAA ADDS ArcGIS layer (all pages) for features intersecting Florida, as GeoJSON.
    private func fetchLayer(_ layer: FAAAirspaceLayer) async -> Result<[Airspace], Error> {
        var result: [Airspace] = []
        var offset = 0
        do {
            while true {
                var components = URLComponents(string: layer.queryURL)!
                components.queryItems = [
                    .init(name: "where", value: "1=1"),
                    .init(name: "geometry", value: "\(floridaBBox.minLon),\(floridaBBox.minLat),\(floridaBBox.maxLon),\(floridaBBox.maxLat)"),
                    .init(name: "geometryType", value: "esriGeometryEnvelope"),
                    .init(name: "inSR", value: "4326"),
                    .init(name: "spatialRel", value: "esriSpatialRelIntersects"),
                    .init(name: "outFields", value: "*"),
                    .init(name: "outSR", value: "4326"),
                    .init(name: "maxAllowableOffset", value: "0.001"),
                    .init(name: "geometryPrecision", value: "5"),
                    .init(name: "resultOffset", value: String(offset)),
                    .init(name: "resultRecordCount", value: "1000"),
                    .init(name: "f", value: "geojson")
                ]
                guard let url = components.url else { throw URLError(.badURL) }
                let (data, response) = try await URLSession.shared.data(from: url)
                guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
                let page = try FAAAirspaceParser.parse(data, layer: layer)
                result += page.airspaces
                guard page.exceededTransferLimit, page.featureCount > 0 else { break }
                offset += page.featureCount
            }
            return .success(result)
        } catch {
            return .failure(error)
        }
    }

    /// Loads CTAF/UNICOM frequencies from bundled airport-frequencies.csv
    private func fetchCTAF() async -> [String: [CTAFFrequency]] {
        ctafParseProgress = 0
        ctafParseError = nil

        guard let url = Bundle.main.url(forResource: "airport-frequencies", withExtension: "csv"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            ctafParseError = "CSV file not found"
            return [:]
        }

        var result: [String: [CTAFFrequency]] = [:]
        let lines = text.split(separator: "\n", omittingEmptySubsequences: true).dropFirst()
        let totalLines = lines.count

        for (index, line) in lines.enumerated() {
            // Update progress every 100 lines
            if index % 100 == 0 {
                await MainActor.run { self.ctafParseProgress = Double(index) / Double(max(1, totalLines)) }
            }

            let fields = CSV.parseLine(line)
            guard fields.count >= 6 else { continue }

            // airport-frequencies.csv columns: id, airport_ref, airport_ident, type, description, frequency_mhz
            let airportIdent = fields[2].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !airportIdent.isEmpty else { continue }

            let type = fields[3].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !type.isEmpty else { continue }

            let freqStr = fields[5].trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            guard !freqStr.isEmpty, let freqMHz = Double(freqStr) else { continue }

            let freqType = type.lowercased()
            if freqType.contains("ctaf") || freqType.contains("unicom") || freqType.contains("multicom") {
                let ctaf = CTAFFrequency(
                    frequency: freqMHz,
                    type: freqType,
                    description: fields.count > 4 ? fields[4].trimmingCharacters(in: CharacterSet(charactersIn: "\"")) : ""
                )
                result[airportIdent, default: []].append(ctaf)
            }
        }

        await MainActor.run { self.ctafParseProgress = 1.0 }
        return result
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
           Date().timeIntervalSince(cached.timestamp) < updateInterval,
           !cached.airspaces.isEmpty {   // older builds could cache an empty list
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
// MARK: - FAA ADDS layers

enum FAAAirspaceLayer {
    case classAirspace, specialUse

    var queryURL: String {
        let base = "https://services6.arcgis.com/ssFJjBXIUyZDrSYZ/arcgis/rest/services"
        switch self {
        case .classAirspace: return "\(base)/Class_Airspace/FeatureServer/0/query"
        case .specialUse: return "\(base)/Special_Use_Airspace/FeatureServer/0/query"
        }
    }
}

/// Parses FAA ADDS GeoJSON into `Airspace`, with the same rules as scripts/build_airspace_snapshot.py.
enum FAAAirspaceParser {
    struct Page {
        let airspaces: [Airspace]
        let featureCount: Int
        let exceededTransferLimit: Bool
    }

    private struct FeatureCollection: Decodable {
        let features: [Feature]
        let exceededTransferLimit: Bool?
        let properties: Extra?
        struct Extra: Decodable { let exceededTransferLimit: Bool? }
    }

    private struct Feature: Decodable {
        let properties: [String: Value]
        let geometry: Geometry?
    }

    /// Only the outer ring of each polygon is kept (the map draws outlines).
    private struct Geometry: Decodable {
        let rings: [[Coordinate2D]]
        enum CodingKeys: String, CodingKey { case type, coordinates }
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            let type = try c.decode(String.self, forKey: .type)
            let polygons: [[[[Double]]]]
            switch type {
            case "Polygon": polygons = [try c.decode([[[Double]]].self, forKey: .coordinates)]
            case "MultiPolygon": polygons = try c.decode([[[[Double]]]].self, forKey: .coordinates)
            default: polygons = []
            }
            rings = polygons.compactMap { polygon in
                polygon.first.map { ring in
                    ring.compactMap { p in
                        p.count >= 2 ? Coordinate2D(CLLocationCoordinate2D(latitude: p[1], longitude: p[0])) : nil
                    }
                }
            }
        }
    }

    /// ArcGIS attribute values are strings, numbers or null.
    enum Value: Decodable {
        case string(String), number(Double), null
        init(from decoder: Decoder) throws {
            let c = try decoder.singleValueContainer()
            if c.decodeNil() { self = .null }
            else if let d = try? c.decode(Double.self) { self = .number(d) }
            else if let s = try? c.decode(String.self) { self = .string(s) }
            else { self = .null }
        }
        var string: String? {
            switch self {
            case .string(let s): return s.trimmingCharacters(in: .whitespaces).isEmpty ? nil : s.trimmingCharacters(in: .whitespaces)
            case .number(let d): return d == d.rounded() ? String(Int(d)) : String(d)
            case .null: return nil
            }
        }
        var number: Double? {
            switch self {
            case .number(let d): return d
            case .string(let s): return Double(s.trimmingCharacters(in: .whitespaces))
            case .null: return nil
            }
        }
    }

    private static let suaTypes: [String: SUAType] = [
        "R": .restricted, "P": .prohibited, "MOA": .moa, "M": .moa, "W": .warning,
        "A": .alert, "D": .warning, "NSA": .nationalSecurity
    ]

    static func parse(_ data: Data, layer: FAAAirspaceLayer) throws -> Page {
        let collection = try JSONDecoder().decode(FeatureCollection.self, from: data)
        var out: [Airspace] = []
        for (index, feature) in collection.features.enumerated() {
            if let a = airspace(from: feature, layer: layer, index: index) { out.append(a) }
        }
        let exceeded = collection.exceededTransferLimit ?? collection.properties?.exceededTransferLimit ?? false
        return Page(airspaces: out, featureCount: collection.features.count, exceededTransferLimit: exceeded)
    }

    private static func airspace(from feature: Feature, layer: FAAAirspaceLayer, index: Int) -> Airspace? {
        let p = feature.properties
        guard let rings = feature.geometry?.rings.filter({ $0.count >= 3 }), !rings.isEmpty else { return nil }
        let objectId = p["OBJECTID"]?.string ?? String(index)
        let name = p["NAME"]?.string ?? ""

        let type: Airspace.AirspaceType
        let id: String
        switch layer {
        case .classAirspace:
            let cls = (p["CLASS"]?.string ?? "").uppercased()
            let local = (p["LOCAL_TYPE"]?.string ?? "").uppercased()
            if let c = AirspaceClass(rawValue: cls), ["B", "C", "D"].contains(cls) {
                type = .classAirspace(c)
            } else if local == "CLASS_E2" {
                type = .classESurface
            } else {
                return nil
            }
            id = "\(p["IDENT"]?.string ?? "CLASS")_\(cls.isEmpty ? "E2" : cls)_\(objectId)"
        case .specialUse:
            guard let sua = suaTypes[(p["TYPE_CODE"]?.string ?? "").uppercased()] else { return nil }
            type = .sua(sua)
            id = "SUA_\(name.replacingOccurrences(of: " ", with: "_"))_\(objectId)"
        }

        return Airspace(
            id: id,
            name: name.isEmpty ? id : name,
            type: type,
            polygons: rings,
            floor: altitude(p, prefix: "LOWER", default: 0),
            ceiling: altitude(p, prefix: "UPPER", default: 17999),
            controllingAgency: p["CONT_AGENT"]?.string,
            frequency: nil,
            isActive: true,
            schedule: p["TIMESOFUSE"]?.string ?? p["WKHR_RMK"]?.string
        )
    }

    /// FAA ADDS altitudes: *_VAL + *_UOM (FT/FL) + *_CODE (SFC/MSL/AGL). Negative values mean "below FL180".
    static func altitude(_ p: [String: Value], prefix: String, default fallback: Int) -> Int {
        guard let value = p["\(prefix)_VAL"]?.number else { return fallback }
        if (p["\(prefix)_CODE"]?.string ?? "").uppercased() == "SFC" { return 0 }
        if value < 0 { return 17999 }
        return (p["\(prefix)_UOM"]?.string ?? "").uppercased() == "FL" ? Int(value * 100) : Int(value)
    }
}

// MARK: - TFRs (tfr.faa.gov, no key)

extension AirspaceDataManager {
    /// Current and upcoming Florida TFRs from tfr.faa.gov. A failed download keeps the previous list.
    func refreshTFRs() async {
        guard let listURL = URL(string: "https://tfr.faa.gov/tfrapi/exportTfrList"),
              let data = try? await NetCache.data(from: listURL),
              let list = try? JSONDecoder().decode([TFRListItem].self, from: data) else { return }
        var result: [Airspace] = []
        await withTaskGroup(of: Airspace?.self) { group in
            for item in list where item.state == "FL" {
                group.addTask {
                    let file = item.notam_id.replacingOccurrences(of: "/", with: "_")
                    guard let url = URL(string: "https://tfr.faa.gov/download/detail_\(file).xml"),
                          let xml = try? await NetCache.data(from: url) else { return nil }
                    return TFRParser.parse(xml, id: item.notam_id, type: item.type)
                }
            }
            for await tfr in group { if let tfr { result.append(tfr) } }
        }
        tfrs = result.sorted { $0.id < $1.id }
    }

    /// Base airspace plus TFRs: what the map, warnings and routing work on.
    var allAirspaces: [Airspace] { airspaces + tfrs }
}

struct TFRListItem: Decodable {
    let notam_id: String
    let type: String
    let state: String
}

/// Reads the shape, altitudes and dates out of a tfr.faa.gov XNOTAM file.
final class TFRParser: NSObject, XMLParserDelegate {
    private var text = ""
    private var values: [String: String] = [:]        // first value of each tag in the file
    private var inMerged = false, inAbd = false, inAvx = false
    private var avx: [String: String] = [:]
    private var merged: [[Coordinate2D]] = [], abd: [[Coordinate2D]] = [], ring: [Coordinate2D] = []

    static func parse(_ data: Data, id: String, type: String) -> Airspace? {
        let delegate = TFRParser()
        let parser = XMLParser(data: data)
        parser.delegate = delegate
        guard parser.parse() else { return nil }
        let rings = (delegate.merged.isEmpty ? delegate.abd : delegate.merged).filter { $0.count >= 3 }
        guard !rings.isEmpty else { return nil }
        let v = delegate.values
        func altitude(_ which: String, _ fallback: Int) -> Int {
            guard let value = Double(v["valDistVer\(which)"] ?? "") else { return fallback }
            return v["uomDistVer\(which)"] == "FL" ? Int(value * 100) : Int(value)
        }
        let start = (v["dateEffective"] ?? "").replacingOccurrences(of: "T", with: " ").prefix(16)
        let end = (v["dateExpire"] ?? "").replacingOccurrences(of: "T", with: " ").prefix(16)
        let tz = v["codeTimeZone"] ?? ""
        return Airspace(
            id: "TFR_\(id)",
            name: "TFR \(id) \(v["txtNameCity"] ?? v["txtLocalName"] ?? "")".trimmingCharacters(in: .whitespaces),
            type: .sua(.tf),
            polygons: rings,
            floor: altitude("Lower", 0),
            ceiling: altitude("Upper", 17999),
            controllingAgency: v["codeFacility"],
            frequency: nil,
            isActive: true,
            schedule: "\(type.capitalized) · \(start) → \(end.isEmpty ? "?" : String(end)) \(tz)"
        )
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        text = ""
        switch name {
        case "abdMergedArea": inMerged = true; ring = []
        case "Abd": inAbd = true; ring = []
        case "Avx": inAvx = true; avx = [:]
        default: break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) { text += string }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        switch name {
        case "abdMergedArea": inMerged = false; merged.append(ring)
        case "Abd": inAbd = false; abd.append(ring)
        case "Avx":
            inAvx = false
            guard inMerged || inAbd, let lat = Self.degrees(avx["geoLat"]), let lon = Self.degrees(avx["geoLong"]) else { return }
            let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            if avx["codeType"] == "CIR", let r = Double(avx["valRadiusArc"] ?? "") {
                let nm = avx["uomRadiusArc"] == "KM" ? r / 1.852 : r
                ring += (0..<36).map { Coordinate2D(Haversine.destination(from: center, course: $0 * 10, distanceNM: nm)) }
            } else {
                // ponytail: arcs (CWA/CCA) reduced to their start point; fine for TFR outlines, sample the arc if one looks wrong.
                ring.append(Coordinate2D(center))
            }
        default:
            // Inside a vertex keep the first lat/long only (nested Frd/DpnUid repeat them for a reference fix).
            if inAvx { if avx[name] == nil { avx[name] = value } }
            else if values[name] == nil, !value.isEmpty { values[name] = value }
        }
    }

    /// "26.67694444N" / "080.03777778W" → signed degrees.
    static func degrees(_ s: String?) -> Double? {
        guard let s, let hemi = s.last, let v = Double(s.dropLast()) else { return nil }
        return hemi == "S" || hemi == "W" ? -v : v
    }
}
