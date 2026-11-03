import SwiftUI
import CoreLocation
import AVFoundation

/// In-flight state from the GPS: active leg (auto-sequenced), flight time, fuel left and alerts.
@MainActor
final class FlightMonitor: ObservableObject {
    static let shared = FlightMonitor()

    /// Index in `waypoints` of the waypoint being flown to.
    @Published var activeIndex = 1
    @Published private(set) var airborneSince: Date?
    @Published private(set) var alerts: [String] = []

    /// Airborne above this ground speed (kt).
    static let airborneSpeed = 40.0
    /// A waypoint is reached inside this distance (NM).
    static let sequenceRadius = 1.0
    /// Airspace look-ahead along the track (NM).
    static let lookAhead = 5.0

    private var lastPlan: [String] = []

    /// Glide range from the current height above the ground (NM), nil on the ground.
    @Published private(set) var glideRangeNM: Double?
    /// Closest landable airport and whether it is inside the glide range.
    @Published private(set) var nearestLandable: (airport: Airport, distanceNM: Double)?
    private var lastGlideCheck = Date.distantPast

    private let speech = AVSpeechSynthesizer()
    private var spokenAt: [String: Date] = [:]
    private var audioReady = false

    /// Still-air glide distance: height above ground × glide ratio.
    nonisolated static func glideRange(altitudeFt: Double, groundFt: Double, ratio: Double) -> Double {
        max(0, altitudeFt - groundFt) * ratio / 6076.12
    }

    /// Updates the glide ring (every 5 s; the nearest-airport search scans the whole database).
    private func updateGlide(position: CLLocationCoordinate2D, altitudeFt: Int, airborne: Bool,
                             model: AppModel, store: AirportStore?) -> String? {
        guard airborne, let store else { glideRangeNM = nil; nearestLandable = nil; return nil }
        if Date.now.timeIntervalSince(lastGlideCheck) > 5 || nearestLandable == nil {
            lastGlideCheck = .now
            if let a = store.nearest(to: position, limit: 1,
                                     matching: ["large_airport", "medium_airport", "small_airport"]).first {
                nearestLandable = (a, a.distanceNM(to: position))
            }
        }
        let ground = Double(nearestLandable?.airport.elevationFt ?? 0)
        let range = Self.glideRange(altitudeFt: Double(altitudeFt), groundFt: ground, ratio: model.glideRatio)
        glideRangeNM = range
        if let n = nearestLandable, n.distanceNM > range {
            return String(format: "Hors plané : %@ à %.0f NM, plané %.1f NM", n.airport.id, n.distanceNM, range)
        }
        return nil
    }

