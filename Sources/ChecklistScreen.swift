import SwiftUI

struct ChecklistScreen: View {
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.checklists) { list in
                    Section {
                        ForEach(list.items) { item in
                            ChecklistItemRow(
                                item: item,
                                list: list,
                                onToggle: { model.toggle(item, in: list) }
                            )
                        }
                    } header: {
                        ChecklistHeaderView(list: list, onReset: { model.reset(list) })
                    }
                }
            }
            .navigationTitle("Checklists")
        }
    }
}

struct ChecklistHeaderView: View {
    let list: Checklist
    let onReset: () -> Void

    private var doneCount: Int {
        list.items.filter(\.done).count
    }
    private var totalCount: Int {
        list.items.count
    }
    private var isComplete: Bool {
        doneCount == totalCount
    }

    var body: some View {
        HStack {
            Text(list.name)
                .font(.headline)
                .foregroundStyle(Theme.textPrimary)
            Text("\(doneCount)/\(totalCount)")
                .font(.subheadline.monospacedDigit().weight(.medium))
                .foregroundStyle(isComplete ? Theme.green : Theme.textSecondary)
            Spacer()
            Button("Réinitialiser", action: onReset)
                .font(.caption)
                .foregroundStyle(Theme.accent)
        }
    }
}

struct ChecklistItemRow: View {
    let item: ChecklistItem
    let list: Checklist
    let onToggle: () -> Void

    var body: some View {
        Button(action: onToggle) {
            HStack(spacing: Theme.spacingM) {
                Image(systemName: item.done ? "checkmark.circle.fill" : "circle")
                    .font(.title2)
                    .foregroundStyle(item.done ? Theme.green : Theme.textTertiary)
                    .animation(.snappy(duration: 0.2), value: item.done)

                Text(item.text)
                    .font(.subheadline)
                    .foregroundStyle(item.done ? Theme.textTertiary : Theme.textPrimary)
                    .strikethrough(item.done, color: Theme.textTertiary)
                    .animation(.snappy(duration: 0.2), value: item.done)

                Spacer()
            }
            .contentShape(Rectangle())
            .padding(.vertical, Theme.spacingXS)
        }
        .buttonStyle(.plain)
    }
}