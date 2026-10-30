import SwiftUI
import MapKit

// Distinguish the two tile layers so the renderer can style them differently.
final class SectionalTileOverlay: MKTileOverlay {}
final class WeatherTileOverlay: MKTileOverlay {}

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
    var region: MKCoordinateRegion
    var regionVersion: Int
    var onSelect: (Airport) -> Void

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

    final class Coordinator: NSObject, MKMapViewDelegate {
        var parent: VFRMapView
        var lastVersion = -1
        init(_ parent: VFRMapView) { self.parent = parent }

        func mapView(_ mv: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            if let line = overlay as? MKPolyline {
                let r = MKPolylineRenderer(polyline: line)
                r.strokeColor = .systemBlue
                r.lineWidth = 3
                r.lineDashPattern = [8, 4]
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
                v.markerTintColor = a.airport.type == "large_airport" ? .systemBlue : .systemTeal
                v.glyphImage = UIImage(systemName: "airplane")
                v.displayPriority = .defaultLow
            }
            return v
        }

        func mapView(_ mv: MKMapView, annotationView view: MKAnnotationView,
                     calloutAccessoryControlTapped control: UIControl) {
            if let a = view.annotation as? AirportAnnotation { parent.onSelect(a.airport) }
        }
    }
}
