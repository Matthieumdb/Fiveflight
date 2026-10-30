import SwiftUI

struct RootView: View {
    @StateObject private var store = AirportStore()
    @StateObject private var location = LocationManager()
    @StateObject private var model = AppModel()

    var body: some View {
        Group {
            if store.ready {
                TabView {
                    MapScreen()
                        .tabItem { Label("Carte", systemImage: "map") }
                    FavoritesScreen()
                        .tabItem { Label("Favoris", systemImage: "star") }
                    LogbookScreen()
                        .tabItem { Label("Carnet", systemImage: "book") }
                    ChecklistScreen()
                        .tabItem { Label("Checklist", systemImage: "checklist") }
                }
            } else {
                LoadingView(progress: store.progress)
            }
        }
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
        VStack(spacing: 16) {
            Image(systemName: "airplane.departure").font(.system(size: 44)).foregroundStyle(.tint)
            Text("Chargement de la base aéronautique").font(.headline)
            ProgressView(value: progress).progressViewStyle(.linear).frame(width: 240)
            Text("\(Int(progress * 100)) %")
                .font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                .contentTransition(.numericText()).animation(.default, value: progress)
        }
        .padding()
    }
}
