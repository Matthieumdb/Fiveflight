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
        for candidate in [embedded(page), lgiDict(page), fromLabels(page)] {
            guard let g = candidate else { continue }
            // Sanity: the airport reference point must land on (or near) the page.
            if bounds.insetBy(dx: -bounds.width * 0.25, dy: -bounds.height * 0.25).contains(g.point(airport)) { return g }
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
            let bbox = numbers(viewport, "BBox"), gpts = numbers(measure, "GPTS")
            var lpts = numbers(measure, "LPTS")
            guard bbox.count == 4, gpts.count >= 6 else { continue }
            // LPTS is optional: default is the BBox corners in GPTS order (ISO 32000-2, 12.10).
            let corners: [Double] = [0, 1, 0, 0, 1, 0, 1, 1]
            if lpts.count != gpts.count { lpts = Array(corners.prefix(gpts.count)) }
            guard lpts.count == gpts.count else { continue }
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

    // MARK: OGC GeoPDF (TerraGo /LGIDict, geographic projection only)

    static func lgiDict(_ page: PDFPage) -> DiagramGeoref? {
        guard let dict = page.pageRef?.dictionary else { return nil }
        var dicts: [CGPDFDictionaryRef] = []
        var single: CGPDFDictionaryRef?
        var array: CGPDFArrayRef?
        if CGPDFDictionaryGetDictionary(dict, "LGIDict", &single), let single { dicts.append(single) }
        if CGPDFDictionaryGetArray(dict, "LGIDict", &array), let array {
            for i in 0..<CGPDFArrayGetCount(array) {
                var d: CGPDFDictionaryRef?
                if CGPDFArrayGetDictionary(array, i, &d), let d { dicts.append(d) }
            }
        }
        func plausible(lon: Double, lat: Double) -> Bool { abs(lat) <= 90 && abs(lon) <= 180 }
        for lgi in dicts {
            var proj: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(lgi, "Projection", &proj), let proj,
               let type = string(proj, "ProjectionType"), type.uppercased() != "GEOGRAPHIC" { continue }
            var pairs: [(geo: CLLocationCoordinate2D, page: CGPoint)] = []
            var reg: CGPDFArrayRef?
            if CGPDFDictionaryGetArray(lgi, "Registration", &reg), let reg {
                for i in 0..<CGPDFArrayGetCount(reg) {
                    var pt: CGPDFArrayRef?
                    guard CGPDFArrayGetArray(reg, i, &pt), let pt else { continue }
                    let v = numbers(pt)
                    guard v.count >= 4, plausible(lon: v[2], lat: v[3]) else { continue }
                    pairs.append((geo: CLLocationCoordinate2D(latitude: v[3], longitude: v[2]), page: CGPoint(x: v[0], y: v[1])))
                }
            }
            if pairs.count < 3 {
                // CTM maps page space to (lon, lat): X = a·x + c·y + e, Y = b·x + d·y + f.
                let m = numbers(lgi, "CTM")
                guard m.count == 6 else { continue }
                let b = page.bounds(for: .mediaBox)
                pairs = [CGPoint(x: b.minX, y: b.minY), CGPoint(x: b.maxX, y: b.minY), CGPoint(x: b.minX, y: b.maxY),
                         CGPoint(x: b.maxX, y: b.maxY)].compactMap { (p: CGPoint) -> (geo: CLLocationCoordinate2D, page: CGPoint)? in
                    let x = Double(p.x), y = Double(p.y)
                    let lon = m[0] * x + m[2] * y + m[4], lat = m[1] * x + m[3] * y + m[5]
                    guard plausible(lon: lon, lat: lat) else { return nil }
                    return (geo: CLLocationCoordinate2D(latitude: lat, longitude: lon), page: p)
                }
            }
            if let g = DiagramGeoref.fit(pairs, method: "PDF") { return g }
        }
        return nil
    }

    private static func string(_ dict: CGPDFDictionaryRef, _ key: String) -> String? {
        var s: CGPDFStringRef?
        if CGPDFDictionaryGetString(dict, key, &s), let s, let cf = CGPDFStringCopyTextString(s) { return cf as String }
        var n: UnsafePointer<CChar>?
        if CGPDFDictionaryGetName(dict, key, &n), let n { return String(cString: n) }
        return nil
    }

    private static func numbers(_ dict: CGPDFDictionaryRef, _ key: String) -> [Double] {
        var arr: CGPDFArrayRef?
        guard CGPDFDictionaryGetArray(dict, key, &arr), let arr else { return [] }
        return numbers(arr)
    }

    /// Numbers of a PDF array; GeoPDF often stores them as strings ("(27.5)").
    private static func numbers(_ arr: CGPDFArrayRef) -> [Double] {
        (0..<CGPDFArrayGetCount(arr)).compactMap { i in
            var r: CGPDFReal = 0
            if CGPDFArrayGetNumber(arr, i, &r) { return Double(r) }
            var n: CGPDFInteger = 0
            if CGPDFArrayGetInteger(arr, i, &n) { return Double(n) }
            var s: CGPDFStringRef?
            if CGPDFArrayGetString(arr, i, &s), let s, let text = CGPDFStringCopyTextString(s) {
                return Double((text as String).trimmingCharacters(in: .whitespaces))
            }
            return nil
        }
    }

    // MARK: Latitude/longitude graduations printed on the diagram ("27°30'N", "80°22'W", "29.5'")

    static func fromLabels(_ page: PDFPage) -> DiagramGeoref? {
        guard let text = page.string,
              let full = try? NSRegularExpression(pattern: #"(\d{1,3})\s*[°º˚o]\s*(\d{1,2}(?:\.\d+)?)\s*['′’]?\s*([NSEW])"#),
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
        // Minute-only graduations ("29.5'") take the degrees of the full labels of their axis. Without a
        // hemisphere letter, the axis is the one whose first-pass fit predicts the label's position best.
        let firstLat = axisFit(labels.filter(\.isLat).map { ($0.value, $0.center) })
        let firstLon = axisFit(labels.filter { !$0.isLat }.map { ($0.value, $0.center) })
        for m in partial.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
            guard !fullRanges.contains(where: { NSIntersectionRange($0, m.range).length > 0 }),
                  let min = Double(ns.substring(with: m.range(at: 1))), min < 60, let c = center(m.range) else { continue }
            let hemi = m.range(at: 2).location != NSNotFound ? ns.substring(with: m.range(at: 2)) : ""
            var axis: Bool?
            if !hemi.isEmpty {
                axis = hemi == "N" || hemi == "S"
            } else {
                var best = Double.infinity
                for (isLat, fit) in [(true, firstLat), (false, firstLon)] {
                    guard let fit, let d = degrees[isLat] else { continue }
                    let err = fit.error(value: d.sign * (d.deg + min / 60), at: c)
                    if err < best { best = err; axis = isLat }
                }
                if best > 40 { axis = nil }   // points: too far from either axis
            }
            guard let isLat = axis, let d = degrees[isLat] else { continue }
            labels.append(Label(value: d.sign * (d.deg + min / 60), isLat: isLat, center: c))
        }
        guard let lat = axisFit(labels.filter(\.isLat).map { ($0.value, $0.center) }),
              let lon = axisFit(labels.filter { !$0.isLat }.map { ($0.value, $0.center) }),
              lat.usesY != lon.usesY else { return nil }
        // Same ground scale on both axes (within 30 %), else the labels were misread.
        let latValues = labels.filter(\.isLat).map(\.value)
        let meanLat = latValues.reduce(0, +) / Double(max(1, latValues.count))
        let ratio = abs(lon.slope) / (abs(lat.slope) * cos(meanLat * .pi / 180))
        guard ratio > 0.7, ratio < 1.3 else { return nil }
        if lat.usesY {   // north-up page
            return DiagramGeoref(a: lon.slope, b: 0, c: lon.offset, d: 0, e: lat.slope, f: lat.offset, method: "Graduations")
        }
        // Page stored rotated a quarter turn (/Rotate): x follows latitude, y follows longitude.
        return DiagramGeoref(a: 0, b: lat.slope, c: lat.offset, d: lon.slope, e: 0, f: lon.offset, method: "Graduations")
    }

    /// 1-D fit of one page coordinate (x or y, whichever correlates best) against a lat or lon value.
    struct AxisFit {
        let slope: Double, offset: Double, usesY: Bool
        func error(value: Double, at p: CGPoint) -> Double {
            abs(slope * value + offset - Double(usesY ? p.y : p.x))
        }
    }

    static func axisFit(_ pts: [(Double, CGPoint)]) -> AxisFit? {
        guard Set(pts.map { ($0.0 * 600).rounded() }).count >= 2 else { return nil }
        func fit(_ xy: [(Double, Double)]) -> (slope: Double, offset: Double, r2: Double)? {
            let n = Double(xy.count)
            let mx = xy.map(\.0).reduce(0, +) / n, my = xy.map(\.1).reduce(0, +) / n
            let sxx = xy.map { ($0.0 - mx) * ($0.0 - mx) }.reduce(0, +)
            let syy = xy.map { ($0.1 - my) * ($0.1 - my) }.reduce(0, +)
            let sxy = xy.map { ($0.0 - mx) * ($0.1 - my) }.reduce(0, +)
            guard sxx > 0, syy > 0 else { return nil }
            return (sxy / sxx, my - sxy / sxx * mx, sxy * sxy / (sxx * syy))
        }
        let fy = fit(pts.map { ($0.0, Double($0.1.y)) }), fx = fit(pts.map { ($0.0, Double($0.1.x)) })
        let pick: (fit: (slope: Double, offset: Double, r2: Double), usesY: Bool)?
        switch (fy, fx) {
        case let (y?, x?): pick = y.r2 >= x.r2 ? (y, true) : (x, false)
        case let (y?, nil): pick = (y, true)
        case let (nil, x?): pick = (x, false)
        default: pick = nil
        }
        guard let pick, pick.fit.r2 > 0.9 else { return nil }
        return AxisFit(slope: pick.fit.slope, offset: pick.fit.offset, usesY: pick.usesY)
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

/// FAA airport diagram or plate with the aircraft's GPS position (ForeFlight-style georeferenced plate).
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
    @State private var pageBounds: CGRect?

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

    /// Whether the GPS fix falls on the page once georeferenced.
    private var onPage: Bool {
        guard let georef, let here = location.location, let pageBounds else { return false }
        return pageBounds.contains(georef.point(here))
    }

    @ViewBuilder private var statusBar: some View {
        let text: String = {
            if let pendingEnd { return "Touchez \(pendingEnd.name) sur la plaque" }
            if computing { return "Géoréférencement…" }
            switch location.authorizationStatus {
            case .denied, .restricted: return "Localisation refusée : Réglages › Fiveflight › Position"
            default: break
            }
            guard let georef else { return "Plaque non géoréférencée : calibrez avec 2 seuils (menu ⋯)" }
            guard let here = location.location else { return "En attente du GPS…" }
            if !onPage, let airport {
                return String(format: "Hors de la plaque · vous êtes à %.1f NM de %@", airport.distanceNM(to: here), ident)
            }
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
        let page = file.flatMap { PDFDocument(url: $0)?.page(at: 0) }
        pageBounds = page?.bounds(for: .mediaBox)
        if let saved = DiagramGeoreferencer.saved(for: key) { georef = saved; return }
        guard let page, let airport else { georef = nil; return }
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
