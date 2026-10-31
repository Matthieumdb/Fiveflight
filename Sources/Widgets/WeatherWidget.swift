import WidgetKit
import SwiftUI

/// Shared entry for all Fiveflight widgets.
struct FiveflightEntry: TimelineEntry {
    let date: Date
    let nearest: [AirportSummary]
    let activeRoute: RouteSummary?
    let weather: WeatherSummary?
}

struct AirportSummary: Codable, Identifiable {
    let id: String
    let name: String
    let nm: Int
    let category: String?
}

struct RouteSummary: Codable {
    let from: String
    let to: String
    let totalNM: Int
    let ete: String
    let fuel: Double
}

struct WeatherSummary: Codable {
    let station: String
    let category: String
    let wind: String
    let visib: String
}

/// Provider that reads cached data from App Group shared defaults.
struct FiveflightProvider: TimelineProvider {
    let sharedDefaults = UserDefaults(suiteName: "group.com.example.efb.fiveflight")!

    func placeholder(in context: Context) -> FiveflightEntry {
        FiveflightEntry(date: Date(), nearest: [], activeRoute: nil, weather: nil)
    }

    func getSnapshot(in context: Context, completion: @escaping (FiveflightEntry) -> Void) {
        completion(entry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<FiveflightEntry>) -> Void) {
        let e = entry()
        // Refresh every 15 minutes; timeline with a single entry is fine.
        let next = Calendar.current.date(byAdding: .minute, value: 15, to: Date())!
        completion(Timeline(entries: [e], policy: .after(next)))
    }

    private func entry() -> FiveflightEntry {
        let nearestData = sharedDefaults.data(forKey: "widget.nearest") ?? Data()
        let routeData = sharedDefaults.data(forKey: "widget.route") ?? Data()
        let weatherData = sharedDefaults.data(forKey: "widget.weather") ?? Data()

        let decoder = JSONDecoder()
        let nearest = (try? decoder.decode([AirportSummary].self, from: nearestData)) ?? []
        let route = try? decoder.decode(RouteSummary.self, from: routeData)
        let weather = try? decoder.decode(WeatherSummary.self, from: weatherData)

        return FiveflightEntry(date: Date(), nearest: nearest, activeRoute: route, weather: weather)
    }
}

// MARK: - Small widget: nearest airport + quick status
struct FiveflightSmallWidget: Widget {
    let kind = "FiveflightSmallWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FiveflightProvider()) { entry in
            SmallWidgetView(entry: entry)
        }
        .configurationDisplayName("Carte VFR")
        .description("Aéroport le plus proche et météo")
        .supportedFamilies([.systemSmall])
    }
}

struct SmallWidgetView: View {
    var entry: FiveflightEntry

    var body: some View {
        ZStack {
            WidgetTheme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Image(systemName: "airplane.circle.fill")
                        .foregroundStyle(WidgetTheme.accent)
                    Text("FIVEFLIGHT").font(.caption2.weight(.heavy)).tracking(1)
                    Spacer()
                }
                if let first = entry.nearest.first {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(first.id).font(.title3.weight(.bold)).monospaced()
                        Text(first.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text("\(first.nm) NM").font(.caption.monospacedDigit())
                        if let cat = first.category {
                            Text(cat).font(.caption2.bold()).foregroundStyle(.white)
                                .padding(.horizontal, 6).padding(.vertical, 1)
                                .background(fltColor(cat), in: Capsule())
                        }
                    }
                } else {
                    Text("Aucune donnée").font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if let wx = entry.weather {
                    HStack(spacing: 4) {
                        Image(systemName: "wind").font(.caption)
                        Text(wx.wind).font(.caption.monospaced())
                        Spacer()
                        Image(systemName: "eye").font(.caption)
                        Text(wx.visib).font(.caption.monospaced())
                    }
                    .foregroundStyle(.secondary)
                }
            }
            .padding(12)
        }
    }

    private func fltColor(_ cat: String) -> Color {
        switch cat {
        case "VFR": return .green
        case "MVFR": return .blue
        case "IFR": return .red
        case "LIFR": return .purple
        default: return .gray
        }
    }
}

// MARK: - Medium widget: route + 3 nearest
struct FiveflightMediumWidget: Widget {
    let kind = "FiveflightMediumWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FiveflightProvider()) { entry in
            MediumWidgetView(entry: entry)
        }
        .configurationDisplayName("Plan de vol")
        .description("Route active et 3 aéroports proches")
        .supportedFamilies([.systemMedium])
    }
}

struct MediumWidgetView: View {
    var entry: FiveflightEntry

