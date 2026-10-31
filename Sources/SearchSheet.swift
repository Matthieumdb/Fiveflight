import SwiftUI
import CoreLocation

// MARK: - Search Sheet

struct SearchSheet: View {
    let nearest: [Airport]
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var searchText = ""
    @State private var selectedTab = 0 // 0 = Nearby, 1 = Search

    private var filteredAirports: [Airport] {
        if searchText.isEmpty { return nearest }
        return nearest.filter { airport in
            airport.id.localizedCaseInsensitiveContains(searchText) ||
            airport.name.localizedCaseInsensitiveContains(searchText) ||
            airport.municipality?.localizedCaseInsensitiveContains(searchText) ?? false
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Search field
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ColorToken.textTertiary)
                    TextField("Search airports (ICAO, name, city)", text: $searchText)
                        .font(TypographyToken.bodyMedium)
                        .foregroundStyle(ColorToken.textPrimary)
                }
                .padding(SpacingToken.space3)
                .background(ColorToken.surfaceCard, in: RoundedRectangle(cornerRadius: RadiusToken.md))
                .padding(.horizontal, SpacingToken.insetMedium)
                .padding(.vertical, SpacingToken.space3)

                // Tab picker
                HStack(spacing: SpacingToken.space2) {
                    ForEach(["Nearby", "All"].indices, id: \.self) { index in
                        Button {
                            selectedTab = index
                        } label: {
                            Text(["Nearby", "All"][index])
                                .font(TypographyToken.labelMedium)
                                .foregroundStyle(selectedTab == index ? ColorToken.textOnBrand : ColorToken.textTertiary)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, SpacingToken.space2)
                                .background(
                                    selectedTab == index ? ColorToken.brandPrimary : ColorToken.surfaceCard,
                                    in: Capsule()
                                )
                        }
                    }
                }
                .padding(.horizontal, SpacingToken.insetMedium)
                .padding(.bottom, SpacingToken.space3)

                // Results
                ScrollView {
                    LazyVStack(spacing: SpacingToken.space1, pinnedViews: [.sectionHeaders]) {
                        Section {
                            ForEach(selectedTab == 0 ? nearest : filteredAirports) { airport in
                                SearchResultRow(airport: airport) {
                                    model.addWaypoint(airport)
                                    dismiss()
                                }
                            }
                        } header: {
                            HStack {
                                Text(selectedTab == 0 ? "Nearby Airports" : "Search Results")
                                    .font(TypographyToken.labelSmall)
                                    .foregroundStyle(ColorToken.textTertiary)
                                    .textCase(.uppercase)
                                Spacer()
                            }
                            .padding(.vertical, SpacingToken.space2)
                            .background(ColorToken.surfaceBase)
                        }
                    }
                    .padding(.horizontal, SpacingToken.insetMedium)
                    .padding(.bottom, SpacingToken.space8)
                }
                .background(ColorToken.surfaceBase)
            }
            .background(ColorToken.surfaceBase)
            .navigationTitle("Add Waypoint")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                        .font(TypographyToken.labelMedium)
                }
            }
        }
    }
}

struct SearchResultRow: View {
    let airport: Airport
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpacingToken.space3) {
                // Airport type indicator
                ZStack {
                    Circle()
                        .fill(airportColor)
                        .frame(width: 40, height: 40)
                    Image(systemName: airportIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(ColorToken.textOnBrand)
                }

                // Airport info
                VStack(alignment: .leading, spacing: SpacingToken.space0) {
                    Text(airport.id)
                        .font(TypographyToken.monoMedium)
                        .foregroundStyle(ColorToken.textPrimary)
                    Text(airport.name)
                        .font(TypographyToken.bodySmall)
                        .foregroundStyle(ColorToken.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                // Distance
                VStack(alignment: .trailing, spacing: SpacingToken.space0) {
                    Text(airport.type.capitalized)
                        .font(TypographyToken.labelXSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                }
            }
            .padding(.vertical, SpacingToken.space2)
            .padding(.horizontal, SpacingToken.space3)
            .background(ColorToken.surfaceCard, in: RoundedRectangle(cornerRadius: RadiusToken.md))
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
}