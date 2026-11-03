import SwiftUI
import MapKit

/// On-disk tile store shared by the map and the region downloader (Caches/tiles/<host path>).
/// ponytail: no size cap, iOS purges Caches under storage pressure; add LRU eviction if it grows too much.
enum TileCache {
    static let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("tiles")

    static func file(for url: URL) -> URL {
        root.appendingPathComponent(url.path.replacingOccurrences(of: "/arcgis/rest/services/", with: "/"))
    }

    static func store(_ data: Data, at file: URL) {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file)
    }

    static func sizeMB() -> Double {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey])
        var bytes = 0
        while let f = files?.nextObject() as? URL { bytes += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return Double(bytes) / 1_048_576
    }

    static func clear() { try? FileManager.default.removeItem(at: root) }
}

/// Downloads the chart tiles of a region (zoom 5 to 11) so the map works without network.
@MainActor
final class OfflineDownloader: ObservableObject {
    static let shared = OfflineDownloader()
    @Published private(set) var progress: Double?
    @Published private(set) var sizeMB = TileCache.sizeMB()

    /// Tile x/y/z covering `region` at each zoom.
    nonisolated static func tiles(for region: MKCoordinateRegion, zooms: ClosedRange<Int>) -> [(Int, Int, Int)] {
        func x(_ lon: Double, _ z: Int) -> Int { Int((lon + 180) / 360 * Double(1 << z)) }
        func y(_ lat: Double, _ z: Int) -> Int {
            let r = lat * .pi / 180
            return Int((1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * Double(1 << z))
        }
        let minLat = region.center.latitude - region.span.latitudeDelta / 2, maxLat = region.center.latitude + region.span.latitudeDelta / 2
        let minLon = region.center.longitude - region.span.longitudeDelta / 2, maxLon = region.center.longitude + region.span.longitudeDelta / 2
        return zooms.flatMap { z in
            (x(minLon, z)...x(maxLon, z)).flatMap { tx in (y(maxLat, z)...y(minLat, z)).map { (tx, $0, z) } }
        }
    }

    func download(region: MKCoordinateRegion, chart: String) async {
        guard progress == nil else { return }
        let all = Self.tiles(for: region, zooms: 5...11)
        progress = 0
        var done = 0
        await withTaskGroup(of: Void.self) { group in
            var it = all.makeIterator()
            func next() -> Bool {
                guard let (x, y, z) = it.next() else { return false }
                group.addTask {
                    let url = URL(string: "https://tiles.arcgis.com/tiles/ssFJjBXIUyZDrSYZ/arcgis/rest/services/\(chart)/MapServer/tile/\(z)/\(y)/\(x)")!
                    let file = TileCache.file(for: url)
                    guard !FileManager.default.fileExists(atPath: file.path),
                          let (data, response) = try? await URLSession.shared.data(from: url),
                          (response as? HTTPURLResponse)?.statusCode == 200 else { return }
                    TileCache.store(data, at: file)
                }
                return true
            }
            for _ in 0..<8 { _ = next() }   // 8 downloads at a time
            while await group.next() != nil {
                done += 1
                progress = Double(done) / Double(all.count)
                _ = next()
            }
        }
        progress = nil
        sizeMB = TileCache.sizeMB()
    }

    func clear() { TileCache.clear(); sizeMB = 0 }
}

/// Layers panel section: prepare a flight (or all Florida) for offline use, see and clear the stores.
struct OfflineChartsSection: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore
    @ObservedObject private var downloader = OfflineDownloader.shared
    @ObservedObject private var preparer = OfflinePreparer.shared
    @ObservedObject private var offline = OfflineState.shared
    @State private var dataMB = NetCache.sizeMB()

    var body: some View {
        Section {
            if let since = offline.showingCacheFrom {
                Label(since == .distantPast ? "Hors ligne" : "Hors ligne · données du \(since.frDateTime)",
                      systemImage: "wifi.slash")
                    .foregroundStyle(ColorToken.warning)
            }
            if let step = preparer.step {
                ProgressView(value: downloader.progress ?? preparer.progress) { Text("Préparation : \(step)…") }
            } else if let p = downloader.progress {
                ProgressView(value: p) { Text("Téléchargement… \(Int(p * 100)) %") }
            } else {
                Button(model.waypoints.count >= 2 ? "Préparer ce vol hors ligne" : "Préparer la zone hors ligne",
                       systemImage: "airplane.circle") {
                    Task { await preparer.prepare(model: model, store: store, wholeFlorida: false); dataMB = NetCache.sizeMB() }
                }
                Button("Tout télécharger : Floride entière", systemImage: "map") {
                    Task { await preparer.prepare(model: model, store: store, wholeFlorida: true); dataMB = NetCache.sizeMB() }
                }
                let count = OfflineDownloader.tiles(for: model.mapRegion, zooms: 5...11).count
                Button("Cartes de la zone affichée (\(count) tuiles)", systemImage: "arrow.down.circle") {
                    Task { await downloader.download(region: model.mapRegion, chart: model.mapChart) }
                }
                .disabled(count > 20_000)
                if count > 20_000 { Text("Zoome un peu : zone trop grande.").font(.caption).foregroundStyle(.secondary) }
            }
            if let report = preparer.lastReport, let at = preparer.preparedAt {
                Text("\(report) (\(at.frDateTime))").font(.caption).foregroundStyle(.secondary)
            }
            LabeledContent("Cartes hors ligne", value: String(format: "%.0f Mo", downloader.sizeMB))
            LabeledContent("Météo, NOTAM, plaques", value: String(format: "%.0f Mo", dataMB + FAADocuments.cacheMB()))
            Button("Effacer les données hors ligne", role: .destructive) {
                downloader.clear(); NetCache.clear(); dataMB = 0
            }
        } header: {
            FFHeader("Hors ligne")
        } footer: {
            Text("« Préparer » enregistre les cartes (Sectional et carte choisie, zoom 5 à 11) de la route ou de la Floride, la météo (METAR, TAF, vents, AIRMET, PIREP), les NOTAM et TFR, les plaques et diagrammes des terrains de la route et les prix carburant. Sans réseau, l'app affiche automatiquement ces dernières données, et la météo FIS-B du récepteur ADS-B en vol.")
        }
    }
}
