import SwiftUI

// MARK: - Profile Slider Row

struct ProfileSliderRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space2) {
            HStack {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(ColorToken.brandPrimary)
                    .frame(width: 24)
                Text(title)
                    .font(TypographyToken.bodyMedium)
                    .foregroundStyle(ColorToken.textPrimary)
                Spacer()
                Text("\(value, specifier: step >= 1 ? "%.0f" : "%.1f") \(unit)")
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
            }

            Slider(value: $value, in: range, step: step)
                .tint(ColorToken.brandPrimary)
        }
        .padding(.vertical, SpacingToken.space1)
    }
}

// MARK: - Calculators Screen

struct CalculatorsScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var selectedCalculator = 0

    private let calculators = [
        ("Weight & Balance", "scalemass"),
        ("Density Altitude", "thermometer"),
        ("Crosswind", "wind"),
        ("True Airspeed", "speedometer"),
        ("Time/Speed/Dist", "clock"),
        ("Fuel Planning", "fuelpump"),
        ("Climb Gradient", "arrow.up.right"),
        ("Glide Range", "arrow.down.right")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Calculator picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpacingToken.space2) {
                        ForEach(calculators.indices, id: \.self) { index in
                            let (title, icon) = calculators[index]
                            Button {
                                withAnimation(AnimationToken.tabSwitch) { selectedCalculator = index }
                            } label: {
                                HStack(spacing: SpacingToken.space1) {
                                    Image(systemName: icon)
                                        .font(.system(size: 14, weight: .medium))
                                    Text(title)
                                        .font(TypographyToken.labelSmall)
                                }
                                .foregroundStyle(selectedCalculator == index ? ColorToken.textOnBrand : ColorToken.textTertiary)
                                .padding(.horizontal, SpacingToken.space3)
                                .padding(.vertical, SpacingToken.space1)
                                .background(
                                    selectedCalculator == index ? ColorToken.brandPrimary : ColorToken.surfaceCard,
                                    in: Capsule()
                                )
                            }
                        }
                    }
                    .padding(.horizontal, SpacingToken.insetMedium)
                }
                .padding(.vertical, SpacingToken.space3)

                // Calculator content
                TabView(selection: $selectedCalculator) {
                    WeightBalanceCalculator()
                        .tag(0)

                    DensityAltitudeCalculator()
                        .tag(1)

                    CrosswindCalculator()
                        .tag(2)

                    TrueAirspeedCalculator()
                        .tag(3)

                    TimeSpeedDistanceCalculator()
                        .tag(4)

                    FuelPlanningCalculator()
                        .tag(5)

                    ClimbGradientCalculator()
                        .tag(6)

                    GlideRangeCalculator()
                        .tag(7)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
            }
            .background(ColorToken.surfaceBase)
            .navigationTitle("Calculators")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Weight & Balance Calculator

struct WeightBalanceCalculator: View {
    @EnvironmentObject private var model: AppModel
    @State private var items: [WBItem] = []

    private var totalWeight: Double {
        items.reduce(0) { $0 + $1.weight }
    }

    private var totalMoment: Double {
        items.reduce(0) { $0 + $1.weight * $1.arm }
    }

    private var cg: Double {
        totalWeight > 0 ? totalMoment / totalWeight : 0
    }

    private var isWithinLimits: Bool {
        guard let aircraft = model.selectedAircraft else { return false }
        return cg >= Double(aircraft.cgForward) && cg <= Double(aircraft.cgAft) && totalWeight <= Double(aircraft.maxWeight)
    }

