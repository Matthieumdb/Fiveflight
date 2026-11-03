import SwiftUI
import MapKit

/// FAA VFR Sectional tiles. When a zoom level is not published by the FAA tile cache
/// (404 or not an image), the tile is cut out of its nearest available parent and upscaled,
/// so zooming in past the chart's native resolution never leaves a grey map.
final class SectionalTileOverlay: MKTileOverlay {
    private static let maxFallbackDepth = 5

    override func loadTile(at path: MKTileOverlayPath, result: @escaping (Data?, Error?) -> Void) {
        load(path, depth: 0, result: result)
    }

    private func load(_ path: MKTileOverlayPath, depth: Int, result: @escaping (Data?, Error?) -> Void) {
        var parent = path
        parent.x = path.x >> depth
        parent.y = path.y >> depth
        parent.z = path.z - depth
        let url = self.url(forTilePath: parent)
        let cached = TileCache.file(for: url)
        let handle: (Data?, Bool, Error?) -> Void = { [weak self] data, ok, error in
            if ok, let data, let image = UIImage(data: data) {
                if depth == 0 {
                    result(data, nil)
                } else {
                    result(Self.crop(image, path: path, depth: depth, tileSize: self?.tileSize ?? CGSize(width: 256, height: 256)), nil)
                }
            } else if depth < Self.maxFallbackDepth, path.z - depth > 1, let self {
                self.load(path, depth: depth + 1, result: result)
            } else {
                result(nil, error)
            }
        }
        // Offline copy first (downloaded region or a tile seen before), then the network.
        if let data = try? Data(contentsOf: cached) { handle(data, true, nil); return }
        URLSession.shared.dataTask(with: url) { data, response, error in
            let ok = (response as? HTTPURLResponse)?.statusCode == 200
            if ok, let data { TileCache.store(data, at: cached) }
            handle(data, ok, error)
        }.resume()
    }

    /// Cuts the quadrant of `image` (a tile `depth` levels above `path`) that covers `path`, scaled to one tile.
    private static func crop(_ image: UIImage, path: MKTileOverlayPath, depth: Int, tileSize: CGSize) -> Data? {
        let factor = CGFloat(1 << depth)
        let subX = CGFloat(path.x - ((path.x >> depth) << depth))
        let subY = CGFloat(path.y - ((path.y >> depth) << depth))
        let renderer = UIGraphicsImageRenderer(size: tileSize)
        let tile = renderer.image { _ in
            image.draw(in: CGRect(x: -subX * tileSize.width, y: -subY * tileSize.height,
                                  width: tileSize.width * factor, height: tileSize.height * factor))
        }
        return tile.pngData()
    }
}

final class WeatherTileOverlay: MKTileOverlay {}
/// Styling for an airspace outline. MKPolygon cannot be subclassed with a custom initializer
/// (its `init(coordinates:count:)` is a class factory, so `super.init` crashes with
/// "unrecognized selector"), so the style is kept next to a plain MKPolygon instead.
struct AirspaceStyle {
    let color: UIColor
    let isTFR: Bool
    var fillAlpha: CGFloat { isTFR ? 0.2 : 0.15 }
    var lineWidth: CGFloat { isTFR ? 2 : 1.5 }
    var dashPattern: [NSNumber] { isTFR ? [4, 4] : [8, 4] }
}

final class AirportAnnotation: NSObject, MKAnnotation {
    enum Role { case nearest, waypoint, navaid }
    let airport: Airport
    let role: Role
    /// Settable so a plan waypoint can be dragged on the map.
    @objc dynamic var coordinate: CLLocationCoordinate2D
    init(_ airport: Airport, role: Role) { self.airport = airport; self.role = role; coordinate = airport.coordinate }
    var title: String? { airport.iata ?? airport.id }
    var subtitle: String? { airport.name }
}

/// MapKit map that can overlay FAA VFR sectional tiles and NEXRAD weather,
/// draw the planned route, and show the airports in view. SwiftUI Map can't do
/// custom tile overlays, so this wraps MKMapView.
///
/// `updateUIView` runs on every SwiftUI render, so each layer is only touched when its own
/// inputs changed (the previous version rebuilt every overlay and annotation each time).
struct VFRMapView: UIViewRepresentable {
    var showSectional: Bool
    var nearest: [Airport]
    var waypoints: [Airport]
    /// Route computed by RoutingEngine (may detour around airspace); straight legs when empty.
    var route: [CLLocationCoordinate2D] = []
    /// Flown GPS track, drawn as a solid magenta line.
    var track: [CLLocationCoordinate2D] = []
    var categories: [String: String]
    var userCoord: CLLocationCoordinate2D?
    var region: MKCoordinateRegion
    var regionVersion: Int
    var onSelect: (Airport) -> Void
    var onRegionChange: (MKCoordinateRegion) -> Void = { _ in }
    var airspaces: [Airspace] = []
    var showAirspace: Bool = true
    /// No live TFR source is wired yet, so TFR polygons stay hidden rather than showing stale data.
    var showTFRs: Bool = false

