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
                        if item.name == "Fuel (gal)" {
                            HStack {
                                Text(item.name)
                                Spacer()
                                Text("\(Int(item.weight/6)) gal").foregroundStyle(.secondary)
                                Stepper("", value: Binding(
                                    get: { item.weight/6 },
                                    set: { wb.updateFuel(gallons: $0) }
                                ), in: 0...100, step: 1).labelsHidden()
                            }
                        } else {
                            HStack {
                                Text(item.name)
                                Spacer()
                                Stepper("", value: $item.weight, in: 0...1000, step: 10).labelsHidden()
                                Text("\(Int(item.weight)) lb").monospacedDigit().frame(width: 60)
                            }
                        }
                    }
                    LabeledContent("Poids total", value: "\(Int(wb.totalWeight)) lb")
                        .foregroundStyle(wb.totalWeight > wb.maxWeight ? .red : .primary)
                    LabeledContent("CG", value: String(format: "%.1f in", wb.cg))
                        .foregroundStyle((wb.cg < wb.cgForward || wb.cg > wb.cgAft) ? .red : .primary)
                    LabeledContent("Limites CG", value: "\(Int(wb.cgForward))–\(Int(wb.cgAft)) in")
                    LabeledContent("Charge utile", value: "\(Int(wb.usefulLoad)) lb")
                }

                // Density Altitude
                Section("Altitude Densité") {
                    Stepper("Alt. pression: \(Int(daPressure)) ft", value: $daPressure, in: -1000...15000, step: 100)
                    Stepper("Temp OAT: \(Int(daTemp))°C", value: $daTemp, in: -40...50)
                    let da = DensityAltitude.calculate(pressureAltitude: daPressure, tempC: daTemp)
                    LabeledContent("Altitude densité", value: "\(da) ft")
                        .foregroundStyle(da > 8000 ? .red : da > 5000 ? .orange : .primary)
                }

                // Crosswind
                Section("Vent de travers") {
                    Stepper("Vent: \(cwWindDir)° \(cwWindSpd) kt", value: $cwWindDir, in: 0...359)
                    Stepper("Force: \(cwWindSpd) kt", value: $cwWindSpd, in: 0...50)
                    Stepper("Piste QHU: \(String(format: "%03d", cwRwy))", value: $cwRwy, in: 0...359, step: 10)
                    let (hw, cw, side) = Crosswind.components(windDir: cwWindDir, windSpeed: cwWindSpd, runwayHeading: cwRwy)
                    LabeledContent("Face", value: "\(hw) kt").foregroundStyle(hw >= 0 ? .green : .red)
                    LabeledContent("Travers", value: "\(cw) kt \(side)").foregroundStyle(cw > 15 ? .red : cw > 10 ? .orange : .primary)
                }
            }
            .navigationTitle("Calculateurs")
        }
    }
}