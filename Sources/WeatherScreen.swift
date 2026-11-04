import SwiftUI
import CoreLocation

// MARK: - Weather Screen

struct WeatherScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var weatherService: WeatherService
    @State private var selectedTab = 0

    private let tabs = ["Aperçu", "Vents", "PIREPs", "AIRMET", "Cartes"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Section", selection: $selectedTab) {
                    ForEach(tabs.indices, id: \.self) { index in
                        Text(tabs[index]).tag(index)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal, SpacingToken.insetMedium)
                .padding(.vertical, SpacingToken.space3)

                // Content
                TabView(selection: $selectedTab) {
                    WeatherOverviewTab()
                        .tag(0)

                    WindsAloftTab()
                        .tag(1)

                    PIREPsTab()
                        .tag(2)

                    AIRMETsTab()
                        .tag(3)

                    WeatherChartsTab()
                        .tag(4)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(ColorToken.surfaceBase)
            .task {
                if weatherService.windsAloft.isEmpty && weatherService.airsigmets.isEmpty {
                    await refreshAllWeather()
                }
            }
            .navigationTitle("Météo")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await refreshAllWeather() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .disabled(weatherService.isLoading)
                }
            }
        }
    }

    private func refreshAllWeather() async {
        for airport in model.waypoints where airport.id != AppModel.gpsWaypointID {
            async let metar = weatherService.fetchMETAR(for: airport.id)
            async let taf = weatherService.fetchTAF(for: airport.id)
            _ = await (metar, taf)
        }

        async let winds: Void = weatherService.fetchWindsAloft()
        async let pireps: Void = weatherService.fetchPIREPs()
        async let airmets: Void = weatherService.fetchAIRMETs()
        _ = await (winds, pireps, airmets)
    }
}

// MARK: - Weather Overview Tab

struct WeatherOverviewTab: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var weatherService: WeatherService

    var body: some View {
        ScrollView {
            LazyVStack(spacing: SpacingToken.space4, pinnedViews: [.sectionHeaders]) {
                // Route weather summary
                if !model.waypoints.isEmpty {
                    Section {
                        RouteWeatherSummary()
                    } header: {
                        SectionHeader(title: "Météo de la route")
                    }
                }

                // Waypoint weather
                Section {
                    ForEach(model.waypoints) { airport in
                        if let metar = weatherService.metars[airport.id] {
                            WaypointWeatherCard(airport: airport, metar: metar)
                        } else {
                            WaypointWeatherPlaceholder(airport: airport)
                        }
                    }
                } header: {
                    SectionHeader(title: "Météo des points")
                }

                // Nearby weather
                Section {
                    NearbyWeatherList()
                } header: {
                    SectionHeader(title: "Aéroports proches")
                }
            }
            .padding(.horizontal, SpacingToken.insetMedium)
            .padding(.bottom, SpacingToken.space8)
        }
        .background(ColorToken.surfaceBase)
        .refreshable {
            await refreshVisibleWeather()
        }
    }

    private func refreshVisibleWeather() async {
        for airport in model.waypoints {
            async let metar = weatherService.fetchMETAR(for: airport.id)
            async let taf = weatherService.fetchTAF(for: airport.id)
            _ = await (metar, taf)
        }
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        HStack {
            Text(title)
                .font(TypographyToken.labelSmall)
                .foregroundStyle(ColorToken.textTertiary)
                .textCase(.uppercase)
            Spacer()
        }
        .padding(.vertical, SpacingToken.space2)
        .background(ColorToken.surfaceBase)
    }
}

