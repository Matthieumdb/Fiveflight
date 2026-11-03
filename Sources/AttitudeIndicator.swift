import SwiftUI

/// Backup attitude indicator fed by the ADS-B receiver's AHRS (Stratux, Sentry…). For situational
/// awareness only, never a primary instrument.
struct AttitudeScreen: View {
    @EnvironmentObject private var model: AppModel
    @ObservedObject private var adsb = ADSBReceiver.shared

    private var fresh: AHRSAttitude? {
        guard let a = adsb.ahrs, Date.now.timeIntervalSince(a.updated) < 2 else { return nil }
        return a
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            VStack(spacing: 16) {
                if !model.adsbEnabled {
                    ContentUnavailableView("Récepteur ADS-B désactivé", systemImage: "gyroscope",
                                           description: Text("Activez le récepteur GDL 90 dans Réglages, puis connectez-vous à son Wi-Fi."))
                } else if let a = fresh {
                    AttitudeIndicator(roll: a.roll, pitch: a.pitch)
                        .frame(maxWidth: 360, maxHeight: 360)
                        .aspectRatio(1, contentMode: .fit)
                    HStack(spacing: 24) {
                        value("Roulis", String(format: "%.0f°", a.roll))
                        value("Tangage", String(format: "%.0f°", a.pitch))
                        value("Cap", a.heading.map { String(format: "%03.0f°", $0) } ?? "—")
                        value("G", a.gLoad.map { String(format: "%.1f", $0) } ?? "—")
                    }
                } else {
                    ContentUnavailableView("Pas d'AHRS", systemImage: "gyroscope",
                                           description: Text("Le récepteur ne transmet pas d'attitude (Stratux avec AHRS, Sentry, Stratus…)."))
                }
                Text("Secours uniquement : ne remplace pas les instruments de l'avion.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationTitle("Horizon artificiel")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func value(_ title: String, _ v: String) -> some View {
        VStack(spacing: 2) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            Text(v).font(TypographyToken.monoMedium)
        }
    }
}

/// Sky/ground ball with pitch ladder and roll pointer.
struct AttitudeIndicator: View {
    let roll: Double
    let pitch: Double

    var body: some View {
        GeometryReader { geo in
            let size = min(geo.size.width, geo.size.height)
            let pxPerDeg = size / 60
            ZStack {
                ZStack {
                    VStack(spacing: 0) {
                        Color(red: 0.25, green: 0.55, blue: 0.9)
                        Color(red: 0.55, green: 0.35, blue: 0.15)
                    }
                    .frame(width: size * 3, height: size * 3)
                    Rectangle().fill(.white).frame(width: size * 3, height: 2)
                    ForEach([-20, -10, 10, 20], id: \.self) { deg in
                        Rectangle().fill(.white)
                            .frame(width: abs(deg) == 10 ? size * 0.25 : size * 0.4, height: 1.5)
                            .offset(y: -CGFloat(deg) * pxPerDeg)
                    }
                }
                .offset(y: CGFloat(pitch) * pxPerDeg)
                .rotationEffect(.degrees(-roll))

                // Fixed aircraft symbol.
                HStack(spacing: size * 0.08) {
                    Rectangle().frame(width: size * 0.22, height: 4)
                    Circle().frame(width: 8, height: 8)
                    Rectangle().frame(width: size * 0.22, height: 4)
                }
                .foregroundStyle(.yellow)
                // Roll pointer.
                Image(systemName: "triangle.fill")
                    .foregroundStyle(.white)
                    .offset(y: -size * 0.42)
                    .rotationEffect(.degrees(-roll))
                Image(systemName: "arrowtriangle.down.fill")
                    .foregroundStyle(.yellow)
                    .offset(y: -size * 0.47)
            }
            .frame(width: size, height: size)
            .clipShape(Circle())
            .overlay(Circle().stroke(.gray, lineWidth: 3))
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
