import SwiftUI

// MARK: - Profile Stepper Row

struct ProfileStepperRow: View {
    let title: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let step: Double
    let unit: String
    let icon: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ColorToken.brandPrimary)
                .frame(width: 28)

            Text(title)
                .font(TypographyToken.bodyMedium)
                .foregroundStyle(ColorToken.textPrimary)

            Spacer()

            HStack(spacing: SpacingToken.space3) {
                Button {
                    value = max(range.lowerBound, value - step)
                } label: {
                    Image(systemName: "minus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ColorToken.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(ColorToken.surfaceCard, in: Circle())
                }
                .buttonStyle(.plain)

                Text("\(Int(value)) \(unit)")
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)
                    .frame(minWidth: 80)

                Button {
                    value = min(range.upperBound, value + step)
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(ColorToken.textPrimary)
                        .frame(width: 36, height: 36)
                        .background(ColorToken.surfaceCard, in: Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, SpacingToken.space1)
    }
}

// MARK: - Logbook Screen

struct LogbookScreen: View {
    @EnvironmentObject private var model: AppModel
    @State private var entries: [LogbookEntry] = []
    @State private var showingAddEntry = false
    @State private var filterText = ""

    var filteredEntries: [LogbookEntry] {
        if filterText.isEmpty { return entries }
        return entries.filter {
            $0.from.localizedCaseInsensitiveContains(filterText) ||
            $0.to.localizedCaseInsensitiveContains(filterText) ||
            $0.aircraft.localizedCaseInsensitiveContains(filterText)
        }
    }

    var body: some View {
        NavigationStack {
            List {
                if filteredEntries.isEmpty {
                    ContentUnavailableView(
                        "No Flights Logged",
                        systemImage: "book",
                        description: Text("Complete a flight and tap 'Log Flight' to add entries")
                    )
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(filteredEntries) { entry in
                        LogbookEntryRow(entry: entry)
                    }
                    .onDelete { indexSet in
                        entries.remove(atOffsets: indexSet)
                    }
                }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
            .background(ColorToken.surfaceBase)
            .searchable(text: $filterText, prompt: "Search flights...")
            .navigationTitle("Logbook")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showingAddEntry = true
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 18, weight: .medium))
                    }
                }
            }
            .sheet(isPresented: $showingAddEntry) {
                AddLogbookEntrySheet()
            }
        }
    }
}

struct LogbookEntryRow: View {
    let entry: LogbookEntry

    var body: some View {
        VStack(alignment: .leading, spacing: SpacingToken.space2) {
            HStack {
                Text(entry.from)
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)

                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(ColorToken.textTertiary)

                Text(entry.to)
                    .font(TypographyToken.monoMedium)
                    .foregroundStyle(ColorToken.textPrimary)

                Spacer()

                Text(entry.date.formatted(date: .abbreviated, time: .omitted))
                    .font(TypographyToken.monoSmall)
                    .foregroundStyle(ColorToken.textTertiary)
            }

            HStack(spacing: SpacingToken.space4) {
                Label("\(entry.distanceNM) NM", systemImage: "point.topleft.down.curvedto.point.bottomright.forward")
                Label("\(entry.eteMinutes / 60)h\(String(format: "%02d", entry.eteMinutes % 60))m", systemImage: "clock")
                Label(entry.aircraft, systemImage: "airplane")
            }
            .font(TypographyToken.bodySmall)
            .foregroundStyle(ColorToken.textSecondary)

            HStack {
                Text(entry.conditions)
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.brandPrimary)
                    .padding(.horizontal, SpacingToken.space2)
                    .padding(.vertical, SpacingToken.space0)
                    .background(ColorToken.brandPrimary.opacity(0.1), in: Capsule())
                Spacer()
            }
        }
        .padding(SpacingToken.cardPadding)
        .background(ColorToken.surfaceCard, in: RoundedRectangle(cornerRadius: RadiusToken.card))
        .overlay(
            RoundedRectangle(cornerRadius: RadiusToken.card)
                .stroke(ColorToken.borderDefault, lineWidth: 0.5)
        )
        .padding(.horizontal, SpacingToken.insetMedium)
        .padding(.vertical, SpacingToken.space1)
    }
}

struct AddLogbookEntrySheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var from = ""
    @State private var to = ""
    @State private var distance = 0
    @State private var eteMinutes = 0
    @State private var aircraft = ""
    @State private var conditions = "VFR"
    @State private var date = Date()

    var body: some View {
        NavigationStack {
            Form {
                Section("Route") {
                    TextField("From (e.g., KJFK)", text: $from)
                        .textInputAutocapitalization(.characters)
                    TextField("To (e.g., KBOS)", text: $to)
                        .textInputAutocapitalization(.characters)
                }

                Section("Details") {
                    ProfileStepperRow(title: "Distance", value: Binding(
                        get: { Double(distance) },
                        set: { distance = Int($0) }
                    ), range: 0...5000, step: 10, unit: "NM", icon: "point.topleft.down.curvedto.point.bottomright.forward")

                    ProfileStepperRow(title: "Time Enroute", value: Binding(
                        get: { Double(eteMinutes) },
                        set: { eteMinutes = Int($0) }
                    ), range: 0...1440, step: 5, unit: "min", icon: "clock")

                    TextField("Aircraft", text: $aircraft)

                    Picker("Conditions", selection: $conditions) {
                        Text("VFR").tag("VFR")
                        Text("MVFR").tag("MVFR")
                        Text("IFR").tag("IFR")
                    }

                    DatePicker("Date", selection: $date, displayedComponents: [.date, .hourAndMinute])
                }
            }
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Save") {
                        let entry = LogbookEntry(
                            date: date,
                            from: from,
                            to: to,
                            distanceNM: distance,
                            eteMinutes: eteMinutes,
                            aircraft: aircraft.isEmpty ? "Unknown" : aircraft,
                            conditions: conditions
                        )
                        // Would save to model
                        dismiss()
                    }
                    .primaryButton(size: .small)
                    .disabled(from.isEmpty || to.isEmpty)
                }
            }
        }
    }
}