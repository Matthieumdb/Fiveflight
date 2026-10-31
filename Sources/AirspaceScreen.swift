import SwiftUI

// MARK: - Airspace Screen

struct AirspaceScreen: View {
    @EnvironmentObject private var airspaceManager: AirspaceDataManager
    @EnvironmentObject private var model: AppModel
    @State private var selectedAltitude = 5500
    @State private var selectedType: AirspaceFilter = .all
    @State private var searchText = ""

    enum AirspaceFilter: String, CaseIterable {
        case all = "All"
        case controlled = "Controlled"
        case sua = "SUA"
        case tfr = "TFR"

        var icon: String {
            switch self {
            case .all: return "shield"
            case .controlled: return "shield.lefthalf.filled"
            case .sua: return "exclamationmark.triangle"
            case .tfr: return "exclamationmark.shield.fill"
            }
        }
    }

    private var filteredAirspaces: [Airspace] {
        airspaceManager.airspaces.filter { airspace in
            guard airspace.isActive else { return false }
            guard selectedAltitude >= airspace.floor && selectedAltitude <= airspace.ceiling else { return false }

            switch selectedType {
            case .all: return true
            case .controlled:
                if case .classAirspace(let cls) = airspace.type {
                    return cls.requiresATC || airspace.type == .classESurface
                }
                return false
            case .sua:
                if case .sua = airspace.type { return true }
                return false
            case .tfr:
                if case .sua(let sua) = airspace.type { return sua == .tf }
                return false
            }
        }
        .filter { searchText.isEmpty || $0.name.localizedCaseInsensitiveContains(searchText) }
        .sorted { a, b in
            // Sort by altitude proximity
            let aDist = abs(a.floor - selectedAltitude)
            let bDist = abs(b.floor - selectedAltitude)
            return aDist < bDist
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Altitude selector
                VStack(spacing: SpacingToken.space3) {
                    HStack {
                        Text("Altitude")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                        Spacer()
                        Text("\(selectedAltitude) ft MSL")
                            .font(TypographyToken.monoMedium)
                            .foregroundStyle(ColorToken.textPrimary)
                    }

                    Slider(
                        value: Binding(
                            get: { Double(selectedAltitude) },
                            set: { selectedAltitude = Int($0) }
                        ),
                        in: 0...18000,
                        step: 500
                    )
                    .tint(ColorToken.brandPrimary)
                }
                .padding(.horizontal, SpacingToken.insetMedium)
                .padding(.vertical, SpacingToken.space3)
                .background(ColorToken.surfaceElevated)

                // Filter chips
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: SpacingToken.space2) {
                        ForEach(AirspaceFilter.allCases, id: \.self) { filter in
                            FilterChip(
                                title: filter.rawValue,
                                icon: filter.icon,
                                isSelected: selectedType == filter,
                                color: filterColor(filter)
                            ) {
                                withAnimation(AnimationToken.fast) { selectedType = filter }
                            }
                        }
                    }
                    .padding(.horizontal, SpacingToken.insetMedium)
                }
                .padding(.vertical, SpacingToken.space2)

                // Search
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(ColorToken.textTertiary)
                    TextField("Search airspace...", text: $searchText)
                        .font(TypographyToken.bodyMedium)
                }
                .padding(SpacingToken.space3)
                .background(ColorToken.surfaceCard, in: RoundedRectangle(cornerRadius: RadiusToken.md))
                .padding(.horizontal, SpacingToken.insetMedium)
                .padding(.bottom, SpacingToken.space2)

                // Airspace list
                List {
                    if filteredAirspaces.isEmpty {
                        ContentUnavailableView(
                            "No Airspace",
                            systemImage: "shield.slash",
                            description: Text("No active airspace at \(selectedAltitude) ft matching your filters")
                        )
                        .listRowBackground(Color.clear)
                        .frame(minHeight: 200)
                    } else {
                        ForEach(filteredAirspaces) { airspace in
                            AirspaceRow(airspace: airspace, altitude: selectedAltitude)
                        }
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(ColorToken.surfaceBase)
            }
            .navigationTitle("Airspace")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        Task { await airspaceManager.refresh() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 18, weight: .medium))
                    }
                    .disabled(airspaceManager.isLoading)
                }
            }
        }
    }

    private func filterColor(_ filter: AirspaceFilter) -> Color {
        switch filter {
        case .all: return ColorToken.brandPrimary
        case .controlled: return ColorToken.classB
        case .sua: return ColorToken.moa
        case .tfr: return ColorToken.tfr
        }
    }
}

// MARK: - Filter Chip