    var body: some View {
        List {
            Section {
                if let aircraft = model.selectedAircraft {
                    AircraftLimitCard(aircraft: aircraft, totalWeight: totalWeight, cg: cg)
                }
            } header: {
                Text("Aircraft Limits")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                    .textCase(.uppercase)
            }

            Section {
                ForEach($items) { $item in
                    WBItemRow(item: $item)
                }
                .onDelete { items.remove(atOffsets: $0) }
                .onMove { items.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    items.append(WBItem(name: "New Item", weight: 0, arm: 0))
                } label: {
                    Label("Add Item", systemImage: "plus.circle.fill")
                        .font(TypographyToken.labelMedium)
                        .foregroundStyle(ColorToken.brandPrimary)
                }
            } header: {
                HStack {
                    Text("Loading")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                    Spacer()
                    EditButton().font(TypographyToken.labelSmall)
                }
            }

            Section {
                ResultRow(title: "Total Weight", value: String(format: "%.0f lb", totalWeight), color: totalWeight > Double(model.selectedAircraft?.maxWeight ?? 9999) ? ColorToken.danger : ColorToken.textPrimary)
                ResultRow(title: "Total Moment", value: String(format: "%.0f lb-in", totalMoment))
                ResultRow(title: "CG Location", value: String(format: "%.1f in", cg), color: isWithinLimits ? ColorToken.success : ColorToken.danger)

                if let aircraft = model.selectedAircraft {
                    ResultRow(title: "CG Range", value: "\(aircraft.cgForward)–\(aircraft.cgAft) in")
                    let remaining = aircraft.usefulLoad - Int(totalWeight - Double(aircraft.emptyWeight))
                    ResultRow(title: "Useful Load Remaining", value: "\(remaining) lb")
                }
            } header: {
                Text("Results")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                    .textCase(.uppercase)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ColorToken.surfaceBase)
        .onAppear {
            if items.isEmpty, let aircraft = model.selectedAircraft {
                items = [
                    WBItem(name: "Empty Weight", weight: Double(aircraft.emptyWeight), arm: Double((aircraft.cgForward + aircraft.cgAft) / 2)),
                    WBItem(name: "Pilot", weight: 170, arm: 37),
                    WBItem(name: "Passenger", weight: 170, arm: 37),
                    WBItem(name: "Fuel (gal)", weight: 0, arm: 48, isFuel: true)
                ]
            }
        }
    }
}

struct WBItem: Identifiable {
    let id = UUID()
    var name: String
    var weight: Double
    var arm: Double
    var isFuel: Bool = false
}

struct WBItemRow: View {
    @Binding var item: WBItem

    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            if item.isFuel {
                VStack(alignment: .leading, spacing: SpacingToken.space1) {
                    Text(item.name)
                        .font(TypographyToken.bodySmall)
                        .foregroundStyle(ColorToken.textSecondary)
                    Stepper("", value: Binding(
                        get: { item.weight / 6.0 },
                        set: { item.weight = $0 * 6.0 }
                    ), in: 0...100, step: 1)
                    .labelsHidden()
                    Text("\(Int(item.weight / 6)) gal = \(Int(item.weight)) lb")
                        .font(TypographyToken.monoSmall)
                        .foregroundStyle(ColorToken.textPrimary)
                }
            } else {
                VStack(alignment: .leading, spacing: SpacingToken.space1) {
                    Text(item.name)
                        .font(TypographyToken.bodySmall)
                        .foregroundStyle(ColorToken.textSecondary)
                    HStack {
                        Stepper("", value: $item.weight, in: 0...1000, step: 10)
                            .labelsHidden()
                        Text("\(Int(item.weight)) lb")
                            .font(TypographyToken.monoSmall)
                            .foregroundStyle(ColorToken.textPrimary)
                            .frame(width: 60, alignment: .trailing)
                    }
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                Text("Arm: \(Int(item.arm)) in")
                    .font(TypographyToken.monoXSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text("Mom: \(Int(item.weight * item.arm))")
                    .font(TypographyToken.monoXSmall)
                    .foregroundStyle(ColorToken.textTertiary)
            }
        }
        .padding(.vertical, SpacingToken.space1)
    }
}

struct AircraftLimitCard: View {
    let aircraft: AircraftProfile
    let totalWeight: Double
    let cg: Double

