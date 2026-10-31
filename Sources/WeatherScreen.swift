import SwiftUI

// MARK: - Weather Screen

struct WeatherScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var weatherService: WeatherService
    @State private var selectedTab = 0

    private let tabs = ["Overview", "Winds Aloft", "PIREPs", "AIRMETs/SIGMETs"]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Tab picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpacingToken.space2) {
                        ForEach(tabs.indices, id: \.self) { index in
                            Button {
                                withAnimation(AnimationToken.tabSwitch) { selectedTab = index }
                            } label: {
                                Text(tabs[index])
                                    .font(TypographyToken.labelMedium)
                                    .foregroundStyle(selectedTab == index ? ColorToken.textOnBrand : ColorToken.textTertiary)
                                    .padding(.horizontal, SpacingToken.space4)
                                    .padding(.vertical, SpacingToken.space2)
                                    .background(
                                        selectedTab == index ? ColorToken.brandPrimary : ColorToken.surfaceCard,
                                        in: Capsule()
                                    )
                            }
                        }
                    }
                    .padding(.horizontal, SpacingToken.insetMedium)
                }
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
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(ColorToken.surfaceBase)
            .navigationTitle("Weather")
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
        for airport in model.waypoints {
            async let metar = weatherService.fetchMETAR(for: airport.id)
            async let taf = weatherService.fetchTAF(for: airport.id)
            _ = await (metar, taf)
        }

        if model.showWindsAloft {
            await weatherService.fetchWindsAloft()
        }
        if model.showPIREPs {
            await weatherService.fetchPIREPs()
        }
        if model.showAIRMETs {
            await weatherService.fetchAIRMETs()
        }
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
                        SectionHeader(title: "Route Weather")
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
                    SectionHeader(title: "Waypoint Weather")
                }

                // Nearby weather
                Section {
                    NearbyWeatherList()
                } header: {
                    SectionHeader(title: "Nearby Airports")
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
                Text("Route Category")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text(worstCategory)
                    .font(TypographyToken.monoLarge)
                    .foregroundStyle(categoryColor)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: SpacingToken.space2) {
                Text("Waypoints")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text("\(model.waypoints.count)")
                    .font(TypographyToken.monoLarge)
                    .foregroundStyle(ColorToken.textPrimary)
            }

            VStack(alignment: .trailing, spacing: SpacingToken.space2) {
                Text("With WX")
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

                    Text(metar.observationTime.formatted(date: .omitted, time: .shortened))
                        .font(TypographyToken.monoXSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                }
            }

            if let decoded = metar.decoded {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: SpacingToken.space3) {
                    WeatherDetailItem(label: "Wind", value: decoded.wind ?? "—", icon: "wind")
                    WeatherDetailItem(label: "Vis", value: decoded.visibility.map { String(format: "%.1f SM", $0) } ?? "—", icon: "eye")
                    WeatherDetailItem(label: "Ceiling", value: decoded.ceiling.map { "\($0) ft" } ?? "—", icon: "cloud")
                    WeatherDetailItem(label: "Temp", value: decoded.temperature.map { "\($0)°C" } ?? "—", icon: "thermometer")
                    WeatherDetailItem(label: "Altimeter", value: decoded.altimeter.map { String(format: "%.2f inHg", $0) } ?? "—", icon: "gauge")
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
        }
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
                Text("Load METAR")
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
        return store.nearest(to: loc, maxCount: 10)
    }

    var body: some View {
        ForEach(nearby.prefix(10)) { airport in
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

    var body: some View {
        ScrollView {
            if weatherService.windsAloft.isEmpty {
                ContentUnavailableView(
                    "No Winds Aloft Data",
                    systemImage: "wind",
                    description: Text("Enable Winds Aloft layer to load forecast data")
                )
            } else {
                LazyVStack(spacing: SpacingToken.space3) {
                    ForEach(weatherService.windsAloft) { wind in
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
                Text("Valid: \(wind.validTime)")
                    .font(TypographyToken.monoSmall)
                    .foregroundStyle(ColorToken.textTertiary)
            }

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: SpacingToken.space3) {
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

            HStack(spacing: SpacingToken.space1) {
                Image(systemName: "arrow.up")
                    .font(.system(size: 10))
                    .rotationEffect(.degrees(Double(level.direction)))
                Text("\(level.speed) kt")
                    .font(TypographyToken.monoSmall)
            }
            .foregroundStyle(ColorToken.textPrimary)

            if let temp = level.temperature {
                Text("\(temp)°C")
                    .font(TypographyToken.monoXSmall)
                    .foregroundStyle(ColorToken.textSecondary)
            }
        }
    }
}

// MARK: - PIREPs Tab

struct PIREPsTab: View {
    @EnvironmentObject private var weatherService: WeatherService

    var body: some View {
        ScrollView {
            if weatherService.pireps.isEmpty {
                ContentUnavailableView(
                    "No PIREPs",
                    systemImage: "bubble.left.and.bubble.right",
                    description: Text("Enable PIREPs layer to load pilot reports")
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
                    "No AIRMETs/SIGMETs",
                    systemImage: "exclamationmark.triangle",
                    description: Text("Enable AIRMETs layer to load in-flight advisories")
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