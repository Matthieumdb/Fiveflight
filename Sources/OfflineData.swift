import Foundation
import CryptoKit
import MapKit

/// Disk copy of every data answer (METAR, TAF, winds, AIRMET, PIREP, NOTAM, TFR, plate lists, fuel
/// prices…): network first, and the last good copy when there is no network, so the whole app keeps
/// working offline with the data of the last connection.
enum NetCache {
    static let root = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("net", isDirectory: true)

    struct Result {
        let data: Data
        /// Nil when fresh from the network, else when the cached copy was saved.
        let cachedAt: Date?
    }

    static func file(for request: URLRequest) -> URL {
        var bytes = Data((request.httpMethod ?? "GET").utf8)
        bytes.append(Data((request.url?.absoluteString ?? "").utf8))
        if let body = request.httpBody { bytes.append(body) }
        let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash)
    }

    /// The saved copy, if any, with its date.
    static func cached(_ request: URLRequest) -> Result? {
        let f = file(for: request)
        guard let data = try? Data(contentsOf: f), !data.isEmpty else { return nil }
        let date = (try? f.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
        return Result(data: data, cachedAt: date)
    }

    static func fetch(_ request: URLRequest) async throws -> Result {
        var req = request
        if req.timeoutInterval > 25 { req.timeoutInterval = 25 }
        do {
            // Unstructured task: a SwiftUI view that re-renders or a pull-to-refresh that ends must not
            // cancel the download half-way (URLError -999), which left lists such as PIREPs empty.
            let sent = req
            let (data, response) = try await Task { try await URLSession.shared.data(for: sent) }.value
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                throw URLError(.badServerResponse)
            }
            if !data.isEmpty {
                try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
                try? data.write(to: file(for: request), options: .atomic)
            }
            await OfflineState.shared.online()
            return Result(data: data, cachedAt: nil)
        } catch {
            // Only a real loss of network means "offline"; a cancelled request or a server error does not.
            let offline = isNetworkLoss(error)
            if let hit = cached(request) {
                if offline { await OfflineState.shared.servedFromCache(hit.cachedAt ?? .distantPast) }
                return hit
            }
            if offline { await OfflineState.shared.failed() }
            throw error
        }
    }

    static func isNetworkLoss(_ error: Error) -> Bool {
        guard let e = error as? URLError else { return false }
        switch e.code {
        case .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost, .cannotConnectToHost,
             .dnsLookupFailed, .dataNotAllowed, .internationalRoamingOff, .callIsActive:
            return true
        default:
            return false
        }
    }

    static func data(from url: URL) async throws -> Data {
        try await fetch(URLRequest(url: url)).data
    }

    static func sizeMB() -> Double {
        let files = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.fileSizeKey])
        var bytes = 0
        while let f = files?.nextObject() as? URL { bytes += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return Double(bytes) / 1_048_576
    }

    static func clear() { try? FileManager.default.removeItem(at: root) }
}

/// Whether the app is currently showing saved data instead of live data.
@MainActor
final class OfflineState: ObservableObject {
    static let shared = OfflineState()
    /// Date of the oldest saved copy shown since the network was last reachable; nil when online.
    @Published private(set) var showingCacheFrom: Date?
    @Published private(set) var lastOnline: Date? = UserDefaults.standard.object(forKey: "lastOnline") as? Date

    func online() {
        showingCacheFrom = nil
        lastOnline = .now
        UserDefaults.standard.set(lastOnline, forKey: "lastOnline")
    }

    func servedFromCache(_ date: Date) {
        showingCacheFrom = min(showingCacheFrom ?? date, date)
    }

    func failed() {
        if showingCacheFrom == nil { showingCacheFrom = lastOnline ?? .distantPast }
    }
}

// MARK: - Prepare a flight for offline use