    /// Speaks alerts that are new (same kind not spoken in the last 2 minutes).
    private func announce(_ found: [String], enabled: Bool) {
        guard enabled else { return }
        for alert in found {
            let kind = alert.split(separator: " ").prefix(2).joined(separator: " ")
            if let t = spokenAt[kind], Date.now.timeIntervalSince(t) < 120 { continue }
            spokenAt[kind] = .now
            if !audioReady {
                try? AVAudioSession.sharedInstance().setCategory(.playback, mode: .voicePrompt,
                                                                 options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
                try? AVAudioSession.sharedInstance().setActive(true)
                audioReady = true
            }
            let spoken = alert
                .replacingOccurrences(of: " NM", with: " nautiques")
                .replacingOccurrences(of: " ft", with: " pieds")
                .replacingOccurrences(of: "gal", with: "gallons")
            let u = AVSpeechUtterance(string: spoken)
            u.voice = AVSpeechSynthesisVoice(language: "fr-FR")
            u.rate = 0.52
            speech.speak(u)
        }
    }

    /// Spoken check of the voice alerts from Réglages.
    func testVoice() {
        spokenAt["Test"] = nil
        announce(["Test alerte vocale Fiveflight"], enabled: true)
    }

    /// Called on each GPS fix.
    func update(position: CLLocationCoordinate2D, groundSpeed: Double, course: Double, altitudeFt: Int,
                model: AppModel, airspaces: [Airspace], store: AirportStore? = nil) {
        let ids = model.waypoints.map(\.id)
        if ids != lastPlan { lastPlan = ids; activeIndex = 1 }

        if groundSpeed > Self.airborneSpeed, airborneSince == nil { airborneSince = .now }
        if groundSpeed < 15, let since = airborneSince, Date.now.timeIntervalSince(since) > 120 { airborneSince = nil }

        // Auto-sequence: next waypoint once within 1 NM of the active one.
        if activeIndex < model.waypoints.count - 1,
           model.waypoints[activeIndex].distanceNM(to: position) < Self.sequenceRadius {
            activeIndex += 1
        }

        var found: [String] = []
        if groundSpeed > Self.airborneSpeed, course >= 0 {
            let ahead = Haversine.destination(from: position, course: Int(course.rounded()), distanceNM: Self.lookAhead)
            for a in airspaces where a.isActive && a.type.needsAlert && a.suaStatus() != .inactive
                && altitudeFt >= a.floor - 300 && altitudeFt <= a.ceiling {
                let inside = a.polygons.contains { Airspace.pointInPolygonStatic(position, polygon: $0.map(\.clCoordinate)) }
                if inside {
                    found.append("Dans \(a.name)")
                } else if a.polygons.contains(where: { Airspace.segmentIntersectsPolygon(position, ahead, polygon: $0) }) {
                    found.append("\(a.name) à moins de \(Int(Self.lookAhead)) NM devant")
                }
            }
        }
        // Obstacle ahead: within 2 NM of the track and less than 500 ft below the aircraft.
        if groundSpeed > Self.airborneSpeed, course >= 0 {
            let ahead = Haversine.destination(from: position, course: Int(course.rounded()), distanceNM: 2)
            if let o = Obstacle.all.first(where: { o in
                o.amslFt + 500 > altitudeFt
                    && Haversine.nauticalMiles(position, o.coordinate) < 2
                    && Haversine.nauticalMiles(ahead, o.coordinate) < Haversine.nauticalMiles(position, o.coordinate)
            }) {
                found.append("Obstacle \(o.amslFt) ft MSL à \(String(format: "%.1f", Haversine.nauticalMiles(position, o.coordinate))) NM")
            }
        }
        // Traffic: within 2 NM and 500 ft.
        for t in ADSBReceiver.shared.traffic
            where Haversine.nauticalMiles(position, t.coordinate) < 2 && abs(t.altitudeFt - altitudeFt) < 500 {
            found.append(String(format: "Trafic %@ à %.1f NM, %+d ft",
                                t.callsign.isEmpty ? "?" : t.callsign, Haversine.nauticalMiles(position, t.coordinate),
                                t.altitudeFt - altitudeFt))
        }
        if let left = fuelRemaining(model: model), model.fuelBurn > 0 {
            let reserve = model.reserveMin / 60 * model.fuelBurn
            let needed = remainingMinutes(position: position, groundSpeed: groundSpeed, model: model) / 60 * model.fuelBurn
            if left - needed < reserve {
                found.append(String(format: "Carburant : %.1f gal restants, réserve entamée à l'arrivée", left))
            }
        }
        let glide = updateGlide(position: position, altitudeFt: altitudeFt,
                                airborne: groundSpeed > Self.airborneSpeed, model: model, store: store)
        if model.showGlideRing, let glide { found.append(glide) }
        if found != alerts {
            if found.count > alerts.count { Haptics.warning() }
            announce(found.filter { !alerts.contains($0) && !$0.hasPrefix("Hors plané") }, enabled: model.voiceAlerts)
            alerts = found
        }
    }

    /// Fuel on board at departure minus burn since takeoff; nil when no fuel load was entered.
    func fuelRemaining(model: AppModel) -> Double? {
        guard model.fuelOnBoard > 0 else { return nil }
        let hours = airborneSince.map { Date.now.timeIntervalSince($0) / 3600 } ?? 0
        return model.fuelOnBoard - hours * model.fuelBurn
    }

    /// Minutes to the last waypoint along the remaining plan at the current (or planned) speed.
    func remainingMinutes(position: CLLocationCoordinate2D, groundSpeed: Double, model: AppModel) -> Double {
        let wps = model.waypoints
        guard activeIndex < wps.count else { return 0 }
        var nm = wps[activeIndex].distanceNM(to: position)
        if activeIndex + 1 < wps.count {
            for i in (activeIndex + 1)..<wps.count { nm += wps[i - 1].distanceNM(to: wps[i].coordinate) }
        }
        let speed = groundSpeed > Self.airborneSpeed ? groundSpeed : model.cruiseGS
        return speed > 0 ? nm / speed * 60 : 0
    }
}

extension Airspace.AirspaceType {
    /// Airspace worth a cockpit alert: controlled, Class E surface, or SUA needing permission (incl. TFR).
    var needsAlert: Bool {
        switch self {
        case .classAirspace(let c): return c.requiresATC
        case .classESurface: return true
        case .sua(let s): return s.requiresPermission || s == .moa
        case .airway: return false
        }
    }
}

// MARK: - Instrument strip

/// GPS instruments under the map: GS, altitude, track, vertical speed, next waypoint, distance, ETE.
struct InstrumentStrip: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var location: LocationManager
    @ObservedObject private var monitor = FlightMonitor.shared
    @Binding var showNearest: Bool