struct FilterChip: View {
    let title: String
    let icon: String
    let isSelected: Bool
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: SpacingToken.space1) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .medium))
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

// MARK: - Airspace Row

struct AirspaceRow: View {
    let airspace: Airspace
    let altitude: Int
    @State private var showingDetail = false

    private var airspaceColor: Color {
        switch airspace.type {
        case .classAirspace(let cls):
            switch cls {
            case .A: return ColorToken.classA
            case .B: return ColorToken.classB
            case .C: return ColorToken.classC
            case .D: return ColorToken.classD
            case .E: return ColorToken.classE
            case .G: return ColorToken.classG
            }
        case .sua(let sua):
            switch sua {
            case .moa: return ColorToken.moa
            case .restricted: return ColorToken.restricted
            case .prohibited: return ColorToken.prohibited
            case .warning: return ColorToken.warningArea
            case .alert: return ColorToken.alertArea
            case .cfa: return ColorToken.cfa
            case .tf: return ColorToken.tfr
            case .nationalSecurity: return ColorToken.nationalSecurity
            }
        case .airway: return ColorToken.info
        case .classESurface: return ColorToken.classESurface
        }
    }

    private var typeLabel: String {
        switch airspace.type {
        case .classAirspace(let cls): return cls.displayName
        case .sua(let sua): return sua.displayName
        case .airway(let name): return "Airway \(name)"
        case .classESurface: return "Class E Surface"
        }
    }

    private var requiresPermission: Bool {
        switch airspace.type {
        case .classAirspace(let cls): return cls.requiresATC
        case .sua(let sua): return sua.requiresPermission
        case .classESurface: return true
        case .airway: return false
        }
    }

    var body: some View {
        Button {
            showingDetail = true
        } label: {
            HStack(spacing: SpacingToken.space3) {
                // Color indicator
                RoundedRectangle(cornerRadius: RadiusToken.xs)
                    .fill(airspaceColor)
                    .frame(width: 6, height: 56)

                VStack(alignment: .leading, spacing: SpacingToken.space1) {
                    HStack(spacing: SpacingToken.space2) {
                        Text(airspace.name)
                            .font(TypographyToken.bodyMedium)
                            .foregroundStyle(ColorToken.textPrimary)
                            .lineLimit(1)

                        Text(typeLabel)
                            .font(TypographyToken.monoXSmall)
                            .foregroundStyle(airspaceColor)
                            .padding(.horizontal, SpacingToken.space2)
                            .padding(.vertical, SpacingToken.space0)
                            .background(airspaceColor.opacity(0.1), in: Capsule())
                    }

                    HStack(spacing: SpacingToken.space3) {
                        Label("\(airspace.floor)–\(airspace.ceiling) ft", systemImage: "altitude")
                            .font(TypographyToken.monoXSmall)
                            .foregroundStyle(ColorToken.textTertiary)

                        if let freq = airspace.frequency, !freq.isEmpty {
                            Label(freq, systemImage: "antenna.radiowaves.left.and.right")
                                .font(TypographyToken.monoXSmall)
                                .foregroundStyle(ColorToken.textTertiary)
                        }

                        if requiresPermission {
                            Label("Permission Req'd", systemImage: "exclamationmark.shield")
                                .font(TypographyToken.labelXSmall)
                                .foregroundStyle(ColorToken.danger)
                        }
                    }
                }

                Spacer()

                // Altitude indicator
                VStack(alignment: .trailing, spacing: SpacingToken.space0) {
                    if altitude >= airspace.floor && altitude <= airspace.ceiling {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 20))
                            .foregroundStyle(ColorToken.danger)
                        Text("YOU'RE IN")
                            .font(TypographyToken.labelXSmall)
                            .foregroundStyle(ColorToken.danger)
                    } else if altitude < airspace.floor {
                        let diff = airspace.floor - altitude
                        Image(systemName: "arrow.up.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(ColorToken.warning)
                        Text("\(diff) ft above")
                            .font(TypographyToken.labelXSmall)
                            .foregroundStyle(ColorToken.warning)
                    } else {
                        let diff = altitude - airspace.ceiling
                        Image(systemName: "arrow.down.circle")
                            .font(.system(size: 20))
                            .foregroundStyle(ColorToken.success)
                        Text("\(diff) ft below")
                            .font(TypographyToken.labelXSmall)
                            .foregroundStyle(ColorToken.success)
                    }
                }
            }
            .padding(.vertical, SpacingToken.space2)
        }
        .buttonStyle(.plain)
        .sheet(isPresented: $showingDetail) {
            AirspaceDetailSheet(airspace: airspace)
        }
    }
}

