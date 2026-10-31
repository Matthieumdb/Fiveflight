import SwiftUI

struct FavoritesScreen: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    @State private var selectedAirport: Airport?

    private var favoriteAirports: [Airport] {
        model.favorites.compactMap { store.airport($0) }.sorted { $0.id < $1.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if favoriteAirports.isEmpty {
                    ContentUnavailableView(
                        "Aucun favori",
                        systemImage: "star",
                        description: Text("Ouvre un aéroport et touche l'étoile pour l'ajouter.")
                    )
                } else {
                    List(favoriteAirports) { airport in
                        FavoriteRowView(airport: airport)
                            .contentShape(Rectangle())
                            .onTapGesture { selectedAirport = airport }
                    }
                }
            }
            .navigationTitle("Favoris")
            .sheet(item: $selectedAirport) { airport in
                AirportDetailSheet(airport: airport, store: store)
            }
        }
    }
}

struct FavoriteRowView: View {
    let airport: Airport
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            Image(systemName: "star.fill")
                .font(.title3)
                .foregroundStyle(Theme.amber)

            VStack(alignment: .leading, spacing: 2) {
                Text(airport.id)
                    .font(.headline)
                    .foregroundStyle(Theme.textPrimary)
                Text(airport.name)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                withAnimation(.snappy) { model.toggleFavorite(airport.id) }
            } label: {
                Image(systemName: "star.fill")
                    .font(.title3)
            }
            .buttonStyle(.borderless)
            .foregroundStyle(Theme.amber)
        }
        .padding(.vertical, Theme.spacingS)
    }
}

struct AirportDetailSheet: View {
    let airport: Airport
    let store: AirportStore

    var body: some View {
        NavigationStack {
            AirportDetailView(
                airport: airport,
                runways: store.runways(for: airport),
                frequencies: store.frequencies(for: airport)
            )
        }
        .presentationDetents([.medium, .large])
    }
}