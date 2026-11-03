import SwiftUI
import Security

/// NOTAMs without any key: the FAA NOTAM Search service (notams.aim.faa.gov, the public site's own
/// JSON endpoint). When an api.faa.gov client id/secret is saved in Réglages, the official NOTAM API
/// is used as a fallback.
enum NOTAMService {
    struct NOTAM: Identifiable, Hashable {
        let id: String
        let location: String
        let text: String
        let start: String
        let end: String
        let keyword: String

        init(id: String, location: String = "", text: String, start: String, end: String, keyword: String = "") {
            self.id = id; self.location = location; self.text = text; self.start = start; self.end = end
            self.keyword = keyword
        }

        /// Runway/aerodrome closures, TFR-like flight restrictions and obstacles are worth a highlight.
        var isImportant: Bool {
            let t = text.uppercased()
            return t.contains("CLSD") || t.contains("TFR") || t.contains("FLIGHT RESTRICTIONS") || keyword == "AIRSPACE"
                || t.contains("U/S") || t.contains("UNSERVICEABLE")
        }
    }

    static var credentials: (id: String, secret: String)? {
        guard let id = Keychain.read("faa.client_id"), let secret = Keychain.read("faa.client_secret"),
              !id.isEmpty, !secret.isEmpty else { return nil }
        return (id, secret)
    }

    /// Short in-memory cache so the airport card and the route briefing don't ask twice.
    @MainActor private static var cache: [String: (Date, [NOTAM])] = [:]

    /// NOTAMs for one location: FAA NOTAM Search first (no key), then the FAA API if a key exists.
    @MainActor
    static func fetch(icao: String) async throws -> [NOTAM] {
        let key = icao.uppercased()
        if let hit = cache[key], Date.now.timeIntervalSince(hit.0) < 600 { return hit.1 }
        let list: [NOTAM]
        do {
            list = try await fetchPublic(location: key)
        } catch {
            // Then the FAA API (if a key is saved), then NOTAMs received over ADS-B (FIS-B).
            let fisb = FISBStore.shared.notams(at: key)
            if credentials != nil, let api = try? await fetchAPI(icao: key) {
                list = api
            } else if !fisb.isEmpty {
                return fisb
            } else {
                throw error
            }
        }
        cache[key] = (.now, list)
        return list
    }

    /// NOTAMs for several locations at once (route briefing); failures are reported per location.
    @MainActor
    static func fetch(locations: [String]) async -> (notams: [String: [NOTAM]], failed: [String]) {
        var out: [String: [NOTAM]] = [:]
        var failed: [String] = []
        for loc in locations {
            do { out[loc] = try await fetch(icao: loc) } catch { failed.append(loc) }
        }
        return (out, failed)
    }

    static func fetchPublic(location: String) async throws -> [NOTAM] {
        var request = URLRequest(url: URL(string: "https://notams.aim.faa.gov/notamSearch/search")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 20
        request.setValue("application/x-www-form-urlencoded; charset=UTF-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/javascript, */*", forHTTPHeaderField: "Accept")
        request.setValue("https://notams.aim.faa.gov/notamSearch/", forHTTPHeaderField: "Referer")
        let fields: [(String, String)] = [
            ("searchType", "0"), ("designatorsForLocation", location), ("designatorForAccountable", ""),
            ("latDegrees", ""), ("latMinutes", "0"), ("latSeconds", "0"), ("longDegrees", ""),
            ("longMinutes", "0"), ("longSeconds", "0"), ("radius", "10"), ("sortColumns", "5 false"),
            ("sortDirection", "true"), ("designatorForNotamNumberSearch", ""), ("notamNumber", ""),
            ("radiusSearchOnDesignator", "false"), ("radiusSearchDesignator", ""), ("latitudeDirection", "N"),
            ("longitudeDirection", "W"), ("freeFormText", ""), ("flightPathText", ""),
            ("flightPathDivertAirfields", ""), ("flightPathBuffer", "4"), ("flightPathIncludeNavaids", "true"),
            ("flightPathIncludeArtcc", "false"), ("flightPathIncludeTfr", "true"),
            ("flightPathIncludeRegulatory", "false"), ("flightPathResultsType", "All NOTAMs"),
            ("archiveDate", ""), ("archiveDesignator", ""), ("offset", "0"), ("notamsOnly", "false"),
            ("filters", ""), ("minRunwayLength", ""), ("minRunwayWidth", ""), ("runwaySurfaceTypes", ""),
            ("predefinedAbraka", ""), ("predefinedDabra", ""), ("flightPathAddlBuffer", ""),
        ]
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        request.httpBody = fields
            .map { "\($0.0)=\($0.1.addingPercentEncoding(withAllowedCharacters: allowed) ?? "")" }
            .joined(separator: "&")
            .data(using: .utf8)
        let data = try await NetCache.fetch(request).data   // saved copy when offline
        return try parsePublic(data)
    }

    /// Parses the FAA NOTAM Search JSON ({"notamList": [...]}); tolerant to missing fields.
    static func parsePublic(_ data: Data) throws -> [NOTAM] {
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let list = root["notamList"] as? [[String: Any]] else { throw URLError(.cannotParseResponse) }
        func str(_ d: [String: Any], _ k: String) -> String {
            if let s = d[k] as? String { return s.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let n = d[k] as? NSNumber { return n.stringValue }
            return ""
        }
        return list.compactMap { d in
            if (d["cancelledOrExpired"] as? Bool) == true { return nil }
            let number = str(d, "notamNumber")
            let text = [str(d, "traditionalMessageFrom4thWord"), str(d, "traditionalMessage"), str(d, "icaoMessage")]
                .first { !$0.isEmpty } ?? ""
            guard !text.isEmpty else { return nil }
            let loc = [str(d, "icaoId"), str(d, "facilityDesignator")].first { !$0.isEmpty } ?? ""
            let end = str(d, "endDate")
            return NOTAM(id: number.isEmpty ? UUID().uuidString : "\(loc) \(number)", location: loc, text: text,
                         start: str(d, "startDate"), end: end.isEmpty ? "PERM" : end, keyword: str(d, "keyword"))
        }
    }

    static func fetchAPI(icao: String) async throws -> [NOTAM] {
        guard let creds = credentials else { throw URLError(.userAuthenticationRequired) }
        var request = URLRequest(url: URL(string: "https://external-api.faa.gov/notamapi/v1/notams?icaoLocation=\(icao)&pageSize=100")!)
        request.setValue(creds.id, forHTTPHeaderField: "client_id")
        request.setValue(creds.secret, forHTTPHeaderField: "client_secret")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        struct Page: Decodable {
            struct Item: Decodable {
                struct Props: Decodable {
                    struct Core: Decodable {
                        struct N: Decodable { let number: String?; let text: String?; let effectiveStart: String?; let effectiveEnd: String? }
                        let notam: N
                    }
                    let coreNOTAMData: Core
                }
                let properties: Props
            }
            let items: [Item]
        }
        return try JSONDecoder().decode(Page.self, from: data).items.map {
            let n = $0.properties.coreNOTAMData.notam
            return NOTAM(id: n.number ?? UUID().uuidString, location: icao, text: n.text ?? "",
                         start: String((n.effectiveStart ?? "").prefix(16)).replacingOccurrences(of: "T", with: " "),
                         end: String((n.effectiveEnd ?? "PERM").prefix(16)).replacingOccurrences(of: "T", with: " "))
        }
    }

    static func searchURL(_ icao: String) -> URL {
        URL(string: "https://notams.aim.faa.gov/notamSearch/nsapp.html#/results?searchType=0&designatorsForLocation=\(icao)")!
    }
}

/// Minimal generic-password Keychain access.
enum Keychain {
    static func read(_ key: String) -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        return String(data: d, encoding: .utf8)
    }

    static func write(_ key: String, _ value: String) {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrAccount as String: key]
        SecItemDelete(q as CFDictionary)
        guard !value.isEmpty else { return }
        var add = q
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        SecItemAdd(add as CFDictionary, nil)
    }
}

