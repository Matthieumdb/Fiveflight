import SwiftUI
import PDFKit
import UniformTypeIdentifiers

// MARK: - App shell (ForeFlight structure)
//
// ForeFlight organises the app as one tab per job: Airports, Maps, Plates, Documents, Imagery,
// Flights, Logbook and More. On iPad every view has its own tab; on iPhone the five most used ones
// stay in the tab bar and the others move to the More list.

enum FFTab: String, CaseIterable, Identifiable, Hashable {
    case airports, maps, plates, documents, imagery, flights, logbook, more
    var id: String { rawValue }

    var title: String {
        switch self {
        case .airports: return "Aéroports"
        case .maps: return "Cartes"
        case .plates: return "Plaques"
        case .documents: return "Documents"
        case .imagery: return "Imagerie"
        case .flights: return "Vols"
        case .logbook: return "Carnet"
        case .more: return "Plus"
        }
    }

    var icon: String {
        switch self {
        case .airports: return "airplane.circle"
        case .maps: return "map"
        case .plates: return "doc.richtext"
        case .documents: return "books.vertical"
        case .imagery: return "cloud.sun"
        case .flights: return "airplane.departure"
        case .logbook: return "book.closed"
        case .more: return "ellipsis"
        }
    }

    /// Tabs shown in the tab bar: everything on iPad, the five ForeFlight iPhone tabs otherwise.
    static func visible(regular: Bool) -> [FFTab] {
        regular ? allCases : [.airports, .maps, .imagery, .flights, .more]
    }

    @MainActor @ViewBuilder var screen: some View {
        switch self {
        case .airports: AirportsScreen()
        case .maps: MapScreen()
        case .plates: NavigationStack { PlatesScreen() }
        case .documents: NavigationStack { DocumentsScreen() }
        case .imagery: ImageryScreen()
        case .flights: FlightPlanScreen()
        case .logbook: NavigationStack { LogbookScreen() }
        case .more: MoreScreen()
        }
    }
}

/// Selected tab, shared so any view can jump to another tab (e.g. "Afficher sur la carte").
@MainActor
final class FFRouter: ObservableObject {
    static let shared = FFRouter()
    @Published var tab: FFTab = .maps
}

// MARK: - More

/// ForeFlight "More": everything that is not a main view, grouped by job.
struct MoreScreen: View {
    @Environment(\.horizontalSizeClass) private var sizeClass
    @EnvironmentObject private var model: AppModel

