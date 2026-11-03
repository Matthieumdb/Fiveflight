import SwiftUI
import CoreLocation

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

    /// Called on each GPS fix.
    func update(position: CLLocationCoordinate2D, groundSpeed: Double, course: Double, altitudeFt: Int,
                model: AppModel, airspaces: [Airspace]) {
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
            for a in airspaces where a.isActive && a.type.needsAlert
                && altitudeFt >= a.floor - 300 && altitudeFt <= a.ceiling {
                let inside = a.polygons.contains { Airspace.pointInPolygonStatic(position, polygon: $0.map(\.clCoordinate)) }
                if inside {
                    found.append("Dans \(a.name)")
                } else if a.polygons.contains(where: { Airspace.segmentIntersectsPolygon(position, ahead, polygon: $0) }) {
                    found.append("\(a.name) à moins de \(Int(Self.lookAhead)) NM devant")
                }
            }
        }
        if let left = fuelRemaining(model: model), model.fuelBurn > 0 {
            let reserve = model.reserveMin / 60 * model.fuelBurn
            let needed = remainingMinutes(position: position, groundSpeed: groundSpeed, model: model) / 60 * model.fuelBurn
            if left - needed < reserve {
                found.append(String(format: "Carburant : %.1f gal restants, réserve entamée à l'arrivée", left))
            }
        }
        if found != alerts {
            if found.count > alerts.count { Haptics.warning() }
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
            .background(.black.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
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
