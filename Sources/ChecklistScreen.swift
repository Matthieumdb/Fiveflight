import SwiftUI

struct ChecklistScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.checklists) { list in
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
                        HStack {
                            Text(list.name)
                            Spacer()
                            Button("Réinitialiser") { model.reset(list) }
                                .font(.caption).textCase(nil)
                        }
                    }
                }
            }
            .navigationTitle("Checklists")
        }
    }
}