    /// FAA chart service shown when `showSectional` is on: VFR_Sectional, VFR_Terminal, IFR_AreaLow or IFR_High.
    var chart: String = MapChart.sectional.rawValue
    /// Apple satellite imagery under the chart (or alone when the chart is off).
    var satellite: Bool = false

    // FAA official charts (ArcGIS, updated per chart cycle); ArcGIS tile = {z}/{y}/{x}.
    fileprivate static func chartURL(_ service: String) -> String {
        "https://tiles.arcgis.com/tiles/ssFJjBXIUyZDrSYZ/arcgis/rest/services/\(service)/MapServer/tile/{z}/{y}/{x}"
    }
    /// Iowa Environmental Mesonet weather layers drawn over the chart, e.g. "nexrad-n0q-900913" (radar,
    /// "-m30m" for 30 min ago) or "goes-east-ir-4km-900913" (GOES infrared). Takes over from `showWeather`.
    var weatherLayers: [String] = []
    /// ADS-B targets from a GDL 90 receiver.
    var traffic: [TrafficTarget] = []
    /// VOR/NDB/fixes in view (zoomed in only).
    var navaids: [Airport] = []
    /// Glide ring around the aircraft (still air), hidden when nil.
    var glideRadiusNM: Double?
    /// Long press on the map: create a user waypoint there.
    var onLongPress: (CLLocationCoordinate2D) -> Void = { _ in }
    /// A plan waypoint was dragged to a new place.
    var onMoveWaypoint: (String, CLLocationCoordinate2D) -> Void = { _, _ in }

    static let radarFrames = ["-m50m", "-m40m", "-m30m", "-m20m", "-m10m", ""]

