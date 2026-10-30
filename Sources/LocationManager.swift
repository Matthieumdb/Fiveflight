import CoreLocation

/// Publishes the device location (when-in-use). Falls back to nothing until authorized.
final class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var coordinate: CLLocationCoordinate2D?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func start() {
        manager.requestWhenInUseAuthorization()
        manager.startUpdatingLocation()
    }

    func locationManager(_ m: CLLocationManager, didUpdateLocations locs: [CLLocation]) {
        guard let c = locs.last?.coordinate else { return }
        coordinate = c
    }

    func locationManager(_ m: CLLocationManager, didFailWithError error: Error) {
        // Keep last known coordinate; a real app would surface this.
    }
}
