import SwiftUI
import CoreLocation

/// One posted fuel price.
struct FuelEntry: Codable, Hashable {
    let fuel: String        // 100LL, Jet A, MOGAS, UL94…
    let service: String     // FS (full service), SS (self service), or "Saisie"
    let price: Double       // USD per gallon
}

struct FuelPrice: Codable, Hashable {
    let ident: String
    var entries: [FuelEntry]
    /// Date the FBO last updated it (AirNav "Updated 27-Oct-2026"), when known.
    var updated: String?
    var fetched: Date
    var source: String      // "AirNav" or "Saisie manuelle"

    var best100LL: Double? { entries.filter { $0.fuel == "100LL" }.map(\.price).min() }
    var bestJetA: Double? { entries.filter { $0.fuel.hasPrefix("Jet A") }.map(\.price).min() }
}

/// Fuel prices: AirNav's public airport pages (prices posted by the FBOs, free), kept on disk for
/// offline use, plus prices typed by the pilot (which win over AirNav when newer).
@MainActor
final class FuelPriceService: ObservableObject {
    static let shared = FuelPriceService()
    @Published private(set) var prices: [String: FuelPrice] = [:]

    private let file = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("fuelprices.json")

    private init() {
        if let data = try? Data(contentsOf: file),
           let saved = try? JSONDecoder().decode([String: FuelPrice].self, from: data) { prices = saved }
    }

    private func save() {
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder().encode(prices).write(to: file, options: .atomic)
    }

    /// AirNav page of the airport, parsed; keeps a manual price that is newer than the AirNav one.
    @discardableResult
    func refresh(_ airport: Airport, maxAge: TimeInterval = 6 * 3600) async -> FuelPrice? {
        let key = airport.id
        if let p = prices[key], Date.now.timeIntervalSince(p.fetched) < maxAge { return p }
        guard let url = URL(string: "https://www.airnav.com/airport/\(airport.id)"),
              let data = try? await NetCache.data(from: url) else { return prices[key] }
        let html = String(decoding: data, as: UTF8.self)
        let parsed = Self.parseAirNav(html)
        guard !parsed.entries.isEmpty else { return prices[key] }
        if let manual = prices[key], manual.source == "Saisie manuelle", Date.now.timeIntervalSince(manual.fetched) < 7 * 86400 {
            return manual
        }
        let p = FuelPrice(ident: key, entries: parsed.entries, updated: parsed.updated, fetched: .now, source: "AirNav")
        prices[key] = p
        save()
        return p
    }

    func setManual(_ ident: String, avgas: Double?, jetA: Double?) {
        var entries: [FuelEntry] = []
        if let avgas, avgas > 0 { entries.append(FuelEntry(fuel: "100LL", service: "Saisie", price: avgas)) }
        if let jetA, jetA > 0 { entries.append(FuelEntry(fuel: "Jet A", service: "Saisie", price: jetA)) }
        if entries.isEmpty { prices[ident] = nil } else {
            prices[ident] = FuelPrice(ident: ident, entries: entries,
                                      updated: Date.now.formatted(date: .abbreviated, time: .omitted),
                                      fetched: .now, source: "Saisie manuelle")
        }
        save()
    }

    /// AirNav FBO tables: a header row naming the fuels, then FS/SS rows with "$7.49" cells, and "Updated dd-Mon-yyyy".
    nonisolated static func parseAirNav(_ html: String) -> (entries: [FuelEntry], updated: String?) {
        var text = html
        let replacements: [(String, String)] = [
            ("(?i)</t[dh]\\s*>", "\t"), ("(?i)<tr[^>]*>", "\n"), ("(?i)</tr\\s*>", "\n"),
            ("(?is)<script.*?</script>", ""), ("(?is)<style.*?</style>", ""), ("<[^>]+>", ""),
            ("&nbsp;", " "), ("&amp;", "&"),
        ]
        for (pattern, with) in replacements {
            text = text.replacingOccurrences(of: pattern, with: with, options: .regularExpression)
        }
        let fuels = ["100LL", "Jet A+", "Jet A", "MOGAS", "UL94", "UL91", "SAF", "G100UL", "80"]
        func fuelName(_ cell: String) -> String? {
            let c = cell.trimmingCharacters(in: .whitespaces)
            return fuels.first { c.caseInsensitiveCompare($0) == .orderedSame }
                ?? (c.uppercased().hasPrefix("JET A") ? "Jet A" : nil)
        }
        var header: [String?]?
        var out: [FuelEntry] = []
        for line in text.components(separatedBy: "\n") {
            let cells = line.components(separatedBy: "\t").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            let names = cells.map(fuelName)
            let hasPrice = line.contains("$")
            if !hasPrice, names.contains(where: { $0 != nil }) {
                header = names
                continue
            }
            guard hasPrice, let h = header else { continue }
            let service = cells.first { !$0.isEmpty && !$0.contains("$") } ?? ""
            for (i, cell) in cells.enumerated() where i < h.count {
                guard let fuel = h[i],
                      let r = cell.range(of: #"\$\s*(\d{1,2}\.\d{2})"#, options: .regularExpression),
                      let price = Double(cell[r].filter { $0.isNumber || $0 == "." }) else { continue }
                out.append(FuelEntry(fuel: fuel, service: String(service.prefix(12)), price: price))
            }
        }
        var updated: String?
        if let r = text.range(of: #"Updated\s+\d{1,2}-[A-Za-z]{3}-\d{4}"#, options: .regularExpression) {
            updated = String(text[r]).replacingOccurrences(of: "Updated", with: "").trimmingCharacters(in: .whitespaces)
        }
        return (Array(Set(out)).sorted { ($0.fuel, $0.price) < ($1.fuel, $1.price) }, updated)
    }
}

// MARK: - View

/// "Carburant" section of the airport sheet: posted prices, manual entry, cheapest nearby.
struct FuelPriceSection: View {
    let airport: Airport
    let store: AirportStore
    @ObservedObject private var service = FuelPriceService.shared
    @State private var loading = false
    @State private var editing = false
    @State private var avgasText = ""
    @State private var jetText = ""
    @State private var nearby: [(Airport, Double, Double)]?   // airport, distance, 100LL price
    @State private var searchingNearby = false