// MARK: - Airspace Detail Sheet

struct AirspaceDetailSheet: View {
    let airspace: Airspace
    @Environment(\.dismiss) private var dismiss

    private var airspaceColor: Color {
        switch airspace.type {
        case .classAirspace(let cls):
            switch cls {
            case .A: return ColorToken.classA
            case .B: return ColorToken.classB
            case .C: return ColorToken.classC
            case .D: return ColorToken.classD
            case .E: return ColorToken.classE
            case .G: return ColorToken.classG
            }
        case .sua(let sua):
            switch sua {
            case .moa: return ColorToken.moa
            case .restricted: return ColorToken.restricted
            case .prohibited: return ColorToken.prohibited
            case .warning: return ColorToken.warningArea
            case .alert: return ColorToken.alertArea
            case .cfa: return ColorToken.cfa
            case .tf: return ColorToken.tfr
            case .nationalSecurity: return ColorToken.nationalSecurity
            }
        case .airway: return ColorToken.info
        case .classESurface: return ColorToken.classESurface
        }
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    VStack(alignment: .leading, spacing: SpacingToken.space3) {
                        HStack {
                            VStack(alignment: .leading, spacing: SpacingToken.space1) {
                                Text(airspace.name)
                                    .font(TypographyToken.headlineMedium)
                                    .foregroundStyle(ColorToken.textPrimary)

                                Text(typeLabel)
                                    .font(TypographyToken.monoMedium)
                                    .foregroundStyle(airspaceColor)
                            }

                            Spacer()

                            Circle()
                                .fill(airspaceColor)
                                .frame(width: 20, height: 20)
                        }

                        Divider()

                        // Key info
                        VStack(spacing: SpacingToken.space2) {
                            DetailRow(icon: "altitude", title: "Altitude", value: "\(airspace.floor) – \(airspace.ceiling) ft MSL")
                            if let freq = airspace.frequency, !freq.isEmpty {
                                DetailRow(icon: "antenna.radiowaves.left.and.right", title: "Frequency", value: freq)
                            }
                            if let agency = airspace.controllingAgency {
                                DetailRow(icon: "building.2", title: "Controlling Agency", value: agency)
                            }
                            if let schedule = airspace.schedule {
                                DetailRow(icon: "clock", title: "Schedule", value: schedule)
                            }
                            DetailRow(icon: "shield", title: "Status", value: airspace.isActive ? "Active" : "Inactive")
                        }
                    }
                    .padding(.vertical, SpacingToken.space2)
                }

                // VFR Requirements
                if case .classAirspace(let cls) = airspace.type, cls != .G {
                    Section {
                        VFRRequirementsView(airspaceClass: cls)
                    } header: {
                        Text("VFR Requirements")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                            .textCase(.uppercase)
                    }
                }

                // SUA Details
                if case .sua(let sua) = airspace.type {
                    Section {
                        SUADetailsView(suaType: sua)
                    } header: {
                        Text("Special Use Airspace Info")
                            .font(TypographyToken.labelSmall)
                            .foregroundStyle(ColorToken.textTertiary)
                            .textCase(.uppercase)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(ColorToken.surfaceBase)
            .navigationTitle("Airspace Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    private var typeLabel: String {
        switch airspace.type {
        case .classAirspace(let cls): return cls.displayName
        case .sua(let sua): return sua.displayName
        case .airway(let name): return "Airway \(name)"
        case .classESurface: return "Class E Surface"
        }
    }
}

struct DetailRow: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(ColorToken.brandPrimary)
                .frame(width: 28)

            Text(title)
                .font(TypographyToken.bodyMedium)
                .foregroundStyle(ColorToken.textSecondary)

            Spacer()

            Text(value)
                .font(TypographyToken.monoMedium)
                .foregroundStyle(ColorToken.textPrimary)
        }
    }
}

// MARK: - VFR Requirements View

struct VFRRequirementsView: View {
    let airspaceClass: AirspaceClass

    var body: some View {
        VStack(spacing: SpacingToken.space2) {
            RequirementRow(
                title: "Visibility",
                value: visibilityRequirement,
                met: true
            )

            RequirementRow(
                title: "Cloud Clearance",
                value: cloudClearanceRequirement,
                met: true
            )

            RequirementRow(
                title: "Equipment",
                value: equipmentRequirement,
                met: true
            )

            RequirementRow(
                title: "Communication",
                value: communicationRequirement,
                met: requiresComm
            )

            RequirementRow(
                title: "Entry Clearance",
                value: entryRequirement,
                met: requiresEntry
            )
        }
    }