    var body: some View {
        ZStack {
            WidgetTheme.bg.ignoresSafeArea()
            HStack(spacing: 16) {
                // Left: active route
                VStack(alignment: .leading, spacing: 8) {
                    Label("Route", systemImage: "arrow.triangle.swap")
                        .font(.caption.weight(.semibold)).foregroundStyle(WidgetTheme.accent)
                    if let r = entry.activeRoute {
                        VStack(alignment: .leading, spacing: 3) {
                            Text("\(r.from) → \(r.to)").font(.headline.monospaced())
                            Text("\(r.totalNM) NM  ·  \(r.ete)  ·  \(String(format: "%.1f", r.fuel)) gal")
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    } else {
                        Text("Aucune route").font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Divider().frame(height: 60)

                // Right: nearest airports
                VStack(alignment: .leading, spacing: 6) {
                    Label("Proches", systemImage: "location.fill")
                        .font(.caption.weight(.semibold)).foregroundStyle(WidgetTheme.accent)
                    ForEach(entry.nearest.prefix(3)) { a in
                        HStack {
                            Circle().fill(dotColor(a.category)).frame(width: 6, height: 6)
                            Text(a.id).font(.subheadline.monospaced()).lineLimit(1)
                            Spacer()
                            Text("\(a.nm) NM").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
        }
    }

    private func dotColor(_ cat: String?) -> Color {
        switch cat {
        case "VFR": return .green
        case "MVFR": return .blue
        case "IFR": return .red
        case "LIFR": return .purple
        default: return .gray
        }
    }
}

// MARK: - Large widget: full dashboard
struct FiveflightLargeWidget: Widget {
    let kind = "FiveflightLargeWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FiveflightProvider()) { entry in
            LargeWidgetView(entry: entry)
        }
        .configurationDisplayName("Tableau de bord")
        .description("Route, 5 aéroports, météo détaillée")
        .supportedFamilies([.systemLarge])
    }
}

struct LargeWidgetView: View {
    var entry: FiveflightEntry

    var body: some View {
        ZStack {
            WidgetTheme.bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Image(systemName: "airplane.departure").foregroundStyle(WidgetTheme.accent)
                    Text("FIVEFLIGHT").font(.title3.weight(.heavy)).tracking(2)
                    Spacer()
                    Text(entry.date, style: .time).font(.caption.monospaced()).foregroundStyle(.secondary)
                }

                // Route card
                if let r = entry.activeRoute {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Route active").font(.caption.weight(.semibold)).foregroundStyle(WidgetTheme.accent)
                        Text("\(r.from) → \(r.to)").font(.title2.weight(.bold)).monospaced()
                        Text("\(r.totalNM) NM  ·  \(r.ete)  ·  \(String(format: "%.1f", r.fuel)) gal (rés. incluse)")
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(WidgetTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                }

                // Nearest airports
                VStack(alignment: .leading, spacing: 4) {
                    Text("Aéroports proches").font(.caption.weight(.semibold)).foregroundStyle(WidgetTheme.accent)
                    ForEach(entry.nearest.prefix(5)) { a in
                        HStack {
                            Circle().fill(dotColor(a.category)).frame(width: 8, height: 8)
                            Text(a.id).font(.subheadline.monospaced())
                            Text(a.name).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                            Spacer()
                            Text("\(a.nm) NM").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            if let cat = a.category {
                                Text(cat).font(.caption2.bold()).foregroundStyle(.white)
                                    .padding(.horizontal, 5).padding(.vertical, 1)
                                    .background(fltColor(cat), in: Capsule())
                            }
                        }
                    }
                }

                // Weather
                if let wx = entry.weather {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("Météo \(wx.station)").font(.caption.weight(.semibold)).foregroundStyle(WidgetTheme.accent)
                        HStack(spacing: 12) {
                            Label(wx.category, systemImage: "cloud").font(.caption)
                            Label(wx.wind, systemImage: "wind").font(.caption)
                            Label(wx.visib, systemImage: "eye").font(.caption)
                        }
                        .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(WidgetTheme.surface, in: RoundedRectangle(cornerRadius: 10))
                }
            }
            .padding(16)
        }
    }

    private func dotColor(_ cat: String?) -> Color {
        switch cat {
        case "VFR": return .green
        case "MVFR": return .blue
        case "IFR": return .red
        case "LIFR": return .purple
        default: return .gray
        }
    }

    private func fltColor(_ cat: String) -> Color {
        switch cat {
        case "VFR": return .green
        case "MVFR": return .blue
        case "IFR": return .red
        case "LIFR": return .purple
        default: return .gray
        }
    }
}

// MARK: - Widget bundle
struct FiveflightWidgetBundle: WidgetBundle {
    var body: some Widget {
        FiveflightSmallWidget()
        FiveflightMediumWidget()
        FiveflightLargeWidget()
    }
}