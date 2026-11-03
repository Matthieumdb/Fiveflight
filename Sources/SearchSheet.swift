import SwiftUI

/// Search any US airport by ICAO / IATA / name. Empty query shows favourites + nearby.
struct SearchSheet: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    var nearest: [Airport]
    var onSelect: ((Airport) -> Void)?
    @State private var query = ""
    @State private var searching = false
    @Environment(\.dismiss) private var dismiss

    private var results: [Airport] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if q.isEmpty {
            var seen = Set<String>(); var out: [Airport] = []
            let recents = model.recents.compactMap { store.airport($0) }
            let favs = model.favorites.compactMap { store.airport($0) }
            let around = nearest.filter { $0.type != "heliport" && $0.type != "closed" }
            for a in recents + favs + around where seen.insert(a.id).inserted { out.append(a) }
            return Array(out.prefix(30))
        }
        let airports = AirportSearch.rank(store.airports, query: q)
        // Building a plan: VOR, NDB, fixes, VFR waypoints and user points are valid waypoints too.
        guard onSelect != nil else { return airports }
        let user = model.userWaypoints.filter { $0.id.contains(q) || $0.name.uppercased().contains(q) }
        let nav = NavaidStore.search(q, limit: 20)
        let exact = nav.filter { $0.id == q }
        return exact + airports + user + nav.filter { $0.id != q }
    }

    var body: some View {
        NavigationStack {
            List(results) { a in
                if let onSelect = onSelect {
                    Button {
                        onSelect(a)
                    } label: {
                        HStack {
                            airportRow(a)
                            // In the flight plan, show which airports are already in the route.
                            if model.waypoints.contains(where: { $0.id == a.id }) {
                                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    NavigationLink {
                        AirportDetailView(airport: a,
                                          runways: store.runways(for: a),
                                          frequencies: store.frequencies(for: a))
                    } label: {
                        airportRow(a)
                    }
                }
            }
            .navigationTitle("Recherche")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } }
            }
            // Keyboard up as soon as the sheet opens.
            .onAppear { searching = true }
            .searchable(text: $query, isPresented: $searching, placement: .navigationBarDrawer(displayMode: .always), prompt: onSelect == nil ? "Code OACI, IATA ou nom" : "Aéroport, VOR, fix, point VFR…")
            .textInputAutocapitalization(.characters)
            .overlay {
                if !query.isEmpty && results.isEmpty { ContentUnavailableView.search(text: query) }
            }
        }
    }

    private func airportRow(_ a: Airport) -> some View {
        HStack(spacing: 12) {
            Image(systemName: a.symbolName)
                .foregroundStyle(a.isAirport ? Theme.accent : Color.indigo).font(.title3)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(a.id).font(.headline.monospaced())
                Text(a.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            if !a.isAirport {
                Text(a.kindLabel).font(.caption).foregroundStyle(.tertiary)
            } else if let m = a.municipality {
                Text(m).font(.caption).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
    }
}

enum AirportSearch {
    /// Best match first: exact code, code prefix, then names; bigger airports before private strips.
    static func rank(_ all: [Airport], query q: String, limit: Int = 50) -> [Airport] {
        let typeRank = ["large_airport": 0, "medium_airport": 1, "small_airport": 2, "seaplane_base": 3, "heliport": 5]
        func score(_ a: Airport) -> Int? {
            let id = a.id.uppercased(), iata = a.iata?.uppercased(), icao = a.icao?.uppercased()
            if id == q || iata == q || icao == q { return 0 }
            if id.hasPrefix(q) || (icao?.hasPrefix(q) ?? false) { return 1 }
            if iata?.hasPrefix(q) ?? false { return 2 }
            let name = a.name.uppercased()
            if name.hasPrefix(q) || name.contains(" " + q) { return 3 }
            if id.contains(q) || name.contains(q) || (a.municipality?.uppercased().contains(q) ?? false) { return 4 }
            return nil
        }
        var scored: [(Airport, Int, Int)] = []
        for a in all {
            if let sc = score(a) { scored.append((a, sc, typeRank[a.type] ?? 4)) }
        }
        scored.sort { ($0.1, $0.2, $0.0.id) < ($1.1, $1.2, $1.0.id) }
        return scored.prefix(limit).map { $0.0 }
    }
}
