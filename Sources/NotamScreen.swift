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
                    ContentUnavailableView(
                        "Aucun NOTAM",
                        systemImage: "exclamationmark.triangle",
                        description: Text("Ajoute des waypoints au plan de vol pour voir les NOTAMs.")
                    )
                } else {
                    List {
                        ForEach(waypoints) { airport in
                            Section(airport.id) {
                                if let n = notams[airport.id], !n.isEmpty {
                                    ForEach(n.filter(\.isActive)) { notam in
                                        NotamRowView(notam: notam)
                                    }
                                } else if notams[airport.id] != nil {
                                    Text("Aucun NOTAM actif")
                                        .font(.caption)
                                        .foregroundStyle(Theme.textTertiary)
                                        .padding(.vertical, Theme.spacingXS)
                                } else {
                                    ProgressView()
                                        .frame(maxWidth: .infinity, alignment: .center)
                                        .padding(.vertical, Theme.spacingM)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("NOTAMs")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { load() } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                    .disabled(loading)
                }
            }
            .task { load() }
            .onChange(of: model.directTo) { _, _ in load() }
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

struct NotamRowView: View {
    let notam: Notam

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.spacingXS) {
            Text(notam.text)
                .font(.caption)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            if let start = notam.start {
                Text("Depuis: \(start.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(.vertical, Theme.spacingXS)
    }
}