    private var visibilityRequirement: String {
        switch airspaceClass {
        case .A: return "N/A (IFR Only)"
        case .B: return "3 SM"
        case .C: return "3 SM"
        case .D: return "3 SM"
        case .E: return "3 SM (below 10,000 MSL), 5 SM (above)"
        case .G: return "1 SM (day), 3 SM (night)"
        }
    }

    private var cloudClearanceRequirement: String {
        switch airspaceClass {
        case .A: return "N/A"
        case .B: return "Clear of clouds"
        case .C: return "500 ft below, 1,000 ft above, 2,000 ft horizontal"
        case .D: return "500 ft below, 1,000 ft above, 2,000 ft horizontal"
        case .E: return "500 ft below, 1,000 ft above, 2,000 ft horizontal"
        case .G: return "Clear of clouds (day), 500/1,000/2,000 (night)"
        }
    }

    private var equipmentRequirement: String {
        switch airspaceClass {
        case .A: return "IFR equipment required"
        case .B: return "Mode C transponder, ADS-B Out"
        case .C: return "Mode C transponder, ADS-B Out"
        case .D: return "Mode C transponder"
        case .E: return "Mode C transponder (above 10,000 MSL)"
        case .G: return "None required"
        }
    }

    private var communicationRequirement: String {
        switch airspaceClass {
        case .A: return "IFR clearance required"
        case .B: return "ATC clearance required"
        case .C: return "Two-way radio comm required"
        case .D: return "Two-way radio comm required"
        case .E: return "Not required (VFR)"
        case .G: return "Not required"
        }
    }

    private var entryRequirement: String {
        switch airspaceClass {
        case .A: return "IFR clearance required"
        case .B: return "ATC clearance required"
        case .C: return "Two-way radio comm required before entry"
        case .D: return "Two-way radio comm required before entry"
        case .E: return "Not required (VFR)"
        case .G: return "Not required"
        }
    }

    private var requiresComm: Bool {
        airspaceClass != .E && airspaceClass != .G
    }

    private var requiresEntry: Bool {
        airspaceClass == .B || airspaceClass == .C || airspaceClass == .D
    }
}

struct RequirementRow: View {
    let title: String
    let value: String
    let met: Bool

    var body: some View {
        HStack(spacing: SpacingToken.space3) {
            Image(systemName: met ? "checkmark.circle.fill" : "xmark.circle.fill")
                .font(.system(size: 20))
                .foregroundStyle(met ? ColorToken.success : ColorToken.danger)

            VStack(alignment: .leading, spacing: SpacingToken.space0) {
                Text(title)
                    .font(TypographyToken.labelSmall)
                    .foregroundStyle(ColorToken.textTertiary)
                Text(value)
                    .font(TypographyToken.bodySmall)
                    .foregroundStyle(ColorToken.textPrimary)
            }

            Spacer()
        }
    }
}

// MARK: - SUA Details View

struct SUADetailsView: View {
    let suaType: SUAType

    var body: some View {
        VStack(spacing: SpacingToken.space2) {
            RequirementRow(
                title: "Permission Required",
                value: suaType.requiresPermission ? "Yes - Contact controlling agency" : "No - Caution advised",
                met: !suaType.requiresPermission
            )

            RequirementRow(
                title: "Typical Activity",
                value: typicalActivity,
                met: true
            )

            RequirementRow(
                title: "Chart Symbol",
                value: chartSymbol,
                met: true
            )
        }
    }

    private var typicalActivity: String {
        switch suaType {
        case .moa: return "Military training, high-speed maneuvers"
        case .restricted: return "Hazardous operations (artillery, missiles)"
        case .prohibited: return "National security, no flight allowed"
        case .warning: return "Hazardous activity over international waters"
        case .alert: return "Unusual aerial activity, high pilot awareness"
        case .cfa: return "Controlled firing, ceases when aircraft detected"
        case .tf: return "Temporary restriction (VIP, disaster, security)"
        case .nationalSecurity: return "National security sensitive area"
        }
    }

    private var chartSymbol: String {
        switch suaType {
        case .moa: return "Blue hatched border"
        case .restricted: return "Blue hatched border, labeled R-XXXX"
        case .prohibited: return "Blue hatched border, labeled P-XXXX"
        case .warning: return "Blue hatched border, labeled W-XXXX"
        case .alert: return "Magenta hatched border, labeled A-XXXX"
        case .cfa: return "Not charted (refer to A/FD)"
        case .tf: return "Magenta border with diagonal lines"
        case .nationalSecurity: return "Magenta border with crosshatching"
        }
    }
}