import SwiftUI

/// Search any US airport by ICAO / IATA / name. Empty query shows favourites + nearby.
struct SearchSheet: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    var nearest: [Airport]
    @State private var query = ""

    private var results: [Airport] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if q.isEmpty {
            var seen = Set<String>()
            var out: [Airport] = []
            let recents = model.recents.compactMap { store.airport($0) }
            let favs = model.favorites.compactMap { store.airport($0) }
            for a in recents + favs + nearest where seen.insert(a.id).inserted { out.append(a) }
            return Array(out.prefix(30))
        }
        var out: [Airport] = []
        for a in store.airports {
            if a.id.uppercased().contains(q)
                || (a.iata?.uppercased().contains(q) ?? false)
                || a.name.uppercased().contains(q) {
                out.append(a)
                if out.count >= 50 { break }
            }
        }
        // ICAO/IATA exact-ish matches first.
        return out.sorted { lhs, _ in lhs.id.uppercased().hasPrefix(q) || lhs.iata?.uppercased() == q }
    }

    var body: some View {
        NavigationStack {
            List(results) { airport in
                NavigationLink {
                    AirportDetailView(
                        airport: airport,
                        runways: store.runways(for: airport),
                        frequencies: store.frequencies(for: airport)
                    )
                } label: {
                    SearchResultRow(airport: airport)
                }
            }
            .navigationTitle("Recherche")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Code OACI, IATA ou nom")
            .textInputAutocapitalization(.characters)
            .overlay {
                if !query.isEmpty && results.isEmpty {
                    ContentUnavailableView.search(text: query)
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let airport: Airport

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            Image(systemName: "airplane.circle.fill")
                .font(.title3)
                .foregroundStyle(Theme.accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(airport.id)
                    .font(.headline.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                Text(airport.name)
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            if let municipality = airport.municipality {
                Text(municipality)
                    .font(.caption)
                    .foregroundStyle(Theme.textTertiary)
                    .lineLimit(1)
            }
        }
        .padding(.vertical, Theme.spacingXS)
    }
}