import SwiftUI

@main
struct FiveflightApp: App {
    @StateObject private var store = AirportStore()
    @StateObject private var model = AppModel.shared
    @StateObject private var airspaceManager = AirspaceDataManager.shared
    @StateObject private var routingEngine = RoutingEngine.shared
    @StateObject private var weatherService = WeatherService.shared
    @StateObject private var locationManager = LocationManager.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(store)
                .environmentObject(model)
                .environmentObject(airspaceManager)
                .environmentObject(routingEngine)
                .environmentObject(weatherService)
                .environmentObject(locationManager)
                .preferredColorScheme(model.colorScheme)
                #if DEBUG
                // Simulator check: launch with env PLAN=KFPR,KAPF to preload a flight plan.
                .onChange(of: store.ready) { _, ready in
                    guard ready, let plan = ProcessInfo.processInfo.environment["PLAN"] else { return }
                    model.waypoints = plan.split(separator: ",").compactMap { store.airport(String($0)) }
                    if let a = model.waypoints.first, let b = model.waypoints.last {
                        model.moveMap(to: .init(latitude: (a.coordinate.latitude + b.coordinate.latitude) / 2,
                                                longitude: (a.coordinate.longitude + b.coordinate.longitude) / 2), span: 2)
                    }
                }
                #endif
        }
    }
}

extension AppModel {
    /// Returns the preferred color scheme based on the appearance mode setting.
    /// 0 = System (nil), 1 = Light (.light), 2 = Dark (.dark)
    var colorScheme: ColorScheme? {
        switch appearanceMode {
        case 1: return .light
        case 2: return .dark
        default: return nil
        }
    }
}