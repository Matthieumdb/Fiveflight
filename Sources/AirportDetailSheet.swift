import SwiftUI

// MARK: - Airport Detail Sheet

struct AirportDetailSheet: View {
    let airport: Airport
    let store: AirportStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var weatherService: WeatherService
    @Environment(\.dismiss) private var dismiss

    private var runways: [Runway] { store.runways(for: airport) }
    private var frequencies: [Frequency] { store.frequencies(for: airport) }
    private var metar: METAR? { weatherService.metars[airport.id] }
    private var taf: TAF? { weatherService.tafs[airport.id] }

    var body: some View {
        NavigationStack {
            List {
                // Header
                Section {
                    AirportHeaderView(airport: airport, metar: metar, airportTypeDisplay: airportTypeDisplay)
                }
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)

                // Quick Actions
                Section {
                    HStack(spacing: SpacingToken.space3) {
                        ActionButton(
                            icon: "plus.circle.fill",
                            label: "Add to Route",
                            color: ColorToken.brandPrimary
                        ) {
                            model.addWaypoint(airport)
                            dismiss()
                        }

                        ActionButton(
                            icon: model.isFavorite(airport.id) ? "star.fill" : "star",
                            label: model.isFavorite(airport.id) ? "Remove Fav" : "Add Favorite",
                            color: ColorToken.warning
                        ) {
                            model.toggleFavorite(airport.id)
                        }

                        ActionButton(
                            icon: "arrow.up.right.square",
                            label: "Nearby",
                            color: ColorToken.info
                        ) {
                            // Would show nearby
                        }
                    }
                }
                .listRowInsets(EdgeInsets(top: SpacingToken.space2, leading: SpacingToken.insetMedium, bottom: SpacingToken.space2, trailing: SpacingToken.insetMedium))
                .listRowBackground(Color.clear)

                // METAR
                if let metar = metar {
                    Section {
                        METARCard(metar: metar)
                    } header: {
                        Text("METAR")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                            .textCase(.uppercase)
                    }
                }

                // TAF
                if let taf = taf {
                    Section {
                        TAFCard(taf: taf)
                    } header: {
                        Text("TAF")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                            .textCase(.uppercase)
                    }
                }

                // Runways
                if !runways.isEmpty {
                    Section {
                        ForEach(runways) { runway in
                            RunwayRow(runway: runway)
                        }
                    } header: {
                        Text("Runways")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                            .textCase(.uppercase)
                    }
                }

                // Frequencies
                if !frequencies.isEmpty {
                    Section {
                        ForEach(frequencies) { freq in
                            FrequencyRow(frequency: freq)
                        }
                    } header: {
                        Text("Frequencies")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                            .textCase(.uppercase)
                    }
                }

                // Services & Info
                Section {
                    InfoRow(icon: "building.2", title: "Type", value: airportTypeDisplay)
                    InfoRow(icon: "mappin", title: "Coordinates", value: coordinateString)
                    InfoRow(icon: "mountain.2", title: "Elevation", value: "\(airport.elevation) ft")
                    if let municipality = airport.municipality {
                        InfoRow(icon: "building", title: "City", value: municipality)
                    }
                    if let state = airport.state {
                        InfoRow(icon: "map", title: "State", value: state)
                    }
                } header: {
                    Text("Information")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ColorToken.surfaceBase)
            .navigationTitle(airport.id)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .task {
            await weatherService.fetchMETAR(for: airport.id)
            await weatherService.fetchTAF(for: airport.id)
        }
    }

    private var airportTypeDisplay: String {
        switch airport.type {
        case "large_airport": return "Large Airport"
        case "medium_airport": return "Medium Airport"
        case "small_airport": return "Small Airport"
        case "heliport": return "Heliport"
        case "seaplane_base": return "Seaplane Base"
        case "balloonport": return "Balloonport"
        default: return airport.type.capitalized
        }
    }

    private var coordinateString: String {
        let lat = airport.coordinate.latitude
        let lon = airport.coordinate.longitude
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%02d°%02d'%s %03d°%02d'%s",
                      Int(abs(lat)), Int((abs(lat).truncatingRemainder(dividingBy: 1)) * 60), latDir,
                      Int(abs(lon)), Int((abs(lon).truncatingRemainder(dividingBy: 1)) * 60), lonDir)
    }
}

// MARK: - Airport Header

struct AirportHeaderView: View {
    let airport: Airport
    let metar: METAR?
    let airportTypeDisplay: String

