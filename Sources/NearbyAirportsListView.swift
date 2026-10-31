import SwiftUI

struct NearbyAirportsListView: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var location: LocationManager
    @EnvironmentObject private var model: AppModel
    let nearest: [Airport]
    let categories: [String: String]
    let onSelect: (Airport) -> Void
    let onAddWaypoint: (Airport) -> Void

    var body: some View {
        List(nearest) { airport in
            AirportRowView(
                airport: airport,
                distance: location.coordinate.map { airport.distanceNM(to: $0) },
                category: categories[airport.id],
                onTap: { onSelect(airport) },
                onAddWaypoint: { onAddWaypoint(airport) }
            )
            .listRowBackground(Color.clear)
            .listRowSeparator(.hidden)
            .listRowInsets(EdgeInsets(
                top: Theme.spacingXS, leading: Theme.pad,
                bottom: Theme.spacingXS, trailing: Theme.pad
            ))
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(Theme.bg)
        .frame(maxHeight: 220)
    }
}

struct AirportRowView: View {
    let airport: Airport
    let distance: Double?
    let category: String?
    let onTap: () -> Void
    let onAddWaypoint: () -> Void

    private var dotColor: Color {
        if let cat = category { return Theme.category(cat) }
        return tint(for: airport.type)
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: Theme.spacingM) {
                Circle()
                    .fill(dotColor)
                    .frame(width: 10, height: 10)
                    .shadow(color: dotColor.opacity(0.7), radius: 3)

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

                if let distance {
                    Text("\(Int(distance.rounded())) NM")
                        .font(.subheadline.monospacedDigit().weight(.medium))
                        .foregroundStyle(Theme.textSecondary)
                }

                Button(action: onAddWaypoint) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title3)
                }
                .buttonStyle(.borderless)
                .foregroundStyle(Theme.accent)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 14)
            .compactCard()
        }
        .buttonStyle(.plain)
    }

    private func tint(for type: String) -> Color {
        switch type {
        case "large_airport":  return Theme.accent
        case "medium_airport": return Color(hex: "48CCCD")
        default:               return Theme.textTertiary
        }
    }
}