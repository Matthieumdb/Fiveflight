import SwiftUI

struct NotamScreen: View {
    @EnvironmentObject private var store: AirportStore
    @EnvironmentObject private var model: AppModel
    @State private var notams: [String: [Notam]] = [:]
    @State private var loading = false

    var body: some View {
        NavigationStack {
            Group {
                if notams.isEmpty && !loading {
                    ContentUnavailableView("Aucun NOTAM",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Ajoute des waypoints au plan de vol pour voir les NOTAMs."))
                } else {
                    List {
                        ForEach(waypoints) { apt in
                            Section(apt.id) {
                                if let n = notams[apt.id], !n.isEmpty {
                                    ForEach(n.filter(\.isActive)) { notam in
                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(notam.text).font(.caption).foregroundStyle(.primary)
                                            if let s = notam.start {
                                                Text("Depuis: \(s.formatted(date: .abbreviated, time: .shortened))")
                                                    .font(.caption2).foregroundStyle(.secondary)
                                            }
                                        }
                                        .padding(.vertical, 2)
                                    }
                                } else if notams[apt.id] != nil {
                                    Text("Aucun NOTAM actif").font(.caption).foregroundStyle(.secondary)
                                } else {
                                    ProgressView().frame(maxWidth: .infinity, alignment: .center)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("NOTAMs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { load() } label: { Image(systemName: "arrow.clockwise") }.disabled(loading)
                }
            }
            .task { load() }
            .onChange(of: model.directTo) { _ in load() }
        }
    }

    private var waypoints: [Airport] {
        var result: [Airport] = []
        if let d = model.directTo, let a = store.airport(d) { result.append(a) }
        return result
    }

    private func load() {
        let wps = waypoints
        guard !wps.isEmpty else { return }
        loading = true
        Task {
            let n = await NotamService.fetch(for: wps.map(\.id))
            notams = n
            loading = false
        }
    }
}