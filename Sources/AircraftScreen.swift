import SwiftUI
import Charts

/// Aircraft profiles: pick the one flown (speed, burn, W&B envelope), add or edit them.
struct AircraftScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: AircraftProfile?

    var body: some View {
        List {
            ForEach(model.aircraftProfiles) { ac in
                HStack {
                    VStack(alignment: .leading) {
                        Text(ac.name).font(TypographyToken.bodyMedium)
                        Text("\(ac.type) · \(Int(ac.cruiseSpeed)) kt · \(ac.fuelBurn, specifier: "%.1f") gal/h · \(Int(ac.capacityGal)) gal")
                            .font(TypographyToken.bodySmall).foregroundStyle(ColorToken.textSecondary)
                    }
                    Spacer()
                    if model.selectedAircraft?.id == ac.id {
                        Image(systemName: "checkmark.circle.fill").foregroundStyle(ColorToken.success)
                    }
                }
                .contentShape(Rectangle())
                .onTapGesture { model.selectAircraft(ac) }
                .swipeActions {
                    Button("Modifier") { editing = ac }.tint(ColorToken.brandPrimary)
                    Button("Supprimer", role: .destructive) { model.aircraftProfiles.removeAll { $0.id == ac.id } }
                }
            }
        }
        .navigationTitle("Avions")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    editing = AircraftProfile(name: "Nouvel avion", type: "", cruiseSpeed: 110, fuelBurn: 8, capacityGal: 40)
                } label: { Image(systemName: "plus") }
            }
        }
        .sheet(item: $editing) { ac in
            AircraftEditor(profile: ac) { saved in
                if let i = model.aircraftProfiles.firstIndex(where: { $0.id == saved.id }) {
                    model.aircraftProfiles[i] = saved
                } else {
                    model.aircraftProfiles.append(saved)
                }
                if model.selectedAircraft?.id == saved.id { model.selectAircraft(saved) }
            }
        }
    }
}

private struct AircraftEditor: View {
    @State var profile: AircraftProfile
    let onSave: (AircraftProfile) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Nom", text: $profile.name)
                    TextField("Type (ex. C172)", text: $profile.type)
                } header: { FFHeader("Identification") }
                Section {
                    number("Vitesse propre (kt)", $profile.cruiseSpeed)
                    number("Consommation (gal/h)", $profile.fuelBurn)
                    number("Capacité carburant (gal)", $profile.capacityGal)
                } header: { FFHeader("Performances") }
                Section {
                    number("Vitesse de montée (kt)", $profile.climbSpeed)
                    number("Taux de montée (ft/min)", $profile.climbRate)
                    number("Conso en montée (gal/h)", $profile.climbBurn)
                    number("Vitesse de descente (kt)", $profile.descentSpeed)
                    number("Taux de descente (ft/min)", $profile.descentRate)
                } header: { FFHeader("Montée et descente") } footer: {
                    Text("Utilisés par le navlog pour le haut de montée (TOC) et le début de descente (TOD).")
                }
                Section {
                    number("Décollage, roulage (ft)", $profile.takeoffRoll)
                    number("Décollage, passage 50 ft (ft)", $profile.takeoff50ft)
                    number("Atterrissage, roulage (ft)", $profile.landingRoll)
                    number("Atterrissage, depuis 50 ft (ft)", $profile.landing50ft)
                } header: { FFHeader("Distances POH") } footer: {
                    Text("Niveau de la mer, 15 °C, masse max, sans vent, piste en dur. Corrigées par aérodrome dans l'onglet Pistes.")
                }
                Section {
                    number("Masse max (lb)", $profile.maxWeight)
                    number("Centrage avant (in)", $profile.cgForward)
                    number("Centrage arrière (in)", $profile.cgAft)
                } header: { FFHeader("Masse et centrage") }
            }
            .navigationTitle(profile.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) { Button("Enregistrer") { onSave(profile); dismiss() } }
            }
        }
    }

    private func number(_ title: String, _ value: Binding<Double>) -> some View {
        LabeledContent(title) {
            TextField(title, value: value, format: .number).keyboardType(.decimalPad).multilineTextAlignment(.trailing)
        }
    }
}

/// W&B envelope (forward/aft CG limits up to max weight) with the loaded aircraft's point.
struct WeightBalanceChart: View {
    @ObservedObject var model: WeightBalanceModel

    var body: some View {
        Chart {
            RectangleMark(xStart: .value("CG avant", model.cgForward), xEnd: .value("CG arrière", model.cgAft),
                          yStart: .value("Masse", 0), yEnd: .value("Masse max", model.maxWeight))
                .foregroundStyle(ColorToken.success.opacity(0.2))
            PointMark(x: .value("CG", model.cg), y: .value("Masse", model.totalWeight))
                .foregroundStyle(model.isWithinLimits ? ColorToken.success : ColorToken.danger)
                .symbolSize(140)
        }
        .chartXScale(domain: min(model.cgForward, model.cg) - 3 ... max(model.cgAft, model.cg) + 3)
        .chartYScale(domain: min(model.totalWeight, model.maxWeight * 0.6) * 0.95 ... max(model.totalWeight, model.maxWeight) * 1.05)
        .chartXAxisLabel("Centrage (in)")
        .chartYAxisLabel("Masse (lb)")
        .frame(height: 220)
    }
}
