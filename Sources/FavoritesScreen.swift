import SwiftUI
import CoreLocation

// MARK: - Favorites Screen

struct FavoritesScreen: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    @State private var showingSearch = false

    private var favoriteAirports: [Airport] {
        model.favorites.compactMap { store.airport($0) }.sorted { $0.id < $1.id }
    }

    var body: some View {
        NavigationStack {
            Group {
                if favoriteAirports.isEmpty {
                    ContentUnavailableView(
                        "No Favorites",
                        systemImage: "star",
                        description: Text("Tap the star on any airport to add it to your favorites")
                    )
                } else {
                    List {
                        ForEach(favoriteAirports) { airport in
                            FavoriteRowView(airport: airport)
                                .listRowInsets(EdgeInsets(top: SpacingToken.space1, leading: SpacingToken.insetMedium, bottom: SpacingToken.space1, trailing: SpacingToken.insetMedium))
                                .listRowBackground(Color.clear)
                                .swipeActions(edge: .trailing) {
                                    Button(role: .destructive) {
                                        model.toggleFavorite(airport.id)
                                    } label: {
                                        Label("Remove", systemImage: "star.slash")
                                    }
                                }
                        }
                        .onDelete { indexSet in
                            for index in indexSet {
                                model.toggleFavorite(favoriteAirports[index].id)
                            }
                        }
                    }
                    .listStyle(.plain)
                    .scrollContentBackground(.hidden)
                }
            }
            .background(ColorToken.surfaceBase)
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingSearch = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showingSearch) {
                SearchSheet(nearest: store.nearest(to: model.userLocation ?? CLLocationCoordinate2D(latitude: 39.8283, longitude: -98.5795), maxCount: 20))
            }
        }
    }
}

struct FavoriteRowView: View {
    let airport: Airport
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var weatherService: WeatherService

    private var metar: METAR? { weatherService.metars[airport.id] }

    var body: some View {
        Button {
            model.addWaypoint(airport)
        } label: {
            HStack(spacing: SpacingToken.space3) {
                // Airport type indicator
                ZStack {
                    Circle()
                        .fill(airportColor)
                        .frame(width: 44, height: 44)
                    Image(systemName: airportIcon)
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(ColorToken.textOnBrand)
                }

                // Airport info
                VStack(alignment: .leading, spacing: SpacingToken.space1) {
                    HStack(spacing: SpacingToken.space2) {
                        Text(airport.id)
                            .font(TypographyToken.monoMedium)
                            .foregroundStyle(ColorToken.textPrimary)

                        if let metar = metar {
                            Text(metar.flightCategory.rawValue)
                                .font(TypographyToken.monoXSmall)
                                .foregroundStyle(ColorToken.textOnBrand)
                                .padding(.horizontal, SpacingToken.space2)
                                .padding(.vertical, SpacingToken.space0)
                                .background(categoryColor(metar.flightCategory.rawValue), in: Capsule())
                        }
                    }

                    Text(airport.name)
                        .font(TypographyToken.bodySmall)
                        .foregroundStyle(ColorToken.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Distance & bearing
                if let loc = model.userLocation {
                    VStack(alignment: .trailing, spacing: SpacingToken.space0) {
                        Text(String(format: "%.0f NM", airport.distanceNM(from: loc)))
                            .font(TypographyToken.monoSmall)
                            .foregroundStyle(ColorToken.textPrimary)

                        let bearing = Haversine.trueCourse(loc, airport.coordinate)
                        Text(String(format: "%03d°", bearing))
                            .font(TypographyToken.monoXSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                    }
                }

                // Favorite indicator
                Image(systemName: "star.fill")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(ColorToken.warning)
            }
            .padding(.vertical, SpacingToken.space1)
        }
        .buttonStyle(.plain)
    }

    private var airportColor: Color {
        switch airport.type {
        case "large_airport": return ColorToken.brandPrimary
        case "medium_airport": return ColorToken.info
        case "small_airport": return ColorToken.success
        case "heliport": return ColorToken.warning
        default: return ColorToken.textTertiary
        }
    }

    private var airportIcon: String {
        switch airport.type {
        case "large_airport": return "airplane"
        case "medium_airport": return "airplane"
        case "small_airport": return "airplane"
        case "heliport": return "helmet"
        default: return "circle"
        }
    }

    private func categoryColor(_ cat: String) -> Color {
        switch cat {
        case "VFR": return ColorToken.vfr
        case "MVFR": return ColorToken.mvfr
        case "IFR": return ColorToken.ifr
        case "LIFR": return ColorToken.lifr
        default: return ColorToken.textTertiary
        }
    }
}
