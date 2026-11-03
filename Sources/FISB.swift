import Foundation
import MapKit
import SwiftUI

/// FIS-B (free in-flight weather over ADS-B 978 MHz), received through the GDL 90 Uplink Data
/// message (0x07) of a Stratux, Sentry, SkyEcho… Decodes text products (METAR, TAF, PIREP, winds,
/// SIGMET/AIRMET text, NOTAM) and NEXRAD radar blocks (regional and CONUS). Layout from RTCA DO-358
/// as implemented by the open-source dump978 / Stratux decoders.
enum FISB {
    /// One decoded text report.
    struct TextReport: Identifiable, Hashable {
        var id: String { kind + " " + location + " " + text.prefix(40) }
        let kind: String        // METAR, SPECI, TAF, PIREP, WINDS, SIGMET, AIRMET, NOTAM…
        let location: String    // ICAO when present
        let text: String
        let received: Date
    }

    /// 4 rows × 32 bins of radar intensity (0…7), with the block's top-left corner and size.
    struct NexradBlock {
        let key: Int
        let conus: Bool
        let north: Double, west: Double, latSize: Double, lonSize: Double
        let bins: [UInt8]
        let received: Date
    }

    enum Product {
        case text([TextReport])
        case nexrad(NexradBlock?, clearedKey: Int?)
    }

    // MARK: Uplink frame

    /// `payload` = the 432-byte UAT uplink (8-byte header + 424 bytes of application data).
    static func decodeUplink(_ payload: [UInt8]) -> [Product] {
        guard payload.count >= 432, payload[6] & 0x20 != 0 else { return [] }   // application data valid
        let app = Array(payload[8..<432])
        var out: [Product] = []
        var pos = 0
        while pos + 2 <= app.count {
            let length = Int(app[pos]) << 1 | Int(app[pos + 1]) >> 7
            let type = app[pos + 1] & 0x0F
            if length == 0 { break }                     // padding
            guard pos + 2 + length <= app.count else { break }
            if type == 0 { out += decodeAPDU(Array(app[(pos + 2)..<(pos + 2 + length)])) }
            pos += 2 + length
        }
        return out
    }

    /// FIS-B APDU: product id, time, then the product payload.
    static func decodeAPDU(_ d: [UInt8]) -> [Product] {
        guard d.count >= 4 else { return [] }
        let product = Int(d[0] & 0x1F) << 6 | Int(d[1]) >> 2
        let segmented = d[1] & 0x02 != 0
        let timeOption = Int(d[1] & 0x01) << 1 | Int(d[2]) >> 7
        let header: Int
        switch timeOption {
        case 0: header = 4
        case 1, 2: header = 5
        default: header = 6
        }
        guard !segmented, d.count > header else { return [] }   // segmented products are rare (long NOTAMs)
        let body = Array(d[header...])
        switch product {
        case 413: return [.text(textReports(dlac(body)))]
        case 63, 64: return [nexrad(body, conus: product == 64)]
        case 8, 11, 12: return twgoText(body, product: product).map { [.text($0)] } ?? []
        default: return []
        }
    }

    // MARK: Text (DLAC 6-bit)

    private static let alphabet: [Character] = Array("\u{03}ABCDEFGHIJKLMNOPQRSTUVWXYZ\u{1A}\t\u{1E}\n| !\"#$%&'()*+,-./0123456789:;<=>?")

    /// DLAC: 4 six-bit characters per 3 bytes; a TAB is followed by a count of spaces.
    static func dlac(_ d: [UInt8]) -> String {
        var out = ""
        var tab = false
        var i = 0, step = 0
        while i < d.count {
            let ch: Int
            switch step {
            case 0: ch = Int(d[i] >> 2)
            case 1:
                guard i + 1 < d.count else { return out }
                ch = Int(d[i] & 0x03) << 4 | Int(d[i + 1] >> 4); i += 1
            case 2:
                guard i + 1 < d.count else { return out }
                ch = Int(d[i] & 0x0F) << 2 | Int(d[i + 1] >> 6); i += 1
            default: ch = Int(d[i] & 0x3F); i += 1
            }
            step = (step + 1) % 4
            if tab {
                out += String(repeating: " ", count: ch)
                tab = false
            } else if ch == 28 {
                tab = true
            } else {
                out.append(alphabet[ch])
            }
        }
        return out
    }

