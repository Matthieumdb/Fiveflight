import SwiftUI
import MapKit

// Distinguish the two tile layers so the renderer can style them differently.
final class SectionalTileOverlay: MKTileOverlay {}
final class WeatherTileOverlay: MKTileOverlay {}
final class AirspacePolygonOverlay: MKPolygon {
    let airspaceColor: UIColor
    let isTFR: Bool
    let fillAlpha: CGFloat
    let strokeColor: UIColor
    let lineWidth: CGFloat
    let dashPattern: [NSNumber]?

    init(coordinates: UnsafePointer<CLLocationCoordinate2D>, count: Int, airspaceColor: UIColor, isTFR: Bool = false) {
        self.airspaceColor = airspaceColor
        self.isTFR = isTFR
        self.fillAlpha = isTFR ? 0.2 : 0.15
        self.strokeColor = airspaceColor
        self.lineWidth = isTFR ? 2 : 1.5
        self.dashPattern = isTFR ? [4, 4] : [8, 4]
        super.init(coordinates: coordinates, count: count)
    }

    static func make(for airspace: Airspace, color: UIColor, isTFR: Bool = false) -> AirspacePolygonOverlay {
        let coords = airspace.polygons.flatMap { $0.map(\.clCoordinate) }
        return AirspacePolygonOverlay(coordinates: coords, count: coords.count, airspaceColor: color, isTFR: isTFR)
    }
}

final class AirportAnnotation: NSObject, MKAnnotation {
    enum Role { case nearest, waypoint }
    let airport: Airport
    let role: Role
    init(_ airport: Airport, role: Role) { self.airport = airport; self.role = role }
    var coordinate: CLLocationCoordinate2D { airport.coordinate }
    var title: String? { airport.iata ?? airport.id }
    var subtitle: String? { airport.name }
}

/// MapKit map that can overlay FAA VFR sectional tiles and NEXRAD weather,
/// draw a multi-waypoint route, and show nearby airports. SwiftUI Map can't do
/// custom tile overlays, so this wraps MKMapView.
struct VFRMapView: UIViewRepresentable {
    var showSectional: Bool
    var showWeather: Bool
    var nearest: [Airport]
    var waypoints: [Airport]
    var categories: [String: String]
    var userCoord: CLLocationCoordinate2D?
    var region: MKCoordinateRegion
    var regionVersion: Int
    var onSelect: (Airport) -> Void
    var onRegionChange: (MKCoordinateRegion) -> Void = { _ in }
    var airspaces: [Airspace] = []
    var showAirspace: Bool = true
    var showTFRs: Bool = true

    // FAA official VFR sectional (ArcGIS, updated per chart cycle); ArcGIS tile = {z}/{y}/{x}.
    private static let sectionalURL =
        "https://tiles.arcgis.com/tiles/ssFJjBXIUyZDrSYZ/arcgis/rest/services/VFR_Sectional/MapServer/tile/{z}/{y}/{x}"
    // NEXRAD base reflectivity (Iowa Environmental Mesonet), standard {z}/{x}/{y}.
    private static let nexradURL =
        "https://mesonet.agron.iastate.edu/cache/tile.py/1.0.0/nexrad-n0q-900913/{z}/{x}/{y}.png"

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> MKMapView {
        let mv = MKMapView()
        mv.delegate = context.coordinator
        mv.showsUserLocation = true
        mv.pointOfInterestFilter = .excludingAll
        // VFR sectionals are light charts; keep the map base light for legibility and
        // to avoid a dark-trait tile-render glitch, while the app chrome stays dark.
        mv.overrideUserInterfaceStyle = .light
        mv.setRegion(region, animated: false)
        context.coordinator.lastVersion = regionVersion
        return mv
    }

