import SwiftUI
import UIKit

struct RootView: View {
    @StateObject private var store = AirportStore()
    @StateObject private var location = LocationManager()
    @StateObject private var model = AppModel()

    init() {
        // Dark, slightly translucent tab bar that matches the cockpit theme.
        let tab = UITabBarAppearance()
        tab.configureWithDefaultBackground()
        tab.backgroundColor = UIColor(Theme.bgElevated).withAlphaComponent(0.92)
        UITabBar.appearance().standardAppearance = tab
        UITabBar.appearance().scrollEdgeAppearance = tab

        let nav = UINavigationBarAppearance()
        nav.configureWithTransparentBackground()
        nav.backgroundColor = UIColor(Theme.bg).withAlphaComponent(0.6)
        nav.titleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        nav.largeTitleTextAttributes = [.foregroundColor: UIColor(Theme.textPrimary)]
        UINavigationBar.appearance().standardAppearance = nav
        UINavigationBar.appearance().scrollEdgeAppearance = nav
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            if store.ready {
                TabView {
                    MapScreen()
                        .tabItem { Label("Carte", systemImage: "map.fill") }
                    FavoritesScreen()
                        .tabItem { Label("Favoris", systemImage: "star.fill") }
                    LogbookScreen()
                        .tabItem { Label("Carnet", systemImage: "book.fill") }
                    ChecklistScreen()
                        .tabItem { Label("Checklist", systemImage: "checklist") }
                    SettingsScreen()
                        .tabItem { Label("Réglages", systemImage: "gearshape.fill") }
                }
            } else {
                LoadingView(progress: store.progress)
            }
        }
        .colorMultiply(model.nightMode ? Color(red: 1.0, green: 0.30, blue: 0.30) : .white)
        .animation(.easeInOut, value: model.nightMode)
        .tint(Theme.accent)
        .preferredColorScheme(.dark)
        .environmentObject(store)
        .environmentObject(location)
        .environmentObject(model)
        .task {
            location.start()
            await store.load()
        }
    }
}

struct LoadingView: View {
    let progress: Double
    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()
            VStack(spacing: 22) {
                ZStack {
                    Circle().fill(Theme.accentGradient)
                        .frame(width: 96, height: 96)
                        .shadow(color: Theme.accent.opacity(0.6), radius: 24)
                    Image(systemName: "airplane.departure")
                        .font(.system(size: 42, weight: .semibold))
                        .foregroundStyle(.white)
                }
                VStack(spacing: 6) {
                    Text("FIVEFLIGHT").font(.title3.weight(.heavy)).tracking(4)
                        .foregroundStyle(Theme.textPrimary)
                    Text("Base aéronautique").font(.footnote).foregroundStyle(Theme.textSecondary)
                }
                ProgressView(value: progress)
                    .progressViewStyle(.linear).tint(Theme.accent)
                    .frame(width: 220)
                Text("\(Int(progress * 100)) %")
                    .font(.subheadline.monospacedDigit()).foregroundStyle(Theme.textSecondary)
                    .contentTransition(.numericText()).animation(.default, value: progress)
            }
        }
    }
}
