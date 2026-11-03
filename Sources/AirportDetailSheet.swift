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

    /// Pushed inside the Airports tab (no own navigation stack, no Done button).
    var embedded = false
    @State private var section: AirportSection = .info

    /// ForeFlight airport view tabs.
    enum AirportSection: String, CaseIterable, Identifiable {
        case info = "Info", weather = "Météo", runways = "Pistes", procedures = "Procéd.", notam = "NOTAM", fbo = "FBO"
        var id: String { rawValue }
    }

    var body: some View {
        if embedded {
            content
        } else {
            NavigationStack {
                content
                    .toolbar {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button("OK") { dismiss() }
                        }
                    }
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var content: some View {
        List {
            Section {
                FFAirportHeader(airport: airport, metar: metar, typeText: airportTypeDisplay,
                                isFavorite: model.isFavorite(airport.id),
                                onDirect: {
                                    model.directTo(airport)
                                    if !embedded { dismiss() }
                                },
                                onAdd: {
                                    model.addWaypoint(airport)
                                    if !embedded { dismiss() }
                                },
                                onMap: {
                                    model.moveMap(to: airport.coordinate, span: 0.3)
                                    FFRouter.shared.tab = .maps
                                    if !embedded { dismiss() }
                                },
                                onFavorite: { model.toggleFavorite(airport.id) })
                Picker("Section", selection: $section) {
                    ForEach(AirportSection.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(FF.barSecondary)
            }
            .listRowInsets(EdgeInsets())
            .listRowBackground(Color.clear)

            switch section {
            case .info: infoSections
            case .weather: weatherSections
            case .runways: runwaySections
            case .procedures: AirportDocumentsSection(ident: airport.id)
            case .notam: NOTAMSection(icao: airport.icao ?? airport.id)
            case .fbo: FuelPriceSection(airport: airport, store: store)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(airport.id)
        .navigationBarTitleDisplayMode(.inline)
        .task {
            model.markViewed(airport.id)
            await weatherService.fetchMETAR(for: airport.id)
            await weatherService.fetchTAF(for: airport.id)
        }
    }

    @ViewBuilder private var infoSections: some View {
        Section {
            InfoRow(icon: "building.2", title: "Type", value: airportTypeDisplay)
            InfoRow(icon: "mappin", title: "Coordonnées", value: coordinateString)
            InfoRow(icon: "mountain.2", title: "Élévation", value: airport.elevationFt.map { "\($0) ft" } ?? "—")
            if let municipality = airport.municipality {
                InfoRow(icon: "building", title: "Ville", value: municipality)
            }
            if let longest = runways.compactMap(\.lengthFt).max() {
                InfoRow(icon: "road.lanes", title: "Piste la plus longue", value: "\(longest) ft")
            }
            if let ctaf = frequencies.first(where: { ["CTAF", "UNIC", "TWR"].contains($0.type.uppercased()) }) {
                InfoRow(icon: "antenna.radiowaves.left.and.right", title: ctaf.type.uppercased(),
                        value: ctaf.mhz)
            }
        } header: { FFHeader("Aéroport") }
        if let metar {
            Section { METARCard(metar: metar) } header: { FFHeader("METAR") }
        }
        frequencySections
        Section {
            HStack {
                Label("Lever / coucher", systemImage: "sun.horizon")
                Spacer()
                Text(sunText).foregroundStyle(.secondary).monospacedDigit()
            }
        } header: { FFHeader("Soleil") }
    }

    @ViewBuilder private var weatherSections: some View {
        if let metar {
            Section { METARCard(metar: metar) } header: { FFHeader("METAR") }
        } else {
            Section { Text("Pas de METAR pour \(airport.id)").foregroundStyle(.secondary) } header: { FFHeader("METAR") }
            NearestMETARSection(airport: airport, store: store)
        }
        if let taf {
            Section { TAFCard(taf: taf) } header: { FFHeader("TAF") }
        } else if let fisbTAF = FISBStore.shared.report("TAF", at: airport.id) {
            Section {
                Text(fisbTAF.text).font(.caption.monospaced()).textSelection(.enabled)
            } header: { FFHeader("TAF (reçu par ADS-B)") }
        }
    }

    @ViewBuilder private var runwaySections: some View {
        if runways.contains(where: { $0.leLat != nil && $0.heLat != nil }) {
            Section {
                AirportTaxiMap(airport: airport, runways: runways)
                    .frame(height: 280)
                    .listRowInsets(EdgeInsets())
            } header: { FFHeader("Vue aérodrome") }
        }
        Section {
            if runways.isEmpty { Text("Aucune donnée").foregroundStyle(.secondary) }
            ForEach(runways) { RunwayRow(runway: $0) }
        } header: { FFHeader("Pistes") }
        if !runways.isEmpty {
            RunwayAnalysisSection(airport: airport, runways: runways, metar: metar)
        }
    }

    @ViewBuilder private var frequencySections: some View {
        Section {
            if frequencies.isEmpty { Text("Aucune donnée").foregroundStyle(.secondary) }
            ForEach(frequencies) { FrequencyRow(frequency: $0) }
        } header: { FFHeader("Fréquences") }
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

    /// Local sunrise / sunset today, "06:52 – 18:31".
    private var sunText: String {
        let sun = Solar.sunriseSunset(lat: airport.coordinate.latitude, lon: airport.coordinate.longitude)
        let f = { (d: Date?) in d?.formatted(date: .omitted, time: .shortened) ?? "—" }
        return "\(f(sun.sunrise)) – \(f(sun.sunset))"
    }

    private var coordinateString: String {
        let lat = airport.coordinate.latitude
        let lon = airport.coordinate.longitude
        let latDir = lat >= 0 ? "N" : "S"
        let lonDir = lon >= 0 ? "E" : "W"
        return String(format: "%02d°%02d'%@ %03d°%02d'%@",
                      Int(abs(lat)), Int((abs(lat).truncatingRemainder(dividingBy: 1)) * 60), latDir,
                      Int(abs(lon)), Int((abs(lon).truncatingRemainder(dividingBy: 1)) * 60), lonDir)
    }
}

// MARK: - ForeFlight airport header

/// Charcoal band: identifier, flight category, name and city, then Direct · Ajouter · Carte · ☆.
struct FFAirportHeader: View {
    let airport: Airport
    let metar: METAR?
    let typeText: String
    let isFavorite: Bool
    let onDirect: () -> Void
    let onAdd: () -> Void
    let onMap: () -> Void
    let onFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(airport.id)
                    .font(TypographyToken.displayMedium)
                    .foregroundStyle(ColorToken.brandSecondary)
                if let metar, metar.flightCategory != .unknown {
                    Text(metar.flightCategory.rawValue)
                        .font(.system(size: 13, weight: .heavy))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 8).padding(.vertical, 3)
                        .background(metar.flightCategory.color, in: RoundedRectangle(cornerRadius: 4))
                }
                Spacer()
                Text(airport.elevationFt.map { "\($0) ft" } ?? "")
                    .font(.system(size: 14, weight: .semibold).monospacedDigit())
                    .foregroundStyle(FF.label)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(airport.name).font(TypographyToken.headlineMedium).foregroundStyle(ColorToken.textPrimary).lineLimit(2)
                Text([airport.municipality, typeText].compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 13)).foregroundStyle(FF.label)
            }
            HStack(spacing: 8) {
                FFBarButton(title: "Direct", icon: "location.north.line.fill", action: onDirect)
                FFBarButton(title: "Ajouter", icon: "plus", action: onAdd)
                FFBarButton(title: "Carte", icon: "map", action: onMap)
                Spacer(minLength: 0)
                FFBarButton(title: nil, icon: isFavorite ? "star.fill" : "star", active: isFavorite, action: onFavorite)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(FF.bar)
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
                BadgeView(text: airport.elevationFt.map { "\($0) ft MSL" } ?? "— ft MSL", color: ColorToken.info)
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
                Text(runway.name)
                    .font(TypographyToken.monoLarge)
                    .foregroundStyle(ColorToken.brandPrimary)
                if let length = runway.lengthFt, let width = runway.widthFt {
                    Text("\(length) × \(width) ft")
                        .font(TypographyToken.monoXSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                }
            }
            .frame(width: 80, alignment: .leading)

            // Surface
            VStack(alignment: .leading, spacing: SpacingToken.space0) {
                Text("Surface")
                    .font(TypographyToken.labelXSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text(runway.surface ?? "—")
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
            Text(frequency.type)
                .font(TypographyToken.monoXSmall)
                .foregroundStyle(ColorToken.textOnBrand)
                .padding(.horizontal, SpacingToken.space2)
                .padding(.vertical, SpacingToken.space0)
                .background(frequencyTypeColor(frequency.type), in: Capsule())

            // Frequency value
            Text(frequency.mhz)
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
