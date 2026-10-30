import SwiftUI

struct FavoritesScreen: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    @State private var selected: Airport?

    private var favAirports: [Airport] {
        model.favorites.compactMap { store.airport($0) }.sorted { $0.id < $1.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if favAirports.isEmpty {
                    ContentUnavailableView("Aucun favori",
                        systemImage: "star",
                        description: Text("Ouvre un aéroport et touche l'étoile pour l'ajouter."))
                } else {
                    List(favAirports) { a in
                        Button { selected = a } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(a.id).font(.headline)
                                Text(a.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        }
                        .tint(.primary)
                    }
                }
            }
            .navigationTitle("Favoris")
            .sheet(item: $selected) { a in
                AirportDetailView(airport: a,
                                  runways: store.runways(for: a),
                                  frequencies: store.frequencies(for: a))
                    .presentationDetents([.medium, .large])
            }
        }
    }
}
