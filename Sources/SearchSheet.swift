import SwiftUI

/// Search any US airport by ICAO / IATA / name. Empty query shows favourites + nearby.
struct SearchSheet: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    var nearest: [Airport]
    var onSelect: ((Airport) -> Void)?
    @State private var query = ""

    private var results: [Airport] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if q.isEmpty {
            var seen = Set<String>(); var out: [Airport] = []
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
        let first = { (a: Airport) in a.id.uppercased().hasPrefix(q) || a.iata?.uppercased() == q }
        let airports = out.filter(first) + out.filter { !first($0) }
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
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: onSelect == nil ? "Code OACI, IATA ou nom" : "Aéroport, VOR, fix, point VFR…")
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
