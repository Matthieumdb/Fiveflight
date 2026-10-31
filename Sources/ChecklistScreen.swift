import SwiftUI

// MARK: - Checklist Screen

struct ChecklistScreen: View {
    @State private var selectedCategory: ChecklistCategory = .preflight
    @State private var checklists: [ChecklistCategory: [ChecklistItem]] = ChecklistCategory.defaultChecklists

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Category picker
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpacingToken.space2) {
                        ForEach(ChecklistCategory.allCases) { category in
                            CategoryPill(
                                title: category.rawValue,
                                icon: category.icon,
                                isSelected: selectedCategory == category,
                                color: category.color
                            ) {
                                withAnimation(AnimationToken.tabSwitch) { selectedCategory = category }
                            }
                        }
                    }
                    .padding(.horizontal, SpacingToken.insetMedium)
                }
                .padding(.vertical, SpacingToken.space3)

                // Checklist
                List {
                    Section {
                        ForEach(checklists[selectedCategory] ?? []) { item in
                            ChecklistItemRow(item: item)
                        }
                    }

                    Section {
                        Button {
                            addItem(to: selectedCategory)
                        } label: {
                            Label("Add Item", systemImage: "plus.circle.fill")
                                .font(TypographyToken.labelMedium)
                                .foregroundStyle(ColorToken.brandPrimary)
                        }
                    }
                }
                .listStyle(.insetGrouped)
                .scrollContentBackground(.hidden)
            }
            .background(ColorToken.surfaceBase)
            .navigationTitle("Checklists")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button("Reset All", role: .destructive) {
                            resetCategory(selectedCategory)
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
            }
        }
    }

    private func addItem(to category: ChecklistCategory) {
        let newItem = ChecklistItem(text: "New Item", isChecked: false)
        checklists[category, default: []].append(newItem)
    }

    private func resetCategory(_ category: ChecklistCategory) {
        checklists[category] = ChecklistCategory.defaultChecklists[category] ?? []
    }
}