    var body: some View {
        VStack(spacing: SpacingToken.space1) {
            ForEach(monitor.alerts, id: \.self) { alert in
                Label(alert, systemImage: "exclamationmark.triangle.fill")
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(.white)
                    .padding(.horizontal, SpacingToken.space3)
                    .padding(.vertical, SpacingToken.space1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(ColorToken.danger, in: RoundedRectangle(cornerRadius: 8))
            }
            HStack(spacing: 0) {
                cell("GS", String(format: "%.0f", location.speed), "kt")
                cell("ALT", String(format: "%.0f", location.altitude * 3.28084), "ft")
                cell("TRK", location.course >= 0 ? String(format: "%03.0f°", location.course) : "---", "V")
                cell("VS", String(format: "%+.0f", (location.verticalSpeed / 10).rounded() * 10), "fpm")
                if let next = nextWaypoint, let here = location.location {
                    let nm = next.distanceNM(to: here)
                    cell(next.id, String(format: "%.0f", nm), "NM")
                    cell("ETE", ete(nm), "")
                }
                Button { showNearest = true } label: {
                    VStack(spacing: 0) {
                        Image(systemName: "airplane.arrival").font(.system(size: 16, weight: .semibold))
                        Text("Nearest").font(TypographyToken.labelXSmall)
                    }
                    .foregroundStyle(ColorToken.danger)
                    .frame(maxWidth: .infinity)
                }
            }
            .padding(.vertical, SpacingToken.space2)
            .background(FF.bar.opacity(0.95), in: RoundedRectangle(cornerRadius: 10))
        }
    }

    private var nextWaypoint: Airport? {
        model.waypoints.indices.contains(monitor.activeIndex) ? model.waypoints[monitor.activeIndex] : nil
    }

    private func ete(_ nm: Double) -> String {
        guard location.speed > 20 else { return "--" }
        let m = Int((nm / location.speed * 60).rounded())
        return m >= 60 ? "\(m / 60)h\(String(format: "%02d", m % 60))" : "\(m)m"
    }

    private func cell(_ title: String, _ value: String, _ unit: String) -> some View {
        VStack(spacing: 0) {
            Text(title).font(TypographyToken.labelXSmall).foregroundStyle(.white.opacity(0.6)).lineLimit(1)
            Text(value).font(TypographyToken.monoMedium).foregroundStyle(.white).lineLimit(1).minimumScaleFactor(0.6)
            Text(unit).font(TypographyToken.labelXSmall).foregroundStyle(.white.opacity(0.5))
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Nearest (emergency)

/// Closest airports with bearing and distance; one tap sets a Direct To.
struct NearestSheet: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var location: LocationManager
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            let here = location.location ?? model.userLocation ?? AppModel.homeCoordinate
            List(store.nearest(to: here, limit: 15, matching: ["large_airport", "medium_airport", "small_airport"])) { a in
                Button {
                    model.directTo(a)
                    dismiss()
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text(a.id).font(TypographyToken.monoMedium)
                            Text(a.name).font(TypographyToken.bodySmall).foregroundStyle(ColorToken.textSecondary).lineLimit(1)
                        }
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(String(format: "%.1f NM", a.distanceNM(to: here))).font(TypographyToken.monoMedium)
                            Text(String(format: "%03d°V", Haversine.trueCourse(here, a.coordinate)))
                                .font(TypographyToken.monoXSmall).foregroundStyle(ColorToken.textTertiary)
                        }
                    }
                }
            }
            .navigationTitle("Nearest — Direct To")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { Button("Fermer") { dismiss() } } }
        }
    }
}
