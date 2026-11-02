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

        // Overlays: rebuild from toggles.
        mv.removeOverlays(mv.overlays)
        if showSectional {
            let o = SectionalTileOverlay(urlTemplate: Self.sectionalURL)
            o.canReplaceMapContent = true
            mv.addOverlay(o, level: .aboveLabels)
        }
        if showWeather {
            let o = WeatherTileOverlay(urlTemplate: Self.nexradURL)
            o.canReplaceMapContent = false
            mv.addOverlay(o, level: .aboveLabels)
        }
        if waypoints.count >= 2 {
            let coords = waypoints.map(\.coordinate)
            mv.addOverlay(MKPolyline(coordinates: coords, count: coords.count), level: .aboveLabels)
        }
        if let uc = userCoord, waypoints.isEmpty {
            for nm in [10.0, 25.0] {
                mv.addOverlay(MKCircle(center: uc, radius: nm * 1852), level: .aboveLabels)
            }
        }

        // Airspace polygons
        if showAirspace {
            for airspace in airspaces {
                guard airspace.isActive else { continue }
                let color = airspaceColor(airspace)
                // Add each polygon ring
                for polygon in airspace.polygons {
                    guard polygon.count >= 3 else { continue }
                    let coords = polygon.map(\.clCoordinate)
                    let overlay = MKPolygon(coordinates: coords, count: coords.count)
                    // Store color in renderer via coordinator lookup
                    context.coordinator.airspaceColors[overlay] = color
                    mv.addOverlay(overlay, level: .aboveLabels)
                }
            }
        }
        if showTFRs {
            for airspace in airspaces {
                guard airspace.isActive, airspaceTypeIsTFR(airspace) else { continue }
                let color = UIColor(ColorToken.tfr)
                for polygon in airspace.polygons {
                    guard polygon.count >= 3 else { continue }
                    let coords = polygon.map(\.clCoordinate)
                    let overlay = MKPolygon(coordinates: coords, count: coords.count)
                    context.coordinator.airspaceColors[overlay] = color
                    mv.addOverlay(overlay, level: .aboveLabels)
                }
            }
        }

        // Annotations: nearest + waypoints (drop and rebuild).
        mv.removeAnnotations(mv.annotations.filter { !($0 is MKUserLocation) })
        mv.addAnnotations(nearest.map { AirportAnnotation($0, role: .nearest) })
        mv.addAnnotations(waypoints.map { AirportAnnotation($0, role: .waypoint) })

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
        var airspaceColors: [MKPolygon: UIColor] = [:]
        init(_ parent: VFRMapView) { self.parent = parent }

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
            if let polygon = overlay as? MKPolygon {
                let r = MKPolygonRenderer(polygon: polygon)
                let color = airspaceColors[polygon] ?? .systemBlue
                r.fillColor = color.withAlphaComponent(0.15)
                r.strokeColor = color
                r.lineWidth = 1.5
                r.lineDashPattern = [8, 4]
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