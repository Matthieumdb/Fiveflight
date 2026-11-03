import SwiftUI
import PDFKit

/// A FAA PDF for an airport: approach plate, airport diagram, minimums, or Chart Supplement page.
struct AirportDocument: Identifiable, Hashable {
    var id: URL { url }
    let title: String
    let url: URL
}

/// d-TPP plates and Chart Supplement pages, read from the FAA search pages (no key). PDFs are kept
/// in Caches so a plate opened once stays available offline.
enum FAADocuments {
    /// AIRAC cycle ("2611") in effect on `date`. Cycles are 28 days; 2611 started 2026-10-29.
    static func cycle(on date: Date = .now) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        var start = cal.date(from: DateComponents(year: 2026, month: 10, day: 29))!
        var year = 26, seq = 11
        while let next = cal.date(byAdding: .day, value: 28, to: start), next <= date {
            start = next
            let y = cal.component(.year, from: next) % 100
            if y != year { year = y; seq = 1 } else { seq += 1 }
        }
        while date < start, let prev = cal.date(byAdding: .day, value: -28, to: start) {
            let y = cal.component(.year, from: prev) % 100
            if y != year { year = y; seq = 13 } else { seq -= 1 }   // 13 cycles in most years
            start = prev
        }
        return String(format: "%02d%02d", year, seq)
    }

    /// Plates (IAP, DP, STAR, diagram, minimums) for `ident`, in FAA order.
    static func plates(for ident: String) async -> [AirportDocument] {
        let page = "https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/dtpp/search/results/?cycle=\(cycle())&ident=\(ident)"
        return await links(page: page, pattern: ##"<a href="(https://aeronav\.faa\.gov/d-tpp/\d+/[^"#]+\.pdf)[^"]*">([^<]+)</a>"##)
    }

    /// The Chart Supplement page(s) for `ident`.
    static func chartSupplement(for ident: String) async -> [AirportDocument] {
        let page = "https://www.faa.gov/air_traffic/flight_info/aeronav/digital_products/dafd/search/results/?cycle=\(cycle())&ident=\(ident)"
        return await links(page: page, pattern: ##"href="https?(://aeronav\.faa\.gov/afd/[^"]+/[a-z]+_\d+_[^"]+\.pdf)""##)
            .enumerated().map { AirportDocument(title: "Chart Supplement" + ($0.offset > 0 ? " (\($0.offset + 1))" : ""), url: $0.element.url) }
    }

    private static func links(page: String, pattern: String) async -> [AirportDocument] {
        guard let url = URL(string: page),
              let data = try? await NetCache.data(from: url),
              let html = String(data: data, encoding: .utf8),
              let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        var seen = Set<URL>()
        return regex.matches(in: html, range: NSRange(html.startIndex..., in: html)).compactMap { m in
            guard let r = Range(m.range(at: 1), in: html) else { return nil }
            var link = String(html[r])
            if link.hasPrefix("://") { link = "https" + link }
            guard let u = URL(string: link), seen.insert(u).inserted else { return nil }
            let title = m.numberOfRanges > 2 ? Range(m.range(at: 2), in: html).map { String(html[$0]) } : nil
            return AirportDocument(title: title?.replacingOccurrences(of: "&amp;", with: "&") ?? u.lastPathComponent, url: u)
        }
    }

    static var pdfDirectory: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("faa-pdf")
    }

    static func cacheMB() -> Double {
        let files = FileManager.default.enumerator(at: pdfDirectory, includingPropertiesForKeys: [.fileSizeKey])
        var bytes = 0
        while let f = files?.nextObject() as? URL { bytes += (try? f.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0 }
        return Double(bytes) / 1_048_576
    }

    /// Local copy of a FAA PDF, downloaded on first use.
    static func localFile(for url: URL) async throws -> URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("faa-pdf")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(url.pathComponents.suffix(2).joined(separator: "_"))
        if FileManager.default.fileExists(atPath: file.path) { return file }
        let (tmp, response) = try await URLSession.shared.download(from: url)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw URLError(.badServerResponse) }
        try? FileManager.default.removeItem(at: file)
        try FileManager.default.moveItem(at: tmp, to: file)
        return file
    }
}

// MARK: - Views

/// "Procédures & documents" section of the airport sheet.
struct AirportDocumentsSection: View {
    let ident: String
    @State private var docs: [AirportDocument]?

    var body: some View {
        Section {
            if let docs {
                if docs.isEmpty {
                    Text("Aucune plaque FAA pour ce terrain").foregroundStyle(ColorToken.textTertiary)
                }
                ForEach(docs) { doc in
                    if doc.title.localizedCaseInsensitiveContains("diagram") {
                        NavigationLink {
                            GeoDiagramScreen(document: doc, ident: ident)
                        } label: {
                            Label(doc.title, systemImage: "location.viewfinder")
                        }
                    } else {
                        NavigationLink(doc.title) { PDFDocumentScreen(document: doc) }
                    }
                }
            } else {
                HStack { ProgressView(); Text("Chargement des plaques…").foregroundStyle(ColorToken.textTertiary) }
            }
        } header: {
            Text("Plaques & Chart Supplement")
        }
        .task(id: ident) {
            async let plates = FAADocuments.plates(for: ident)
            async let cs = FAADocuments.chartSupplement(for: ident)
            docs = await cs + plates
        }
    }
}

/// Full-screen PDF (cached for offline use).
struct PDFDocumentScreen: View {
    let document: AirportDocument
    @State private var file: URL?
    @State private var failed = false

    var body: some View {
        Group {
            if let file {
                PDFKitView(url: file)
            } else if failed {
                ContentUnavailableView("PDF indisponible", systemImage: "doc.questionmark",
                                       description: Text("Pas de réseau et pas de copie hors ligne."))
            } else {
                ProgressView()
            }
        }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { if let file { ShareLink(item: file) } } }
        .task {
            do { file = try await FAADocuments.localFile(for: document.url) } catch { failed = true }
        }
    }
}

struct PDFKitView: UIViewRepresentable {
    let url: URL
    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.document = PDFDocument(url: url)
        return v
    }
    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
    }
}
