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