struct RouteWeatherSummary: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var weatherService: WeatherService

    private var worstCategory: String {
        let categories = model.waypoints.compactMap { weatherService.metars[$0.id]?.flightCategory.rawValue }
        let order = ["LIFR", "IFR", "MVFR", "VFR"]
        return order.first { cat in categories.contains(cat) } ?? "VFR"
    }

    private var categoryColor: Color {
        switch worstCategory {
        case "VFR": return ColorToken.vfr
        case "MVFR": return ColorToken.mvfr
        case "IFR": return ColorToken.ifr
        case "LIFR": return ColorToken.lifr
        default: return ColorToken.textTertiary
        }
    }

    var body: some View {
        HStack(spacing: SpacingToken.space4) {
            VStack(alignment: .leading, spacing: SpacingToken.space2) {
                Text("Catégorie route")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text(worstCategory)
                    .font(TypographyToken.monoLarge)
                    .foregroundStyle(categoryColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: SpacingToken.space2) {
                Text("Points")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text("\(model.waypoints.count)")
                    .font(TypographyToken.monoLarge)
                    .foregroundStyle(ColorToken.textPrimary)
            }

            VStack(alignment: .trailing, spacing: SpacingToken.space2) {
                Text("Avec météo")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text("\(model.waypoints.filter { weatherService.metars[$0.id] != nil }.count)")
                    .font(TypographyToken.monoLarge)
                    .foregroundStyle(ColorToken.textPrimary)
            }
        }
        .padding(SpacingToken.cardPadding)
        .background(categoryColor.opacity(0.1), in: RoundedRectangle(cornerRadius: RadiusToken.card))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusToken.card)
                .stroke(categoryColor.opacity(0.3), lineWidth: 1)
        )
    }
}

struct WaypointWeatherCard: View {
    let airport: Airport
    let metar: METAR

    var body: some View {
        VStack(spacing: SpacingToken.space3) {
            HStack {
                VStack(alignment: .leading, spacing: SpacingToken.space0) {
                    Text(airport.id)
                        .font(TypographyToken.monoMedium)
                        .foregroundStyle(ColorToken.textPrimary)
                    Text(airport.name)
                        .font(TypographyToken.bodySmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SpacingToken.space0) {
                    Text(metar.flightCategory.rawValue)
                        .font(TypographyToken.monoMedium)
                        .foregroundStyle(ColorToken.textOnBrand)
                        .padding(.horizontal, SpacingToken.space3)
                        .padding(.vertical, SpacingToken.space1)
                        .background(categoryColor(metar.flightCategory.rawValue), in: Capsule())

                    let stale = Date.now.timeIntervalSince(metar.observationTime) > 75 * 60
                    Text("\(metar.observationTime.formatted(date: .omitted, time: .shortened)) · \(metar.observationTime.zulu)")
                        .font(TypographyToken.monoXSmall)
                        .foregroundStyle(stale ? ColorToken.warning : ColorToken.textTertiary)
                    if stale {
                        Text("METAR ancien").font(TypographyToken.labelXSmall).foregroundStyle(ColorToken.warning)
                    }
                }
            }

            if let decoded = metar.decoded {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .topLeading), GridItem(.flexible(), alignment: .topLeading)],
                          spacing: SpacingToken.space3) {
                    WeatherDetailItem(label: "Vent", value: decoded.wind ?? "—", icon: "wind")
                    WeatherDetailItem(label: "Visibilité", value: decoded.visibility.map { String(format: "%.1f SM", $0) } ?? "—", icon: "eye")
                    WeatherDetailItem(label: "Plafond", value: decoded.ceiling.map { "\($0) ft" } ?? "—", icon: "cloud")
                    WeatherDetailItem(label: "Température", value: decoded.temperature.map { "\($0)°C" } ?? "—", icon: "thermometer")
                    WeatherDetailItem(label: "Altimètre", value: decoded.altimeter.map { String(format: "%.2f inHg", $0) } ?? "—", icon: "gauge")
                }
            }

            Text(metar.rawText)
                .font(TypographyToken.monoXSmall)
                .foregroundStyle(ColorToken.textTertiary)
                .lineLimit(2)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(SpacingToken.cardPadding)
        .background(ColorToken.surfaceCard, in: RoundedRectangle(cornerRadius: RadiusToken.card))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusToken.card)
                .stroke(ColorToken.borderDefault, lineWidth: 0.5)
        )
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