/// NOTAM section of the airport sheet.
struct NOTAMSection: View {
    let icao: String
    @State private var notams: [NOTAMService.NOTAM]?
    @State private var failed = false

    var body: some View {
        Section {
            if failed {
                Label("NOTAM indisponibles (réseau ou service FAA). Consulte-les avant le vol.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(ColorToken.warning)
                link
            } else if let notams {
                if notams.isEmpty { Text("Aucun NOTAM en vigueur").foregroundStyle(ColorToken.textTertiary) }
                ForEach(notams) { NOTAMRow(notam: $0) }
                if !notams.isEmpty { link }
            } else {
                HStack { ProgressView(); Text("Chargement des NOTAM…").foregroundStyle(ColorToken.textTertiary) }
            }
        } header: {
            Text("NOTAM")
        } footer: {
            Text("Source : FAA NOTAM Search, sans clé.")
        }
        .task(id: icao) {
            failed = false
            do { notams = try await NOTAMService.fetch(icao: icao) } catch { failed = true }
        }
    }

    private var link: some View {
        Link("Ouvrir FAA NOTAM Search", destination: NOTAMService.searchURL(icao))
    }
}

/// One NOTAM: number, text, validity. Closures and restrictions are highlighted.
struct NOTAMRow: View {
    let notam: NOTAMService.NOTAM
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if notam.isImportant {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(ColorToken.warning)
                }
                Text(notam.id).font(TypographyToken.monoSmall).foregroundStyle(ColorToken.brandPrimary)
            }
            Text(notam.text).font(TypographyToken.bodySmall).textSelection(.enabled)
            Text("\(notam.start) → \(notam.end) UTC").font(TypographyToken.labelXSmall).foregroundStyle(ColorToken.textTertiary)
        }
    }
}

/// Réglages: FAA API key fields.
struct FAAKeySection: View {
    @State private var clientID = Keychain.read("faa.client_id") ?? ""
    @State private var secret = Keychain.read("faa.client_secret") ?? ""

    var body: some View {
        Section {
            TextField("client_id", text: $clientID).textInputAutocapitalization(.never).autocorrectionDisabled()
            SecureField("client_secret", text: $secret)
            Button("Enregistrer la clé") {
                Keychain.write("faa.client_id", clientID.trimmingCharacters(in: .whitespaces))
                Keychain.write("faa.client_secret", secret.trimmingCharacters(in: .whitespaces))
            }
            Link("Obtenir une clé gratuite sur api.faa.gov", destination: URL(string: "https://api.faa.gov/s/")!)
        } header: {
            Text("NOTAM : clé FAA (facultative)")
        } footer: {
            Text("Plus nécessaire : les NOTAM viennent de FAA NOTAM Search sans clé. La clé ne sert que de secours et reste dans le trousseau.")
        }
    }
}