/// One tap before leaving the Wi-Fi: chart tiles over Florida or along the route, weather, NOTAMs,
/// TFRs, plates and diagrams of the route airports, fuel prices. Everything lands in the caches above.
@MainActor
final class OfflinePreparer: ObservableObject {
    static let shared = OfflinePreparer()
    @Published private(set) var step: String?
    @Published private(set) var progress: Double = 0
    @Published private(set) var lastReport: String?
    @Published private(set) var preparedAt: Date? = UserDefaults.standard.object(forKey: "offlinePreparedAt") as? Date

    /// Florida plus a margin (the whole VFR area of the app).
    static let florida = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 27.7, longitude: -83.75),
                                            span: MKCoordinateSpan(latitudeDelta: 7.0, longitudeDelta: 8.1))

    /// Region around the route (or Florida when there is no route), with a 0.4° margin.
    static func region(for waypoints: [Airport]) -> MKCoordinateRegion {
        guard waypoints.count >= 2 else { return florida }
        let lats = waypoints.map(\.coordinate.latitude), lons = waypoints.map(\.coordinate.longitude)
        let minLat = lats.min()! - 0.4, maxLat = lats.max()! + 0.4, minLon = lons.min()! - 0.4, maxLon = lons.max()! + 0.4
        return MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2),
                                  span: MKCoordinateSpan(latitudeDelta: maxLat - minLat, longitudeDelta: maxLon - minLon))
    }

    func prepare(model: AppModel, store: AirportStore, wholeFlorida: Bool) async {
        guard step == nil else { return }
        var failures: [String] = []
        let route = model.waypoints.filter(\.isAirport)
        let around = wholeFlorida
            ? store.airports.filter { ["large_airport", "medium_airport", "small_airport"].contains($0.type)
                && FloridaArea.contains(lat: $0.coordinate.latitude, lon: $0.coordinate.longitude) }
            : store.nearest(to: route.first?.coordinate ?? model.mapRegion.center, limit: 40,
                            matching: ["large_airport", "medium_airport", "small_airport"])
        let weatherIds = Array(Set((route + around).map { $0.icao ?? $0.id }))
            .filter { $0.count == 4 && $0.hasPrefix("K") }
            .sorted()

        step = "Cartes"; progress = 0.05
        var region = wholeFlorida ? Self.florida
            : model.waypoints.count >= 2 ? Self.region(for: model.waypoints) : model.mapRegion
        if OfflineDownloader.tiles(for: region, zooms: 5...11).count > 20_000 { region = Self.florida }
        for chart in Set([model.mapChart, MapChart.sectional.rawValue]) {
            await OfflineDownloader.shared.download(region: region, chart: chart)
        }

        step = "Météo"; progress = 0.55
        let wx = WeatherService.shared
        for chunk in weatherIds.chunked(into: 50) {
            await wx.fetchMETARs(for: chunk)
            await wx.fetchTAFs(for: chunk)
        }
        _ = await wx.fetchAllWindPeriods()
        await wx.fetchPIREPs()
        await wx.fetchAIRMETs()
        if wx.metars.isEmpty { failures.append("météo") }

        step = "NOTAM et TFR"; progress = 0.7
        let routeIds = route.map { $0.icao ?? $0.id }
        let notams = await NOTAMService.fetch(locations: routeIds)
        if !notams.failed.isEmpty { failures.append("NOTAM " + notams.failed.joined(separator: ", ")) }
        await AirspaceDataManager.shared.refreshTFRs()

        step = "Plaques et diagrammes"; progress = 0.8
        for a in route {
            let docs = await FAADocuments.chartSupplement(for: a.id) + FAADocuments.plates(for: a.id)
            for d in docs where d.title.localizedCaseInsensitiveContains("diagram")
                || d.title.localizedCaseInsensitiveContains("supplement") || route.count <= 3 {
                _ = try? await FAADocuments.localFile(for: d.url)
            }
        }

        step = "Prix carburant"; progress = 0.92
        for a in route { _ = await FuelPriceService.shared.refresh(a) }

        progress = 1
        step = nil
        preparedAt = .now
        UserDefaults.standard.set(preparedAt, forKey: "offlinePreparedAt")
        lastReport = failures.isEmpty ? "Vol prêt hors ligne." : "Prêt, sauf : " + failures.joined(separator: " · ")
    }
}
