import SwiftUI

struct Leg: Identifiable {
    let id = UUID()
    let from: Airport
    let to: Airport
    var nm: Double { Haversine.nauticalMiles(from.coordinate, to.coordinate) }
    var course: Int { Haversine.trueCourse(from.coordinate, to.coordinate) }
}

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
    private var totalFuel: Double { fuelEnroute + fuelReserve }

    private func hm(_ minutes: Int) -> String { "\(minutes / 60)h\(String(format: "%02d", minutes % 60))" }

    var body: some View {
        NavigationStack {
            List {
                Section("Trajet") {
                    ForEach(waypoints) { wp in
                        Label {
                            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                                Text(wp.id).font(.headline.monospaced())
                                Text(wp.name).font(.caption).foregroundStyle(Theme.textSecondary).lineLimit(1)
                            }
                        } icon: {
                            Image(systemName: "mappin.circle.fill")
                                .foregroundStyle(Theme.accent)
                        }
                    }
                    .onDelete { waypoints.remove(atOffsets: $0) }
                    .onMove { waypoints.move(fromOffsets: $0, toOffset: $1) }
                }

                if !legs.isEmpty {
                    Section("Segments") {
                        ForEach(legs) { leg in
                            LegRowView(leg: leg)
                        }
                    }
                }

                Section("Performance") {
                    ProfileStepper(title: "Vitesse sol", value: $model.cruiseGS, range: 40...500, step: 5, unit: "kt", icon: "speedometer")
                    ProfileStepper(title: "Consommation", value: $model.fuelBurn, range: 1...100, step: 1, unit: "gal/h", icon: "fuelpump")
                    ProfileStepper(title: "Réserve", value: $model.reserveMin, range: 0...120, step: 5, unit: "min", icon: "timer")
                }

                Section("Totaux") {
                    LabeledContent("Distance", value: "\(Int(totalNM.rounded())) NM")
                    LabeledContent("Temps en route", value: hm(enrouteMin))
                    LabeledContent("Carburant en route", value: String(format: "%.1f gal", fuelEnroute))
                    LabeledContent("Réserve", value: String(format: "%.1f gal", fuelReserve))
                    LabeledContent {
                        Text(String(format: "%.1f gal", totalFuel))
                            .font(.headline.monospacedDigit().weight(.bold))
                            .foregroundStyle(Theme.accent)
                    } label: {
                        Text("Carburant requis")
                            .font(.headline.weight(.semibold))
                    }
                }

                if waypoints.count >= 2 {
                    Section {
                        Button {
                            model.logFlight(from: waypoints.first!.id, to: waypoints.last!.id,
                                            nm: Int(totalNM.rounded()), eteMinutes: enrouteMin)
                            dismiss()
                        } label: {
                            Label("Enregistrer au carnet", systemImage: "book.fill")
                                .frame(maxWidth: .infinity)
                        }
                        .primaryButton()
                    }
                }
            }
            .navigationTitle("Plan de vol")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { EditButton() }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") { dismiss() }
                        .primaryButton(fill: false)
                }
            }
        }
    }
}

struct LegRowView: View {
    let leg: Leg

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text("\(leg.from.id) → \(leg.to.id)")
                    .font(.subheadline.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                HStack(spacing: Theme.spacingS) {
                    Label("\(Int(leg.nm.rounded())) NM", systemImage: "point.topleft.down.curvedto.point.bottomright.forward")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                    Label("\(String(format: "%03d", leg.course))°", systemImage: "safari")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, Theme.spacingXS)
    }
}

struct ProfileStepper: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.body)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            Text(title)
                .font(.subheadline)
                .foregroundStyle(Theme.textPrimary)
            Spacer()
            Stepper("", value: $value, in: range, step: step)
                .labelsHidden()
            Text("\(Int(value)) \(unit)")
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(Theme.textPrimary)
                .frame(width: 80, alignment: .trailing)
        }
        .padding(.vertical, Theme.spacingXS)
    }
}