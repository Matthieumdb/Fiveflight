import SwiftUI
import MapKit

struct AirspaceScreen: View {
    @EnvironmentObject private var location: LocationManager
    @State private var altitude: Int = 3000
    @State private var selectedAirspace: Airspace?
    @State private var showingDetail = false
    @State private var obstacles: [Obstacle] = []

    var body: some View {
        NavigationStack {
            List {
                Section("Altitude de référence") {
                    Stepper("\(altitude) ft MSL", value: $altitude, in: 0...18000, step: 500)
                }

                Section("Espace aérien à votre position") {
                    if let loc = location.coordinate {
                        let airspaces = AirspaceChecker.check(
                            coordinate: loc,
                            altitude: altitude
                        )
                        if airspaces.isEmpty {
                            Label("Aucun espace aérien contrôlé", systemImage: "checkmark.circle")
                                .foregroundStyle(.green)
                        } else {
                            ForEach(airspaces) { airspace in
                                Button {
                                    selectedAirspace = airspace
                                    showingDetail = true
                                } label: {
                                    HStack {
                                        Circle().fill(Color(hex: airspace.color))
                                            .frame(width: 12, height: 12)
                                        VStack(alignment: .leading) {
                                            Text(airspace.name).foregroundStyle(Theme.textPrimary)
                                            Text("\(airspace.floor.map { "\($0) ft" } ?? "SFC") - \(airspace.ceiling.map { "\($0) ft" } ?? "UNL")")
                                                .font(.caption).foregroundStyle(Theme.textSecondary)
                                        }
                                    }
                                }
                            }
                        }
                    } else {
                        Label("Localisation non disponible", systemImage: "location.slash")
                            .foregroundStyle(.orange)
                    }
                }

                Section("Obstacles sur la route (5 NM)") {
                    if obstacles.isEmpty {
                        Text("Ajoutez un plan de vol pour voir les obstacles").foregroundStyle(.secondary)
                    } else {
                        ForEach(obstacles) { obs in
                            HStack {
                                Text(obs.type.capitalized)
                                Spacer()
                                Text("\(obs.topElevation) ft AMSL").monospacedDigit()
                            }
                        }
                    }
                }
            }
            .navigationTitle("Espace Aérien")
            .sheet(isPresented: $showingDetail) {
                if let airspace = selectedAirspace {
                    AirspaceDetailView(airspace: airspace)
                }
            }
            .onAppear { checkObstacles() }
        }
    }

    private func checkObstacles() {
        // Would check against current flight plan
        obstacles = []
    }
}

struct AirspaceDetailView: View {
    let airspace: Airspace
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section("Informations") {
                    LabeledContent("Nom", value: airspace.name)
                    LabeledContent("Type", value: airspace.type.rawValue)
                    LabeledContent("Plancher", value: airspace.floor.map { "\($0) ft MSL" } ?? "Surface")
                    LabeledContent("Plafond", value: airspace.ceiling.map { "\($0) ft MSL" } ?? "Illimité")
                }

                Section("Exigences VFR") {
                    ForEach(requirements(for: airspace.type), id: \.self) { req in
                        Text(req)
                    }
                }
            }
            .navigationTitle(airspace.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                }
            }
        }
    }

    private func requirements(for type: AirspaceType) -> [String] {
        switch type {
        case .classA:
            return ["IFR obligatoire", "Autorisation ATC requise", "Transpondeur Mode C/S"]
        case .classB:
            return ["Autorisation ATC requise", "Transpondeur Mode C/S", "Radio bidirectionnelle", "VFR: 3 SM visibilité, hors des nuages"]
        case .classC:
            return ["Radio bidirectionnelle", "Transpondeur Mode C/S", "Contact ATC avant entrée", "VFR: 3 SM, 1000 ft dessus, 500 ft dessous, 2000 ft horizontal"]
        case .classD:
            return ["Radio bidirectionnelle", "Contact tour avant entrée", "VFR: 3 SM, 1000 ft dessus, 500 ft dessous, 2000 ft horizontal"]
        case .classE:
            return ["VFR: 3 SM, 1000 ft dessus, 500 ft dessous, 2000 ft horizontal (sous 10k ft)", "Au-dessus 10k ft: 5 SM, 1000 ft dessus, 1000 ft dessous, 1 SM horizontal"]
        case .moa:
            return ["Activité militaire possible", "Vérifier statut auprès de ATC/FSS", "Éviter si actif"]
        case .restricted, .prohibited:
            return ["Entrée interdite sans autorisation", "Dangereux: tirs, missiles, etc."]
        case .tfr:
            return ["Restriction temporaire", "Vérifier NOTAMs", "Interdit sauf autorisation"]
        default:
            return ["Règles VFR standard"]
        }
    }
}