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
            .navigationTitle("Carnet de vol")
            .toolbar { if !model.logbook.isEmpty { EditButton() } }
        }
    }
}
