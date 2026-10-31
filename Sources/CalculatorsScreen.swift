import SwiftUI

struct CalculatorsScreen: View {
    @StateObject private var wb = WeightBalanceModel()
    @State private var daPressure = 0.0
    @State private var daTemp = 15.0
    @State private var cwWindDir = 0
    @State private var cwWindSpd = 0
    @State private var cwRwy = 0

    var body: some View {
        NavigationStack {
            List {
                // Weight & Balance
                Section("Mass & Centrage") {
                    ForEach($wb.items) { $item in
                        WeightBalanceRow(item: $item, model: wb)
                    }

                    Divider()

                    ResultRow(
                        title: "Poids total",
                        value: "\(Int(wb.totalWeight)) lb",
                        color: wb.totalWeight > wb.maxWeight ? Theme.red : Theme.textPrimary
                    )

                    ResultRow(
                        title: "CG",
                        value: String(format: "%.1f in", wb.cg),
                        color: (wb.cg < wb.cgForward || wb.cg > wb.cgAft) ? Theme.red : Theme.textPrimary
                    )

                    ResultRow(
                        title: "Limites CG",
                        value: "\(Int(wb.cgForward))–\(Int(wb.cgAft)) in"
                    )

                    ResultRow(
                        title: "Charge utile",
                        value: "\(Int(wb.usefulLoad)) lb"
                    )
                }

                // Density Altitude
                Section("Altitude Densité") {
                    ProfileStepper(title: "Alt. pression", value: $daPressure, range: -1000...15000, step: 100, unit: "ft", icon: "altitude")
                    ProfileStepper(title: "Temp OAT", value: $daTemp, range: -40...50, step: 1, unit: "°C", icon: "thermometer")

                    let da = DensityAltitude.calculate(pressureAltitude: daPressure, tempC: daTemp)
                    ResultRow(
                        title: "Altitude densité",
                        value: "\(da) ft",
                        color: da > 8000 ? Theme.red : (da > 5000 ? Theme.orange : Theme.textPrimary)
                    )
                }

                // Crosswind
                Section("Vent de travers") {
                    ProfileStepper(title: "Direction vent", value: Binding(
                        get: { Double(cwWindDir) },
                        set: { cwWindDir = Int($0) }
                    ), range: 0...359, step: 1, unit: "°", icon: "wind")

                    ProfileStepper(title: "Force vent", value: Binding(
                        get: { Double(cwWindSpd) },
                        set: { cwWindSpd = Int($0) }
                    ), range: 0...50, step: 1, unit: "kt", icon: "wind")

                    ProfileStepper(title: "Piste QHU", value: Binding(
                        get: { Double(cwRwy) },
                        set: { cwRwy = Int($0) }
                    ), range: 0...359, step: 10, unit: "°", icon: "number")

                    let (hw, cw, side) = Crosswind.components(windDir: cwWindDir, windSpeed: cwWindSpd, runwayHeading: cwRwy)

                    ResultRow(
                        title: "Vent de face",
                        value: "\(hw) kt",
                        color: hw >= 0 ? Theme.green : Theme.red
                    )

                    ResultRow(
                        title: "Vent de travers",
                        value: "\(cw) kt \(side)",
                        color: cw > 15 ? Theme.red : (cw > 10 ? Theme.orange : Theme.textPrimary)
                    )
                }
            }
            .navigationTitle("Calculateurs")
        }
    }
}

struct WeightBalanceRow: View {
    @Binding var item: WeightBalanceItem
    @ObservedObject var model: WeightBalanceModel

    var body: some View {
        if item.name == "Fuel (gal)" {
            HStack {
                Label(item.name, systemImage: "fuelpump")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Text("\(Int(item.weight/6)) gal")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
                Stepper("", value: Binding(
                    get: { item.weight/6 },
                    set: { model.updateFuel(gallons: $0) }
                ), in: 0...100, step: 1)
                    .labelsHidden()
            }
            .padding(.vertical, Theme.spacingXS)
        } else {
            HStack {
                Label(item.name, systemImage: "person")
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
                Stepper("", value: $item.weight, in: 0...1000, step: 10)
                    .labelsHidden()
                Text("\(Int(item.weight)) lb")
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 60, alignment: .trailing)
            }
            .padding(.vertical, Theme.spacingXS)
        }
    }
}

struct ResultRow: View {
    let title: String
    let value: String
    var color: Color = Theme.textPrimary

    var body: some View {
        HStack {
            Text(title)
                .foregroundStyle(Theme.textSecondary)
            Spacer()
            Text(value)
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(color)
        }
        .padding(.vertical, Theme.spacingXS)
    }
}