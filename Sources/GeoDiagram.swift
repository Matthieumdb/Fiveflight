import SwiftUI
import PDFKit
import CoreLocation

/// Maps a coordinate to a point of an FAA airport diagram page (PDF user space):
/// x = a·lon + b·lat + c, y = d·lon + e·lat + f.
struct DiagramGeoref: Codable, Equatable {
    var a, b, c, d, e, f: Double
    /// How it was obtained: "PDF" (embedded geo data), "Graduations" (lat/lon labels), "Calibration".
    var method: String

    func point(_ coord: CLLocationCoordinate2D) -> CGPoint {
        CGPoint(x: a * coord.longitude + b * coord.latitude + c, y: d * coord.longitude + e * coord.latitude + f)
    }

    /// Least-squares affine fit from (lon, lat) → (x, y); needs 3+ points not on a line.
    static func fit(_ pairs: [(geo: CLLocationCoordinate2D, page: CGPoint)], method: String) -> DiagramGeoref? {
        guard pairs.count >= 3 else { return nil }
        // Normal equations for [lon lat 1] · [p q r]ᵀ = target.
        var m = [[Double]](repeating: [0, 0, 0], count: 3)
        var vx = [0.0, 0, 0], vy = [0.0, 0, 0]
        for p in pairs {
            let row = [p.geo.longitude, p.geo.latitude, 1]
            for i in 0..<3 {
                for j in 0..<3 { m[i][j] += row[i] * row[j] }
                vx[i] += row[i] * Double(p.page.x)
                vy[i] += row[i] * Double(p.page.y)
            }
        }
        guard let sx = solve3(m, vx), let sy = solve3(m, vy) else { return nil }
        return DiagramGeoref(a: sx[0], b: sx[1], c: sx[2], d: sy[0], e: sy[1], f: sy[2], method: method)
    }

    /// Similarity (scale + rotation + shift) from two points, in a local metric frame (no shear).
    static func twoPoint(_ g1: CLLocationCoordinate2D, _ p1: CGPoint, _ g2: CLLocationCoordinate2D, _ p2: CGPoint) -> DiagramGeoref? {
        let k = cos(g1.latitude * .pi / 180)
        // Geo as complex numbers (east, north) in "degrees of latitude".
        let gx1 = g1.longitude * k, gy1 = g1.latitude, gx2 = g2.longitude * k, gy2 = g2.latitude
        let dgx = gx2 - gx1, dgy = gy2 - gy1
        let den = dgx * dgx + dgy * dgy
        guard den > 1e-12 else { return nil }
        let dpx = Double(p2.x - p1.x), dpy = Double(p2.y - p1.y)
        // s = dp / dg (complex division)
        let sr = (dpx * dgx + dpy * dgy) / den, si = (dpy * dgx - dpx * dgy) / den
        // page = s · (lon·k, lat) + t
        let tx = Double(p1.x) - (sr * gx1 - si * gy1), ty = Double(p1.y) - (si * gx1 + sr * gy1)
        return DiagramGeoref(a: sr * k, b: -si, c: tx, d: si * k, e: sr, f: ty, method: "Calibration")
    }

    private static func solve3(_ m: [[Double]], _ v: [Double]) -> [Double]? {
        func det(_ a: [[Double]]) -> Double {
            a[0][0] * (a[1][1] * a[2][2] - a[1][2] * a[2][1]) - a[0][1] * (a[1][0] * a[2][2] - a[1][2] * a[2][0])
                + a[0][2] * (a[1][0] * a[2][1] - a[1][1] * a[2][0])
        }
        let dm = det(m)
        guard abs(dm) > 1e-18 else { return nil }
        return (0..<3).map { col in
            var c = m
            for r in 0..<3 { c[r][col] = v[r] }
            return det(c) / dm
        }
    }
}

/// Finds the georeference of an FAA airport diagram, best source first.
enum DiagramGeoreferencer {
    static func compute(page: PDFPage, airport: CLLocationCoordinate2D) -> DiagramGeoref? {
        let bounds = page.bounds(for: .mediaBox)
        for candidate in [embedded(page), fromLabels(page)] {
            guard let g = candidate else { continue }
            // Sanity: the airport reference point must land on the page.
            if bounds.insetBy(dx: -bounds.width * 0.1, dy: -bounds.height * 0.1).contains(g.point(airport)) { return g }
        }
        return nil
    }

    // MARK: Embedded geospatial PDF (ISO 32000 viewport /VP with /Measure /GEO)