    var body: some View {
        NavigationStack {
            List {
                if sizeClass != .regular {
                    Section {
                        moreLink(.plates) { PlatesScreen() }
                        moreLink(.documents) { DocumentsScreen() }
                        moreLink(.logbook) { LogbookScreen() }
                    } header: { FFHeader("Vues") }
                }
                Section {
                    row("Avions", "airplane", subtitle: model.selectedAircraft.map { "\($0.name) · \($0.type)" }) { AircraftScreen() }
                    row("Masse & centrage, calculateurs", "scalemass") { CalculatorsScreen() }
                    row("Checklists", "checklist") { ChecklistScreen() }
                    row("Favoris", "star") { FavoritesScreen() }
                } header: { FFHeader("Planification") }
                Section {
                    row("Horizon artificiel (AHRS)", "gyroscope") { AttitudeScreen() }
                    row("Espaces aériens & SUA", "shield.lefthalf.filled") { AirspaceScreen() }
                    row("Appareils (ADS-B)", "dot.radiowaves.left.and.right") { DevicesScreen() }
                } header: { FFHeader("En vol") }
                Section {
                    row("Téléchargements", "arrow.down.circle") { DownloadsScreen() }
                    row("Réglages", "gearshape") { SettingsScreen() }
                } header: { FFHeader("Application") }
                Section {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    Text("Projet personnel, non destiné à la navigation réelle. Données FAA, NOAA et OurAirports.")
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Plus")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    private func moreLink<D: View>(_ tab: FFTab, @ViewBuilder destination: () -> D) -> some View {
        NavigationLink(destination: destination()) { FFIconLabel(title: tab.title, icon: tab.icon) }
    }

    private func row<D: View>(_ title: String, _ icon: String, subtitle: String? = nil,
                              @ViewBuilder destination: () -> D) -> some View {
        NavigationLink(destination: destination()) { FFIconLabel(title: title, icon: icon, subtitle: subtitle) }
    }
}

/// ForeFlight list label: blue rounded-square glyph, title, optional grey subtitle.
struct FFIconLabel: View {
    let title: String
    let icon: String
    var subtitle: String? = nil
    var tint: Color = FF.accent

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(tint, in: RoundedRectangle(cornerRadius: 7))
            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                if let subtitle {
                    Text(subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
        }
    }
}

/// ADS-B receiver screen (ForeFlight "Devices").
struct DevicesScreen: View {
    var body: some View {
        List { ADSBSection() }
            .listStyle(.insetGrouped)
            .navigationTitle("Appareils")
            .navigationBarTitleDisplayMode(.inline)
    }
}

/// Offline charts and data (ForeFlight "Downloads").
struct DownloadsScreen: View {
    @State private var cacheMB = FAADocuments.cacheMB()

    var body: some View {
        List {
            OfflineChartsSection()
            Section {
                HStack {
                    Label("Plaques et documents FAA", systemImage: "doc.on.doc")
                    Spacer()
                    Text(String(format: "%.0f Mo", cacheMB)).foregroundStyle(.secondary).monospacedDigit()
                }
                Button("Vider le cache des PDF", role: .destructive) {
                    try? FileManager.default.removeItem(at: FAADocuments.pdfDirectory)
                    cacheMB = FAADocuments.cacheMB()
                }
            } header: { FFHeader("Documents en cache") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Téléchargements")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Plates

/// ForeFlight "Plates": the airports of the flight, then favorites and recents; each opens its binder
/// (diagram, procedures, Chart Supplement).
struct PlatesScreen: View {
    @EnvironmentObject private var model: AppModel
    @EnvironmentObject private var store: AirportStore
    @State private var query = ""

    /// Fields that can have FAA plates: public airports, not heliports or private strips ("07FA").
    private static func mayHavePlates(_ a: Airport) -> Bool {
        guard ["large_airport", "medium_airport", "small_airport", "seaplane_base"].contains(a.type) else { return false }
        return !(a.id.count == 4 && a.id.first?.isNumber == true)
    }
    private var routeAirports: [Airport] { model.waypoints.filter { $0.isAirport && Self.mayHavePlates($0) } }
    private var favorites: [Airport] { model.favorites.sorted().compactMap { store.airport($0) }.filter(Self.mayHavePlates) }
    private var recents: [Airport] { model.recents.prefix(10).compactMap { store.airport($0) }.filter(Self.mayHavePlates) }

    private var searchResults: [Airport] {
        let q = query.trimmingCharacters(in: .whitespaces).uppercased()
        guard q.count >= 2 else { return [] }
        return AirportSearch.rank(store.airports.filter(Self.mayHavePlates), query: q, limit: 30)
    }

    var body: some View {
        List {
            if !query.isEmpty {
                Section { ForEach(searchResults) { binderLink($0) } } header: { FFHeader("Résultats") }
            } else {
                if !routeAirports.isEmpty {
                    Section { ForEach(routeAirports) { binderLink($0) } } header: { FFHeader("Vol en cours") }
                }
                Section {
                    if favorites.isEmpty { Text("Aucun favori").foregroundStyle(.secondary) }
                    ForEach(favorites) { binderLink($0) }
                } header: { FFHeader("Favoris") }
                if !recents.isEmpty {
                    Section { ForEach(recents) { binderLink($0) } } header: { FFHeader("Récents") }
                }
            }
        }
        .listStyle(.insetGrouped)
        .searchable(text: $query, placement: .navigationBarDrawer(displayMode: .always), prompt: "Rechercher un aéroport")
        .navigationTitle("Plaques")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func binderLink(_ airport: Airport) -> some View {
        NavigationLink {
            List { AirportDocumentsSection(ident: airport.id) }
                .listStyle(.insetGrouped)
                .navigationTitle(airport.id)
                .navigationBarTitleDisplayMode(.inline)
        } label: {
            VStack(alignment: .leading, spacing: 1) {
                Text(airport.id).font(.system(size: 17, weight: .bold))
                Text(airport.name).font(.footnote).foregroundStyle(.secondary).lineLimit(1)
            }
        }
    }
}

// MARK: - Documents

/// ForeFlight "Documents": the pilot's own PDFs (POH, checklists, charts) imported from Files,
/// and the FAA PDFs already downloaded for offline use.
struct DocumentsScreen: View {
    @State private var userDocs: [URL] = []
    @State private var cachedDocs: [URL] = []
    @State private var importing = false

    static var userDirectory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].appendingPathComponent("Documents pilote")
    }

    var body: some View {
        List {
            Section {
                if userDocs.isEmpty {
                    Text("Importez vos PDF (manuel de vol, checklists, cartes) depuis Fichiers.")
                        .foregroundStyle(.secondary)
                }
                ForEach(userDocs, id: \.self) { url in
                    NavigationLink { LocalPDFScreen(url: url) } label: {
                        FFIconLabel(title: url.deletingPathExtension().lastPathComponent, icon: "doc.fill")
                    }
                }
                .onDelete { offsets in
                    for i in offsets { try? FileManager.default.removeItem(at: userDocs[i]) }
                    reload()
                }
            } header: { FFHeader("Mes documents") }

            Section {
                if cachedDocs.isEmpty {
                    Text("Les plaques ouvertes une fois restent ici, disponibles hors ligne.")
                        .foregroundStyle(.secondary)
                }
                ForEach(cachedDocs, id: \.self) { url in
                    NavigationLink { LocalPDFScreen(url: url) } label: {
                        FFIconLabel(title: url.deletingPathExtension().lastPathComponent, icon: "doc.richtext", tint: .gray)
                    }
                }
            } header: { FFHeader("FAA (hors ligne)") }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("Documents")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button { importing = true } label: { Image(systemName: "plus") }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf], allowsMultipleSelection: true) { result in
            guard case .success(let urls) = result else { return }
            let dir = Self.userDirectory
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for url in urls {
                let scoped = url.startAccessingSecurityScopedResource()
                defer { if scoped { url.stopAccessingSecurityScopedResource() } }
                let target = dir.appendingPathComponent(url.lastPathComponent)
                try? FileManager.default.removeItem(at: target)
                try? FileManager.default.copyItem(at: url, to: target)
            }
            reload()
        }
        .onAppear(perform: reload)
    }

    private func reload() {
        let fm = FileManager.default
        func pdfs(in dir: URL) -> [URL] {
            ((try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension.lowercased() == "pdf" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
        }
        userDocs = pdfs(in: Self.userDirectory)
        cachedDocs = pdfs(in: FAADocuments.pdfDirectory)
    }
}

/// A PDF already on the device.
struct LocalPDFScreen: View {
    let url: URL
    var body: some View {
        PDFKitView(url: url)
            .ignoresSafeArea(edges: .bottom)
            .navigationTitle(url.deletingPathExtension().lastPathComponent)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarTrailing) { ShareLink(item: url) } }
    }
}
