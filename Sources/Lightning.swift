import Foundation
import MapKit

/// Lightning strike density (last 15 min, 8 km cells) from NOAA nowCOAST, a free public WMS fed by
/// the ground lightning networks. The layer name is read from the service's GetCapabilities, so a
/// rename on NOAA's side does not break the layer. When nowCOAST answers nothing, the community
/// Blitzortung network (lightningmaps.org tiles) is tried.
final class LightningTileOverlay: WeatherTileOverlay {
    static let service = "https://nowcoast.noaa.gov/geoserver/observations/lightning_detection/ows"

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        Task {
            let layers = await LightningLayers.shared.names()
            if let data = await Self.get(Self.wmsURL(path, layers: layers)) { result(data, nil); return }
            var fallback = URLRequest(url: URL(string: "https://tiles.lightningmaps.org/?x=\(path.x)&y=\(path.y)&z=\(path.z)&s=256&t=5")!)
            fallback.setValue("https://www.lightningmaps.org/", forHTTPHeaderField: "Referer")
            result(await Self.get(fallback), nil)
        }
    }

    /// GetMap for one Web-Mercator tile.
    static func wmsURL(_ path: MKTileOverlayPath, layers: String) -> URLRequest {
        let world = 20_037_508.342789244
        let size = 2 * world / Double(1 << path.z)
        let minX = -world + Double(path.x) * size, maxY = world - Double(path.y) * size
        let bbox = String(format: "%.3f,%.3f,%.3f,%.3f", minX, maxY - size, minX + size, maxY)
        var c = URLComponents(string: service)!
        c.queryItems = [
            .init(name: "SERVICE", value: "WMS"), .init(name: "VERSION", value: "1.3.0"),
            .init(name: "REQUEST", value: "GetMap"), .init(name: "LAYERS", value: layers),
            .init(name: "STYLES", value: ""), .init(name: "CRS", value: "EPSG:3857"),
            .init(name: "BBOX", value: bbox), .init(name: "WIDTH", value: "256"), .init(name: "HEIGHT", value: "256"),
            .init(name: "FORMAT", value: "image/png"), .init(name: "TRANSPARENT", value: "TRUE"),
        ]
        var r = URLRequest(url: c.url!)
        r.timeoutInterval = 15
        return r
    }

    /// Image data, or nil when the answer is not a PNG/JPEG (WMS errors come back as XML).
    static func get(_ request: URLRequest) async -> Data? {
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200,
              let type = (response as? HTTPURLResponse)?.value(forHTTPHeaderField: "Content-Type"),
              type.hasPrefix("image") else { return nil }
        return data
    }
}

/// Layer names of the nowCOAST lightning service, read once per launch.
actor LightningLayers {
    static let shared = LightningLayers()
    private var cached: String?

    func names() async -> String {
        if let cached { return cached }
        let fallback = "lightning_detection"
        guard let url = URL(string: LightningTileOverlay.service + "?SERVICE=WMS&VERSION=1.3.0&REQUEST=GetCapabilities"),
              let data = try? await NetCache.data(from: url),
              let xml = String(data: data, encoding: .utf8) else { return fallback }
        let names = Self.layerNames(xml)
        cached = names.isEmpty ? fallback : names.joined(separator: ",")
        return cached ?? fallback
    }

    /// Named layers under <Capability> (GeoServer's root layer has no name), the lightning ones if any.
    static func layerNames(_ xml: String) -> [String] {
        guard let cap = xml.range(of: "<Capability>") else { return [] }
        let body = String(xml[cap.upperBound...])
        guard let re = try? NSRegularExpression(pattern: "<Layer[^>]*>\\s*<Name>([^<]+)</Name>") else { return [] }
        let all = re.matches(in: body, range: NSRange(body.startIndex..., in: body)).compactMap {
            Range($0.range(at: 1), in: body).map { String(body[$0]) }
        }
        let leaves = all
        let lightning = leaves.filter { $0.localizedCaseInsensitiveContains("light") || $0.localizedCaseInsensitiveContains("strike") }
        return lightning.isEmpty ? leaves : lightning
    }
}
