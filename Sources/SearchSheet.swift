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
            var seen = Set<String>(); var out: [Airport] = []
            for a in model.favorites.compactMap({ store.airport($0) }) + nearest
            where seen.insert(a.id).inserted { out.append(a) }
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
            List(results) { a in
                NavigationLink {
                    AirportDetailView(airport: a,
                                      runways: store.runways(for: a),
                                      frequencies: store.frequencies(for: a))
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "airplane.circle.fill")
                            .foregroundStyle(Theme.accent).font(.title3)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(a.id).font(.headline.monospaced())
                            Text(a.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if let m = a.municipality {
                            Text(m).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                        }
                    }
                }
            }
            .navigationTitle("Recherche")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Code OACI, IATA ou nom")
            .textInputAutocapitalization(.characters)
            .overlay {
                if !query.isEmpty && results.isEmpty { ContentUnavailableView.search(text: query) }
            }
        }
    }
}
