import SwiftUI
import MapKit

struct LogbookScreen: View {
    @EnvironmentObject private var model: AppModel

    static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy, HH:mm"; f.locale = .init(identifier: "fr_FR")
        return f
    }()

    var body: some View {
        Group { // pushed inside MoreScreen's NavigationStack
            List {
                CurrencySection()
                if model.logbook.isEmpty {
                    Section {
                        Text("Trace une route puis touche « Log Flight » pour enregistrer le vol.")
                            .foregroundStyle(ColorToken.textTertiary)
                    }
                } else {
                    Section("Totaux") {
                        let totalNM = model.logbook.reduce(0) { $0 + $1.nm }
                        let totalMin = model.logbook.reduce(0) { $0 + $1.eteMinutes }
                        let landings = model.logbook.reduce(0) { $0 + ($1.landingsDay ?? 0) + ($1.landingsNight ?? 0) }
                        LabeledContent("Vols", value: "\(model.logbook.count)")
                        LabeledContent("Distance", value: "\(totalNM) NM")
                        LabeledContent("Temps", value: "\(totalMin / 60)h\(String(format: "%02d", totalMin % 60))")
                        LabeledContent("Atterrissages", value: "\(landings)")
                    }
                    Section("Vols") {
                        ForEach(model.logbook) { e in
                            NavigationLink { LogEntryScreen(entry: e) } label: { LogRow(entry: e) }
                        }
                        .onDelete(perform: model.deleteLog)
                    }
                }
            }
            .navigationTitle("Carnet de vol")
            .toolbar {
                if !model.logbook.isEmpty {
                    ToolbarItem(placement: .topBarLeading) { EditButton() }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let url = csvURL() {
                            ShareLink(item: url) { Image(systemName: "square.and.arrow.up") }
                        }
                    }
                }
            }
        }
    }

    /// Write the logbook to a CSV in the temp dir for sharing.
    private func csvURL() -> URL? {
        let iso = ISO8601DateFormatter()
        var csv = "date,from,to,nm,minutes,aircraft,landings_day,landings_night,remarks\n"
        for e in model.logbook.reversed() {
            let remarks = (e.remarks ?? "").replacingOccurrences(of: "\"", with: "\"\"")
            csv += "\(iso.string(from: e.date)),\(e.from),\(e.to),\(e.nm),\(e.eteMinutes),\(e.aircraft ?? ""),"
                + "\(e.landingsDay ?? 0),\(e.landingsNight ?? 0),\"\(remarks)\"\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("carnet-fiveflight.csv")
        do { try csv.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}

private struct LogRow: View {
    let entry: LogEntry
    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(entry.from) → \(entry.to)").font(.headline.monospaced())
                Text(LogbookScreen.df.string(from: entry.date) + (entry.aircraft.map { " · \($0)" } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(entry.nm) NM").font(.subheadline.monospacedDigit())
                Text("\(entry.eteMinutes / 60)h\(String(format: "%02d", entry.eteMinutes % 60))")
                    .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - Currency

/// Passenger currency (3 landings in 90 days, 14 CFR 61.57), medical and flight review (24 months).
private struct CurrencySection: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        let since = Date.now.addingTimeInterval(-90 * 86400)
        let recent = model.logbook.filter { $0.date >= since }
        let day = recent.reduce(0) { $0 + ($1.landingsDay ?? 0) + ($1.landingsNight ?? 0) }
        let night = recent.reduce(0) { $0 + ($1.landingsNight ?? 0) }
        Section("Qualifications") {
            status("Passagers de jour", ok: day >= 3, detail: "\(day)/3 atterrissages en 90 j")
            status("Passagers de nuit", ok: night >= 3, detail: "\(night)/3 atterrissages de nuit en 90 j")
            dateRow("Visite médicale valide jusqu'au", $model.medicalExpiry, ok: { $0 > Date.now })
            dateRow("Dernier flight review", $model.flightReviewDate,
                    ok: { Calendar.current.date(byAdding: .month, value: 24, to: $0)! > Date.now })
        }
    }

    private func status(_ title: String, ok: Bool, detail: String) -> some View {
        HStack {
            Image(systemName: ok ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(ok ? ColorToken.success : ColorToken.warning)
            VStack(alignment: .leading) {
                Text(title)
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private func dateRow(_ title: String, _ seconds: Binding<Double>, ok: (Date) -> Bool) -> some View {
        let date = Binding<Date>(get: { seconds.wrappedValue > 0 ? Date(timeIntervalSince1970: seconds.wrappedValue) : .now },
                                 set: { seconds.wrappedValue = $0.timeIntervalSince1970 })
        let entered = seconds.wrappedValue > 0
        return HStack {
            Image(systemName: !entered ? "questionmark.circle" : ok(date.wrappedValue) ? "checkmark.seal.fill" : "xmark.octagon.fill")
                .foregroundStyle(!entered ? ColorToken.textTertiary : ok(date.wrappedValue) ? ColorToken.success : ColorToken.danger)
            DatePicker(title, selection: date, displayedComponents: .date)
        }
    }
}

// MARK: - Entry detail: edit, replay, export

struct LogEntryScreen: View {
    @EnvironmentObject private var model: AppModel
    @State var entry: LogEntry
    @State private var progress = 1.0
    @State private var playing = false

    private var track: [CLLocationCoordinate2D] { (entry.track ?? []).map(\.clCoordinate) }

    var body: some View {
        Form {
            if track.count >= 2 {
                Section("Rejouer la trace") {
                    let shown = Array(track.prefix(max(2, Int(Double(track.count) * progress))))
                    Map {
                        MapPolyline(coordinates: track).stroke(.gray.opacity(0.4), lineWidth: 3)
                        MapPolyline(coordinates: shown).stroke(.pink, lineWidth: 3)
                        if let last = shown.last {
                            Annotation("", coordinate: last) { Image(systemName: "airplane.circle.fill").foregroundStyle(.pink) }
                        }
                    }
                    .frame(height: 260)
                    .listRowInsets(EdgeInsets())
                    HStack {
                        Button { playing.toggle(); if playing && progress >= 1 { progress = 0 } } label: {
                            Image(systemName: playing ? "pause.fill" : "play.fill")
                        }
                        .buttonStyle(.borderless)
                        Slider(value: $progress, in: 0...1)
                    }
                }
            }
            Section("Vol") {
                LabeledContent("Trajet", value: "\(entry.from) → \(entry.to)")
                LabeledContent("Date", value: LogbookScreen.df.string(from: entry.date))
                TextField("Avion", text: Binding(get: { entry.aircraft ?? "" }, set: { entry.aircraft = $0 }))
                Stepper("Temps de vol : \(entry.eteMinutes / 60)h\(String(format: "%02d", entry.eteMinutes % 60))",
                        value: $entry.eteMinutes, in: 0...1440, step: 5)
                Stepper("Atterrissages de jour : \(entry.landingsDay ?? 0)",
                        value: Binding(get: { entry.landingsDay ?? 0 }, set: { entry.landingsDay = $0 }), in: 0...50)
                Stepper("Atterrissages de nuit : \(entry.landingsNight ?? 0)",
                        value: Binding(get: { entry.landingsNight ?? 0 }, set: { entry.landingsNight = $0 }), in: 0...50)
                TextField("Remarques", text: Binding(get: { entry.remarks ?? "" }, set: { entry.remarks = $0 }), axis: .vertical)
            }
            if !track.isEmpty {
                Section("Exporter la trace") {
                    let name = "\(entry.from)-\(entry.to)"
                    if let gpx = FlightExport.gpx(name: name, route: [], track: track) { ShareLink("GPX", item: gpx) }
                    if let kml = FlightExport.kml(name: name, route: [], track: track) { ShareLink("KML (Google Earth)", item: kml) }
                }
            }
        }
        .navigationTitle("\(entry.from) → \(entry.to)")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: entry) { _, new in model.updateLog(new) }
        .task(id: playing) {
            while playing, progress < 1, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 50_000_000)
                progress = min(1, progress + 0.005)
            }
            playing = false
        }
    }
}