    static func embedded(_ page: PDFPage) -> DiagramGeoref? {
        guard let dict = page.pageRef?.dictionary else { return nil }
        var vp: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, "VP", &vp), let vp else { return nil }
        for i in 0..<CGPDFArrayGetCount(vp) {
            var viewport: CGPDFDictionaryRef?
            guard CGPDFArrayGetDictionary(vp, i, &viewport), let viewport else { continue }
            var measure: CGPDFDictionaryRef?
            guard CGPDFDictionaryGetDictionary(viewport, "Measure", &measure), let measure else { continue }
            let bbox = numbers(viewport, "BBox"), gpts = numbers(measure, "GPTS"), lpts = numbers(measure, "LPTS")
            guard bbox.count == 4, gpts.count >= 6, gpts.count / 2 == lpts.count / 2 else { continue }
            let x0 = min(bbox[0], bbox[2]), y0 = min(bbox[1], bbox[3])
            let w = abs(bbox[2] - bbox[0]), h = abs(bbox[3] - bbox[1])
            var pairs: [(geo: CLLocationCoordinate2D, page: CGPoint)] = []
            for k in 0..<(gpts.count / 2) {
                pairs.append((CLLocationCoordinate2D(latitude: gpts[2 * k], longitude: gpts[2 * k + 1]),
                              CGPoint(x: x0 + lpts[2 * k] * w, y: y0 + lpts[2 * k + 1] * h)))
            }
            if let g = DiagramGeoref.fit(pairs, method: "PDF") { return g }
        }
        return nil
    }

    private static func numbers(_ dict: CGPDFDictionaryRef, _ key: String) -> [Double] {
        var arr: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, key, &arr), let arr else { return [] }
        return (0..<CGPDFArrayGetCount(arr)).compactMap { i in
            var r: CGPDFReal = 0
            if CGPDFArrayGetNumber(arr, i, &r) { return Double(r) }
            var n: CGPDFInteger = 0
            return CGPDFArrayGetInteger(arr, i, &n) ? Double(n) : nil
        }
    }

    // MARK: Latitude/longitude graduations printed on the diagram ("27°30'N", "80°22'W", "29.5'")

    static func fromLabels(_ page: PDFPage) -> DiagramGeoref? {
        guard let text = page.string,
              let full = try? NSRegularExpression(pattern: #"(\d{1,3})\s*[°º˚o]\s*(\d{1,2}(?:\.\d+)?)\s*['′’]\s*([NSEW])"#),
              let partial = try? NSRegularExpression(pattern: #"(?<![\d°º˚.])(\d{1,2}(?:\.\d+)?)\s*['′’]\s*([NSEW])?"#)
        else { return nil }
        let ns = text as NSString
        struct Label { let value: Double; let isLat: Bool; let center: CGPoint }
        var labels: [Label] = []
        var fullRanges: [NSRange] = []
        var degrees: [Bool: (deg: Double, sign: Double)] = [:]   // isLat → degrees seen
        func center(_ r: NSRange) -> CGPoint? {
            guard let sel = page.selection(for: r) else { return nil }
            let b = sel.bounds(for: page)
            return b.isEmpty ? nil : CGPoint(x: b.midX, y: b.midY)
        }
        for m in full.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard let deg = Double(ns.substring(with: m.range(at: 1))), let min = Double(ns.substring(with: m.range(at: 2))),
                  min < 60, let c = center(m.range) else { continue }
            let hemi = ns.substring(with: m.range(at: 3))
            let isLat = hemi == "N" || hemi == "S"
            let sign: Double = (hemi == "S" || hemi == "W") ? -1 : 1
            labels.append(Label(value: sign * (deg + min / 60), isLat: isLat, center: c))
            degrees[isLat] = (deg, sign)
            fullRanges.append(m.range)
        }
        // Minute-only graduations take the degrees of the full labels of the same axis.
        for m in partial.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard !fullRanges.contains(where: { NSIntersectionRange($0, m.range).length > 0 }),
                  let min = Double(ns.substring(with: m.range(at: 1))), min < 60, let c = center(m.range) else { continue }
            let hemi = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
            let axes: [Bool] = hemi.isEmpty ? [] : [hemi == "N" || hemi == "S"]
            for isLat in axes {
                guard let d = degrees[isLat] else { continue }
                labels.append(Label(value: d.sign * (d.deg + min / 60), isLat: isLat, center: c))
            }
        }
        // 1-D fits: y from latitude, x from longitude (FAA diagrams are north-up).
        func fit(_ pts: [(Double, Double)]) -> (slope: Double, offset: Double)? {
            let values = Set(pts.map { ($0.0 * 600).rounded() })
            guard values.count >= 2 else { return nil }
            let n = Double(pts.count)
            let mx = pts.map(\.0).reduce(0, +) / n, my = pts.map(\.1).reduce(0, +) / n
            let sxx = pts.map { ($0.0 - mx) * ($0.0 - mx) }.reduce(0, +)
            guard sxx > 0 else { return nil }
            let slope = pts.map { ($0.0 - mx) * ($0.1 - my) }.reduce(0, +) / sxx
            return (slope, my - slope * mx)
        }
        guard let lat = fit(labels.filter(\.isLat).map { ($0.value, Double($0.center.y)) }),
              let lon = fit(labels.filter { !$0.isLat }.map { ($0.value, Double($0.center.x)) }),
              lat.slope > 0, lon.slope > 0 else { return nil }
        // Same ground scale on both axes (within 30 %), else the labels were misread.
        let meanLat = labels.filter(\.isLat).map(\.value).reduce(0, +) / Double(max(1, labels.filter(\.isLat).count))
        let ratio = lon.slope / (lat.slope * cos(meanLat * .pi / 180))
        guard ratio > 0.7, ratio < 1.3 else { return nil }
        return DiagramGeoref(a: lon.slope, b: 0, c: lon.offset, d: 0, e: lat.slope, f: lat.offset, method: "Graduations")
    }

    // MARK: Saved calibrations

    static func saved(for key: String) -> DiagramGeoref? {
        guard let data = UserDefaults.standard.data(forKey: "georef." + key) else { return nil }
        return try? JSONDecoder().decode(DiagramGeoref.self, from: data)
    }

    static func save(_ g: DiagramGeoref?, for key: String) {
        UserDefaults.standard.set(g.flatMap { try? JSONEncoder().encode($0) }, forKey: "georef." + key)
    }
}