    /// Splits product 413 text into reports ("METAR KFPR 031553Z …", "TAF KVRB …").
    static func textReports(_ text: String, received: Date = .now) -> [TextReport] {
        text.split(whereSeparator: { $0 == "\u{1E}" || $0 == "\u{03}" }).compactMap { raw in
            let t = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            let words = t.split(separator: " ", maxSplits: 2)
            guard words.count >= 2 else { return nil }
            var kind = String(words[0])
            if kind.hasPrefix("TAF") { kind = "TAF" }
            var location = String(words[1])
            if location.count == 3, location.allSatisfy({ $0.isLetter || $0.isNumber }) { location = "K" + location }
            let body = words.count > 2 ? String(words[2]) : ""
            return TextReport(kind: kind, location: location, text: kind + " " + location + " " + body, received: received)
        }
    }

    /// Text record of a TWGO product (8 = NOTAM-TFR, 11 = AIRMET, 12 = SIGMET); graphics are ignored.
    static func twgoText(_ d: [UInt8], product: Int) -> [TextReport]? {
        guard d.count >= 11, (d[0] & 0xF0) >> 4 == 2 else { return nil }
        let location = dlac(Array(d[2..<5])).trimmingCharacters(in: .whitespaces.union(.controlCharacters))
        let recordLength = Int(d[6]) << 8 | Int(d[7])
        guard recordLength > 5 else { return nil }
        let end = min(d.count, 11 + recordLength - 5)
        let text = dlac(Array(d[11..<end])).trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters))
        guard !text.isEmpty else { return nil }
        let kind = product == 8 ? "NOTAM" : product == 11 ? "AIRMET" : "SIGMET"
        let loc = location.count == 3 ? "K" + location : location
        return [TextReport(kind: kind, location: loc, text: text, received: .now)]
    }

    // MARK: NEXRAD

    static let blockWidth = 48.0 / 60, wideBlockWidth = 96.0 / 60, blockHeight = 4.0 / 60
    static let blockThreshold = 405_000, blocksPerRing = 450

    static func nexrad(_ d: [UInt8], conus: Bool) -> Product {
        guard d.count >= 4 else { return .nexrad(nil, clearedKey: nil) }
        let rle = d[0] & 0x80 != 0
        let south = d[0] & 0x40 != 0
        var block = Int(d[0] & 0x0F) << 16 | Int(d[1]) << 8 | Int(d[2])
        let scale = Int(d[0] & 0x30) >> 4
        let key = (conus ? 1 << 24 : 0) | (south ? 1 << 23 : 0) | block
        guard rle else { return .nexrad(nil, clearedKey: key) }   // "empty" block list: no echoes there
        var bins: [UInt8] = []
        for b in d[3...] {
            let run = Int(b >> 3) + 1
            bins += Array(repeating: b & 0x07, count: run)
            if bins.count >= 128 { break }
        }
        guard bins.count >= 128 else { return .nexrad(nil, clearedKey: nil) }
        let realScale = scale == 1 ? 5.0 : scale == 2 ? 9.0 : 1.0
        if block >= blockThreshold { block &= ~1 }
        var lat = blockHeight * Double(block / blocksPerRing)
        var lon = Double(block % blocksPerRing) * blockWidth
        let lonSize = (block >= blockThreshold ? wideBlockWidth : blockWidth) * realScale
        let latSize = blockHeight * realScale
        lat = south ? -lat : lat + blockHeight
        if lon > 180 { lon -= 360 }
        return .nexrad(NexradBlock(key: key, conus: conus, north: lat, west: lon, latSize: latSize, lonSize: lonSize,
                                   bins: Array(bins.prefix(128)), received: .now), clearedKey: nil)
    }

    static func color(_ level: UInt8) -> UIColor? {
        switch level {
        case 1: return UIColor(red: 0.30, green: 0.80, blue: 0.30, alpha: 0.35)
        case 2: return UIColor(red: 0.10, green: 0.75, blue: 0.10, alpha: 0.7)
        case 3: return UIColor(red: 0.05, green: 0.55, blue: 0.05, alpha: 0.75)
        case 4: return UIColor(red: 1.00, green: 0.90, blue: 0.00, alpha: 0.8)
        case 5: return UIColor(red: 1.00, green: 0.55, blue: 0.00, alpha: 0.85)
        case 6: return UIColor(red: 0.95, green: 0.10, blue: 0.10, alpha: 0.85)
        case 7: return UIColor(red: 0.80, green: 0.10, blue: 0.80, alpha: 0.9)
        default: return nil
        }
    }
}

