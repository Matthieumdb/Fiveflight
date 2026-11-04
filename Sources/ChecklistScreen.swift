import SwiftUI

/// Checklists of the current aircraft (and the shared ones): tick items, edit, add or delete lists.
struct ChecklistScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var editing: Checklist?

    private var lists: [Checklist] {
        model.checklists.filter { $0.aircraftID == nil || $0.aircraftID == model.selectedAircraft?.id }
    }

    var body: some View {
        Group { // pushed inside MoreScreen's NavigationStack
            List {
                if let ac = model.selectedAircraft {
                    Section {
                        Text("Avion : \(ac.name). Les listes propres à un autre avion sont masquées.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                ForEach(lists) { list in
                    Section {
                        ForEach(list.items) { item in
                            Button { model.toggle(item, in: list) } label: {
                                HStack {
                                    Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                                        .foregroundStyle(item.done ? .green : .secondary)
                                    Text(item.text)
                                        .strikethrough(item.done)
                                        .foregroundStyle(item.done ? .secondary : .primary)
                                }
                            }
                            .tint(.primary)
                        }
                    } header: {
                        let done = list.items.filter(\.done).count
                        HStack {
                            Text(list.name)
                            Text("\(done)/\(list.items.count)")
                                .monospacedDigit()
                                .foregroundStyle(done == list.items.count ? .green : .secondary)
                            Spacer()
                            Button("Modifier") { editing = list }
                                .font(.caption).textCase(nil)
                            Button("Réinitialiser") { model.reset(list) }
                                .font(.caption).textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Checklists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        editing = Checklist(name: "Nouvelle checklist", items: [], aircraftID: model.selectedAircraft?.id)
                    } label: { Image(systemName: "plus") }
                }
            }
            .sheet(item: $editing) { list in
                ChecklistEditor(list: list)
            }
        }
    }
}

/// Edit one checklist: name, aircraft, items (add, rename, reorder, delete).
private struct ChecklistEditor: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State var list: Checklist
    @State private var newItem = ""

    var body: some View {
        NavigationStack {
            List {
                Section("Nom") {
                    TextField("Nom", text: $list.name)
                }
                Section("Avion") {
                    Picker("Pour", selection: $list.aircraftID) {
                        Text("Tous les avions").tag(UUID?.none)
                        ForEach(model.aircraftProfiles) { Text($0.name).tag(UUID?.some($0.id)) }
                    }
                }
                Section("Éléments") {
                    ForEach($list.items) { $item in
                        TextField("Élément", text: $item.text)
                    }
                    .onDelete { list.items.remove(atOffsets: $0) }
                    .onMove { list.items.move(fromOffsets: $0, toOffset: $1) }
                    HStack {
                        TextField("Nouvel élément", text: $newItem)
                            .onSubmit(add)
                        Button("Ajouter", action: add).disabled(newItem.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                }
                if model.checklists.contains(where: { $0.id == list.id }) {
                    Section {
                        Button("Supprimer la checklist", role: .destructive) {
                            model.deleteChecklist(list.id)
                            dismiss()
                        }
                    }
                }
            }
            .environment(\.editMode, .constant(.active))
            .navigationTitle(list.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("OK") {
                        add()
                        model.updateChecklist(list)
                        dismiss()
                    }
                }
            }
        }
    }

    private func add() {
        let text = newItem.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty else { return }
        list.items.append(ChecklistItem(text: text))
        newItem = ""
    }
}
