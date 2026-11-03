import SwiftUI
import UIKit

/// VFR flight plan in the FAA/ICAO format, pre-filled from the plan, for Leidos Flight Service
/// (1800wxbrief.com / 1-800-WX-BRIEF). Leidos' filing API is reserved to vendors under agreement,
/// so the app builds the complete plan, copies it, opens 1800wxbrief.com and dials Flight Service
/// for the briefing, filing, activation and closing.
struct VFRFlightPlanFilingScreen: View {
    @EnvironmentObject private var model: AppModel

    @AppStorage("fp.aircraftID") private var aircraftID = ""
    @AppStorage("fp.aircraftType") private var aircraftType = ""
    @AppStorage("fp.equipment") private var equipment = "S/C"
    @AppStorage("fp.color") private var color = ""
    @AppStorage("fp.pilotName") private var pilotName = ""
    @AppStorage("fp.pilotPhone") private var pilotPhone = ""
    @AppStorage("fp.homeBase") private var homeBase = "KFPR"
    private var departure: Date { model.departureTime }
    @State private var persons = 1
    @State private var alternate = ""
    @State private var remarks = ""
    @State private var copied = false

    private static let flightServicePhone = URL(string: "tel://18009927433")!
    private static let leidosSite = URL(string: "https://www.1800wxbrief.com/")!

    private var points: [Airport] { model.waypoints.filter { $0.id != AppModel.gpsWaypointID } }
    private var dep: Airport? { points.first }
    private var dest: Airport? { points.last }

    private var enduranceMinutes: Int {
        if model.fuelOnBoard > 0, model.fuelBurn > 0 { return Int(model.fuelOnBoard / model.fuelBurn * 60) }
        return Int((model.selectedAircraft?.enduranceHours ?? 0) * 60)
    }

    private var missing: [String] {
        var m: [String] = []
        if aircraftID.trimmingCharacters(in: .whitespaces).isEmpty { m.append("immatriculation") }
        if typeCode.isEmpty { m.append("type avion") }
        if points.count < 2 { m.append("départ et destination") }
        if pilotName.trimmingCharacters(in: .whitespaces).isEmpty { m.append("nom du pilote") }
        if pilotPhone.trimmingCharacters(in: .whitespaces).isEmpty { m.append("téléphone") }
        return m
    }

    private var typeCode: String {
        let t = aircraftType.isEmpty ? (model.selectedAircraft?.type ?? "") : aircraftType
        return t.uppercased().trimmingCharacters(in: .whitespaces)
    }