/// Own-aircraft symbol drawn on the diagram.
final class OwnshipPDFAnnotation: PDFAnnotation {
    var course: Double = 0

    override func draw(with box: PDFDisplayBox, in context: CGContext) {
        let r = bounds
        context.saveGState()
        context.translateBy(x: r.midX, y: r.midY)
        context.rotate(by: CGFloat(-course * .pi / 180))   // PDF y is up; course is clockwise from north
        let s = r.width / 2
        let path = CGMutablePath()
        path.move(to: CGPoint(x: 0, y: s))
        path.addLine(to: CGPoint(x: s * 0.7, y: -s * 0.7))
        path.addLine(to: CGPoint(x: 0, y: -s * 0.35))
        path.addLine(to: CGPoint(x: -s * 0.7, y: -s * 0.7))
        path.closeSubpath()
        context.addPath(path)
        context.setFillColor(UIColor.systemBlue.cgColor)
        context.setStrokeColor(UIColor.white.cgColor)
        context.setLineWidth(1.5)
        context.drawPath(using: .fillStroke)
        context.restoreGState()
    }
}

// MARK: - Screen

/// FAA airport diagram with the aircraft's GPS position (ForeFlight-style georeferenced diagram).
struct GeoDiagramScreen: View {
    let document: AirportDocument
    let ident: String
    @EnvironmentObject private var store: AirportStore
    @ObservedObject private var location = LocationManager.shared
    @State private var file: URL?
    @State private var failed = false
    @State private var georef: DiagramGeoref?
    @State private var computing = true
    /// Calibration: chosen runway end waiting for its tap, and the first point already placed.
    @State private var pendingEnd: (name: String, coord: CLLocationCoordinate2D)?
    @State private var firstPoint: (CLLocationCoordinate2D, CGPoint)?
    @State private var showPicker = false

    private var tapHandler: ((CGPoint) -> Void)? {
        guard pendingEnd != nil else { return nil }
        return { point in handleTap(point) }
    }

    private var key: String { ident + "." + document.url.lastPathComponent }
    private var airport: Airport? { store.airport(ident) }

    private var runwayEnds: [(name: String, coord: CLLocationCoordinate2D)] {
        guard let airport else { return [] }
        return store.runways(for: airport).flatMap { r -> [(name: String, coord: CLLocationCoordinate2D)] in
            var out: [(name: String, coord: CLLocationCoordinate2D)] = []
            if let la = r.leLat, let lo = r.leLon, !r.leIdent.isEmpty {
                out.append(("Seuil \(r.leIdent)", CLLocationCoordinate2D(latitude: la, longitude: lo)))
            }
            if let la = r.heLat, let lo = r.heLon, !r.heIdent.isEmpty {
                out.append(("Seuil \(r.heIdent)", CLLocationCoordinate2D(latitude: la, longitude: lo)))
            }
            return out
        }
    }

