import Foundation
import CoreLocation
import WidgetKit

/// Publishes what the home-screen widget shows (nearest airports, active route, local weather)
/// to the shared App Group. The JSON keys match the widget's `AirportSummary`,
/// `RouteSummary` and `WeatherSummary` types in Sources/Widgets/WeatherWidget.swift.
@MainActor
enum WidgetBridge {
    static let appGroup = "group.com.fiveflight.app"

    private struct AirportPayload: Codable { let id: String; let name: String; let nm: Int; let category: String? }
    private struct RoutePayload: Codable { let from: String; let to: String; let totalNM: Int; let ete: String; let fuel: Double }
    private struct WeatherPayload: Codable { let station: String; let category: String; let wind: String; let visib: String }

    private static var lastSignature = ""

    static func update(store: AirportStore, model: AppModel, weather: WeatherService) {
        // Without a signed App Group (unsigned IPA) this suite is unavailable: nothing to do.
        guard let defaults = UserDefaults(suiteName: appGroup) else { return }
        let position = model.userLocation ?? AppModel.homeCoordinate

        let nearest = store.nearest(to: position, limit: 3, matching: ["large_airport", "medium_airport", "small_airport"])
        let airports = nearest.map {
            AirportPayload(id: $0.id, name: $0.name, nm: Int($0.distanceNM(to: position).rounded()),
                           category: weather.metars[$0.id]?.flightCategory.rawValue)
        }

        var route: RoutePayload?
        if let first = model.waypoints.first, let last = model.waypoints.last, model.waypoints.count >= 2 {
            route = RoutePayload(from: first.id, to: last.id, totalNM: Int(model.totalDistanceNM.rounded()),
                                 ete: model.formattedTotalTime, fuel: (model.totalFuelGallons * 10).rounded() / 10)
        }

        var wx: WeatherPayload?
        if let station = nearest.first(where: { weather.metars[$0.id] != nil }), let metar = weather.metars[station.id] {
            let wind: String
            if let speed = metar.windSpeed {
                let dir = metar.windDirection.map { String(format: "%03ld", $0) } ?? "VRB"
                wind = speed == 0 ? "Calme" : "\(dir)/\(speed)" + (metar.windGust.map { "G\($0)" } ?? "") + " kt"
            } else {
                wind = "—"
            }
            let visib = metar.visibility.map { $0 >= 10 ? "10+ SM" : String(format: "%g SM", $0) } ?? "—"
            wx = WeatherPayload(station: station.id, category: metar.flightCategory.rawValue, wind: wind, visib: visib)
        }

        let encoder = JSONEncoder()
        let nearestData = try? encoder.encode(airports)
        let routeData = route.flatMap { try? encoder.encode($0) }
        let weatherData = wx.flatMap { try? encoder.encode($0) }

        // Only write and reload timelines when something the widget shows actually changed.
        let signature = [nearestData, routeData, weatherData].map { $0?.base64EncodedString() ?? "-" }.joined(separator: "|")
        guard signature != lastSignature else { return }
        lastSignature = signature

        defaults.set(nearestData, forKey: "widget.nearest")
        if let routeData { defaults.set(routeData, forKey: "widget.route") } else { defaults.removeObject(forKey: "widget.route") }
        if let weatherData { defaults.set(weatherData, forKey: "widget.weather") } else { defaults.removeObject(forKey: "widget.weather") }
        WidgetCenter.shared.reloadAllTimelines()
    }
}