    var body: some View {
        Form {
            Section {
                TextField("Immatriculation (N12345)", text: $aircraftID)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Type OACI (\(model.selectedAircraft?.type ?? "C172"))", text: $aircraftType)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Équipement (S/C, G/C…)", text: $equipment)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                TextField("Couleur (WHITE BLUE)", text: $color).textInputAutocapitalization(.characters)
                LabeledContent("Vitesse propre", value: "\(Int(model.cruiseGS)) kt")
            } header: { FFHeader("Avion") }

            Section {
                LabeledContent("Départ", value: dep?.id ?? "—")
                DatePicker("Heure de départ", selection: $model.departureTime)
                LabeledContent("Altitude", value: "\(model.cruiseAlt) ft")
                LabeledContent("Route", value: routeText)
                LabeledContent("Destination", value: dest?.id ?? "—")
                LabeledContent("Durée estimée", value: hhmm(Int(model.totalTimeMinutes.rounded())))
                TextField("Dégagement (facultatif)", text: $alternate)
                    .textInputAutocapitalization(.characters).autocorrectionDisabled()
                LabeledContent("Autonomie", value: enduranceMinutes > 0 ? hhmm(enduranceMinutes) : "Saisir le carburant au départ")
                Stepper("Personnes à bord : \(persons)", value: $persons, in: 1...9)
                TextField("Remarques", text: $remarks)
            } header: { FFHeader("Vol") }

            Section {
                TextField("Nom", text: $pilotName).textContentType(.name)
                TextField("Téléphone", text: $pilotPhone).keyboardType(.phonePad).textContentType(.telephoneNumber)
                TextField("Base (OACI)", text: $homeBase).textInputAutocapitalization(.characters)
            } header: { FFHeader("Pilote") }

            Section {
                Text(icaoPlan).font(TypographyToken.monoXSmall).textSelection(.enabled)
            } header: { FFHeader("Plan de vol OACI (FAA)") } footer: {
                if !missing.isEmpty {
                    Text("À compléter : \(missing.joined(separator: ", ")).").foregroundStyle(ColorToken.warning)
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = icaoPlan
                    copied = true
                    Haptics.success()
                } label: {
                    Label(copied ? "Plan copié" : "Copier le plan", systemImage: copied ? "checkmark.circle.fill" : "doc.on.doc")
                }
                Link(destination: Self.leidosSite) {
                    Label("Déposer sur 1800wxbrief.com (Leidos)", systemImage: "paperplane.fill")
                }
                Link(destination: Self.flightServicePhone) {
                    Label("Appeler Flight Service : briefing, dépôt", systemImage: "phone.fill")
                }
                ShareLink(item: icaoPlan) { Label("Partager le plan", systemImage: "square.and.arrow.up") }
            } header: { FFHeader("Briefing et dépôt Leidos") } footer: {
                Text("Copie le plan puis colle-le dans 1800wxbrief.com > Flight Plans, ou dicte-le au téléphone (1-800-WX-BRIEF). Le dépôt direct depuis l'app demande un accès développeur Leidos, réservé aux éditeurs sous contrat.")
            }

            Section {
                Link(destination: Self.flightServicePhone) {
                    Label("Activer le plan (1-800-WX-BRIEF)", systemImage: "play.circle.fill")
                }
                Link(destination: Self.flightServicePhone) {
                    Label("Clôturer le plan à l'arrivée", systemImage: "stop.circle.fill")
                }
            } header: { FFHeader("En vol") } footer: {
                Text("En l'air : Flight Service sur 122.2 MHz ou la fréquence RCO de la carte. Un plan VFR non clôturé déclenche les recherches 30 min après l'heure prévue.")
            }
        }
        .navigationTitle("Plan de vol VFR")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            if aircraftType.isEmpty, let t = model.selectedAircraft?.type { aircraftType = t }
        }
        .onChange(of: icaoPlan) { _, _ in copied = false }
    }

    // MARK: ICAO plan

    private var routeText: String {
        let mid = points.dropFirst().dropLast().map(\.flightPlanToken)
        return mid.isEmpty ? "DCT" : "DCT " + mid.joined(separator: " DCT ") + " DCT"
    }

    private func hhmm(_ minutes: Int) -> String {
        String(format: "%02d%02d", max(0, minutes) / 60, max(0, minutes) % 60)
    }

    private func icao(_ a: Airport?) -> String {
        guard let a else { return "ZZZZ" }
        let code = a.icao ?? a.id
        return code.count == 4 && code.allSatisfy(\.isLetter) ? code : "ZZZZ"
    }

    /// Item 7 to 19 of the ICAO flight plan, as filed with FAA Flight Service.
    var icaoPlan: String {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let c = utc.dateComponents([.year, .month, .day, .hour, .minute], from: departure)
        let time = String(format: "%02d%02d", c.hour ?? 0, c.minute ?? 0)
        let dof = String(format: "%02d%02d%02d", (c.year ?? 2000) % 100, c.month ?? 1, c.day ?? 1)
        let speed = String(format: "N%04d", Int(model.cruiseGS.rounded()))
        let level = String(format: "A%03d", model.cruiseAlt / 100)
        let ete = hhmm(Int(model.totalTimeMinutes.rounded()))
        let id = aircraftID.uppercased().replacingOccurrences(of: " ", with: "")
        let type = typeCode.isEmpty ? "ZZZZ" : typeCode

        var item18 = ["DOF/\(dof)"]
        if icao(dep) == "ZZZZ", let d = dep { item18.append("DEP/\(d.id)") }
        if icao(dest) == "ZZZZ", let d = dest { item18.append("DEST/\(d.id)") }
        if type == "ZZZZ" { item18.append("TYP/UNKNOWN") }
        let rmk = remarks.trimmingCharacters(in: .whitespaces).uppercased()
        if !rmk.isEmpty { item18.append("RMK/\(rmk)") }

        var item19 = ["E/\(hhmm(enduranceMinutes))", "P/\(persons)"]
        let colour = color.trimmingCharacters(in: .whitespaces).uppercased()
        if !colour.isEmpty { item19.append("A/\(colour)") }
        let pilot = [pilotName.uppercased(), pilotPhone.filter(\.isNumber), homeBase.uppercased()]
            .filter { !$0.isEmpty }.joined(separator: " ")
        if !pilot.isEmpty { item19.append("C/\(pilot)") }

        let alt = alternate.trimmingCharacters(in: .whitespaces).uppercased()
        let altPart = alt.isEmpty ? "" : " " + alt
        let ident = id.isEmpty ? "NXXXXX" : id
        return """
        (FPL-\(ident)-VG
        -\(type)/L-\(equipment.uppercased())
        -\(icao(dep))\(time)
        -\(speed)\(level) \(routeText)
        -\(icao(dest))\(ete)\(altPart)
        -\(item18.joined(separator: " "))
        -\(item19.joined(separator: " ")))
        """
    }
}
