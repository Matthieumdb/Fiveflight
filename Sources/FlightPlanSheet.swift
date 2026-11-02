import SwiftUI

struct Leg: Identifiable {
    let id = UUID()
    let from: Airport
    let to: Airport
    var nm: Double { Haversine.nauticalMiles(from.coordinate, to.coordinate) }
    var course: Int { Haversine.trueCourse(from.coordinate, to.coordinate) }
}

/// Full flight plan: editable waypoints, per-leg table, performance + fuel with reserve.
struct FlightPlanSheet: View {
    @Binding var waypoints: [Airport]
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss

    private var legs: [Leg] {
        zip(waypoints, waypoints.dropFirst()).map { Leg(from: $0.0, to: $0.1) }
    }
    private var totalNM: Double { legs.reduce(0) { $0 + $1.nm } }
    private var hours: Double { model.cruiseGS > 0 ? totalNM / model.cruiseGS : 0 }
    private var enrouteMin: Int { Int((hours * 60).rounded()) }
    private var fuelEnroute: Double { hours * model.fuelBurn }
    private var fuelReserve: Double { model.reserveMin / 60 * model.fuelBurn }

    private func hm(_ minutes: Int) -> String { "\(minutes / 60)h\(String(format: "%02d", minutes % 60))" }

    var body: some View {
        NavigationStack {
            List {
                Section("Trajet") {
                    ForEach(waypoints) { wp in
                        Label {
                            VStack(alignment: .leading, spacing: 1) {
                                Text(wp.id).font(.headline.monospaced())
                                Text(wp.name).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                            }
                        } icon: { Image(systemName: "mappin.circle.fill").foregroundStyle(Theme.accent) }
                    }
                    .onDelete { waypoints.remove(atOffsets: $0) }
                    .onMove { waypoints.move(fromOffsets: $0, toOffset: $1) }
                }

                if !legs.isEmpty {
                    Section("Segments") {
                        ForEach(legs) { leg in
                            HStack {
                                Text("\(leg.from.id) → \(leg.to.id)").font(.subheadline.monospaced())
                                Spacer()
                                Text("\(Int(leg.nm.rounded())) NM").monospacedDigit()
                                Text("\(String(format: "%03d", leg.course))°")
                                    .monospacedDigit().foregroundStyle(.secondary)
                                    .frame(width: 54, alignment: .trailing)
                            }
                            .font(.subheadline)
                        }
                    }
                }

                Section("Performance") {
                    Stepper(value: $model.cruiseGS, in: 40.0...500.0, step: 5.0) {
                        Text("Vitesse sol : \(Int(model.cruiseGS)) kt")
                    }
                    Stepper(value: $model.fuelBurn, in: 1.0...100.0, step: 1.0) {
                        Text("Conso : \(Int(model.fuelBurn)) gal/h")
                    }
                    Stepper(value: $model.reserveMin, in: 0.0...120.0, step: 5.0) {
                        Text("Réserve : \(Int(model.reserveMin)) min")
                    }
                }

                Section("Totaux") {
                    LabeledContent("Distance", value: "\(Int(totalNM.rounded())) NM")
                    LabeledContent("Temps en route", value: hm(enrouteMin))
                    LabeledContent("Carburant en route", value: String(format: "%.1f gal", fuelEnroute))
                    LabeledContent("Réserve", value: String(format: "%.1f gal", fuelReserve))
                    LabeledContent {
                        Text(String(format: "%.1f gal", fuelEnroute + fuelReserve))
                            .bold().foregroundStyle(Theme.accent)
                    } label: { Text("Carburant requis").bold() }
                }

                if waypoints.count >= 2 {
                    Section {
                        Button {
                            model.logFlight(from: waypoints.first!.id, to: waypoints.last!.id,
                                            nm: Int(totalNM.rounded()), eteMinutes: enrouteMin)
                            dismiss()
                        } label: { Label("Enregistrer au carnet", systemImage: "book.fill") }
                    }
                }
            }
            .navigationTitle("Plan de vol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) { Button("OK") { dismiss() } }
            }
        }
    }
}
