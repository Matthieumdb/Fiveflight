import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ProfileRow(
                        title: "Vitesse sol",
                        value: Binding(
                            get: { Int(model.cruiseGS) },
                            set: { model.cruiseGS = Double($0) }
                        ),
                        range: 40...500,
                        step: 5,
                        unit: "kt",
                        systemImage: "speedometer"
                    )

                    ProfileRow(
                        title: "Consommation",
                        value: Binding(
                            get: { Int(model.fuelBurn) },
                            set: { model.fuelBurn = Double($0) }
                        ),
                        range: 1...100,
                        step: 1,
                        unit: "gal/h",
                        systemImage: "fuelpump"
                    )

                    ProfileRow(
                        title: "Réserve",
                        value: Binding(
                            get: { Int(model.reserveMin) },
                            set: { model.reserveMin = Double($0) }
                        ),
                        range: 0...120,
                        step: 5,
                        unit: "min",
                        systemImage: "timer"
                    )
                } header: {
                    Text("Profil avion")
                } footer: {
                    Text("Utilisé par le calculateur de vol et le plan ICAO.")
                        .foregroundStyle(Theme.textSecondary)
                }

                Section {
                    Toggle(isOn: $model.nightMode) {
                        Label("Mode nuit (rouge)", systemImage: "moon.fill")
                            .foregroundStyle(Theme.textPrimary)
                    }
                    .tint(Theme.accent)
                } footer: {
                    Text("Teinte rouge pour préserver la vision nocturne en vol de nuit.")
                        .foregroundStyle(Theme.textSecondary)
                }

                Section("Sources de données") {
                    LabeledContent("Aéroports", value: "OurAirports")
                    LabeledContent("Carte VFR", value: "FAA Sectionnelles")
                    LabeledContent("Météo", value: "NOAA + Iowa Mesonet")
                    LabeledContent("Espace aérien", value: "Données FAA (échantillon)")
                }

                Section {
                    LabeledContent("Version", value: "0.4")
                    LabeledContent("Zone", value: "US · VFR")
                } header: {
                    Text("À propos")
                } footer: {
                    Text("Démo — ne pas utiliser pour la navigation réelle. Données de services publics tiers, non certifiées.")
                        .foregroundStyle(Theme.textSecondary)
                }
            }
            .navigationTitle("Réglages")
        }
    }
}

struct ProfileRow: View {
    let title: String
    @Binding var value: Int
    let range: ClosedRange<Int>
    let step: Int
    let unit: String
    let systemImage: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingS) {
            HStack {
                Image(systemName: systemImage)
                    .font(.body)
                    .foregroundStyle(Theme.accent)
                    .frame(width: 24)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(Theme.textPrimary)
                Spacer()
            }

            HStack {
                Stepper("", value: $value, in: range, step: step)
                    .labelsHidden()
                Text("\(value) \(unit)")
                    .font(.title3.monospacedDigit().weight(.semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .frame(width: 90, alignment: .trailing)
            }
        }
        .padding(.vertical, Theme.spacingXS)
    }
}