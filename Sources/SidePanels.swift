import SwiftUI

// MARK: - Flight Plan Side Panel

struct FlightPlanSidePanel: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var routingEngine: RoutingEngine
    @Binding var isPresented: Bool
    @Binding var routePolyline: [CLLocationCoordinate2D]
    @Binding var routeWarnings: [RouteWarning]

    @State private var showingEditor = false

    var body: some View {
        NavigationStack {
            List {
                // Active Route Summary
                if !model.waypoints.isEmpty {
                    Section {
                        ActiveRouteCard(
                            routePolyline: $routePolyline,
                            routeWarnings: $routeWarnings
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }

                // Waypoints
                Section {
                    if model.waypoints.isEmpty {
                        ContentUnavailableView(
                            "No Waypoints",
                            systemImage: "mappin.slash",
                            description: Text("Add airports to build your flight plan")
                        )
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                        .frame(minHeight: 120)
                    } else {
                        ForEach(Array(model.waypoints.enumerated()), id: \.element.id) { index, airport in
                            WaypointRow(
                                index: index,
                                airport: airport,
                                isFirst: index == 0,
                                isLast: index == model.waypoints.count - 1,
                                leg: index < model.legs.count ? model.legs[index] : nil
                            )
                            .listRowInsets(EdgeInsets(top: SpacingToken.space1, leading: SpacingToken.insetMedium, bottom: SpacingToken.space1, trailing: SpacingToken.insetMedium))
                        }
                        .onDelete { model.waypoints.remove(atOffsets: $0) }
                        .onMove { model.waypoints.move(fromOffsets: $0, toOffset: $1) }
                    }

                    Button {
                        showingEditor = true
                    } label: {
                        Label("Add Waypoint", systemImage: "plus.circle.fill")
                            .font(TypographyToken.labelMedium)
                            .foregroundStyle(ColorToken.brandPrimary)
                            .frame(maxWidth: .infinity, alignment: .center)
                            .padding(.vertical, SpacingToken.space3)
                    }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                } header: {
                    HStack {
                        Text("Waypoints")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                            .textCase(.uppercase)
                        Spacer()
                        if !model.waypoints.isEmpty {
                            EditButton()
                                .font(TypographyToken.labelSmall)
                        }
                    }
                }

                // Performance Section
                if model.waypoints.count >= 2 {
                    Section {
                        PerformanceCard()
                    } header: {
                        Text("Performance")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                            .textCase(.uppercase)
                    }
                }

                // Route Options
                Section {
                    RouteOptionsCard()
                } header: {
                    Text("Route Options")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                }

                // Warnings
                if !routeWarnings.isEmpty {
                    Section {
                        ForEach(routeWarnings) { warning in
                            RouteWarningRow(warning: warning)
                        }
                    } header: {
                        Text("Airspace Warnings")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                            .textCase(.uppercase)
                    }
                }

                // Actions
                if model.waypoints.count >= 2 {
                    Section {
                        Button {
                            Task { await calculateRoute() }
                        } label: {
                            Label("Calculate Route", systemImage: "arrow.triangle.turn.up.right.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryButton(size: .regular)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                        Button {
                            model.logFlight(
                                from: model.waypoints.first!.id,
                                to: model.waypoints.last!.id,
                                nm: Int(model.totalDistanceNM.rounded()),
                                eteMinutes: Int(model.totalTimeMinutes.rounded())
                            )
                        } label: {
                            Label("Log Flight", systemImage: "book.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .secondaryButton()
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)

                        Button(role: .destructive) {
                            withAnimation { model.clearFlightPlan() }
                        } label: {
                            Label("Clear Flight Plan", systemImage: "trash")
                                .frame(maxWidth: .infinity)
                        }
                        .destructiveButton(filled: false)
                        .listRowInsets(EdgeInsets())
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ColorToken.surfaceBase)
            .navigationTitle("Flight Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        withAnimation(AnimationToken.spring) { isPresented = false }
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingEditor = true
                    } label: {
                        Image(systemName: "pencil")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showingEditor) {
                FlightPlanEditorSheet()
            }
        }
        .frame(maxWidth: LayoutToken.sidebarWidthRegular)
        .background(ColorToken.surfaceBase)
    }

    private func calculateRoute() async {
        _ = await routingEngine.calculateRoute(
            waypoints: model.waypoints,
            cruiseAltitude: model.cruiseAlt,
            mode: routingEngine.currentMode,
            airspaces: AirspaceDataManager.shared.airspaces
        )
    }
}

// MARK: - Active Route Card

struct ActiveRouteCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var routingEngine: RoutingEngine
    @Binding var routePolyline: [CLLocationCoordinate2D]
    @Binding var routeWarnings: [RouteWarning]

    var body: some View {
        VStack(spacing: SpacingToken.space4) {
            // Origin → Destination
            HStack(spacing: SpacingToken.space4) {
                VStack(alignment: .leading, spacing: SpacingToken.space1) {
                    Text("FROM")
                        .font(TypographyToken.labelXSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                    Text(model.waypoints.first?.id ?? "—")
                        .font(TypographyToken.monoLarge)
                        .foregroundStyle(ColorToken.textPrimary)
                    if let name = model.waypoints.first?.name {
                        Text(name)
                            .font(TypographyToken.bodySmall)
                            .foregroundStyle(ColorToken.textSecondary)
                            .lineLimit(1)
                    }
                }

                Image(systemName: "arrow.right")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ColorToken.brandPrimary)
                    .padding(.horizontal, SpacingToken.space2)

                VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                    Text("TO")
                        .font(TypographyToken.labelXSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                    Text(model.waypoints.last?.id ?? "—")
                        .font(TypographyToken.monoLarge)
                        .foregroundStyle(ColorToken.textPrimary)
                    if let name = model.waypoints.last?.name {
                        Text(name)
                            .font(TypographyToken.bodySmall)
                            .foregroundStyle(ColorToken.textSecondary)
                            .lineLimit(1)
                            .multilineTextAlignment(.trailing)
                    }
                }
            }

            Divider()

            // Key metrics
            HStack(spacing: SpacingToken.space6) {
                MetricPill(
                    icon: "point.topleft.down.curvedto.point.bottomright.forward",
                    value: String(format: "%.0f NM", model.totalDistanceNM),
                    label: "Distance",
                    color: ColorToken.brandPrimary
                )

                MetricPill(
                    icon: "clock",
                    value: model.formattedTotalTime,
                    label: "Time",
                    color: ColorToken.info
                )

                MetricPill(
                    icon: "fuelpump",
                    value: String(format: "%.1f gal", model.totalFuelGallons),
                    label: "Fuel",
                    color: ColorToken.warning
                )
            }

            // Routing mode picker
            VStack(alignment: .leading, spacing: SpacingToken.space2) {
                HStack {
                    Text("Routing Mode")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                    Spacer()
                }

                Picker("Mode", selection: $routingEngine.currentMode) {
                    ForEach(RoutingEngine.RoutingMode.allCases) { mode in
                        HStack {
                            Image(systemName: mode.icon)
                            Text(mode.rawValue)
                        }.tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }

            // Warnings summary
            if !routeWarnings.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpacingToken.space2) {
                        ForEach(routeWarnings) { warning in
                            WarningBadge(warning: warning)
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
        .padding(.horizontal, SpacingToken.insetMedium)
        .padding(.vertical, SpacingToken.space2)
    }
}

struct MetricPill: View {
    let icon: String
    let value: String
    let label: String
    let color: Color

    var body: some View {
        VStack(spacing: SpacingToken.space1) {
            HStack(spacing: SpacingToken.space1) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
                Text(value)
                    .font(TypographyToken.monoMedium)
            }
            .foregroundStyle(color)

            Text(label)
                .font(TypographyToken.labelXSmall)
                .foregroundStyle(ColorToken.textTertiary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, SpacingToken.space3)
        .background(color.opacity(0.1), in: RoundedRectangle(cornerRadius: RadiusToken.md))
    }
}

struct WarningBadge: View {
    let warning: RouteWarning

    var body: some View {
        HStack(spacing: SpacingToken.space1) {
            Image(systemName: warning.type.icon)
                .font(.system(size: 10, weight: .medium))
            Text(warning.airspaceName)
                .font(TypographyToken.labelXSmall)
                .lineLimit(1)
        }
        .padding(.horizontal, SpacingToken.space2)
        .padding(.vertical, SpacingToken.space1)
        .background(Color(hex: warning.type.color).opacity(0.15), in: Capsule())
        .foregroundStyle(Color(hex: warning.type.color))
    }
}

// MARK: - Waypoint Row

struct WaypointRow: View {
    let index: Int
    let airport: Airport
    let isFirst: Bool
    let isLast: Bool
    let leg: FlightLeg?
    @EnvironmentObject private var model: AppModel

    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            // Number badge
            ZStack {
                Circle()
                    .fill(isFirst ? ColorToken.success : (isLast ? ColorToken.danger : ColorToken.brandPrimary))
                    .frame(width: 28, height: 28)
                Text("\(index + 1)")
                    .font(TypographyToken.monoXSmall)
                    .foregroundStyle(ColorToken.textOnBrand)
            }

            // Airport info
            VStack(alignment: .leading, spacing: SpacingToken.space0) {
                HStack(spacing: SpacingToken.space2) {
                    Text(airport.id)
                        .font(TypographyToken.monoMedium)
                        .foregroundStyle(ColorToken.textPrimary)

                    if model.isFavorite(airport.id) {
                        Image(systemName: "star.fill")
                            .font(.system(size: 10))
                            .foregroundStyle(ColorToken.warning)
                    }
                }

                Text(airport.name)
                    .font(TypographyToken.bodySmall)
                    .foregroundStyle(ColorToken.textSecondary)
                    .lineLimit(1)
            }

            Spacer()

            // Leg info
            if let leg = leg {
                VStack(alignment: .trailing, spacing: SpacingToken.space0) {
                    Text(leg.formattedDistance)
                        .font(TypographyToken.monoSmall)
                        .foregroundStyle(ColorToken.textPrimary)
                    HStack(spacing: SpacingToken.space1) {
                        Image(systemName: "safari")
                            .font(.system(size: 9))
                        Text(leg.courseString)
                            .font(TypographyToken.monoXSmall)
                    }
                    .foregroundStyle(ColorToken.textTertiary)
                }
            }

            // Favorite button
            Button {
                withAnimation(.snappy) { model.toggleFavorite(airport.id) }
            } label: {
                Image(systemName: model.isFavorite(airport.id) ? "star.fill" : "star")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(model.isFavorite(airport.id) ? ColorToken.warning : ColorToken.textTertiary)
            }
            .buttonStyle(.plain)
        }
        .padding(.vertical, SpacingToken.space1)
        .contentShape(Rectangle())
    }
}

// MARK: - Performance Card

struct PerformanceCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var routingEngine: RoutingEngine

    var body: some View {
        VStack(spacing: SpacingToken.space3) {
            // Aircraft selector
            if let aircraft = model.selectedAircraft {
                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space0) {
                        Text(aircraft.name)
                            .font(TypographyToken.headlineSmall)
                            .foregroundStyle(ColorToken.textPrimary)
                        Text("\(aircraft.type) • \(Int(aircraft.cruiseSpeed)) kt • \(aircraft.fuelBurn, specifier: "%.1f") gph")
                            .font(TypographyToken.bodySmall)
                            .foregroundStyle(ColorToken.textSecondary)
                    }
                    Spacer()
                    Menu {
                        ForEach(model.aircraftProfiles) { ac in
                            Button(ac.name) { model.selectAircraft(ac) }
                        }
                    } label: {
                        Image(systemName: "chevron.down.circle.fill")
                            .font(.system(size: 22))
                            .foregroundStyle(ColorToken.brandPrimary)
                    }
                }
            }

            Divider()

            // Performance inputs
            VStack(spacing: SpacingToken.space3) {
                ProfileSlider(
                    title: "Cruise Altitude",
                    value: Binding(
                        get: { Double(model.cruiseAlt) },
                        set: { model.cruiseAlt = Int($0) }
                    ),
                    range: 500...17500,
                    step: 500,
                    unit: "ft",
                    icon: "altitude",
                    format: { String(format: "%.0f", $0) }
                )

                ProfileSlider(
                    title: "Ground Speed",
                    value: $model.cruiseGS,
                    range: 40...500,
                    step: 5,
                    unit: "kt",
                    icon: "speedometer"
                )

                ProfileSlider(
                    title: "Fuel Burn",
                    value: $model.fuelBurn,
                    range: 1...100,
                    step: 0.5,
                    unit: "gal/h",
                    icon: "fuelpump"
                )

                ProfileSlider(
                    title: "Reserve",
                    value: Binding(
                        get: { Double(model.reserveMin) },
                        set: { model.reserveMin = Int($0) }
                    ),
                    range: 0...120,
                    step: 5,
                    unit: "min",
                    icon: "timer"
                )
            }

            Divider()

            // Summary
            HStack {
                VStack(alignment: .leading, spacing: SpacingToken.space1) {
                    Text("Total Fuel Required")
                        .font(TypographyToken.labelMedium)
                        .foregroundStyle(ColorToken.textSecondary)
                    Text(String(format: "%.1f gal", model.totalFuelGallons))
                        .font(TypographyToken.numberLarge)
                        .foregroundStyle(ColorToken.brandPrimary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                    Text("Endurance")
                        .font(TypographyToken.labelMedium)
                        .foregroundStyle(ColorToken.textSecondary)
                    if let ac = model.selectedAircraft {
                        Text(String(format: "%.1f hrs", ac.enduranceHours))
                            .font(TypographyToken.numberMedium)
                            .foregroundStyle(ColorToken.success)
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

struct ProfileSlider: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let icon: String
    var format: (Double) -> String = { String(format: "%.0f", $0) }

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space2) {
            HStack(spacing: SpacingToken.space2) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ColorToken.brandPrimary)
                    .frame(width: 24)
                Text(title)
                    .font(TypographyToken.labelMedium)
                    .foregroundStyle(ColorToken.textSecondary)
                Spacer()
                Text("\(format(value)) \(unit)")
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
            }

            Slider(value: $value, in: range, step: step)
                .tint(ColorToken.brandPrimary)
        }
    }
}

// MARK: - Route Options Card

struct RouteOptionsCard: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var routingEngine: RoutingEngine

    var body: some View {
        VStack(spacing: SpacingToken.space3) {
            Toggle("Avoid Class B/C/D", isOn: .constant(true))
                .toggleStyle(AviationToggleStyle())

            Toggle("Avoid Restricted/Prohibited", isOn: .constant(true))
                .toggleStyle(AviationToggleStyle())

            Toggle("Avoid MOAs", isOn: .constant(false))
                .toggleStyle(AviationToggleStyle())

            Toggle("Avoid TFRs", isOn: .constant(true))
                .toggleStyle(AviationToggleStyle())

            Divider()

            HStack {
                Text("Altitude Buffer")
                    .font(TypographyToken.labelMedium)
                    .foregroundStyle(ColorToken.textSecondary)
                Spacer()
                Text("500 ft")
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
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

// MARK: - Route Warning Row

struct RouteWarningRow: View {
    let warning: RouteWarning

    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            Image(systemName: warning.type.icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(Color(hex: warning.type.color))
                .frame(width: 28)

            VStack(alignment: .leading, spacing: SpacingToken.space0) {
                Text(warning.airspaceName)
                    .font(TypographyToken.bodySmall)
                    .foregroundStyle(ColorToken.textPrimary)
                Text(warning.message)
                    .font(TypographyToken.bodyXSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                    .lineLimit(2)
            }

            Spacer()

            Text("Leg \(warning.legIndex + 1)")
                .font(TypographyToken.monoXSmall)
                .foregroundStyle(ColorToken.textTertiary)
                .padding(.horizontal, SpacingToken.space2)
                .padding(.vertical, SpacingToken.space0)
                .background(ColorToken.surfaceElevated, in: Capsule())
        }
        .padding(.vertical, SpacingToken.space1)
    }
}

// MARK: - Flight Plan Editor Sheet

struct FlightPlanEditorSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var routingEngine: RoutingEngine
    @Environment(\.dismiss) private var dismiss
    @State private var searchQuery = ""

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.waypoints) { wp in
                        WaypointRow(
                            index: model.waypoints.firstIndex(where: { $0.id == wp.id }) ?? 0,
                            airport: wp,
                            isFirst: model.waypoints.first?.id == wp.id,
                            isLast: model.waypoints.last?.id == wp.id,
                            leg: nil
                        )
                    }
                    .onDelete { model.waypoints.remove(atOffsets: $0) }
                    .onMove { model.waypoints.move(fromOffsets: $0, toOffset: $1) }
                } header: {
                    Text("Waypoints (drag to reorder)")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                }

                Section {
                    Button {
                        // Would show airport search
                    } label: {
                        Label("Add Waypoint", systemImage: "plus.circle.fill")
                            .font(TypographyToken.labelMedium)
                            .foregroundStyle(ColorToken.brandPrimary)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Edit Flight Plan")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        Task {
                            _ = await routingEngine.calculateRoute(
                                waypoints: model.waypoints,
                                cruiseAltitude: model.cruiseAlt,
                                mode: routingEngine.currentMode,
                                airspaces: AirspaceDataManager.shared.airspaces
                            )
                        }
                        dismiss()
                    }
                    .primaryButton(size: .small)
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Layers Side Panel

struct LayersSidePanel: View {
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    var body: some View {
        NavigationStack {
            List {
                Section {
                    LayerToggleRow(
                        title: "Sectional Chart",
                        subtitle: "FAA VFR Sectionals",
                        icon: "map",
                        isOn: $model.showSectional,
                        color: ColorToken.info
                    )

                    LayerToggleRow(
                        title: "NEXRAD Radar",
                        subtitle: "Real-time precipitation",
                        icon: "cloud.rain",
                        isOn: $model.showRadar,
                        color: ColorToken.critical
                    )

                    LayerToggleRow(
                        title: "Airspace",
                        subtitle: "Class B/C/D/E & SUA",
                        icon: "shield.lefthalf.filled",
                        isOn: $model.showAirspace,
                        color: ColorToken.classB
                    )

                    LayerToggleRow(
                        title: "TFRs",
                        subtitle: "Temporary Flight Restrictions",
                        icon: "exclamationmark.shield.fill",
                        isOn: $model.showTFRs,
                        color: ColorToken.tfr
                    )
                } header: {
                    Text("Map Layers")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                }

                Section {
                    LayerToggleRow(
                        title: "Winds Aloft",
                        subtitle: "Forecast winds at altitude",
                        icon: "wind",
                        isOn: $model.showWindsAloft,
                        color: ColorToken.info
                    )

                    LayerToggleRow(
                        title: "PIREPs",
                        subtitle: "Pilot reports",
                        icon: "bubble.left.and.bubble.right",
                        isOn: $model.showPIREPs,
                        color: ColorToken.warning
                    )

                    LayerToggleRow(
                        title: "AIRMETs/SIGMETs",
                        subtitle: "In-flight advisories",
                        icon: "exclamationmark.triangle",
                        isOn: $model.showAIRMETs,
                        color: ColorToken.danger
                    )
                } header: {
                    Text("Weather")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                }

                Section {
                    LayerToggleRow(
                        title: "Airways",
                        subtitle: "Victor & Jet routes",
                        icon: "arrow.up.and.down",
                        isOn: $model.showAirways,
                        color: ColorToken.success
                    )
                } header: {
                    Text("Navigation")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                }

                Section {
                    Button {
                        Task { await AirspaceDataManager.shared.refresh() }
                    } label: {
                        HStack {
                            Label("Refresh Airspace Data", systemImage: "arrow.clockwise")
                                .font(TypographyToken.labelMedium)
                                .foregroundStyle(ColorToken.brandPrimary)
                            Spacer()
                            if AirspaceDataManager.shared.isLoading {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                        }
                    }
                    .disabled(AirspaceDataManager.shared.isLoading)

                    if let lastUpdate = AirspaceDataManager.shared.lastUpdate {
                        HStack {
                            Text("Last Updated")
                                .font(TypographyToken.bodySmall)
                                .foregroundStyle(ColorToken.textSecondary)
                            Spacer()
                            Text(lastUpdate.formatted(date: .abbreviated, time: .shortened))
                                .font(TypographyToken.monoSmall)
                                .foregroundStyle(ColorToken.textTertiary)
                        }
                    }
                } header: {
                    Text("Data")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ColorToken.surfaceBase)
            .navigationTitle("Layers")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(AnimationToken.spring) { isPresented = false }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
            }
        }
        .frame(maxWidth: LayoutToken.sidebarWidthRegular)
        .background(ColorToken.surfaceBase)
    }
}

struct LayerToggleRow: View {
    let title: String
    let subtitle: String
    let icon: String
    @Binding var isOn: Bool
    let color: Color

    var body: some View {
        Toggle(isOn: $isOn) {
            HStack(spacing: SpacingToken.space3) {
                ZStack {
                    Circle()
                        .fill(color.opacity(0.15))
                        .frame(width: 36, height: 36)
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(color)
                }

                VStack(alignment: .leading, spacing: SpacingToken.space0) {
                    Text(title)
                        .font(TypographyToken.bodyMedium)
                        .foregroundStyle(ColorToken.textPrimary)
                    Text(subtitle)
                        .font(TypographyToken.bodyXSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                }
            }
        }
        .toggleStyle(AviationToggleStyle())
        .listRowInsets(EdgeInsets(top: SpacingToken.space2, leading: SpacingToken.insetMedium, bottom: SpacingToken.space2, trailing: SpacingToken.insetMedium))
    }
}

// MARK: - Nearby Side Panel

struct NearbySidePanel: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    @Binding var isPresented: Bool

    private var nearby: [Airport] {
        guard let loc = model.userLocation else { return [] }
        return store.nearest(to: loc, maxCount: 20)
    }

    var body: some View {
        NavigationStack {
            List {
                if nearby.isEmpty {
                    ContentUnavailableView(
                        "No Location",
                        systemImage: "location.slash",
                        description: Text("Enable location services to see nearby airports")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(nearby) { airport in
                        NearbyAirportRow(airport: airport)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ColorToken.surfaceBase)
            .navigationTitle("Nearby Airports")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        withAnimation(AnimationToken.spring) { isPresented = false }
                    } label: {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
            }
        }
        .frame(maxWidth: LayoutToken.sidebarWidthRegular)
        .background(ColorToken.surfaceBase)
    }
}

struct NearbyAirportRow: View {
    let airport: Airport
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Button {
            model.addWaypoint(airport)
        } label: {
            HStack(spacing: SpacingToken.space3) {
                ZStack {
                    Circle()
                        .fill(airportColor)
                        .frame(width: 40, height: 40)
                    Image(systemName: airportIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(ColorToken.textOnBrand)
                }

                VStack(alignment: .leading, spacing: SpacingToken.space0) {
                    HStack(spacing: SpacingToken.space2) {
                        Text(airport.id)
                            .font(TypographyToken.monoMedium)
                            .foregroundStyle(ColorToken.textPrimary)
                        if model.isFavorite(airport.id) {
                            Image(systemName: "star.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(ColorToken.warning)
                        }
                    }
                    Text(airport.name)
                        .font(TypographyToken.bodySmall)
                        .foregroundStyle(ColorToken.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: SpacingToken.space0) {
                    if let loc = model.userLocation {
                        Text(String(format: "%.0f NM", airport.distanceNM(from: loc)))
                            .font(TypographyToken.monoSmall)
                            .foregroundStyle(ColorToken.textPrimary)
                    }
                    Text(bearingString)
                        .font(TypographyToken.monoXSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                }

                Image(systemName: "plus.circle.fill")
                    .font(.system(size: 20, weight: .medium))
                    .foregroundStyle(ColorToken.brandPrimary)
            }
        }
        .buttonStyle(.plain)
        .padding(.vertical, SpacingToken.space1)
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

    private var bearingString: String {
        guard let loc = model.userLocation else { return "—" }
        let bearing = Haversine.trueCourse(loc, airport.coordinate)
        return String(format: "%03d°", bearing)
    }
}
