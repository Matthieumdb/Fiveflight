import SwiftUI
import MapKit

// MARK: - Takeoff / landing performance

/// Takeoff and landing distances from the POH baseline of the aircraft profile, corrected with the usual
/// rules of thumb: density altitude, weight, head/tail wind and grass. An estimate to cross-check, not the POH.
enum RunwayPerformance {
    struct Distances {
        let groundRoll: Double
        let over50: Double
    }

    /// Density altitude (ft) from field elevation, altimeter setting (inHg) and temperature (°C).
    static func densityAltitude(elevationFt: Double, altimeterInHg: Double?, temperatureC: Double?) -> Double {
        let pressureAlt = elevationFt + (29.92 - (altimeterInHg ?? 29.92)) * 1000
        let isa = 15 - 2 * pressureAlt / 1000
        return pressureAlt + 120 * ((temperatureC ?? isa) - isa)
    }

    /// Head (+) / cross wind components (kt) for a runway of true heading `runwayHeading`.
    /// METAR winds are true in the US.
    static func components(runwayHeading: Double, windFrom: Double, speed: Double) -> (head: Double, cross: Double) {
        let a = (windFrom - runwayHeading) * .pi / 180
        return (speed * cos(a), speed * sin(a))
    }

    static func takeoff(_ ac: AircraftProfile, densityAltitude da: Double, weight: Double,
                        headwind: Double, paved: Bool) -> Distances {
        // +10 % per 1000 ft DA (compounded), weight squared, −10 % per 9 kt head / +10 % per 2 kt tail.
        let f = factor(da: da, perThousand: 0.10) * pow(weightRatio(ac, weight), 2) * windFactor(headwind)
        var roll = ac.takeoffRoll * f
        var over = ac.takeoff50ft * f
        if !paved { let extra = over * 0.15; roll += extra; over += extra }  // grass: +15 % of the 50 ft figure
        return Distances(groundRoll: roll, over50: over)
    }

    static func landing(_ ac: AircraftProfile, densityAltitude da: Double, weight: Double,
                        headwind: Double, paved: Bool) -> Distances {
        // +4 % per 1000 ft DA, proportional to weight, same wind correction.
        let f = factor(da: da, perThousand: 0.04) * weightRatio(ac, weight) * windFactor(headwind)
        var roll = ac.landingRoll * f
        var over = ac.landing50ft * f
        if !paved { let extra = roll * 0.45; roll += extra; over += extra }  // grass: +45 % of the ground roll
        return Distances(groundRoll: roll, over50: over)
    }

    private static func factor(da: Double, perThousand k: Double) -> Double {
        pow(1 + k, max(0, da) / 1000)
    }

    private static func weightRatio(_ ac: AircraftProfile, _ w: Double) -> Double {
        guard ac.maxWeight > 0 else { return 1 }
        return max(0.7, min(1.1, w / ac.maxWeight))
    }

    private static func windFactor(_ head: Double) -> Double {
        head >= 0 ? max(0.5, 1 - 0.10 * head / 9) : 1 + 0.10 * (-head) / 2
    }
}

/// "Pistes" tab: wind components per runway end from the METAR, best runway, and the takeoff/landing
/// distances of the selected aircraft against the runway length.
struct RunwayAnalysisSection: View {
    let airport: Airport
    let runways: [Runway]
    let metar: METAR?
    @EnvironmentObject private var model: AppModel
    @State private var weight: Double = 0

    private struct EndRow: Identifiable {
        let ident: String
        let length: Int?
        let paved: Bool
        let head: Double?
        let cross: Double?
        var id: String { ident }
    }

    private var aircraft: AircraftProfile? { model.selectedAircraft ?? model.aircraftProfiles.first }

    private var rows: [EndRow] {
        runways.filter { !$0.closed }.flatMap { r in
            r.ends.map { end -> EndRow in
                var head: Double?, cross: Double?
                if let m = metar, let speed = m.windSpeed {
                    if let dir = m.windDirection, speed > 0 {
                        let c = RunwayPerformance.components(runwayHeading: end.headingT, windFrom: Double(dir), speed: Double(speed))
                        head = c.head; cross = c.cross
                    } else if speed == 0 { head = 0; cross = 0 }
                }
                return EndRow(ident: end.ident, length: r.lengthFt, paved: r.isPaved, head: head, cross: cross)
            }
        }
        .sorted { ($0.head ?? -999) > ($1.head ?? -999) }
    }