    var body: some View {
        HStack(spacing: SpacingToken.space4) {
            VStack(alignment: .leading, spacing: SpacingToken.space1) {
                Text("Weight")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text(String(format: "%.0f / %d lb", totalWeight, aircraft.maxWeight))
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(totalWeight > Double(aircraft.maxWeight) ? ColorToken.danger : ColorToken.success)
            }

            Divider().frame(height: 40)

            VStack(alignment: .leading, spacing: SpacingToken.space1) {
                Text("CG")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text(String(format: "%.1f in (%.0f–%.0f)", cg, aircraft.cgForward, aircraft.cgAft))
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(cg >= Double(aircraft.cgForward) && cg <= Double(aircraft.cgAft) ? ColorToken.success : ColorToken.danger)
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

// MARK: - Density Altitude Calculator

struct DensityAltitudeCalculator: View {
    @State private var pressureAltitude = 0.0
    @State private var temperature = 15.0

    var body: some View {
        CalculatorCard(title: "Density Altitude", icon: "thermometer") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Pressure Altitude", value: $pressureAltitude, range: -1000...15000, step: 100, unit: "ft", icon: "altitude")
                ProfileSliderRow(title: "Temperature (OAT)", value: $temperature, range: -40...50, step: 1, unit: "°C", icon: "thermometer")

                let da = DensityAltitude.calculate(pressureAltitude: pressureAltitude, tempC: temperature)
                let isaTemp = 15.0 - (pressureAltitude / 1000.0 * 2.0)
                let deviation = temperature - isaTemp

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space1) {
                        Text("Density Altitude")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(da) ft")
                            .font(TypographyToken.numberLarge)
                            .foregroundStyle(da > 8000 ? ColorToken.danger : (da > 5000 ? ColorToken.warning : ColorToken.success))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                        Text("ISA Deviation")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(deviation >= 0 ? "+" : "")\(String(format: "%.1f", deviation))°C")
                            .font(TypographyToken.monoMedium)
                            .foregroundStyle(deviation > 10 ? ColorToken.warning : ColorToken.textPrimary)
                    }
                }
            }
        }
    }
}

// MARK: - Crosswind Calculator

struct CrosswindCalculator: View {
    @State private var windDirection = 0.0
    @State private var windSpeed = 0.0
    @State private var runwayHeading = 0.0

    var body: some View {
        CalculatorCard(title: "Crosswind Component", icon: "wind") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Wind Direction", value: $windDirection, range: 0...359, step: 1, unit: "°", icon: "wind")
                ProfileSliderRow(title: "Wind Speed", value: $windSpeed, range: 0...50, step: 1, unit: "kt", icon: "wind")
                ProfileSliderRow(title: "Runway Heading", value: $runwayHeading, range: 0...359, step: 1, unit: "°", icon: "number")

                let (headwind, crosswind, side) = Crosswind.components(
                    windDir: Int(windDirection),
                    windSpeed: Int(windSpeed),
                    runwayHeading: Int(runwayHeading)
                )

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space1) {
                        Text("Headwind")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(headwind) kt")
                            .font(TypographyToken.numberMedium)
                            .foregroundStyle(headwind >= 0 ? ColorToken.success : ColorToken.danger)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                        Text("Crosswind")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(crosswind) kt \(side)")
                            .font(TypographyToken.numberMedium)
                            .foregroundStyle(crosswind > 15 ? ColorToken.danger : (crosswind > 10 ? ColorToken.warning : ColorToken.success))
                    }
                }
            }
        }
    }
}

// MARK: - True Airspeed Calculator

struct TrueAirspeedCalculator: View {
    @State private var ias = 100.0
    @State private var pressureAltitude = 0.0
    @State private var temperature = 15.0

    var body: some View {
        CalculatorCard(title: "True Airspeed", icon: "speedometer") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Indicated Airspeed", value: $ias, range: 40...300, step: 1, unit: "kt", icon: "speedometer")
                ProfileSliderRow(title: "Pressure Altitude", value: $pressureAltitude, range: -1000...25000, step: 100, unit: "ft", icon: "altitude")
                ProfileSliderRow(title: "Temperature (OAT)", value: $temperature, range: -40...50, step: 1, unit: "°C", icon: "thermometer")

                let tas = TrueAirspeed.calculate(ias: ias, pressureAltitude: pressureAltitude, tempC: temperature)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space1) {
                        Text("True Airspeed")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(Int(tas.rounded())) kt")
                            .font(TypographyToken.numberLarge)
                            .foregroundStyle(ColorToken.brandPrimary)
                    }
                    Spacer()
                }
            }
        }
    }
}

// MARK: - Time/Speed/Distance Calculator

struct TimeSpeedDistanceCalculator: View {
    @State private var distance = 0.0
    @State private var speed = 120.0
    @State private var time = 0.0
    @State private var solvingFor: SolveFor = .time

    enum SolveFor: String, CaseIterable { case time = "Time", speed = "Speed", distance = "Distance" }