    private var price: FuelPrice? { service.prices[airport.id] }

    var body: some View {
        Section {
            if let price {
                ForEach(price.entries, id: \.self) { e in
                    LabeledContent("\(e.fuel) · \(serviceName(e.service))", value: String(format: "$%.2f", e.price))
                        .monospacedDigit()
                }
                Text("\(price.source)\(price.updated.map { " · mis à jour \($0)" } ?? "") · relevé \(price.fetched.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption).foregroundStyle(ColorToken.textTertiary)
            } else if loading {
                HStack { ProgressView(); Text("Recherche des prix…").foregroundStyle(ColorToken.textTertiary) }
            } else {
                Text("Aucun prix publié pour ce terrain").foregroundStyle(ColorToken.textTertiary)
            }
            Button("Saisir un prix", systemImage: "square.and.pencil") {
                avgasText = price?.best100LL.map { String(format: "%.2f", $0) } ?? ""
                jetText = price?.bestJetA.map { String(format: "%.2f", $0) } ?? ""
                editing = true
            }
            Button(searchingNearby ? "Recherche…" : "100LL le moins cher à 40 NM", systemImage: "fuelpump") {
                Task { await findNearby() }
            }
            .disabled(searchingNearby)
            if let nearby {
                if nearby.isEmpty { Text("Aucun prix trouvé autour").foregroundStyle(ColorToken.textTertiary) }
                ForEach(nearby, id: \.0.id) { item in
                    LabeledContent("\(item.0.id) · \(Int(item.1.rounded())) NM", value: String(format: "$%.2f", item.2))
                        .monospacedDigit()
                }
            }
        } header: { FFHeader("Carburant") }
        .task(id: airport.id) {
            loading = true
            await service.refresh(airport)
            loading = false
        }
        .alert("Prix carburant \(airport.id)", isPresented: $editing) {
            TextField("100LL ($/gal)", text: $avgasText).keyboardType(.decimalPad)
            TextField("Jet A ($/gal)", text: $jetText).keyboardType(.decimalPad)
            Button("Enregistrer") {
                func v(_ s: String) -> Double? { Double(s.replacingOccurrences(of: ",", with: ".")) }
                service.setManual(airport.id, avgas: v(avgasText), jetA: v(jetText))
            }
            Button("Annuler", role: .cancel) {}
        }
    }

    private func serviceName(_ s: String) -> String {
        switch s.uppercased() {
        case "FS": return "service complet"
        case "SS": return "libre-service"
        case "SAISIE": return "saisi"
        default: return s
        }
    }

    private func findNearby() async {
        searchingNearby = true
        defer { searchingNearby = false }
        let candidates = store.nearest(to: airport.coordinate, limit: 15, matching: ["large_airport", "medium_airport", "small_airport"])
            .filter { $0.distanceNM(to: airport.coordinate) <= 40 }
        var found: [(Airport, Double, Double)] = []
        await withTaskGroup(of: (Airport, Double?).self) { group in
            for a in candidates { group.addTask { @MainActor in (a, await FuelPriceService.shared.refresh(a)?.best100LL) } }
            for await (a, p) in group { if let p { found.append((a, a.distanceNM(to: airport.coordinate), p)) } }
        }
        nearby = found.sorted { $0.2 < $1.2 }
    }
}
