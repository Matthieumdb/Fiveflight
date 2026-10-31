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
                    VStack(alignment: .leading, spacing: Theme.spacingS) {
                        HStack {
                            Text("\(altitude) ft MSL")
                                .font(.title3.monospacedDigit().weight(.semibold))
                                .foregroundStyle(Theme.textPrimary)
                            Spacer()
                        }
                        Slider(value: Binding(
                            get: { Double(altitude) },
                            set: { altitude = Int($0.rounded()) }
                        ), in: 0...18000, step: 500)
                        .tint(Theme.accent)
                    }
                    .padding(.vertical, Theme.spacingXS)
                }

                Section {
                    if let loc = location.coordinate {
                        let airspaces = AirspaceChecker.check(
                            coordinate: loc,
                            altitude: altitude
                        )

                        if airspaces.isEmpty {
                            Label("Aucun espace aérien contrôlé", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(Theme.green)
                                .font(.subheadline)
                                .padding(.vertical, Theme.spacingXS)
                        } else {
                            ForEach(airspaces) { airspace in
                                Button {
                                    selectedAirspace = airspace
                                    showingDetail = true
                                } label: {
                                    AirspaceRowView(airspace: airspace)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    } else {
                        Label("Localisation non disponible", systemImage: "location.slash")
                            .foregroundStyle(Theme.orange)
                            .font(.subheadline)
                            .padding(.vertical, Theme.spacingXS)
                    }
                } header: {
                    Text("Espace aérien à votre position")
                } footer: {
                    Text("Basé sur la position GPS actuelle et l'altitude sélectionnée.")
                }

                Section {
                    if obstacles.isEmpty {
                        ContentUnavailableView(
                            "Aucun obstacle",
                            systemImage: "mountain.2",
                            description: Text("Ajoutez un plan de vol pour voir les obstacles sur la route.")
                        )
                        .listRowBackground(Color.clear)
                        .listRowSeparator(.hidden)
                    } else {
                        ForEach(obstacles) { obs in
                            HStack {
                                Label(obs.type.capitalized, systemImage: "triangle.fill")
                                    .font(.subheadline)
                                    .foregroundStyle(Theme.textPrimary)
                                Spacer()
                                Text("\(obs.topElevation) ft AMSL")
                                    .font(.subheadline.monospacedDigit())
                                    .foregroundStyle(Theme.textSecondary)
                            }
                            .padding(.vertical, Theme.spacingXS)
                        }
                    }
                } header: {
                    Text("Obstacles sur la route (5 NM)")
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
        obstacles = []
    }
}

struct AirspaceRowView: View {
    let airspace: Airspace

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            Circle()
                .fill(Color(hex: airspace.color))
                .frame(width: 12, height: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(airspace.name)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(airspace.floor.map { "\($0) ft" } ?? "SFC") – \(airspace.ceiling.map { "\($0) ft" } ?? "UNL")")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.caption.weight(.semibold))
                .foregroundStyle(Theme.textTertiary)
        }
        .padding(.vertical, Theme.spacingXS)
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
                        Label(req, systemImage: "checkmark.circle")
                            .font(.subheadline)
                            .foregroundStyle(Theme.textPrimary)
                    }
                }
            }
            .navigationTitle(airspace.name)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fermer") { dismiss() }
                        .primaryButton(fill: false)
                }
            }
        }
        .presentationDetents([.medium])
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