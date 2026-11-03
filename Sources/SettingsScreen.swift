import SwiftUI

struct SettingsScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        Group { // pushed inside MoreScreen's NavigationStack
            List {
                Section {
                    Stepper(value: $model.cruiseGS, in: 40.0...500.0, step: 5.0) {
                        Text("Vitesse propre (TAS) : \(Int(model.cruiseGS)) kt")
                    }
                    Stepper(value: $model.fuelBurn, in: 1.0...100.0, step: 1.0) {
                        Text("Conso : \(Int(model.fuelBurn)) gal/h")
                    }
                    Stepper(value: $model.reserveMin, in: 0.0...120.0, step: 5.0) {
                        Text("Réserve : \(Int(model.reserveMin)) min")
                    }
                    Stepper(value: $model.fuelOnBoard, in: 0.0...300.0, step: 1.0) {
                        Text(model.fuelOnBoard > 0 ? "Carburant au départ : \(Int(model.fuelOnBoard)) gal" : "Carburant au départ : non saisi")
                    }
                } header: {
                    Text("Profil avion")
                } footer: {
                    Text("Utilisé par le calculateur de vol et le plan.")
                }

                FAAKeySection()

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
                    LabeledContent("NOTAM", value: "Indisponibles (clé FAA requise)")
                }

                Section {
                    LabeledContent("Version", value: Self.appVersion)
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

    /// "1.0.39 (39)", read from the bundle so it always matches the release tag.
    static var appVersion: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "\(short) (\(build))"
    }
}