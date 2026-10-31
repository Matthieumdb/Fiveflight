import SwiftUI

struct LogbookScreen: View {
    @EnvironmentObject private var model: AppModel

    private static let df: DateFormatter = {
        let f = DateFormatter(); f.dateFormat = "d MMM yyyy, HH:mm"; f.locale = .init(identifier: "fr_FR")
        return f
    }()

    var body: some View {
        NavigationStack {
            Group {
                if model.logbook.isEmpty {
                    ContentUnavailableView("Carnet vide",
                        systemImage: "book",
                        description: Text("Trace une route puis touche « Carnet » pour enregistrer le vol."))
                } else {
                    List {
                        Section("Totaux") {
                            let totalNM = model.logbook.reduce(0) { $0 + $1.nm }
                            let totalMin = model.logbook.reduce(0) { $0 + $1.eteMinutes }
                            LabeledContent("Vols", value: "\(model.logbook.count)")
                            LabeledContent("Distance", value: "\(totalNM) NM")
                            LabeledContent("Temps", value: "\(totalMin / 60)h\(String(format: "%02d", totalMin % 60))")
                        }
                        Section("Vols") {
                        ForEach(model.logbook) { e in
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("\(e.from) → \(e.to)").font(.headline.monospaced())
                                    Text(Self.df.string(from: e.date))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                VStack(alignment: .trailing, spacing: 2) {
                                    Text("\(e.nm) NM").font(.subheadline.monospacedDigit())
                                    Text("\(e.eteMinutes / 60)h\(String(format: "%02d", e.eteMinutes % 60))")
                                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete(perform: model.deleteLog)
                        }
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
        var csv = "date,from,to,nm,minutes\n"
        for e in model.logbook.reversed() {
            csv += "\(iso.string(from: e.date)),\(e.from),\(e.to),\(e.nm),\(e.eteMinutes)\n"
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("carnet-fiveflight.csv")
        do { try csv.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }
}
