import SwiftUI
import Security

/// FAA NOTAM API (external-api.faa.gov). It needs a free client id/secret from api.faa.gov,
/// entered once in Réglages and kept in the Keychain.
enum NOTAMService {
    struct NOTAM: Identifiable, Hashable {
        let id: String
        let text: String
        let start: String
        let end: String
    }

    static var credentials: (id: String, secret: String)? {
        guard let id = Keychain.read("faa.client_id"), let secret = Keychain.read("faa.client_secret"),
              !id.isEmpty, !secret.isEmpty else { return nil }
        return (id, secret)
    }

    static func fetch(icao: String) async throws -> [NOTAM] {
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
            return NOTAM(id: n.number ?? UUID().uuidString, text: n.text ?? "",
                         start: String((n.effectiveStart ?? "").prefix(16)).replacingOccurrences(of: "T", with: " "),
                         end: String((n.effectiveEnd ?? "PERM").prefix(16)).replacingOccurrences(of: "T", with: " "))
        }
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
            if NOTAMService.credentials == nil {
                Label("Ajoute ta clé FAA (gratuite, api.faa.gov) dans Plus > Réglages pour charger les NOTAM.",
                      systemImage: "key.fill")
                    .foregroundStyle(ColorToken.warning)
                link
            } else if failed {
                Label("NOTAM indisponibles (réseau ou clé refusée). Consulte-les avant le vol.", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(ColorToken.warning)
                link
            } else if let notams {
                if notams.isEmpty { Text("Aucun NOTAM en vigueur").foregroundStyle(ColorToken.textTertiary) }
                ForEach(notams) { n in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(n.id).font(TypographyToken.monoSmall).foregroundStyle(ColorToken.brandPrimary)
                        Text(n.text).font(TypographyToken.bodySmall)
                        Text("\(n.start) → \(n.end) UTC").font(TypographyToken.labelXSmall).foregroundStyle(ColorToken.textTertiary)
                    }
                }
            } else {
                HStack { ProgressView(); Text("Chargement des NOTAM…").foregroundStyle(ColorToken.textTertiary) }
            }
        } header: {
            Text("NOTAM")
        }
        .task(id: icao) {
            guard NOTAMService.credentials != nil else { return }
            do { notams = try await NOTAMService.fetch(icao: icao) } catch { failed = true }
        }
    }

    private var link: some View {
        Link("Ouvrir FAA NOTAM Search", destination: URL(string: "https://notams.aim.faa.gov/notamSearch/nsapp.html#/results?searchType=0&designatorsForLocation=\(icao)")!)
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
            Text("NOTAM (API FAA)")
        } footer: {
            Text("La clé reste dans le trousseau de l'iPhone et ne sert qu'à interroger l'API NOTAM de la FAA.")
        }
    }
}