    var body: some View {
        Group {
            if let file {
                GeoPDFView(url: file, georef: georef, position: location.location,
                           course: location.course >= 0 ? location.course : location.heading,
                           onTap: tapHandler)
                    .ignoresSafeArea(edges: .bottom)
            } else if failed {
                ContentUnavailableView("Diagramme indisponible", systemImage: "doc.questionmark",
                                       description: Text("Pas de réseau et pas de copie hors ligne."))
            } else {
                ProgressView()
            }
        }
        .safeAreaInset(edge: .top) { statusBar }
        .navigationTitle(document.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button("Calibrer avec 2 seuils de piste", systemImage: "scope") { firstPoint = nil; showPicker = true }
                        .disabled(runwayEnds.count < 2)
                    if georef?.method == "Calibration" {
                        Button("Effacer la calibration", systemImage: "trash", role: .destructive) {
                            DiagramGeoreferencer.save(nil, for: key)
                            Task { await load() }
                        }
                    }
                    if let file { ShareLink(item: file) }
                } label: { Image(systemName: "ellipsis.circle") }
            }
        }
        .confirmationDialog("Point de calibration \(firstPoint == nil ? 1 : 2)", isPresented: $showPicker) {
            ForEach(runwayEnds, id: \.name) { end in
                Button(end.name) { pendingEnd = end }
            }
        }
        .task {
            location.start()
            await load()
        }
    }

    @ViewBuilder private var statusBar: some View {
        let text: String = {
            if let pendingEnd { return "Touchez \(pendingEnd.name) sur le diagramme" }
            if computing { return "Géoréférencement…" }
            guard let georef else { return "Position non disponible : calibrez avec 2 seuils (menu ⋯)" }
            let src = georef.method == "PDF" ? "données FAA du PDF"
                : georef.method == "Graduations" ? "graduations lat/lon" : "calibration manuelle"
            return "Position GPS affichée · \(src)"
        }()
        Text(text)
            .font(.caption.weight(.medium))
            .frame(maxWidth: .infinity)
            .padding(.vertical, 6)
            .background(.ultraThinMaterial)
    }

    private func load() async {
        computing = true
        defer { computing = false }
        do { file = try await FAADocuments.localFile(for: document.url) } catch { failed = true; return }
        if let saved = DiagramGeoreferencer.saved(for: key) { georef = saved; return }
        guard let file, let page = PDFDocument(url: file)?.page(at: 0), let airport else { georef = nil; return }
        georef = DiagramGeoreferencer.compute(page: page, airport: airport.coordinate)
    }

    private func handleTap(_ point: CGPoint) {
        guard let end = pendingEnd else { return }
        pendingEnd = nil
        if let first = firstPoint {
            firstPoint = nil
            if let g = DiagramGeoref.twoPoint(first.0, first.1, end.coord, point) {
                georef = g
                DiagramGeoreferencer.save(g, for: key)
                Haptics.tap()
            }
        } else {
            firstPoint = (end.coord, point)
            showPicker = true
        }
    }
}

/// PDFView showing page 1 with the ownship annotation; taps report page coordinates when calibrating.
struct GeoPDFView: UIViewRepresentable {
    let url: URL
    let georef: DiagramGeoref?
    let position: CLLocationCoordinate2D?
    let course: Double
    var onTap: ((CGPoint) -> Void)?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> PDFView {
        let v = PDFView()
        v.autoScales = true
        v.displayMode = .singlePage
        v.document = PDFDocument(url: url)
        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.tapped(_:)))
        v.addGestureRecognizer(tap)
        return v
    }

    func updateUIView(_ v: PDFView, context: Context) {
        if v.document?.documentURL != url { v.document = PDFDocument(url: url) }
        context.coordinator.onTap = onTap
        context.coordinator.pdfView = v
        guard let page = v.document?.page(at: 0) else { return }
        let c = context.coordinator
        if let old = c.ownship { page.removeAnnotation(old); c.ownship = nil }
        guard let georef, let position else { return }
        let p = georef.point(position)
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.contains(p) else { return }
        let size = max(14, bounds.width / 28)
        let a = OwnshipPDFAnnotation(bounds: CGRect(x: p.x - size / 2, y: p.y - size / 2, width: size, height: size),
                                     forType: .stamp, withProperties: nil)
        a.course = course
        page.addAnnotation(a)
        c.ownship = a
    }

    final class Coordinator: NSObject {
        var onTap: ((CGPoint) -> Void)?
        weak var pdfView: PDFView?
        var ownship: OwnshipPDFAnnotation?

        @objc func tapped(_ g: UITapGestureRecognizer) {
            guard let onTap, let v = pdfView, let page = v.document?.page(at: 0) else { return }
            onTap(v.convert(g.location(in: v), to: page))
        }
    }
}
