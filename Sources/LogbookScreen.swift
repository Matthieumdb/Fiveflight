import SwiftUI

struct LogbookScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            Group {
                if model.logbook.isEmpty {
                    ContentUnavailableView(
                        "Carnet vide",
                        systemImage: "book",
                        description: Text("Trace une route puis touche « Carnet » pour enregistrer le vol.")
                    )
                } else {
                    List {
                        Section("Totaux") {
                            TotalsRow(
                                flights: model.logbook.count,
                                totalNM: model.logbook.reduce(0) { $0 + $1.nm },
                                totalMin: model.logbook.reduce(0) { $0 + $1.eteMinutes }
                            )
                        }

                        Section("Vols") {
                            ForEach(model.logbook) { entry in
                                LogEntryRow(entry: entry)
                            }
                            .onDelete(perform: model.deleteLog)
                        }
                    }
                }
            }
            .navigationTitle("Carnet de vol")
            .toolbar {
                if !model.logbook.isEmpty {
                    ToolbarItem(placement: .topBarLeading) {
                        EditButton()
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if let url = csvURL() {
                            ShareLink(item: url) {
                                Image(systemName: "square.and.arrow.up")
                            }
                        }
                    }
                }
            }
        }
    }

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

struct TotalsRow: View {
    let flights: Int
    let totalNM: Int
    let totalMin: Int

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Label("\(flights) vols", systemImage: "airplane")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Label("\(totalNM) NM", systemImage: "point.topleft.down.curvedto.point.bottomright.forward")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
                Label("\(totalMin / 60)h\(String(format: "%02d", totalMin % 60))", systemImage: "clock")
                    .font(.subheadline)
                    .foregroundStyle(Theme.textSecondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Image(systemName: "chart.bar.fill")
                    .font(.title)
                    .foregroundStyle(Theme.accent)
            }
        }
        .padding(.vertical, Theme.spacingXS)
    }
}

struct LogEntryRow: View {
    let entry: LogEntry

    private static let df: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "d MMM yyyy, HH:mm"
        f.locale = .init(identifier: "fr_FR")
        return f
    }()

    var body: some View {
        HStack(spacing: Theme.spacingM) {
            VStack(alignment: .leading, spacing: Theme.spacingXS) {
                Text("\(entry.from) → \(entry.to)")
                    .font(.headline.monospaced())
                    .foregroundStyle(Theme.textPrimary)
                Text(Self.df.string(from: entry.date))
                    .font(.caption)
                    .foregroundStyle(Theme.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: Theme.spacingXS) {
                Text("\(entry.nm) NM")
                    .font(.subheadline.monospacedDigit().weight(.medium))
                    .foregroundStyle(Theme.textPrimary)
                Text("\(entry.eteMinutes / 60)h\(String(format: "%02d", entry.eteMinutes % 60))")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(Theme.textSecondary)
            }
        }
        .padding(.vertical, Theme.spacingXS)
    }
}