enum ChecklistCategory: String, CaseIterable, Identifiable {
    case preflight = "Preflight"
    case beforeStart = "Before Start"
    case afterStart = "After Start"
    case taxi = "Taxi"
    case beforeTakeoff = "Before Takeoff"
    case afterTakeoff = "After Takeoff"
    case cruise = "Cruise"
    case descent = "Descent"
    case beforeLanding = "Before Landing"
    case afterLanding = "After Landing"
    case shutdown = "Shutdown"
    case emergency = "Emergency"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .preflight: return "airplane.circle"
        case .beforeStart: return "key.fill"
        case .afterStart: return "bolt.fill"
        case .taxi: return "arrow.triangle.turn.up.right.circle"
        case .beforeTakeoff: return "arrow.up.circle"
        case .afterTakeoff: return "arrow.up.right.circle"
        case .cruise: return "speedometer"
        case .descent: return "arrow.down.circle"
        case .beforeLanding: return "arrow.down.right.circle"
        case .afterLanding: return "arrow.down.left.circle"
        case .shutdown: return "stop.circle"
        case .emergency: return "exclamationmark.triangle"
        }
    }

    var color: Color {
        switch self {
        case .preflight, .beforeStart, .afterStart: return ColorToken.brandPrimary
        case .taxi, .beforeTakeoff, .afterTakeoff: return ColorToken.warning
        case .cruise, .descent: return ColorToken.info
        case .beforeLanding, .afterLanding, .shutdown: return ColorToken.success
        case .emergency: return ColorToken.danger
        }
    }

    static let defaultChecklists: [ChecklistCategory: [ChecklistItem]] = [
        .preflight: [
            ChecklistItem(text: "Documents (AROW)", isChecked: false),
            ChecklistItem(text: "Fuel quantity & quality", isChecked: false),
            ChecklistItem(text: "Oil level", isChecked: false),
            ChecklistItem(text: "Control surfaces free", isChecked: false),
            ChecklistItem(text: "Tires & brakes", isChecked: false),
            ChecklistItem(text: "Lights operational", isChecked: false),
            ChecklistItem(text: "Static ports clear", isChecked: false),
            ChecklistItem(text: "Pitot tube cover removed", isChecked: false),
        ],
        .beforeStart: [
            ChecklistItem(text: "Seat belts fastened", isChecked: false),
            ChecklistItem(text: "Doors/windows secured", isChecked: false),
            ChecklistItem(text: "Fuel selector ON", isChecked: false),
            ChecklistItem(text: "Mixture RICH", isChecked: false),
            ChecklistItem(text: "Carb heat COLD", isChecked: false),
            ChecklistItem(text: "Master switch ON", isChecked: false),
            ChecklistItem(text: "Beacon ON", isChecked: false),
        ],
        .afterStart: [
            ChecklistItem(text: "Oil pressure GREEN", isChecked: false),
            ChecklistItem(text: "Ammeter/charging", isChecked: false),
            ChecklistItem(text: "Vacuum in green", isChecked: false),
            ChecklistItem(text: "Avionics ON", isChecked: false),
            ChecklistItem(text: "ATIS/AWOS copied", isChecked: false),
            ChecklistItem(text: "Clearance obtained", isChecked: false),
        ],
        .taxi: [
            ChecklistItem(text: "Brakes tested", isChecked: false),
            ChecklistItem(text: "Instruments checked", isChecked: false),
            ChecklistItem(text: "Flight controls free", isChecked: false),
            ChecklistItem(text: "Runway assignment", isChecked: false),
        ],
        .beforeTakeoff: [
            ChecklistItem(text: "Flight controls FREE & CORRECT", isChecked: false),
            ChecklistItem(text: "Trim SET for takeoff", isChecked: false),
            ChecklistItem(text: "Flaps SET", isChecked: false),
            ChecklistItem(text: "Fuel pump ON", isChecked: false),
            ChecklistItem(text: "Mixture RICH", isChecked: false),
            ChecklistItem(text: "Carb heat COLD", isChecked: false),
            ChecklistItem(text: "Doors/windows LATCHED", isChecked: false),
            ChecklistItem(text: "Seat belts SECURED", isChecked: false),
            ChecklistItem(text: "Transponder ALT", isChecked: false),
            ChecklistItem(text: "Lights AS REQUIRED", isChecked: false),
            ChecklistItem(text: "Runway CLEAR", isChecked: false),
            ChecklistItem(text: "Line up & wait / Takeoff clearance", isChecked: false),
        ],
        .afterTakeoff: [
            ChecklistItem(text: "Gear UP (if retractable)", isChecked: false),
            ChecklistItem(text: "Flaps UP", isChecked: false),
            ChecklistItem(text: "Fuel pump OFF", isChecked: false),
            ChecklistItem(text: "Climb power SET", isChecked: false),
        ],
        .cruise: [
            ChecklistItem(text: "Power SET per POH", isChecked: false),
            ChecklistItem(text: "Mixture LEANED", isChecked: false),
            ChecklistItem(text: "Fuel quantity MONITORED", isChecked: false),
            ChecklistItem(text: "Engine instruments GREEN", isChecked: false),
            ChecklistItem(text: "Navigation CONFIRMED", isChecked: false),
            ChecklistItem(text: "Weather MONITORED", isChecked: false),
        ],
        .descent: [
            ChecklistItem(text: "ATIS/AWOS copied", isChecked: false),
            ChecklistItem(text: "Approach briefed", isChecked: false),
            ChecklistItem(text: "Mixture RICH", isChecked: false),
            ChecklistItem(text: "Carb heat AS REQUIRED", isChecked: false),
            ChecklistItem(text: "Fuel pump ON", isChecked: false),
            ChecklistItem(text: "Lights ON", isChecked: false),
        ],
        .beforeLanding: [
            ChecklistItem(text: "Seat belts FASTENED", isChecked: false),
            ChecklistItem(text: "Fuel selector FULLEST TANK", isChecked: false),
            ChecklistItem(text: "Mixture RICH", isChecked: false),
            ChecklistItem(text: "Carb heat HOT", isChecked: false),
            ChecklistItem(text: "Fuel pump ON", isChecked: false),
            ChecklistItem(text: "Gear DOWN (if retractable)", isChecked: false),
            ChecklistItem(text: "Flaps AS REQUIRED", isChecked: false),
            ChecklistItem(text: "Lights ON", isChecked: false),
            ChecklistItem(text: "Final approach FIXED", isChecked: false),
        ],
        .afterLanding: [
            ChecklistItem(text: "Flaps UP", isChecked: false),
            ChecklistItem(text: "Carb heat COLD", isChecked: false),
            ChecklistItem(text: "Fuel pump OFF", isChecked: false),
            ChecklistItem(text: "Transponder STBY", isChecked: false),
            ChecklistItem(text: "Lights AS REQUIRED", isChecked: false),
        ],
        .shutdown: [
            ChecklistItem(text: "Avionics OFF", isChecked: false),
            ChecklistItem(text: "Mixture IDLE CUTOFF", isChecked: false),
            ChecklistItem(text: "Ignition OFF", isChecked: false),
            ChecklistItem(text: "Master OFF", isChecked: false),
            ChecklistItem(text: "Control lock INSTALLED", isChecked: false),
            ChecklistItem(text: "Chocks/Tie-downs SET", isChecked: false),
            ChecklistItem(text: "Hobbs/Tach RECORDED", isChecked: false),
        ],
        .emergency: [
            ChecklistItem(text: "FLY THE AIRPLANE", isChecked: false),
            ChecklistItem(text: "Best glide speed ESTABLISHED", isChecked: false),
            ChecklistItem(text: "Emergency field SELECTED", isChecked: false),
            ChecklistItem(text: "Mayday DECLARED", isChecked: false),
            ChecklistItem(text: "Transponder 7700", isChecked: false),
            ChecklistItem(text: "Fuel OFF", isChecked: false),
            ChecklistItem(text: "Ignition OFF", isChecked: false),
            ChecklistItem(text: "Master OFF", isChecked: false),
            ChecklistItem(text: "Seat belts TIGHT", isChecked: false),
            ChecklistItem(text: "Doors UNLATCHED", isChecked: false),
        ],
    ]
}