    var body: some View {
        CalculatorCard(title: "Time / Speed / Distance", icon: "clock") {
            VStack(spacing: SpacingToken.space4) {
                Picker("Solve For", selection: $solvingFor) {
                    ForEach(SolveFor.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if solvingFor != .time {
                    ProfileSliderRow(title: "Time", value: $time, range: 0...600, step: 1, unit: "min", icon: "clock")
                }
                if solvingFor != .speed {
                    ProfileSliderRow(title: "Speed", value: $speed, range: 1...500, step: 1, unit: "kt", icon: "speedometer")
                }
                if solvingFor != .distance {
                    ProfileSliderRow(title: "Distance", value: $distance, range: 0...5000, step: 1, unit: "NM", icon: "point.topleft.down.curvedto.point.bottomright.forward")
                }

                Divider()

                let result = TimeSpeedDistance.calculate(
                    distance: solvingFor == .distance ? nil : distance,
                    speed: solvingFor == .speed ? nil : speed,
                    time: solvingFor == .time ? nil : time
                )

                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space1) {
                        Text(solvingFor.rawValue)
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text(resultDisplay(result, for: solvingFor))
                            .font(TypographyToken.numberLarge)
                            .foregroundStyle(ColorToken.brandPrimary)
                    }
                    Spacer()
                }
            }
        }
    }

    private func resultDisplay(_ result: (distance: Double, speed: Double, time: Double), for solve: SolveFor) -> String {
        switch solve {
        case .time: return "\(Int(result.time)) min"
        case .speed: return "\(Int(result.speed.rounded())) kt"
        case .distance: return "\(Int(result.distance.rounded())) NM"
        }
    }
}

// MARK: - Fuel Planning Calculator

struct FuelPlanningCalculator: View {
    @State private var distance = 100.0
    @State private var speed = 120.0
    @State private var fuelBurn = 10.0
    @State private var reserveMin = 30.0
    @State private var taxiFuel = 1.0

    var body: some View {
        CalculatorCard(title: "Fuel Planning", icon: "fuelpump") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Distance", value: $distance, range: 0...2000, step: 10, unit: "NM", icon: "point.topleft.down.curvedto.point.bottomright.forward")
                ProfileSliderRow(title: "Ground Speed", value: $speed, range: 40...500, step: 5, unit: "kt", icon: "speedometer")
                ProfileSliderRow(title: "Fuel Burn", value: $fuelBurn, range: 1...100, step: 0.5, unit: "gal/h", icon: "fuelpump")
                ProfileSliderRow(title: "Reserve", value: $reserveMin, range: 0...180, step: 5, unit: "min", icon: "timer")
                ProfileSliderRow(title: "Taxi Fuel", value: $taxiFuel, range: 0...10, step: 0.5, unit: "gal", icon: "fuelpump.fill")

                let enrouteTime = distance / speed
                let enrouteFuel = enrouteTime * fuelBurn
                let reserveFuel = (reserveMin / 60.0) * fuelBurn
                let totalFuel = enrouteFuel + reserveFuel + taxiFuel

                Divider()

                VStack(spacing: SpacingToken.space2) {
                    ResultRow(title: "Enroute Time", value: String(format: "%dh%02dm", Int(enrouteTime), Int((enrouteTime.truncatingRemainder(dividingBy: 1)) * 60)))
                    ResultRow(title: "Enroute Fuel", value: String(format: "%.1f gal", enrouteFuel))
                    ResultRow(title: "Reserve Fuel", value: String(format: "%.1f gal", reserveFuel))
                    ResultRow(title: "Taxi Fuel", value: String(format: "%.1f gal", taxiFuel))
                    ResultRow(title: "TOTAL REQUIRED", value: String(format: "%.1f gal", totalFuel), color: ColorToken.brandPrimary)
                }
            }
        }
    }
}

// MARK: - Climb Gradient Calculator

struct ClimbGradientCalculator: View {
    @State private var groundSpeed = 75.0
    @State private var climbRate = 500.0
    @State private var requiredGradient = 200.0

    var body: some View {
        CalculatorCard(title: "Climb Gradient", icon: "arrow.up.right") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Ground Speed", value: $groundSpeed, range: 40...200, step: 1, unit: "kt", icon: "speedometer")
                ProfileSliderRow(title: "Climb Rate", value: $climbRate, range: 0...3000, step: 50, unit: "ft/min", icon: "arrow.up")
                ProfileSliderRow(title: "Required Gradient", value: $requiredGradient, range: 0...1000, step: 50, unit: "ft/NM", icon: "arrow.up.right")

                let actualGradient = (climbRate / groundSpeed) * 60.0
                let meets = actualGradient >= requiredGradient

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space1) {
                        Text("Actual Gradient")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(Int(actualGradient.rounded())) ft/NM")
                            .font(TypographyToken.numberLarge)
                            .foregroundStyle(meets ? ColorToken.success : ColorToken.danger)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                        Text("Required")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(Int(requiredGradient)) ft/NM")
                            .font(TypographyToken.monoMedium)
                            .foregroundStyle(ColorToken.textPrimary)
                    }
                }

                Text(meets ? "✓ Meets requirement" : "✗ Does not meet requirement")
                    .font(TypographyToken.labelMedium)
                    .foregroundStyle(meets ? ColorToken.success : ColorToken.danger)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Glide Range Calculator

