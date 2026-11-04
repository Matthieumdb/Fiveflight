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
        ("Masse et centrage", "scalemass"),
        ("Altitude densité", "thermometer"),
        ("Vent traversier", "wind"),
        ("Vitesse propre", "speedometer"),
        ("Temps/vitesse/dist.", "clock"),
        ("Carburant", "fuelpump"),
        ("Pente de montée", "arrow.up.right"),
        ("Finesse", "arrow.down.right")
    ]

    var body: some View {
        Group { // pushed inside MoreScreen's NavigationStack
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
            .navigationTitle("Calculateurs")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Weight & Balance Calculator

struct WeightBalanceCalculator: View {
    @EnvironmentObject private var model: AppModel
    @StateObject private var wbModel = WeightBalanceModel()

    private var aircraft: AircraftProfile? { model.selectedAircraft ?? model.aircraftProfiles.first }
    private var aircraftHeader: String { "Limites · \(aircraft?.name ?? "avion")" }

    var body: some View {
        List {
            Section {
                AircraftLimitCard(model: wbModel)
            } header: {
                Text(aircraftHeader)
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                    .textCase(.uppercase)
            }

            Section {
                ForEach($wbModel.items) { $item in
                    WBItemRow(item: $item)
                }
                .onDelete { wbModel.items.remove(atOffsets: $0) }
                .onMove { wbModel.items.move(fromOffsets: $0, toOffset: $1) }

                Button {
                    wbModel.items.append(WeightBalanceItem(name: "New Item", weight: 0, arm: wbModel.items.last?.arm ?? 0))
                } label: {
                    Label("Ajouter un élément", systemImage: "plus.circle.fill")
                        .font(TypographyToken.labelMedium)
                        .foregroundStyle(ColorToken.brandPrimary)
                }
            } header: {
                HStack {
                    Text("Chargement")
                        .font(TypographyToken.labelSmall)
                        .foregroundStyle(ColorToken.textTertiary)
                        .textCase(.uppercase)
                    Spacer()
                    FREditButton().font(TypographyToken.labelSmall)
                }
            }

            Section {
                ResultRow(title: "Masse totale", value: String(format: "%.0f lb", wbModel.totalWeight), color: wbModel.totalWeight > wbModel.maxWeight ? ColorToken.danger : ColorToken.textPrimary)
                ResultRow(title: "Moment total", value: String(format: "%.0f lb-in", wbModel.totalMoment))
                ResultRow(title: "Centrage", value: String(format: "%.1f in", wbModel.cg), color: wbModel.isWithinLimits ? ColorToken.success : ColorToken.danger)

                ResultRow(title: "Plage de centrage", value: String(format: "%.0f–%.0f in", wbModel.cgForward, wbModel.cgAft))
                ResultRow(title: "Charge restante", value: String(format: "%.0f lb", wbModel.maxWeight - wbModel.totalWeight), color: wbModel.totalWeight > wbModel.maxWeight ? ColorToken.danger : ColorToken.textPrimary)
                WeightBalanceChart(model: wbModel)
            } header: {
                Text("Résultats")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                    .textCase(.uppercase)
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(ColorToken.surfaceBase)
        .onAppear { if let aircraft { wbModel.sync(with: aircraft) } }
    }
}

struct WBItemRow: View {
    @Binding var item: WeightBalanceItem

    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            if item.name == "Fuel (gal)" {
                VStack(alignment: .leading, spacing: SpacingToken.space1) {
                    Text(item.displayName)
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
                    Text(item.displayName)
                        .font(TypographyToken.bodySmall)
                        .foregroundStyle(ColorToken.textSecondary)
                    HStack {
                        Stepper("", value: $item.weight, in: 0...(item.name == WeightBalanceItem.emptyName ? 10000 : 1000), step: item.name == WeightBalanceItem.emptyName ? 1 : 10)
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
                Text("Bras : \(Int(item.arm)) in")
                    .font(TypographyToken.monoXSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text("Moment : \(Int(item.weight * item.arm))")
                    .font(TypographyToken.monoXSmall)
                    .foregroundStyle(ColorToken.textTertiary)
            }
        }
        .padding(.vertical, SpacingToken.space1)
    }
}

struct AircraftLimitCard: View {
    @ObservedObject var model: WeightBalanceModel

    var body: some View {
        HStack(spacing: SpacingToken.space4) {
            VStack(alignment: .leading, spacing: SpacingToken.space1) {
                Text("Masse")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text(String(format: "%.0f / %.0f lb", model.totalWeight, model.maxWeight))
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(model.totalWeight > model.maxWeight ? ColorToken.danger : ColorToken.success)
            }

            Divider().frame(height: 40)

            VStack(alignment: .leading, spacing: SpacingToken.space1) {
                Text("Centrage")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text(String(format: "%.1f in (%.0f–%.0f)", model.cg, model.cgForward, model.cgAft))
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(model.cg >= model.cgForward && model.cg <= model.cgAft ? ColorToken.success : ColorToken.danger)
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
        CalculatorCard(title: "Altitude densité", icon: "thermometer") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Altitude pression", value: $pressureAltitude, range: -1000...15000, step: 100, unit: "ft", icon: "altitude")
                ProfileSliderRow(title: "Température extérieure", value: $temperature, range: -40...50, step: 1, unit: "°C", icon: "thermometer")

                let da = DensityAltitude.calculate(pressureAltitude: pressureAltitude, tempC: temperature)
                let isaTemp = 15.0 - (pressureAltitude / 1000.0 * 2.0)
                let deviation = temperature - isaTemp

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space1) {
                        Text("Altitude densité")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(da) ft")
                            .font(TypographyToken.numberLarge)
                            .foregroundStyle(da > 8000 ? ColorToken.danger : (da > 5000 ? ColorToken.warning : ColorToken.success))
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                        Text("Écart ISA")
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
        CalculatorCard(title: "Composantes du vent", icon: "wind") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Direction du vent", value: $windDirection, range: 0...359, step: 1, unit: "°", icon: "wind")
                ProfileSliderRow(title: "Force du vent", value: $windSpeed, range: 0...50, step: 1, unit: "kt", icon: "wind")
                ProfileSliderRow(title: "Cap de la piste", value: $runwayHeading, range: 0...359, step: 1, unit: "°", icon: "number")

                let (headwind, crosswind, side) = Crosswind.components(
                    windDir: Int(windDirection),
                    windSpeed: Int(windSpeed),
                    runwayHeading: Int(runwayHeading)
                )

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space1) {
                        Text(headwind >= 0 ? "Vent de face" : "Vent arrière")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(abs(headwind)) kt")
                            .font(TypographyToken.numberMedium)
                            .foregroundStyle(headwind >= 0 ? ColorToken.success : ColorToken.danger)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                        Text("Vent traversier")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(crosswind) kt \(side == "R" ? "D" : "G")")
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
        CalculatorCard(title: "Vitesse propre", icon: "speedometer") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Vitesse indiquée", value: $ias, range: 40...300, step: 1, unit: "kt", icon: "speedometer")
                ProfileSliderRow(title: "Altitude pression", value: $pressureAltitude, range: -1000...25000, step: 100, unit: "ft", icon: "altitude")
                ProfileSliderRow(title: "Température extérieure", value: $temperature, range: -40...50, step: 1, unit: "°C", icon: "thermometer")

                let tas = TrueAirspeed.calculate(ias: ias, pressureAltitude: pressureAltitude, tempC: temperature)

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space1) {
                        Text("Vitesse propre (TAS)")
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

    enum SolveFor: String, CaseIterable { case time = "Temps", speed = "Vitesse", distance = "Distance" }

    var body: some View {
        CalculatorCard(title: "Time / Speed / Distance", icon: "clock") {
            VStack(spacing: SpacingToken.space4) {
                Picker("Calculer", selection: $solvingFor) {
                    ForEach(SolveFor.allCases, id: \.self) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)

                if solvingFor != .time {
                    ProfileSliderRow(title: "Temps", value: $time, range: 0...600, step: 1, unit: "min", icon: "clock")
                }
                if solvingFor != .speed {
                    ProfileSliderRow(title: "Vitesse", value: $speed, range: 1...500, step: 1, unit: "kt", icon: "speedometer")
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
        CalculatorCard(title: "Carburant", icon: "fuelpump") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Distance", value: $distance, range: 0...2000, step: 10, unit: "NM", icon: "point.topleft.down.curvedto.point.bottomright.forward")
                ProfileSliderRow(title: "Vitesse sol", value: $speed, range: 40...500, step: 5, unit: "kt", icon: "speedometer")
                ProfileSliderRow(title: "Consommation", value: $fuelBurn, range: 1...100, step: 0.5, unit: "gal/h", icon: "fuelpump")
                ProfileSliderRow(title: "Reserve", value: $reserveMin, range: 0...180, step: 5, unit: "min", icon: "timer")
                ProfileSliderRow(title: "Roulage", value: $taxiFuel, range: 0...10, step: 0.5, unit: "gal", icon: "fuelpump.fill")

                let enrouteTime = distance / speed
                let enrouteFuel = enrouteTime * fuelBurn
                let reserveFuel = (reserveMin / 60.0) * fuelBurn
                let totalFuel = enrouteFuel + reserveFuel + taxiFuel

                Divider()

                VStack(spacing: SpacingToken.space2) {
                    ResultRow(title: "Temps en route", value: String(format: "%dh%02dm", Int(enrouteTime), Int((enrouteTime.truncatingRemainder(dividingBy: 1)) * 60)))
                    ResultRow(title: "Carburant en route", value: String(format: "%.1f gal", enrouteFuel))
                    ResultRow(title: "Réserve", value: String(format: "%.1f gal", reserveFuel))
                    ResultRow(title: "Roulage", value: String(format: "%.1f gal", taxiFuel))
                    ResultRow(title: "TOTAL NÉCESSAIRE", value: String(format: "%.1f gal", totalFuel), color: ColorToken.brandPrimary)
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
        CalculatorCard(title: "Pente de montée", icon: "arrow.up.right") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Vitesse sol", value: $groundSpeed, range: 40...200, step: 1, unit: "kt", icon: "speedometer")
                ProfileSliderRow(title: "Taux de montée", value: $climbRate, range: 0...3000, step: 50, unit: "ft/min", icon: "arrow.up")
                ProfileSliderRow(title: "Pente requise", value: $requiredGradient, range: 0...1000, step: 50, unit: "ft/NM", icon: "arrow.up.right")

                let actualGradient = (climbRate / groundSpeed) * 60.0
                let meets = actualGradient >= requiredGradient

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space1) {
                        Text("Pente obtenue")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(Int(actualGradient.rounded())) ft/NM")
                            .font(TypographyToken.numberLarge)
                            .foregroundStyle(meets ? ColorToken.success : ColorToken.danger)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                        Text("Requise")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text("\(Int(requiredGradient)) ft/NM")
                            .font(TypographyToken.monoMedium)
                            .foregroundStyle(ColorToken.textPrimary)
                    }
                }

                Text(meets ? "✓ Pente requise atteinte" : "✗ Pente requise non atteinte")
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
        CalculatorCard(title: "Distance de plané", icon: "arrow.down.right") {
            VStack(spacing: SpacingToken.space4) {
                ProfileSliderRow(title: "Hauteur sol", value: $altitudeAGL, range: 0...20000, step: 100, unit: "ft", icon: "altitude")
                ProfileSliderRow(title: "Finesse", value: $glideRatio, range: 5...20, step: 0.5, unit: ":1", icon: "arrow.down.right")
                ProfileSliderRow(title: "Vent (+ arrière)", value: $windComponent, range: -50...50, step: 1, unit: "kt", icon: "wind")

                let nmPer1000ft = glideRatio * 6076.0 / 5280.0 // Convert to NM per 1000ft
                let stillAirRange = (altitudeAGL / 1000.0) * nmPer1000ft
                let windEffect = (windComponent / (altitudeAGL / 1000.0 * glideRatio / 60.0)) * (altitudeAGL / 1000.0) * nmPer1000ft
                let totalRange = stillAirRange + windEffect

                Divider()

                HStack {
                    VStack(alignment: .leading, spacing: SpacingToken.space1) {
                        Text("Sans vent")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text(String(format: "%.1f NM", stillAirRange))
                            .font(TypographyToken.numberMedium)
                            .foregroundStyle(ColorToken.textPrimary)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: SpacingToken.space1) {
                        Text("Avec le vent")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Text(String(format: "%.1f NM", totalRange))
                            .font(TypographyToken.numberMedium)
                            .foregroundStyle(ColorToken.brandPrimary)
                    }
                }

                Text("Vitesse de plané : voir le manuel de vol (POH)")
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

        if distance == nil { d = s * t / 60.0 } else if speed == nil { s = t > 0 ? d / t * 60.0 : 0 } else { t = s > 0 ? d / s * 60.0 : 0 }

        return (d, s, t)
    }
}