    var body: some View {
        VStack(spacing: SpacingToken.space4) {
            HStack {
                VStack(alignment: .leading, spacing: SpacingToken.space1) {
                    Text(airport.id)
                        .font(TypographyToken.displayMedium)
                        .foregroundStyle(ColorToken.textPrimary)

                    Text(airport.name)
                        .font(TypographyToken.bodyLarge)
                        .foregroundStyle(ColorToken.textSecondary)
                        .lineLimit(2)
                }

                Spacer()

                // Flight category badge
                if let metar = metar {
                    VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                        Text(metar.flightCategory.rawValue)
                            .font(TypographyToken.monoMedium)
                            .foregroundStyle(ColorToken.textOnBrand)
                            .padding(.horizontal, SpacingToken.space3)
                            .padding(.vertical, SpacingToken.space1)
                            .background(categoryColor(metar.flightCategory.rawValue), in: Capsule())

                        Text(metar.rawText)
                            .font(TypographyToken.monoXSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                            .lineLimit(1)
                            .frame(maxWidth: 200, alignment: .trailing)
                    }
                }
            }

            // Type badges
            HStack(spacing: SpacingToken.space2) {
                BadgeView(text: airportTypeDisplay, color: ColorToken.brandPrimary)
                BadgeView(text: "\(airport.elevation) ft MSL", color: ColorToken.info)
                if airport.type != "heliport" && airport.type != "seaplane_base" {
                    BadgeView(text: "VFR", color: ColorToken.success)
                }
            }
        }
        .padding(SpacingToken.cardPadding)
        .background(
            LinearGradient.surfaceGradient,
            in: RoundedRectangle(cornerRadius: RadiusToken.card)
        )
        .overlay(
            RoundedRectangle(cornerRadius: RadiusToken.card)
                .stroke(ColorToken.borderDefault, lineWidth: 0.5)
        )
        .padding(.horizontal, SpacingToken.insetMedium)
        .padding(.top, SpacingToken.space2)
    }

    private func categoryColor(_ cat: String) -> Color {
        switch cat {
        case "VFR": return ColorToken.vfr
        case "MVFR": return ColorToken.mvfr
        case "IFR": return ColorToken.ifr
        case "LIFR": return ColorToken.lifr
        default: return ColorToken.unknown
        }
    }
}

struct BadgeView: View {
    let text: String
    let color: Color

    var body: some View {
        Text(text)
            .font(TypographyToken.labelXSmall)
            .foregroundStyle(color)
            .padding(.horizontal, SpacingToken.space2)
            .padding(.vertical, SpacingToken.space0)
            .background(color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Action Button

struct ActionButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: SpacingToken.space1) {
                Image(systemName: icon)
                    .font(.system(size: 22, weight: .medium))
                Text(label)
                    .font(TypographyToken.labelSmall)
            }
            .foregroundStyle(color)
            .frame(maxWidth: .infinity)
            .padding(.vertical, SpacingToken.space3)
            .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: RadiusToken.md))
        }
        .buttonStyle(.plain)
    }
}

// MARK: - METAR Card

struct METARCard: View {
    let metar: METAR

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space3) {
            HStack {
                Text(metar.station)
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
                Spacer()
                Text(metar.observationTime.formatted(date: .omitted, time: .shortened))
                    .font(TypographyToken.monoSmall)
                    .foregroundStyle(ColorToken.textTertiary)
            }

            Text(metar.rawText)
                .font(TypographyToken.monoSmall)
                .foregroundStyle(ColorToken.textPrimary)
                .textSelection(.enabled)

            // Decoded info
            if let decoded = metar.decoded {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: SpacingToken.space2) {
                    DecodedMETARRow(label: "Wind", value: decoded.wind)
                    DecodedMETARRow(label: "Visibility", value: decoded.visibilityStr.isEmpty ? nil : decoded.visibilityStr)
                    DecodedMETARRow(label: "Ceiling", value: decoded.ceilingStr.isEmpty ? nil : decoded.ceilingStr)
                    DecodedMETARRow(label: "Temp/Dew", value: decoded.temperatureStr.isEmpty ? nil : decoded.temperatureStr)
                    DecodedMETARRow(label: "Altimeter", value: decoded.altimeterStr.isEmpty ? nil : decoded.altimeterStr)
                    DecodedMETARRow(label: "Flight Cat", value: metar.flightCategory.rawValue)
                }
            }
        }
        .padding(SpacingToken.cardPadding)
        .background(ColorToken.surfaceCard, in: RoundedRectangle(cornerRadius: RadiusToken.card))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusToken.card)
                .stroke(ColorToken.borderDefault, lineWidth: 0.5)
        )
    }
}