struct GlideRangeCalculator: View {
    @State private var altitudeAGL = 3000.0
    @State private var glideRatio = 9.0
    @State private var windComponent = 0.0

    var body: some View {
        CalculatorCard(title: "Emergency Glide Range", icon: "arrow.down.right") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Altitude AGL", value: $altitudeAGL, range: 0...20000, step: 100, unit: "ft", icon: "altitude")
                ProfileSliderRow(title: "Glide Ratio", value: $glideRatio, range: 5...20, step: 0.5, unit: ":1", icon: "arrow.down.right")
                ProfileSliderRow(title: "Wind Component", value: $windComponent, range: -50...50, step: 1, unit: "kt", icon: "wind")

                let nmPer1000ft = glideRatio * 6076.0 / 5280.0 // Convert to NM per 1000ft
                let stillAirRange = (altitudeAGL / 1000.0) * nmPer1000ft
                let windEffect = (windComponent / (altitudeAGL / 1000.0 * glideRatio / 60.0)) * (altitudeAGL / 1000.0) * nmPer1000ft
                let totalRange = stillAirRange + windEffect

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space1) {
                        Text("Still Air Range")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text(String(format: "%.1f NM", stillAirRange))
                            .font(TypographyToken.numberMedium)
                            .foregroundStyle(ColorToken.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                        Text("With Wind")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text(String(format: "%.1f NM", totalRange))
                            .font(TypographyToken.numberMedium)
                            .foregroundStyle(ColorToken.brandPrimary)
                    }
                }

                Text("Glide speed: ~\(Int(70 * sqrt(altitudeAGL / 3000))) kt (adjust per POH)")
                    .font(TypographyToken.bodySmall)
                    .foregroundStyle(ColorToken.textTertiary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
}

// MARK: - Calculator Card Wrapper

struct CalculatorCard<Content: View>: View {
    let title: String
    let icon: String
    @ViewBuilder let content: Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Header
                HStack {
                    Image(systemName: icon)
                        .font(.system(size: 24, weight: .medium))
                        .foregroundStyle(ColorToken.brandPrimary)
                    Text(title)
                        .font(TypographyToken.headlineMedium)
                        .foregroundStyle(ColorToken.textPrimary)
                    Spacer()
                }
                .padding(SpacingToken.cardPadding)
                .background(ColorToken.surfaceElevated)

                content
                    .padding(SpacingToken.cardPadding)
            }
        }
        .background(ColorToken.surfaceBase)
    }
}

// MARK: - Result Row

struct ResultRow: View {
    let title: String
    let value: String
    var color: Color = ColorToken.textPrimary

    var body: some View {
        HStack {
            Text(title)
                .font(TypographyToken.bodyMedium)
                .foregroundStyle(ColorToken.textSecondary)
            Spacer()
            Text(value)
                .font(TypographyToken.monoMedium)
                .foregroundStyle(color)
        }
    }
}

struct TrueAirspeed {
    static func calculate(ias: Double, pressureAltitude: Double, tempC: Double) -> Double {
        // Simplified TAS calculation
        let densityRatio = pow(1.0 - pressureAltitude * 6.875e-6, 4.2561)
        let tempKelvin = tempC + 273.15
        let isaTempKelvin = 288.15 - pressureAltitude * 0.0019812
        let tempRatio = sqrt(tempKelvin / isaTempKelvin)
        return ias / sqrt(densityRatio) * tempRatio
    }
}

struct TimeSpeedDistance {
    static func calculate(distance: Double?, speed: Double?, time: Double?) -> (distance: Double, speed: Double, time: Double) {
        var d = distance ?? 0, s = speed ?? 0, t = time ?? 0

        if distance == nil { d = s * t / 60.0 } else if speed == nil { s = d / t * 60.0 } else { t = d / s * 60.0 }

        return (d, s, t)
    }
}