    private var densityAltitude: Double {
        RunwayPerformance.densityAltitude(elevationFt: Double(airport.elevationFt ?? 0),
                                          altimeterInHg: metar?.altimeter,
                                          temperatureC: metar?.temperature.map { Double($0) })
    }

    var body: some View {
        let endRows = self.rows
        Section {
            if let m = metar {
                LabeledContent("Vent", value: m.decoded?.wind ?? "—")
                LabeledContent("Altitude densité", value: "\(Int(densityAltitude.rounded())) ft")
            } else {
                Text("Pas de METAR : vent inconnu, calcul à 15 °C / 29.92.").foregroundStyle(.secondary)
            }
            ForEach(Array(endRows.enumerated()), id: \.element.id) { i, r in
                HStack {
                    Text(r.ident).font(TypographyToken.monoMedium).frame(width: 48, alignment: .leading)
                    if let h = r.head, let c = r.cross {
                        Label("\(abs(Int(h.rounded()))) kt", systemImage: h >= 0 ? "arrow.down" : "arrow.up")
                            .foregroundStyle(h >= 0 ? ColorToken.success : ColorToken.danger)
                        Label("\(abs(Int(c.rounded()))) kt", systemImage: c >= 0 ? "arrow.left" : "arrow.right")
                            .foregroundStyle(abs(c) > 15 ? ColorToken.danger : (abs(c) > 10 ? ColorToken.warning : .secondary))
                    }
                    Spacer()
                    if i == 0, metar != nil, (r.head ?? 0) > 0 {
                        Text("Préférée").font(.caption.bold()).foregroundStyle(ColorToken.success)
                    }
                }
                .font(.subheadline.monospacedDigit())
            }
        } header: { FFHeader("Vent par piste") } footer: {
            Text("↓ vent de face, ↑ vent arrière, ← → traversier. Orange au-delà de 10 kt, rouge au-delà de 15 kt.")
        }

        if let ac = aircraft {
            Section {
                LabeledContent("Avion", value: ac.name)
                Stepper(value: $weight, in: ac.maxWeight * 0.6...ac.maxWeight, step: 50) {
                    LabeledContent("Masse", value: "\(Int(weight)) lb")
                }
                ForEach(endRows) { r in
                    let to = RunwayPerformance.takeoff(ac, densityAltitude: densityAltitude, weight: weight,
                                                       headwind: r.head ?? 0, paved: r.paved)
                    let ld = RunwayPerformance.landing(ac, densityAltitude: densityAltitude, weight: weight,
                                                       headwind: r.head ?? 0, paved: r.paved)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(r.ident).font(TypographyToken.monoMedium)
                            Text(r.length.map { "\($0) ft" + (r.paved ? "" : " · herbe") } ?? "longueur inconnue")
                                .font(.caption).foregroundStyle(.secondary)
                            Spacer()
                        }
                        distanceLine("Décollage", to, length: r.length)
                        distanceLine("Atterrissage", ld, length: r.length)
                    }
                }
            } header: { FFHeader("Performances") } footer: {
                Text("Estimation à partir des chiffres POH du profil avion (Plus › Avions), corrigés : +10 %/1000 ft d'altitude densité au décollage, +4 % à l'atterrissage, masse, vent (−10 % par 9 kt de face, +10 % par 2 kt arrière), herbe. Vérifiez toujours avec le manuel de vol.")
            }
            .onAppear { if weight == 0 { weight = ac.maxWeight } }
        }
    }

    private func distanceLine(_ title: String, _ d: RunwayPerformance.Distances, length: Int?) -> some View {
        let ratio = length.map { d.over50 / Double(max(1, $0)) } ?? 0
        let color: Color = length == nil ? .primary : (ratio > 1 ? ColorToken.danger : (ratio > 0.7 ? ColorToken.warning : ColorToken.success))
        return HStack {
            Text(title).frame(width: 96, alignment: .leading)
            Text("roulage \(Int(d.groundRoll.rounded())) ft")
            Spacer()
            Text("15 m : \(Int(d.over50.rounded())) ft").foregroundStyle(color).bold()
        }
        .font(.caption.monospacedDigit())
    }
}