/// Thread-safe radar grid read by the map tile renderer.
final class NexradGrid: @unchecked Sendable {
    static let shared = NexradGrid()
    private let lock = NSLock()
    private var blocks: [Int: FISB.NexradBlock] = [:]

    func update(_ block: FISB.NexradBlock?, cleared: Int?) {
        lock.lock(); defer { lock.unlock() }
        if let block { blocks[block.key] = block }
        if let cleared { blocks[cleared] = nil }
        if blocks.count > 4000 || Int.random(in: 0..<50) == 0 {
            blocks = blocks.filter { Date.now.timeIntervalSince($0.value.received) < 1800 }
        }
    }

    func snapshot() -> [FISB.NexradBlock] {
        lock.lock(); defer { lock.unlock() }
        return blocks.values.filter { Date.now.timeIntervalSince($0.received) < 1800 }
    }

    var isEmpty: Bool { lock.lock(); defer { lock.unlock() }; return blocks.isEmpty }
    func clear() { lock.lock(); blocks = [:]; lock.unlock() }
}

/// FIS-B radar drawn as map tiles from the received blocks (no internet needed).
final class FISBRadarOverlay: WeatherTileOverlay {
    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        let n = Double(1 << path.z)
        func lon(_ x: Int) -> Double { Double(x) / n * 360 - 180 }
        func lat(_ y: Int) -> Double { atan(sinh(.pi * (1 - 2 * Double(y) / n))) * 180 / .pi }
        let west = lon(path.x), east = lon(path.x + 1), north = lat(path.y), south = lat(path.y + 1)
        let size = tileSize
        func px(_ lo: Double) -> CGFloat { CGFloat((lo - west) / (east - west)) * size.width }
        func mercY(_ la: Double) -> Double { log(tan(.pi / 4 + la * .pi / 360)) }
        func py(_ la: Double) -> CGFloat { CGFloat((mercY(north) - mercY(la)) / (mercY(north) - mercY(south))) * size.height }
        let blocks = NexradGrid.shared.snapshot()
            .filter { $0.west < east && $0.west + $0.lonSize > west && $0.north > south && $0.north - $0.latSize < north }
            .sorted { $0.conus && !$1.conus }   // regional (finer) drawn last, on top
        guard !blocks.isEmpty else { result(nil, nil); return }
        let image = UIGraphicsImageRenderer(size: size).image { ctx in
            for b in blocks {
                let binW = b.lonSize / 32, binH = b.latSize / 4
                for row in 0..<4 {
                    for col in 0..<32 {
                        guard let c = FISB.color(b.bins[row * 32 + col]) else { continue }
                        let lo = b.west + Double(col) * binW, la = b.north - Double(row) * binH
                        let rect = CGRect(x: px(lo), y: py(la), width: px(lo + binW) - px(lo) + 0.5,
                                          height: py(la - binH) - py(la) + 0.5)
                        ctx.cgContext.setFillColor(c.cgColor)
                        ctx.cgContext.fill(rect)
                    }
                }
            }
        }
        result(image.pngData(), nil)
    }
}