    func updateUIView(_ mv: MKMapView, context: Context) {
        context.coordinator.parent = self

        // Update tile overlays only when toggles change
        context.coordinator.updateTileOverlays(on: mv, showSectional: showSectional, showWeather: showWeather)

        // Update route polyline
        context.coordinator.updateRoutePolyline(on: mv, waypoints: waypoints)

        // Update user location circles
        context.coordinator.updateUserCircles(on: mv, userCoord: userCoord, waypoints: waypoints)

        // Update airspace polygons (single pass, no dual TFR loop)
        context.coordinator.updateAirspacePolygons(on: mv, airspaces: airspaces, showAirspace: showAirspace, showTFRs: showTFRs, colorFor: airspaceColor, isTFR: airspaceTypeIsTFR)

        // Update annotations only when data changes
        context.coordinator.updateAnnotations(on: mv, nearest: nearest, waypoints: waypoints, categories: categories)

        // Recenter only when SwiftUI bumps the version.
        if context.coordinator.lastVersion != regionVersion {
            context.coordinator.lastVersion = regionVersion
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

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: VFRMapView
        var lastVersion = -1
        var sectionalOverlay: SectionalTileOverlay?
        var weatherOverlay: WeatherTileOverlay?
        var routePolyline: MKPolyline?
        var userCircles: [MKCircle] = []
        var airspaceOverlays: [MKPolygon] = []
        var airportAnnotations: [AirportAnnotation] = []
        var waypointAnnotations: [AirportAnnotation] = []

        init(_ parent: VFRMapView) { self.parent = parent }

        func updateTileOverlays(on mv: MKMapView, showSectional: Bool, showWeather: Bool) {
            // Sectional
            if showSectional {
                if sectionalOverlay == nil {
                    let o = SectionalTileOverlay(urlTemplate: VFRMapView.sectionalURL)
                    o.canReplaceMapContent = true
                    o.minimumZ = 6
                    o.maximumZ = 16
                    sectionalOverlay = o
                    mv.addOverlay(o, level: .aboveLabels)
                }
            } else if let overlay = sectionalOverlay {
                mv.removeOverlay(overlay)
                sectionalOverlay = nil
            }

            // Weather
            if showWeather {
                if weatherOverlay == nil {
                    let o = WeatherTileOverlay(urlTemplate: VFRMapView.nexradURL)
                    o.canReplaceMapContent = false
                    weatherOverlay = o
                    mv.addOverlay(o, level: .aboveLabels)
                }
            } else if let overlay = weatherOverlay {
                mv.removeOverlay(overlay)
                weatherOverlay = nil
            }
        }

        func updateRoutePolyline(on mv: MKMapView, waypoints: [Airport]) {
            if let existing = routePolyline {
                mv.removeOverlay(existing)
                routePolyline = nil
            }
            if waypoints.count >= 2 {
                let coords = waypoints.map(\.coordinate)
                let polyline = MKPolyline(coordinates: coords, count: coords.count)
                routePolyline = polyline
                mv.addOverlay(polyline, level: .aboveLabels)
            }
        }

        func updateUserCircles(on mv: MKMapView, userCoord: CLLocationCoordinate2D?, waypoints: [Airport]) {
            for circle in userCircles {
                mv.removeOverlay(circle)
            }
            userCircles.removeAll()

            if let uc = userCoord, waypoints.isEmpty {
                for nm in [10.0, 25.0] {
                    let circle = MKCircle(center: uc, radius: nm * 1852)
                    userCircles.append(circle)
                    mv.addOverlay(circle, level: .aboveLabels)
                }
            }
        }

        @_optimize(none)
        func updateAirspacePolygons(on mv: MKMapView, airspaces: [Airspace], showAirspace: Bool, showTFRs: Bool, colorFor: (Airspace) -> UIColor, isTFR: (Airspace) -> Bool) {
            // Remove existing
            for overlay in airspaceOverlays {
                mv.removeOverlay(overlay)
            }
            airspaceOverlays.removeAll()

            guard showAirspace || showTFRs else { return }

            for airspace in airspaces {
                guard airspace.isActive else { continue }

                let tf = isTFR(airspace)
                let shouldShow = (!tf && showAirspace) || (tf && showTFRs)
                guard shouldShow else { continue }

                let color = tf ? UIColor(ColorToken.tfr) : colorFor(airspace)

                for polygon in airspace.polygons {
                    guard polygon.count >= 3 else { continue }
                    let coords = polygon.map(\.clCoordinate)
                    let overlay = makeAirspaceOverlay(coords: coords, color: color, isTFR: tf)
                    airspaceOverlays.append(overlay)
                    mv.addOverlay(overlay, level: .aboveLabels)
                }
            }
        }

        @_optimize(none)
        private func makeAirspaceOverlay(coords: [CLLocationCoordinate2D], color: UIColor, isTFR: Bool) -> AirspacePolygonOverlay {
            AirspacePolygonOverlay(coordinates: coords, count: coords.count, airspaceColor: color, isTFR: isTFR)
        }

        func updateAnnotations(on mv: MKMapView, nearest: [Airport], waypoints: [Airport], categories: [String: String]) {
            // Check if annotations actually changed
            let newNearestIds = Set(nearest.map(\.id))
            let newWaypointIds = Set(waypoints.map(\.id))
            let currentNearestIds = Set(airportAnnotations.map { $0.airport.id })
            let currentWaypointIds = Set(waypointAnnotations.map { $0.airport.id })

            if newNearestIds == currentNearestIds && newWaypointIds == currentWaypointIds {
                return // No change
            }

            // Remove old annotations (except user location)
            let toRemove = mv.annotations.filter { !($0 is MKUserLocation) }
            mv.removeAnnotations(toRemove)

            // Add new annotations
            airportAnnotations = nearest.map { AirportAnnotation($0, role: .nearest) }
            waypointAnnotations = waypoints.map { AirportAnnotation($0, role: .waypoint) }
            mv.addAnnotations(airportAnnotations)
            mv.addAnnotations(waypointAnnotations)
        }

        func mapView(_ mv: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = .systemBlue
                r.lineWidth = 3
                r.lineDashPattern = [8, 4]
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
            if let polygon = overlay as? AirspacePolygonOverlay {
                let r = MKPolygonRenderer(polygon: polygon)
                r.fillColor = polygon.airspaceColor.withAlphaComponent(polygon.fillAlpha)
                r.strokeColor = polygon.strokeColor
                r.lineWidth = polygon.lineWidth
                r.lineDashPattern = polygon.dashPattern
                return r
            }
            return MKOverlayRenderer(overlay: overlay)
        }

        func mapView(_ mv: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let a = annotation as? AirportAnnotation else { return nil }
            let id = "airport"
            let v = (mv.dequeueReusableAnnotationView(withIdentifier: id) as? MKMarkerAnnotationView)
                ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: id)
            v.annotation = annotation
            v.canShowCallout = true
            v.rightCalloutAccessoryView = UIButton(type: .detailDisclosure)
            switch a.role {
            case .waypoint:
                v.markerTintColor = .systemGreen
                v.glyphImage = UIImage(systemName: "mappin")
                v.displayPriority = .required
            case .nearest:
                v.markerTintColor = Self.categoryColor(parent.categories[a.airport.id])
                    ?? (a.airport.type == "large_airport" ? .systemBlue : .systemTeal)
                v.glyphImage = UIImage(systemName: "airplane")
                v.displayPriority = parent.categories[a.airport.id] != nil ? .required : .defaultLow
            }
            return v
        }

        func mapView(_ mv: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            if let a = view.annotation as? AirportAnnotation { parent.onSelect(a.airport) }
        }

        func mapView(_ mv: MKMapView, regionDidChangeAnimated animated: Bool) {
            parent.onRegionChange(mv.region)
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