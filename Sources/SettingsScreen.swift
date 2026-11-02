import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Stepper(value: $model.cruiseGS, in: 40.0...500.0, step: 5.0) {
                        Text("Vitesse sol : \(Int(model.cruiseGS)) kt")
                    }
                    Stepper(value: $model.fuelBurn, in: 1.0...100.0, step: 1.0) {
                        Text("Conso : \(Int(model.fuelBurn)) gal/h")
                    }
                    Stepper(value: $model.reserveMin, in: 0.0...120.0, step: 5.0) {
                        Text("Réserve : \(Int(model.reserveMin)) min")
                    }
                } header: {
                    Text("Profil avion")
                } footer: {
                    Text("Utilisé par le calculateur de vol et le plan.")
                }

                Section {
                    Toggle(isOn: $model.nightMode) {
                        Label("Mode nuit (rouge)", systemImage: "moon.fill")
                    }
                } footer: {
                    Text("Teinte rouge pour préserver la vision nocturne en vol de nuit.")
                }

                Section {
                    Toggle(isOn: $model.showSectional) {
                        Label("Carte VFR Sectional (FAA)", systemImage: "map")
                    }
                    Toggle(isOn: $model.showRadar) {
                        Label("Radar NEXRAD (Iowa State)", systemImage: "cloud.rain")
                    }
                } header: {
                    Text("Couches carte")
                } footer: {
                    Text("Activation immédiate sur la carte principale.")
                }

                Section {
                    Picker("Apparence", selection: $model.appearanceMode) {
                        Text("Système").tag(0)
                        Text("Clair").tag(1)
                        Text("Sombre").tag(2)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Affichage")
                } footer: {
                    Text("Respecte le mode système par défaut.")
                }

                Section("Sources de données") {
                    LabeledContent("Aéroports", value: "OurAirports")
                    LabeledContent("Carte VFR", value: "FAA sectionnelles")
                    LabeledContent("Météo", value: "NOAA + Iowa Mesonet")
                    LabeledContent("Espaces aériens", value: "FAA ArcGIS")
                    LabeledContent("NOTAM", value: "FAA (clé requise)")
                }

                Section {
                    LabeledContent("Version", value: "1.0.37")
                    LabeledContent("Zone", value: "US · VFR")
                } header: {
                    Text("À propos")
                } footer: {
                    Text("Démo — ne pas utiliser pour la navigation réelle. Données de services publics tiers, non certifiées.")
                }
            }
            .navigationTitle("Réglages")
        }
    }
}