struct WeatherDetailItem: View {
    let label: String
    let value: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space0) {
            HStack(spacing: SpacingToken.space1) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                Text(label)
                    .font(TypographyToken.labelXSmall)
            }
            .foregroundStyle(ColorToken.textTertiary)
            Text(value)
                .font(TypographyToken.monoSmall)
                .foregroundStyle(ColorToken.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct WaypointWeatherPlaceholder: View {
    let airport: Airport
    @EnvironmentObject private var weatherService: WeatherService

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: SpacingToken.space0) {
                Text(airport.id)
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
                Text(airport.name)
                    .font(TypographyToken.bodySmall)
                    .foregroundStyle(ColorToken.textTertiary)
                    .lineLimit(1)
            }

            Spacer()

            Button {
                Task { await weatherService.fetchMETAR(for: airport.id) }
            } label: {
                Text("Charger le METAR")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.brandPrimary)
                    .padding(.horizontal, SpacingToken.space3)
                    .padding(.vertical, SpacingToken.space1)
                    .background(ColorToken.brandPrimary.opacity(0.1), in: Capsule())
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

struct NearbyWeatherList: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var weatherService: WeatherService

    private var nearby: [Airport] {
        guard let loc = model.userLocation else { return [] }
        // Only airports that can have a METAR (US ICAO codes), not heliports and private strips.
        return store.nearest(to: loc, limit: 80, matching: ["large_airport", "medium_airport", "small_airport"])
            .filter { $0.id.count == 4 && ($0.id.hasPrefix("K") || $0.id.hasPrefix("P")) }
    }

    var body: some View {
        Group { ForEach(nearby.prefix(10)) { airport in
            if let metar = weatherService.metars[airport.id] {
                HStack(spacing: SpacingToken.space3) {
                    ZStack {
                        Circle()
                            .fill(categoryColor(metar.flightCategory.rawValue))
                            .frame(width: 10, height: 10)
                    }
                    .frame(width: 24)

                    Text(airport.id)
                        .font(TypographyToken.monoSmall)
                        .foregroundStyle(ColorToken.textPrimary)

                    Text(metar.flightCategory.rawValue)
                        .font(TypographyToken.monoXSmall)
                        .foregroundStyle(categoryColor(metar.flightCategory.rawValue))
                        .padding(.horizontal, SpacingToken.space2)
                        .padding(.vertical, SpacingToken.space0)
                        .background(categoryColor(metar.flightCategory.rawValue).opacity(0.1), in: Capsule())

                    Spacer()

                    if let decoded = metar.decoded {
                        Text(decoded.wind)
                            .font(TypographyToken.monoXSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                    }
                }
                .padding(.vertical, SpacingToken.space1)
                .padding(.horizontal, SpacingToken.space3)
                .background(ColorToken.surfaceCard, in: RoundedRectangle(cornerRadius: RadiusToken.md))
            } else {
                Button {
                    Task { await weatherService.fetchMETAR(for: airport.id) }
                } label: {
                    HStack {
                        Text(airport.id)
                            .font(TypographyToken.monoSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Spacer()
                        Image(systemName: "cloud")
                            .font(.system(size: 14))
                            .foregroundStyle(ColorToken.textTertiary)
                    }
                }
                .buttonStyle(.plain)
            }
        } }
        .task(id: nearby.map(\.id)) {
            await weatherService.refreshMETARs(forVisible: nearby.map(\.id))
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

// MARK: - Winds Aloft Tab

struct WindsAloftTab: View {
    @EnvironmentObject private var weatherService: WeatherService
    @EnvironmentObject private var model: AppModel

    /// Stations in route order (distance from the departure along the plan), else nearest first.
    private var stations: [WindsAloft] {
        let path = model.routePath.count >= 2 ? model.routePath : model.waypoints.map(\.coordinate)
        guard let start = path.first ?? model.userLocation else { return weatherService.windsAloft }
        func key(_ w: WindsAloft) -> Double {
            let c = CLLocationCoordinate2D(latitude: w.latitude, longitude: w.longitude)
            guard path.count >= 2 else { return Haversine.nauticalMiles(start, c) }
            // Projection on the route: distance from the start to the nearest route point.
            var best = Double.infinity, along = 0.0, run = 0.0
            for i in path.indices {
                if i > 0 { run += Haversine.nauticalMiles(path[i - 1], path[i]) }
                let d = Haversine.nauticalMiles(path[i], c)
                if d < best { best = d; along = run }
            }
            return best > 60 ? 10_000 + best : along
        }
        return weatherService.windsAloft.sorted { key($0) < key($1) }
    }

    var body: some View {
        ScrollView {
            if weatherService.windsAloft.isEmpty {
                ContentUnavailableView(
                    "Pas de vents en altitude",
                    systemImage: "wind",
                    description: Text("Tirez vers le bas pour charger les vents FD de Floride.")
                )
            } else {
                LazyVStack(spacing: SpacingToken.space3) {
                    ForEach(stations) { wind in
                        WindsAloftCard(wind: wind)
                    }
                }
                .padding(.horizontal, SpacingToken.insetMedium)
                .padding(.bottom, SpacingToken.space8)
            }
        }
        .background(ColorToken.surfaceBase)
        .refreshable {
            await weatherService.fetchWindsAloft()
        }
    }
}

struct WindsAloftCard: View {
    let wind: WindsAloft

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space3) {
            HStack {
                Text(wind.station)
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
                Spacer()
                Text("Valide \(wind.validTime)")
                    .font(TypographyToken.monoSmall)
                    .foregroundStyle(ColorToken.textTertiary)
            }

            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), alignment: .topLeading), count: 4), spacing: SpacingToken.space3) {
                ForEach(wind.levels) { level in
                    WindLevelView(level: level)
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

struct WindLevelView: View {
    let level: WindsAloftLevel

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space1) {
            Text("\(level.altitude) ft")
                .font(TypographyToken.labelXSmall)
                .foregroundStyle(ColorToken.textTertiary)

            if (level.direction == 0 && level.speed == 0) || level.direction >= 990 {
                Text("Variable").font(TypographyToken.monoSmall).foregroundStyle(ColorToken.textPrimary)
            } else {
                HStack(spacing: SpacingToken.space1) {
                    // FD direction is where the wind comes FROM; the arrow shows where it blows.
                    Image(systemName: "arrow.up")
                        .font(.system(size: 10))
                        .rotationEffect(.degrees(Double(level.direction) + 180))
                    Text(String(format: "%03d° %d kt", level.direction, level.speed))
                        .font(TypographyToken.monoSmall)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
                .foregroundStyle(ColorToken.textPrimary)
            }

            // Placeholder keeps every column the same height (FD has no temperature at 3 000 ft).
            Text(level.temperature.map { "\($0)°C" } ?? " ")
                .font(TypographyToken.monoXSmall)
                .foregroundStyle(ColorToken.textSecondary)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

// MARK: - PIREPs Tab

struct PIREPsTab: View {
    @EnvironmentObject private var weatherService: WeatherService

    var body: some View {
        ScrollView {
            if weatherService.pireps.isEmpty {
                ContentUnavailableView(
                    "Aucun PIREP",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Aucun PIREP en Floride ces 3 dernières heures. Tirez pour actualiser.")
                )
            } else {
                LazyVStack(spacing: SpacingToken.space3) {
                    ForEach(weatherService.pireps) { pirep in
                        PIREPCard(pirep: pirep)
                    }
                }
                .padding(.horizontal, SpacingToken.insetMedium)
                .padding(.bottom, SpacingToken.space8)
            }
        }
        .background(ColorToken.surfaceBase)
        .refreshable {
            await weatherService.fetchPIREPs()
        }
    }
}

struct PIREPCard: View {
    let pirep: PIREP

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space3) {
            HStack {
                Text(pirep.location)
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
                Spacer()
                Text(pirep.time.formatted(date: .omitted, time: .shortened))
                    .font(TypographyToken.monoSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text(pirep.aircraftType)
                    .font(TypographyToken.labelXSmall)
                    .foregroundStyle(ColorToken.brandPrimary)
                    .padding(.horizontal, SpacingToken.space2)
                    .padding(.vertical, SpacingToken.space0)
                    .background(ColorToken.brandPrimary.opacity(0.1), in: Capsule())
            }

            Text(pirep.rawText)
                .font(TypographyToken.monoSmall)
                .foregroundStyle(ColorToken.textSecondary)
                .lineLimit(3)

            if !pirep.elements.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpacingToken.space2) {
                        ForEach(pirep.elements) { element in
                            PIREPElementBadge(element: element)
                        }
                    }
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

struct PIREPElementBadge: View {
    let element: PIREPElement

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space0) {
            Text(element.type)
                .font(TypographyToken.labelXSmall)
                .foregroundStyle(ColorToken.textTertiary)
            Text(element.value)
                .font(TypographyToken.monoSmall)
                .foregroundStyle(element.severityColor)
        }
        .padding(.horizontal, SpacingToken.space3)
        .padding(.vertical, SpacingToken.space2)
        .background(element.severityColor.opacity(0.1), in: RoundedRectangle(cornerRadius: RadiusToken.md))
    }
}

// MARK: - AIRMETs/SIGMETs Tab

struct AIRMETsTab: View {
    @EnvironmentObject private var weatherService: WeatherService

    var body: some View {
        ScrollView {
            if weatherService.airsigmets.isEmpty {
                ContentUnavailableView(
                    "Aucun AIRMET/SIGMET",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Aucun avis en cours sur la Floride. Tirez pour actualiser.")
                )
            } else {
                LazyVStack(spacing: SpacingToken.space3) {
                    ForEach(weatherService.airsigmets) { advisory in
                        AirSigmetCard(advisory: advisory)
                    }
                }
                .padding(.horizontal, SpacingToken.insetMedium)
                .padding(.bottom, SpacingToken.space8)
            }
        }
        .background(ColorToken.surfaceBase)
        .refreshable {
            await weatherService.fetchAIRMETs()
        }
    }
}

struct AirSigmetCard: View {
    let advisory: AirSigmet

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space3) {
            HStack {
                Text(advisory.displayType)
                    .font(TypographyToken.monoSmall)
                    .foregroundStyle(ColorToken.textOnBrand)
                    .padding(.horizontal, SpacingToken.space3)
                    .padding(.vertical, SpacingToken.space1)
                    .background(advisory.hazardColor, in: Capsule())

                Text(advisory.sequence)
                    .font(TypographyToken.monoSmall)
                    .foregroundStyle(ColorToken.textSecondary)

                Spacer()

                Text(advisory.validTime)
                    .font(TypographyToken.monoSmall)
                    .foregroundStyle(ColorToken.textTertiary)
            }

            Text(advisory.hazard)
                .font(TypographyToken.bodyMedium)
                .foregroundStyle(ColorToken.textPrimary)

            Text(advisory.rawText)
                .font(TypographyToken.monoSmall)
                .foregroundStyle(ColorToken.textTertiary)
                .lineLimit(3)
        }
        .padding(SpacingToken.cardPadding)
        .background(ColorToken.surfaceCard, in: RoundedRectangle(cornerRadius: RadiusToken.card))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusToken.card)
                .stroke(advisory.hazardColor.opacity(0.3), lineWidth: 1)
        )
    }
}

// MARK: - Charts (aviationweather.gov images)

/// Surface analysis and WPC prognostic charts; tap one to zoom.
struct WeatherChartsTab: View {
    private static let charts: [(String, String)] = [
        ("Analyse de surface", "F000_wpc_sfc"),
        ("Prévision +6 h", "F006_wpc_prog"),
        ("Prévision +12 h", "F012_wpc_prog"),
        ("Prévision +18 h", "F018_wpc_prog"),
        ("Prévision +24 h", "F024_wpc_prog"),
        ("Prévision +48 h", "F048_wpc_prog")
    ]
    @State private var zoomed: URL?

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: SpacingToken.space4) {
                ForEach(Self.charts, id: \.1) { title, file in
                    let url = URL(string: "https://aviationweather.gov/data/products/progs/\(file).gif")!
                    VStack(alignment: .leading, spacing: SpacingToken.space2) {
                        Text(title).font(TypographyToken.labelMedium)
                        AsyncImage(url: url) { image in
                            image.resizable().scaledToFit()
                        } placeholder: {
                            ProgressView().frame(maxWidth: .infinity, minHeight: 160)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        .onTapGesture { zoomed = url }
                    }
                }
            }
            .padding(SpacingToken.insetMedium)
        }
        .sheet(item: $zoomed) { url in
            NavigationStack {
                ScrollView([.horizontal, .vertical]) {
                    AsyncImage(url: url) { $0.resizable().scaledToFit().frame(width: 1400) } placeholder: { ProgressView() }
                }
                .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { zoomed = nil } } }
            }
        }
    }
}

extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}
