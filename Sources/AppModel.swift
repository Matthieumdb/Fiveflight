import Foundation

struct LogEntry: Codable, Identifiable {
    var id = UUID()
    var date: Date
    var from: String
    var to: String
    var nm: Int
    var eteMinutes: Int
}

struct ChecklistItem: Codable, Identifiable {
    var id = UUID()
    var text: String
    var done = false
}

struct Checklist: Codable, Identifiable {
    var id = UUID()
    var name: String
    var items: [ChecklistItem]
}

/// App-wide persisted state: favourites, logbook, checklists. Saved to UserDefaults.
@MainActor
final class AppModel: ObservableObject {
    @Published var favorites: Set<String> = []
    @Published var logbook: [LogEntry] = []
    @Published var checklists: [Checklist] = []

    private let defaults = UserDefaults.standard

    init() { load() }

    // Favorites
    func isFavorite(_ id: String) -> Bool { favorites.contains(id) }
    func toggleFavorite(_ id: String) {
        if favorites.contains(id) { favorites.remove(id) } else { favorites.insert(id) }
        save()
    }

    // Logbook
    func logFlight(from: String, to: String, nm: Int, eteMinutes: Int) {
        logbook.insert(LogEntry(date: .now, from: from, to: to, nm: nm, eteMinutes: eteMinutes), at: 0)
        save()
    }
    func deleteLog(_ offsets: IndexSet) { logbook.remove(atOffsets: offsets); save() }

    // Checklists
    func toggle(_ item: ChecklistItem, in list: Checklist) {
        guard let li = checklists.firstIndex(where: { $0.id == list.id }),
              let ii = checklists[li].items.firstIndex(where: { $0.id == item.id }) else { return }
        checklists[li].items[ii].done.toggle()
        save()
    }
    func reset(_ list: Checklist) {
        guard let li = checklists.firstIndex(where: { $0.id == list.id }) else { return }
        for i in checklists[li].items.indices { checklists[li].items[i].done = false }
        save()
    }

    // Persistence
    private func load() {
        if let d = defaults.data(forKey: "favorites"),
           let v = try? JSONDecoder().decode(Set<String>.self, from: d) { favorites = v }
        if let d = defaults.data(forKey: "logbook"),
           let v = try? JSONDecoder().decode([LogEntry].self, from: d) { logbook = v }
        if let d = defaults.data(forKey: "checklists"),
           let v = try? JSONDecoder().decode([Checklist].self, from: d) { checklists = v }
        if checklists.isEmpty { checklists = Self.defaultChecklists }
    }
    private func save() {
        let e = JSONEncoder()
        defaults.set(try? e.encode(favorites), forKey: "favorites")
        defaults.set(try? e.encode(logbook), forKey: "logbook")
        defaults.set(try? e.encode(checklists), forKey: "checklists")
    }

    static let defaultChecklists: [Checklist] = [
        Checklist(name: "Prévol", items: [
            "Documents à bord", "Essence & huile vérifiées", "Surfaces & gouvernes",
            "Pneus & freins", "Pitot / prises statiques", "Feux & gyrophare"
        ].map { ChecklistItem(text: $0) }),
        Checklist(name: "Avant décollage", items: [
            "Harnais & portes", "Volets réglés", "Trim décollage",
            "Instruments moteur dans le vert", "Magnétos testées", "Transpondeur ALT"
        ].map { ChecklistItem(text: $0) }),
        Checklist(name: "Après atterrissage", items: [
            "Volets rentrés", "Transpondeur STBY", "Feux inutiles éteints", "Réchauffage carbu froid"
        ].map { ChecklistItem(text: $0) })
    ]
}