// MARK: - Airport view with own position (taxi)

/// Satellite view of the airport with its runways drawn and labelled from their threshold coordinates,
/// and the aircraft's GPS position: the taxi aid in place of a georeferenced diagram.
struct AirportTaxiMap: View {
    let airport: Airport
    let runways: [Runway]
    @State private var position: MapCameraPosition = .automatic

    private var drawable: [(name: String, a: CLLocationCoordinate2D, b: CLLocationCoordinate2D)] {
        runways.compactMap { r in
            guard let la = r.leLat, let lo = r.leLon, let ha = r.heLat, let ho = r.heLon else { return nil }
            return (r.name, CLLocationCoordinate2D(latitude: la, longitude: lo), CLLocationCoordinate2D(latitude: ha, longitude: ho))
        }
    }

    var body: some View {
        Map(position: $position) {
            UserAnnotation()
            ForEach(Array(drawable.enumerated()), id: \.offset) { _, r in
                MapPolyline(coordinates: [r.a, r.b]).stroke(.white.opacity(0.85), lineWidth: 3)
            }
            ForEach(runways.filter { !$0.closed }) { r in
                if let la = r.leLat, let lo = r.leLon, !r.leIdent.isEmpty {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: la, longitude: lo)) { label(r.leIdent) }
                }
                if let ha = r.heLat, let ho = r.heLon, !r.heIdent.isEmpty {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: ha, longitude: ho)) { label(r.heIdent) }
                }
            }
        }
        .mapStyle(.hybrid(elevation: .flat))
        .mapControls { MapUserLocationButton(); MapCompass() }
        .onAppear {
            position = .region(MKCoordinateRegion(center: airport.coordinate,
                                                  span: MKCoordinateSpan(latitudeDelta: 0.03, longitudeDelta: 0.03)))
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.caption2.bold().monospaced())
            .foregroundStyle(.white)
            .padding(.horizontal, 4).padding(.vertical, 1)
            .background(.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 3))
    }
}

// MARK: - Weather for fields without a METAR

/// For an airport without a METAR: the closest reporting station's METAR, with its distance.
struct NearestMETARSection: View {
    let airport: Airport
    let store: AirportStore
    @EnvironmentObject private var weather: WeatherService
    @State private var found: (METAR, Double)?
    @State private var searching = true

    var body: some View {
        Section {
            if let f = found {
                Text("Station la plus proche : \(f.0.station), à \(Int(f.1.rounded())) NM").font(.caption).foregroundStyle(.secondary)
                METARCard(metar: f.0)
            } else if searching {
                HStack { ProgressView(); Text("Recherche de la station la plus proche…").foregroundStyle(.secondary) }
            } else {
                Text("Aucune station METAR à moins de 50 NM.").foregroundStyle(.secondary)
            }
        } header: { FFHeader("Météo estimée") } footer: {
            Text("Pas d'observation sur ce terrain : conditions de la station voisine, à extrapoler avec prudence.")
        }
        .task(id: airport.id) {
            searching = true
            defer { searching = false }
            let candidates = store.nearest(to: airport.coordinate, limit: 12,
                                           matching: ["large_airport", "medium_airport", "small_airport"])
                .filter { $0.id != airport.id && ($0.icao ?? $0.id).hasPrefix("K") && $0.distanceNM(to: airport.coordinate) <= 50 }
            let ids = candidates.map { $0.icao ?? $0.id }
            await weather.fetchMETARs(for: ids)
            for (a, id) in zip(candidates, ids) {
                if let m = weather.metars[id] { found = (m, a.distanceNM(to: airport.coordinate)); return }
            }
        }
    }
}