struct DecodedMETARRow: View {
    let label: String
    let value: String?

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space0) {
            Text(label)
                .font(TypographyToken.labelXSmall)
                .foregroundStyle(ColorToken.textTertiary)
            Text(value ?? "—")
                .font(TypographyToken.monoSmall)
                .foregroundStyle(ColorToken.textPrimary)
        }
    }
}

// MARK: - TAF Card

struct TAFCard: View {
    let taf: TAF

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space3) {
            HStack {
                Text(taf.station)
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
                Spacer()
                Text("Valid: \(taf.validFrom.formatted(date: .omitted, time: .shortened)) – \(taf.validTo.formatted(date: .omitted, time: .shortened))")
                    .font(TypographyToken.monoSmall)
                    .foregroundStyle(ColorToken.textTertiary)
            }

            Text(taf.rawText)
                .font(TypographyToken.monoSmall)
                .foregroundStyle(ColorToken.textPrimary)
                .textSelection(.enabled)
        }
        .padding(SpacingToken.cardPadding)
        .background(ColorToken.surfaceCard, in: RoundedRectangle(cornerRadius: RadiusToken.card))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusToken.card)
                .stroke(ColorToken.borderDefault, lineWidth: 0.5)
        )
    }
}

// MARK: - Runway Row

struct RunwayRow: View {
    let runway: Runway

    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            // Runway designation
            VStack(alignment: .leading, spacing: SpacingToken.space0) {
                Text(runway.designation)
                    .font(TypographyToken.monoLarge)
                    .foregroundStyle(ColorToken.brandPrimary)
                Text("\(runway.length) × \(runway.width) ft")
                    .font(TypographyToken.monoXSmall)
                    .foregroundStyle(ColorToken.textTertiary)
            }
            .frame(width: 80, alignment: .leading)

            // Surface
            VStack(alignment: .leading, spacing: SpacingToken.space0) {
                Text("Surface")
                    .font(TypographyToken.labelXSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text(runway.surface)
                    .font(TypographyToken.bodySmall)
                    .foregroundStyle(ColorToken.textPrimary)
            }

            Spacer()

            // Lighting
            if runway.lighted {
                VStack(alignment: .trailing, spacing: SpacingToken.space0) {
                    Text("Lighting")
                        .font(TypographyToken.labelXSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                    Image(systemName: "lightbulb.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(ColorToken.warning)
                }
            }

            // Heading
            VStack(alignment: .trailing, spacing: SpacingToken.space0) {
                Text("Heading")
                    .font(TypographyToken.labelXSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text("\(runway.trueHeading)°T / \(runway.magneticHeading)°M")
                    .font(TypographyToken.monoSmall)
                    .foregroundStyle(ColorToken.textPrimary)
            }
        }
        .padding(.vertical, SpacingToken.space1)
    }
}

// MARK: - Frequency Row

struct FrequencyRow: View {
    let frequency: Frequency

    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            // Type badge
            Text(frequency.typeShort)
                .font(TypographyToken.monoXSmall)
                .foregroundStyle(ColorToken.textOnBrand)
                .padding(.horizontal, SpacingToken.space2)
                .padding(.vertical, SpacingToken.space0)
                .background(frequencyTypeColor(frequency.type), in: Capsule())

            // Frequency value
            Text(frequency.displayValue)
                .font(TypographyToken.monoMedium)
                .foregroundStyle(ColorToken.textPrimary)

            Spacer()

            // Description
            if !frequency.description.isEmpty {
                Text(frequency.description)
                    .font(TypographyToken.bodySmall)
                    .foregroundStyle(ColorToken.textSecondary)
            }
        }
        .padding(.vertical, SpacingToken.space1)
    }

    private func frequencyTypeColor(_ type: String) -> Color {
        switch type.uppercased() {
        case let t where t.contains("CTAF") || t.contains("UNICOM"): return ColorToken.warning
        case let t where t.contains("TOWER") || t.contains("TWR"): return ColorToken.brandPrimary
        case let t where t.contains("GROUND"): return ColorToken.info
        case let t where t.contains("APPROACH") || t.contains("DEP"): return ColorToken.success
        case let t where t.contains("CENTER"): return ColorToken.critical
        case let t where t.contains("ATIS") || t.contains("AWOS") || t.contains("ASOS"): return ColorToken.success
        default: return ColorToken.textTertiary
        }
    }
}

// MARK: - Info Row

struct InfoRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ColorToken.brandPrimary)
                .frame(width: 28)

            Text(title)
                .font(TypographyToken.bodyMedium)
                .foregroundStyle(ColorToken.textSecondary)

            Spacer()

            Text(value)
                .font(TypographyToken.monoMedium)
                .foregroundStyle(ColorToken.textPrimary)
        }
        .padding(.vertical, SpacingToken.space1)
    }
}