/// Everything received over FIS-B, for the map, the airport sheet and the weather screen.
@MainActor
final class FISBStore: ObservableObject {
    static let shared = FISBStore()
    @Published private(set) var reports: [String: FISB.TextReport] = [:]   // newest per kind+location
    @Published private(set) var lastUplink: Date?
    /// Bumped (at most every 20 s) when radar blocks arrive, so the map redraws its FIS-B radar layer.
    @Published private(set) var radarVersion = 0
    private var lastRadarBump = Date.distantPast
    private var radarDirty = false

    func ingest(_ payload: [UInt8]) {
        lastUplink = .now
        for product in FISB.decodeUplink(payload) {
            switch product {
            case .text(let list):
                for r in list { handle(r) }
            case .nexrad(let block, let cleared):
                NexradGrid.shared.update(block, cleared: cleared)
                radarDirty = true
            }
        }
        if radarDirty, Date.now.timeIntervalSince(lastRadarBump) > 20 {
            radarDirty = false
            lastRadarBump = .now
            radarVersion += 1
        }
    }

    private func handle(_ r: FISB.TextReport) {
        let key = r.kind == "NOTAM" ? "NOTAM \(r.location) \(r.text.prefix(30))" : "\(r.kind) \(r.location)"
        reports[key] = r
        if (r.kind == "METAR" || r.kind == "SPECI"), let metar = RawMETAR.parse(String(r.text.dropFirst(r.kind.count + 1))) {
            WeatherService.shared.store(metar, as: metar.station)
        }
        if reports.count > 3000 {
            reports = reports.filter { Date.now.timeIntervalSince($0.value.received) < 3 * 3600 }
        }
    }

    func list(_ kind: String) -> [FISB.TextReport] {
        reports.values.filter { $0.kind == kind }.sorted { $0.location < $1.location }
    }

    func report(_ kind: String, at location: String) -> FISB.TextReport? { reports["\(kind) \(location)"] }

    func notams(at location: String) -> [NOTAMService.NOTAM] {
        reports.values.filter { $0.kind == "NOTAM" && $0.location == location }.map {
            NOTAMService.NOTAM(id: "FISB \($0.id)", location: location, text: $0.text, start: "", end: "", keyword: "FIS-B")
        }
    }

    var connected: Bool { lastUplink.map { Date.now.timeIntervalSince($0) < 120 } ?? false }
}

