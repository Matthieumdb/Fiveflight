import CoreLocation

/// One airport row from the OurAirports dataset (public domain).
struct Airport: Identifiable, Hashable {
    let id: String          // OurAirports "ident" (e.g. "LFPG", "KJFK")
    let name: String
    let type: String        // large_airport, small_airport, heliport, ...
    let icao: String?
    let iata: String?
    let municipality: String?
    let elevationFt: Int?
    let coordinate: CLLocationCoordinate2D

    static func == (a: Airport, b: Airport) -> Bool { a.id == b.id }
    func hash(into h: inout Hasher) { h.combine(id) }
}

extension Airport {
    /// Great-circle distance in nautical miles to a point.
    func distanceNM(to c: CLLocationCoordinate2D) -> Double {
        Haversine.nauticalMiles(coordinate, c)
    }
}

enum Haversine {
    static func nauticalMiles(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let rEarthNM = 3440.065
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let la1 = a.latitude * .pi / 180
        let la2 = b.latitude * .pi / 180
        let h = sin(dLat/2) * sin(dLat/2)
            + cos(la1) * cos(la2) * sin(dLon/2) * sin(dLon/2)
        return rEarthNM * 2 * atan2(sqrt(h), sqrt(1 - h))
    }

    /// Initial great-circle true course from a to b, in degrees (0–360).
    static func trueCourse(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Int {
        let la1 = a.latitude * .pi / 180, la2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(la2)
        let x = cos(la1) * sin(la2) - sin(la1) * cos(la2) * cos(dLon)
        let deg = atan2(y, x) * 180 / .pi
        return (Int(deg.rounded()) % 360 + 360) % 360
    }
}
