import SwiftUI
import CoreLocation

/// ForeFlight "Airports" view: search bar, Recent / Favorites / Nearby lists, then the airport
/// with its Info · Météo · Pistes · Fréq. · NOTAM tabs.
struct AirportsScreen: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var weather: WeatherService
    @State private var query = ""
    @State private var list: AirportList = .nearby

    enum AirportList: String, CaseIterable, Identifiable {
        case recent = "Récents", favorites = "Favoris", nearby = "Proches"
        var id: String { rawValue }
    }

    private var here: CLLocationCoordinate2D { model.userLocation ?? AppModel.homeCoordinate }

    private var airports: [Airport] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if !q.isEmpty { return AirportSearch.rank(store.airports, query: q, limit: 60) }
        switch list {
        case .recent: return model.recents.compactMap { store.airport($0) }
        case .favorites: return model.favorites.sorted().compactMap { store.airport($0) }
        case .nearby: return store.nearest(to: here, limit: 30, matching: ["large_airport", "medium_airport", "small_airport", "seaplane_base"])
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if query.isEmpty {
                    Section {
                        Picker("Liste", selection: $list) {
                            ForEach(AirportList.allCases) { Text($0.rawValue).tag($0) }
                        }
                        .pickerStyle(.segmented)
                    }
                    .listRowInsets(EdgeInsets(top: 0, leading: 0, bottom: 0, trailing: 0))
                    .listRowBackground(Color.clear)
                }
                Section {
                    if airports.isEmpty {
                        Text(list == .favorites ? "Aucun favori. Touchez ☆ sur un aéroport." : "Aucun aéroport")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(airports) { a in
                        NavigationLink {
                            AirportDetailSheet(airport: a, store: store, embedded: true)
                        } label: {
                            AirportListRow(airport: a, from: here, category: weather.metars[a.id]?.flightCategory)
                        }
                        .swipeActions {
                            Button { model.toggleFavorite(a.id) } label: {
                                Label("Favori", systemImage: model.isFavorite(a.id) ? "star.slash" : "star")
                            }
                            .tint(.orange)
                            Button { model.addWaypoint(a) } label: { Label("Au vol", systemImage: "plus") }
                                .tint(FF.accent)
                        }
                    }
                } header: {
                    FFHeader(query.isEmpty ? list.rawValue : "Résultats")
                } footer: {
                    // Legend of the flight-category dots.
                    HStack(spacing: 12) {
                        ForEach([FlightCategory.vfr, .mvfr, .ifr, .lifr], id: \.self) { c in
                            HStack(spacing: 4) {
                                Circle().fill(c.color).frame(width: 8, height: 8)
                                Text(c.rawValue)
                            }
                        }
                        HStack(spacing: 4) {
                            Circle().fill(Color.gray.opacity(0.5)).frame(width: 8, height: 8)
                            Text("pas de METAR")
                        }
                    }
                    .font(.caption2)
                }
            }
            .listStyle(.insetGrouped)
            .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always),
                        prompt: "Identifiant, ville ou nom")
            .navigationTitle("Aéroports")
            .navigationBarTitleDisplayMode(.inline)
            .task(id: airports.map(\.id).prefix(25).joined()) {
                let ids = airports.prefix(25).map(\.id).filter { $0.count == 4 }
                if !ids.isEmpty { await weather.refreshMETARs(forVisible: ids) }
            }
        }
    }
}

/// ForeFlight airport row: flight-category dot, identifier, name, distance and bearing.
struct AirportListRow: View {
    let airport: Airport
    let from: CLLocationCoordinate2D
    let category: FlightCategory?

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(category.map { $0 == .unknown ? Color.gray.opacity(0.5) : $0.color } ?? Color.gray.opacity(0.5))
                .frame(width: 12, height: 12)
            VStack(alignment: .leading, spacing: 1) {
                Text(airport.id).font(.system(size: 17, weight: .bold))
                Text(airport.name).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(Int(airport.distanceNM(to: from).rounded())) NM").font(.subheadline.monospacedDigit())
                // No bearing to the airport you are on.
                if airport.distanceNM(to: from) >= 0.5 {
                    Text(String(format: "%03d°", Haversine.trueCourse(from, airport.coordinate)))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
    }
}