/// Minimal raw METAR decoder (FIS-B gives the raw text only).
enum RawMETAR {
    static func parse(_ raw: String, now: Date = .now) -> METAR? {
        let text = raw.components(separatedBy: " RMK").first ?? raw
        let tokens = text.split(separator: " ").map(String.init)
        guard let station = tokens.first, station.count == 4 else { return nil }
        var wdir: FlexValue?, wspd: Double?, wgst: Double?, visib: FlexValue?, temp: Double?, dewp: Double?, altim: Double?
        var clouds: [METARResponse.CloudLayer] = []
        var obs: Date?
        var pendingWhole: String?
        func match(_ s: String, _ pattern: String) -> [String]? {
            guard let re = try? NSRegularExpression(pattern: "^" + pattern + "$"),
                  let m = re.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
            return (0..<m.numberOfRanges).map { Range(m.range(at: $0), in: s).map { String(s[$0]) } ?? "" }
        }
        for t in tokens.dropFirst() {
            if obs == nil, let m = match(t, #"(\d{2})(\d{2})(\d{2})Z"#) {
                var cal = Calendar(identifier: .gregorian); cal.timeZone = TimeZone(identifier: "UTC")!
                var c = cal.dateComponents([.year, .month], from: now)
                c.day = Int(m[1]); c.hour = Int(m[2]); c.minute = Int(m[3])
                if var d = cal.date(from: c) {
                    if d > now.addingTimeInterval(3600) { d = cal.date(byAdding: .month, value: -1, to: d) ?? d }
                    obs = d
                }
            } else if let m = match(t, #"(\d{3}|VRB)(\d{2,3})(?:G(\d{2,3}))?KT"#) {
                wdir = FlexValue(m[1]); wspd = Double(m[2]); wgst = Double(m[3])
            } else if t.allSatisfy(\.isNumber), t.count == 1 {
                pendingWhole = t
            } else if let m = match(t, #"(P|M)?(\d+(?:/\d+)?)SM"#) {
                visib = FlexValue((pendingWhole.map { $0 + " " } ?? "") + m[2])
                pendingWhole = nil
            } else if let m = match(t, #"(FEW|SCT|BKN|OVC|VV)(\d{3})\w*"#) {
                clouds.append(.init(cover: m[1], base: Double(m[2]).map { $0 * 100 }))
            } else if let m = match(t, #"(M?\d{2})/(M?\d{2})?"#) {
                func v(_ s: String) -> Double? { Double(s.replacingOccurrences(of: "M", with: "-")) }
                temp = v(m[1]); dewp = v(m[2])
            } else if let m = match(t, #"A(\d{4})"#), let a = Double(m[1]) {
                altim = a / 100 * 33.8639
            }
        }
        let response = METARResponse(icaoId: station, obsTime: (obs ?? now).timeIntervalSince1970, rawOb: raw,
                                     temp: temp, dewp: dewp, wdir: wdir, wspd: wspd, wgst: wgst, visib: visib,
                                     altim: altim, clouds: clouds, fltCat: nil, wxString: nil)
        return METAR(from: response)
    }
}

// MARK: - Views

/// FIS-B weather received in flight: status, METAR/TAF/PIREP/AIRMET/NOTAM text.
struct FISBWeatherScreen: View {
    @ObservedObject private var fisb = FISBStore.shared
    @State private var kind = "METAR"
    private let kinds = ["METAR", "TAF", "PIREP", "AIRMET", "SIGMET", "NOTAM", "WINDS"]

    var body: some View {
        List {
            Section {
                if let last = fisb.lastUplink {
                    Label("Dernière réception \(last.formatted(date: .omitted, time: .shortened))",
                          systemImage: fisb.connected ? "antenna.radiowaves.left.and.right" : "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(fisb.connected ? ColorToken.success : ColorToken.textTertiary)
                } else {
                    Label("Aucune donnée FIS-B reçue", systemImage: "antenna.radiowaves.left.and.right.slash")
                        .foregroundStyle(ColorToken.textTertiary)
                }
                Picker("Produit", selection: $kind) { ForEach(kinds, id: \.self) { Text($0).tag($0) } }
            } footer: {
                Text("Météo gratuite reçue en vol sur 978 MHz par un récepteur ADS-B (Stratux, Sentry, SkyEcho), sans internet. Les METAR reçus colorent aussi les terrains sur la carte ; le radar FIS-B s'active dans les couches.")
            }
            Section(kind) {
                let items = fisb.list(kind)
                if items.isEmpty { Text("Rien reçu pour l'instant").foregroundStyle(ColorToken.textTertiary) }
                ForEach(items) { r in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(r.location).font(.headline)
                        Text(r.text).font(.caption.monospaced()).textSelection(.enabled)
                        Text("Reçu \(r.received.formatted(date: .omitted, time: .shortened))")
                            .font(.caption2).foregroundStyle(ColorToken.textTertiary)
                    }
                }
            }
        }
        .navigationTitle("Météo ADS-B (FIS-B)")
    }
}