struct CategoryPill: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpacingToken.space1) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                Text(title)
                    .font(TypographyToken.labelSmall)
            }
            .foregroundStyle(isSelected ? ColorToken.textOnBrand : color)
            .padding(.horizontal, SpacingToken.space3)
            .padding(.vertical, SpacingToken.space1)
            .background(
                isSelected ? color : color.opacity(0.1),
                in: Capsule()
            )
        }
        .buttonStyle(.plain)
    }
}

@Observable
final class ChecklistItem: Identifiable {
    let id = UUID()
    var text: String
    var isChecked: Bool

    init(text: String, isChecked: Bool = false) {
        self.text = text
        self.isChecked = isChecked
    }
}

struct ChecklistItemRow: View {
    @Bindable var item: ChecklistItem

    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            Button {
                withAnimation(AnimationToken.springFast) { item.isChecked.toggle() }
            } label: {
                ZStack {
                    Circle()
                        .stroke(item.isChecked ? ColorToken.success : ColorToken.borderDefault, lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if item.isChecked {
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(ColorToken.success)
                    }
                }
            }
            .buttonStyle(.plain)

            Text(item.text)
                .font(TypographyToken.bodyMedium)
                .foregroundStyle(item.isChecked ? ColorToken.textTertiary : ColorToken.textPrimary)
                .strikethrough(item.isChecked)

            Spacer()
        }
        .padding(.vertical, SpacingToken.space1)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(AnimationToken.springFast) { item.isChecked.toggle() }
        }
    }
}