    fileprivate static func mesonetURL(_ layer: String) -> String {
        "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/\(layer)/{z}/{x}/{y}.png"
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.delegate = context.coordinator
        mv.showsUserLocation = true
        mv.showsCompass = true
        mv.showsScale = true
        mv.pointOfInterestFilter = .excludingAll
        // VFR sectionals are light charts; keep the map base light for legibility.
        mv.overrideUserInterfaceStyle = .light
        mv.setRegion(region, animated: false)
        context.coordinator.lastVersion = regionVersion

        // Native "locate me / follow" button.
        let tracking = MKUserTrackingButton(mapView: mv)
        tracking.translatesAutoresizingMaskIntoConstraints = false
        tracking.backgroundColor = .systemBackground
        tracking.layer.cornerRadius = 8
        tracking.layer.masksToBounds = true
        mv.addSubview(tracking)

        let press = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.longPress(_:)))
        press.minimumPressDuration = 0.5
        press.delegate = context.coordinator
        mv.addGestureRecognizer(press)
        NSLayoutConstraint.activate([
            tracking.trailingAnchor.constraint(equalTo: mv.safeAreaLayoutGuide.trailingAnchor, constant: -12),
            tracking.bottomAnchor.constraint(equalTo: mv.safeAreaLayoutGuide.bottomAnchor, constant: -16)
        ])
        return mv
    }

    func updateUIView(_ mv: MKMapView, context: Context) {
        let c = context.coordinator
        c.parent = self
        mv.mapType = satellite ? .hybrid : .standard
        c.updateTileOverlays(on: mv, showSectional: showSectional, weatherLayers: weatherLayers, chart: chart, satellite: satellite)
        c.updateRoute(on: mv, coordinates: route.count >= 2 ? route : waypoints.map(\.coordinate))
        c.updateTrack(on: mv, coordinates: track)
        c.updateUserCircles(on: mv, userCoord: waypoints.isEmpty ? userCoord : nil)
        c.updateGlideRing(on: mv, center: userCoord, radiusNM: glideRadiusNM)
        c.updateAirspacePolygons(on: mv, airspaces: airspaces, showAirspace: showAirspace, showTFRs: showTFRs,
                                 colorFor: airspaceColor, isTFR: airspaceTypeIsTFR)
        c.updateAnnotations(on: mv, nearest: nearest, waypoints: waypoints, navaids: navaids)
        c.updateTraffic(on: mv, traffic: traffic)
        c.updateCategoryColors(on: mv, categories: categories)

        // Recenter only when SwiftUI bumps the version.
        if c.lastVersion != regionVersion {
            c.lastVersion = regionVersion
            mv.setRegion(region, animated: true)
        }
    }

    // Color helpers
    private func airspaceColor(_ airspace: Airspace) -> UIColor {
        switch airspace.type {
        case .classAirspace(let cls):
            switch cls {
            case .A: return UIColor(ColorToken.classA)
            case .B: return UIColor(ColorToken.classB)
            case .C: return UIColor(ColorToken.classC)
            case .D: return UIColor(ColorToken.classD)
            case .E: return UIColor(ColorToken.classE)
            case .G: return UIColor(ColorToken.classG)
            }
        case .sua(let sua):
            switch sua {
            case .moa: return UIColor(ColorToken.moa)
            case .restricted: return UIColor(ColorToken.restricted)
            case .prohibited: return UIColor(ColorToken.prohibited)
            case .warning: return UIColor(ColorToken.warningArea)
            case .alert: return UIColor(ColorToken.alertArea)
            case .cfa: return UIColor(ColorToken.cfa)
            case .tf: return UIColor(ColorToken.tfr)
            case .nationalSecurity: return UIColor(ColorToken.nationalSecurity)
            }
        case .airway: return UIColor(ColorToken.info)
        case .classESurface: return UIColor(ColorToken.classESurface)
        }
    }

    private func airspaceTypeIsTFR(_ airspace: Airspace) -> Bool {
        if case .sua(let sua) = airspace.type, sua == .tf { return true }
        return false
    }

    final class Coordinator: NSObject, MKMapViewDelegate, UIGestureRecognizerDelegate {
        var parent: VFRMapView
        var lastVersion = -1
        private var sectionalOverlay: SectionalTileOverlay?
        private var chartKey = ""
        private var weatherOverlays: [String: WeatherTileOverlay] = [:]
        private var routeOverlay: MKPolyline?
        private var routeKey = ""
        private var trackOverlay: MKPolyline?
        private var trackKey = ""
        private var userCircles: [MKCircle] = []
        private var circleCenter: CLLocation?
        private var airspaceOverlays: [MKPolygon] = []
        private var airspaceStyles: [ObjectIdentifier: AirspaceStyle] = [:]
        private var airspaceKey = ""
        private var annotationsByKey: [String: AirportAnnotation] = [:]
        private var lastCategories: [String: String] = [:]
        private var glideCircle: MKCircle?

        init(_ parent: VFRMapView) { self.parent = parent }

        func gestureRecognizer(_ g: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool { true }

        @objc func longPress(_ g: UILongPressGestureRecognizer) {
            guard g.state == .began, let mv = g.view as? MKMapView else { return }
            let point = g.location(in: mv)
            // A long press on a marker is MapKit's drag, not a new point.
            var hit = mv.hitTest(point, with: nil)
            while let v = hit {
                if v is MKAnnotationView { return }
                hit = v.superview
            }
            let coord = mv.convert(point, toCoordinateFrom: mv)
            Haptics.tap()
            parent.onLongPress(coord)
        }

        /// Green still-air glide ring, redrawn when the aircraft moved 200 m or the radius changed 0.2 NM.
        func updateGlideRing(on mv: MKMapView, center: CLLocationCoordinate2D?, radiusNM: Double?) {
            if let old = glideCircle {
                if let center, let radiusNM, radiusNM > 0.1,
                   abs(old.radius - radiusNM * 1852) < 370,
                   CLLocation(latitude: old.coordinate.latitude, longitude: old.coordinate.longitude)
                       .distance(from: CLLocation(latitude: center.latitude, longitude: center.longitude)) < 200 {
                    return
                }
                mv.removeOverlay(old)
                glideCircle = nil
            }
            guard let center, let radiusNM, radiusNM > 0.1 else { return }
            let circle = MKCircle(center: center, radius: radiusNM * 1852)
            glideCircle = circle
            mv.addOverlay(circle, level: .aboveLabels)
        }

        func updateTileOverlays(on mv: MKMapView, showSectional: Bool, weatherLayers: [String], chart: String, satellite: Bool) {
            let chartKey = "\(chart)|\(satellite)"
            if let o = sectionalOverlay, chartKey != self.chartKey || !showSectional {
                mv.removeOverlay(o)
                sectionalOverlay = nil
            }
            self.chartKey = chartKey
            if showSectional, sectionalOverlay == nil {
                let o = SectionalTileOverlay(urlTemplate: VFRMapView.chartURL(chart))
                // TAC only exists around big airports: keep the base map visible elsewhere (and under satellite).
                o.canReplaceMapContent = !satellite && chart != MapChart.terminal.rawValue
                sectionalOverlay = o
                mv.insertOverlay(o, at: 0, level: .aboveLabels)
            } else if !showSectional, let o = sectionalOverlay {
                mv.removeOverlay(o)
                sectionalOverlay = nil
            }

            for (layer, o) in weatherOverlays where !weatherLayers.contains(layer) {
                mv.removeOverlay(o)
                weatherOverlays[layer] = nil
            }
            for layer in weatherLayers where weatherOverlays[layer] == nil {
                let o = WeatherTileOverlay(urlTemplate: VFRMapView.mesonetURL(layer))
                o.canReplaceMapContent = false
                weatherOverlays[layer] = o
                if let s = sectionalOverlay {
                    mv.insertOverlay(o, above: s)
                } else {
                    mv.insertOverlay(o, at: 0, level: .aboveLabels)
                }
            }
        }

        func updateRoute(on mv: MKMapView, coordinates: [CLLocationCoordinate2D]) {
            let key = coordinates.map { String(format: "%.5f,%.5f", $0.latitude, $0.longitude) }.joined(separator: ";")
            guard key != routeKey else { return }
            routeKey = key
            if let existing = routeOverlay {
                mv.removeOverlay(existing)
                routeOverlay = nil
            }
            guard coordinates.count >= 2 else { return }
            let polyline = MKPolyline(coordinates: coordinates, count: coordinates.count)
            routeOverlay = polyline
            mv.addOverlay(polyline, level: .aboveLabels)
        }

        func updateTrack(on mv: MKMapView, coordinates: [CLLocationCoordinate2D]) {
            let key = "\(coordinates.count)|\(coordinates.last?.latitude ?? 0)|\(coordinates.last?.longitude ?? 0)"
            guard key != trackKey else { return }
            trackKey = key
            if let old = trackOverlay { mv.removeOverlay(old); trackOverlay = nil }
            guard coordinates.count >= 2 else { return }
            let line = MKPolyline(coordinates: coordinates, count: coordinates.count)
            trackOverlay = line
            mv.addOverlay(line, level: .aboveLabels)
        }

        /// 10 and 25 NM range rings around the aircraft, redrawn only after it moved 200 m or more.
        func updateUserCircles(on mv: MKMapView, userCoord: CLLocationCoordinate2D?) {
            let newCenter = userCoord.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
            switch (circleCenter, newCenter) {
            case (nil, nil):
                return
            case let (old?, new?) where old.distance(from: new) < 200:
                return
            default:
                break
            }
            mv.removeOverlays(userCircles)
            userCircles.removeAll()
            circleCenter = newCenter
            guard let uc = userCoord else { return }
            for nm in [10.0, 25.0] {
                let circle = MKCircle(center: uc, radius: nm * 1852)
                userCircles.append(circle)
                mv.addOverlay(circle, level: .aboveLabels)
            }
        }

        func updateAirspacePolygons(on mv: MKMapView, airspaces: [Airspace], showAirspace: Bool, showTFRs: Bool,
                                    colorFor: (Airspace) -> UIColor, isTFR: (Airspace) -> Bool) {
            let key = "\(showAirspace)|\(showTFRs)|" + airspaces.map(\.id).joined(separator: ",")
            guard key != airspaceKey else { return }
            airspaceKey = key

            mv.removeOverlays(airspaceOverlays)
            airspaceOverlays.removeAll()
            airspaceStyles.removeAll()
            guard showAirspace || showTFRs else { return }

            for airspace in airspaces where airspace.isActive {
                let tf = isTFR(airspace)
                guard (tf && showTFRs) || (!tf && showAirspace) else { continue }
                // SUA out of its published hours is drawn faded.
                let base = tf ? UIColor(ColorToken.tfr) : colorFor(airspace)
                let color = airspace.suaStatus() == .inactive ? base.withAlphaComponent(0.35) : base
                for polygon in airspace.polygons where polygon.count >= 3 {
                    let coords = polygon.map(\.clCoordinate)
                    let overlay = MKPolygon(coordinates: coords, count: coords.count)
                    airspaceStyles[ObjectIdentifier(overlay)] = AirspaceStyle(color: color, isTFR: tf)
                    airspaceOverlays.append(overlay)
                }
            }
            mv.addOverlays(airspaceOverlays, level: .aboveLabels)
        }

        /// Adds/removes only the annotations that changed (keyed by role + airport id).
        func updateAnnotations(on mv: MKMapView, nearest: [Airport], waypoints: [Airport], navaids: [Airport] = []) {
            let waypointIds = Set(waypoints.map(\.id))
            var wanted: [String: (Airport, AirportAnnotation.Role)] = [:]
            for a in nearest where !waypointIds.contains(a.id) { wanted["n:\(a.id)"] = (a, .nearest) }
            for a in navaids where !waypointIds.contains(a.id) { wanted["v:\(a.type):\(a.id)"] = (a, .navaid) }
            // Keyed by position too, so a moved user point is re-added at its new place.
            for a in waypoints {
                wanted[String(format: "w:%@:%.5f,%.5f", a.id, a.coordinate.latitude, a.coordinate.longitude)] = (a, .waypoint)
            }

            let stale = annotationsByKey.filter { wanted[$0.key] == nil }
            if !stale.isEmpty {
                mv.removeAnnotations(Array(stale.values))
                for key in stale.keys { annotationsByKey.removeValue(forKey: key) }
            }
            var added: [AirportAnnotation] = []
            for (key, value) in wanted where annotationsByKey[key] == nil {
                let annotation = AirportAnnotation(value.0, role: value.1)
                annotationsByKey[key] = annotation
                added.append(annotation)
            }
            if !added.isEmpty { mv.addAnnotations(added) }
        }

        private var trafficByID: [UInt32: TrafficAnnotation] = [:]

        func updateTraffic(on mv: MKMapView, traffic: [TrafficTarget]) {
            let wanted = Dictionary(uniqueKeysWithValues: traffic.map { ($0.id, $0) })
            for (id, a) in trafficByID where wanted[id] == nil || wanted[id] != a.target {
                mv.removeAnnotation(a)
                trafficByID[id] = nil
            }
            for (id, t) in wanted where trafficByID[id] == nil {
                let a = TrafficAnnotation(t)
                trafficByID[id] = a
                mv.addAnnotation(a)
            }
        }

        /// Recolours visible markers when new METARs arrive, without re-adding them.
        func updateCategoryColors(on mv: MKMapView, categories: [String: String]) {
            guard categories != lastCategories else { return }
            lastCategories = categories
            for annotation in annotationsByKey.values where annotation.role == .nearest {
                if let view = mv.view(for: annotation) as? MKMarkerAnnotationView {
                    style(view, for: annotation)
                }
            }
        }

        private func style(_ v: MKMarkerAnnotationView, for a: AirportAnnotation) {
            switch a.role {
            case .waypoint:
                v.markerTintColor = a.airport.type == "user" ? .systemPurple : .systemGreen
                v.glyphImage = UIImage(systemName: a.airport.isAirport ? "airplane" : a.airport.symbolName)
                v.displayPriority = .required
                v.isDraggable = true
            case .navaid:
                v.markerTintColor = a.airport.type == "vor" ? .systemIndigo
                    : a.airport.type == "vfr_wp" ? .systemOrange : .systemGray
                v.glyphImage = UIImage(systemName: a.airport.symbolName)
                v.displayPriority = a.airport.type == "vor" ? .defaultHigh : .defaultLow
            case .nearest:
                let category = parent.categories[a.airport.id]
                v.markerTintColor = Self.categoryColor(category)
                    ?? (a.airport.type == "large_airport" ? .systemBlue : .systemTeal)
                v.glyphImage = UIImage(systemName: a.airport.type == "heliport" ? "h.circle" : "airplane")
                v.displayPriority = a.airport.type == "large_airport" || a.airport.type == "medium_airport"
                    ? .defaultHigh : .defaultLow
            }
            if a.role != .waypoint { v.isDraggable = false }
        }

        func mapView(_ mv: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline, line === trackOverlay {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = .systemPink
                r.lineWidth = 3
                return r
            }
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = .systemBlue
                r.lineWidth = 3
                r.lineDashPattern = [8, 4]
                return r
            }
            if let circle = overlay as? MKCircle, circle === glideCircle {
                let r = MKCircleRenderer(circle: circle)
                r.strokeColor = UIColor.systemGreen.withAlphaComponent(0.9)
                r.fillColor = UIColor.systemGreen.withAlphaComponent(0.06)
                r.lineWidth = 2.5
                return r
            }
            if let circle = overlay as? MKCircle {
                let r = MKCircleRenderer(circle: circle)
                r.strokeColor = UIColor(red: 0.18, green: 0.63, blue: 1.0, alpha: 0.45)
                r.lineWidth = 1
                r.lineDashPattern = [4, 4]
                return r
            }
            if let weather = overlay as? WeatherTileOverlay {
                let r = MKTileOverlayRenderer(tileOverlay: weather)
                r.alpha = 0.55
                return r
            }
            if let tile = overlay as? MKTileOverlay {
                return MKTileOverlayRenderer(tileOverlay: tile)
            }
            if let polygon = overlay as? MKPolygon {
                let style = airspaceStyles[ObjectIdentifier(polygon)] ?? AirspaceStyle(color: .systemBlue, isTFR: false)
                let r = MKPolygonRenderer(polygon: polygon)
                r.fillColor = style.color.withAlphaComponent(style.fillAlpha)
                r.strokeColor = style.color
                r.lineWidth = style.lineWidth
                r.lineDashPattern = style.dashPattern
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mv: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            if let t = annotation as? TrafficAnnotation {
                let v = MKAnnotationView(annotation: t, reuseIdentifier: nil)
                let config = UIImage.SymbolConfiguration(pointSize: 22, weight: .bold)
                    .applying(UIImage.SymbolConfiguration(paletteColors: [.systemOrange]))
                v.image = UIImage(systemName: "airplane", withConfiguration: config)
                // SF "airplane" points east; rotate to the target's track.
                v.transform = CGAffineTransform(rotationAngle: CGFloat(Double(t.target.trackDeg - 90) * .pi / 180))
                v.canShowCallout = true
                v.displayPriority = .required
                return v
            }
            guard let a = annotation as? AirportAnnotation else { return nil }
            let id = "airport"
            let v = (mv.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            v.annotation = annotation
            v.canShowCallout = false   // one tap opens the airport sheet directly
            v.titleVisibility = .adaptive
            style(v, for: a)
            return v
        }

        func mapView(_ mv: MKMapView, didSelect view: MKAnnotationView) {
            guard let a = view.annotation as? AirportAnnotation else { return }   // traffic shows its callout
            mv.deselectAnnotation(a, animated: false)
            parent.onSelect(a.airport)
        }

        func mapView(_ mv: MKMapView, annotationView view: MKAnnotationView,
                     didChange newState: MKAnnotationView.DragState, fromOldState oldState: MKAnnotationView.DragState) {
            guard newState == .ending || newState == .canceling else { return }
            view.dragState = .none
            guard newState == .ending, let a = view.annotation as? AirportAnnotation, a.role == .waypoint else { return }
            let id = a.airport.id, coord = a.coordinate
            DispatchQueue.main.async { [weak self] in self?.parent.onMoveWaypoint(id, coord) }
        }

        func mapView(_ mv: MKMapView, regionDidChangeAnimated animated: Bool) {
            let region = mv.region
            // Defer so SwiftUI state is never mutated in the middle of a view update.
            DispatchQueue.main.async { [weak self] in self?.parent.onRegionChange(region) }
        }

        static func categoryColor(_ cat: String?) -> UIColor? {
            switch cat {
            case "VFR":  return UIColor(red: 0.19, green: 0.82, blue: 0.35, alpha: 1)
            case "MVFR": return UIColor(red: 0.18, green: 0.63, blue: 1.0, alpha: 1)
            case "IFR":  return UIColor(red: 1.0, green: 0.27, blue: 0.23, alpha: 1)
            case "LIFR": return UIColor(red: 0.75, green: 0.35, blue: 0.95, alpha: 1)
            default:     return nil
            }
        }
    }
}

/// FAA chart services offered on the map.
enum MapChart: String, CaseIterable, Identifiable {
    case sectional = "VFR_Sectional", terminal = "VFR_Terminal", ifrLow = "IFR_AreaLow", ifrHigh = "IFR_High"
    var id: String { rawValue }
    var label: String {
        switch self {
        case .sectional: return "Sectional"
        case .terminal: return "TAC"
        case .ifrLow: return "IFR bas"
        case .ifrHigh: return "IFR haut"
        }
    }
}
