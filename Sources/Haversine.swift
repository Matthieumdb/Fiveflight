import Foundation
import CoreLocation

/// Aviation navigation calculations using Haversine formula
struct Haversine {
    private static let earthRadiusNM: Double = 3440.065  // Earth radius in nautical miles
    private static let earthRadiusKM: Double = 6371.0    // Earth radius in kilometers
    private static let deg2rad = Double.pi / 180.0
    private static let rad2deg = 180.0 / Double.pi

    /// Calculate great-circle distance between two coordinates in nautical miles
    static func nauticalMiles(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> Double {
        let lat1 = coord1.latitude * deg2rad
        let lon1 = coord1.longitude * deg2rad
        let lat2 = coord2.latitude * deg2rad
        let lon2 = coord2.longitude * deg2rad

        let dLat = lat2 - lat1
        let dLon = lon2 - lon1

        let a = sin(dLat/2) * sin(dLat/2) + cos(lat1) * cos(lat2) * sin(dLon/2) * sin(dLon/2)
        let c = 2 * atan2(sqrt(a), sqrt(1-a))

        return earthRadiusNM * c
    }

    /// Calculate great-circle distance in kilometers
    static func kilometers(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> Double {
        return nauticalMiles(coord1, coord2) * 1.852
    }

    /// Calculate initial true course from coord1 to coord2 in degrees (0-360)
    static func trueCourse(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> Int {
        let lat1 = coord1.latitude * deg2rad
        let lon1 = coord1.longitude * deg2rad
        let lat2 = coord2.latitude * deg2rad
        let lon2 = coord2.longitude * deg2rad

        let dLon = lon2 - lon1

        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)

        let bearing = atan2(y, x) * rad2deg
        let normalized = fmod(bearing + 360.0, 360.0)

        return Int(normalized.rounded())
    }

    /// Calculate magnetic course given true course and magnetic variation
    static func magneticCourse(trueCourse: Int, variation: Double) -> Int {
        let magnetic = Double(trueCourse) - variation
        let normalized = fmod(magnetic + 360.0, 360.0)
        return Int(normalized.rounded())
    }

    /// Calculate destination coordinate given start, course, and distance
    static func destination(
        from start: CLLocationCoordinate2D,
        course: Int,
        distanceNM: Double
    ) -> CLLocationCoordinate2D {
        let lat1 = start.latitude * deg2rad
        let lon1 = start.longitude * deg2rad
        let brng = Double(course) * deg2rad
        let angularDist = distanceNM / earthRadiusNM

        let lat2 = asin(sin(lat1) * cos(angularDist) + cos(lat1) * sin(angularDist) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(angularDist) * cos(lat1), cos(angularDist) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(latitude: lat2 * rad2deg, longitude: lon2 * rad2deg)
    }

    /// Calculate mid-point between two coordinates
    static func midpoint(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D) -> CLLocationCoordinate2D {
        let lat1 = coord1.latitude * deg2rad
        let lon1 = coord1.longitude * deg2rad
        let lat2 = coord2.latitude * deg2rad
        let lon2 = coord2.longitude * deg2rad

        let dLon = lon2 - lon1

        let bx = cos(lat2) * cos(dLon)
        let by = cos(lat2) * sin(dLon)

        let lat3 = atan2(sin(lat1) + sin(lat2), sqrt((cos(lat1) + bx) * (cos(lat1) + bx) + by * by))
        let lon3 = lon1 + atan2(by, cos(lat1) + bx)

        return CLLocationCoordinate2D(latitude: lat3 * rad2deg, longitude: lon3 * rad2deg)
    }

    /// Check if a coordinate is within a radius of another coordinate
    static func isWithin(_ coord: CLLocationCoordinate2D, of center: CLLocationCoordinate2D, radiusNM: Double) -> Bool {
        return nauticalMiles(coord, center) <= radiusNM
    }

    /// Interpolate between two coordinates by fraction (0.0 to 1.0)
    static func interpolate(_ coord1: CLLocationCoordinate2D, _ coord2: CLLocationCoordinate2D, fraction: Double) -> CLLocationCoordinate2D {
        let lat1 = coord1.latitude * deg2rad
        let lon1 = coord1.longitude * deg2rad
        let lat2 = coord2.latitude * deg2rad
        let lon2 = coord2.longitude * deg2rad

        let lat = lat1 + (lat2 - lat1) * fraction
        let lon = lon1 + (lon2 - lon1) * fraction

        return CLLocationCoordinate2D(latitude: lat * rad2deg, longitude: lon * rad2deg)
    }
}

// MARK: - Solar Calculations (NOAA Algorithm)

struct SolarCalculator {
    /// Sunrise/sunset (UTC instants) of the local solar day containing `date` at `coordinate`.
    /// Delegates to `Solar` so the briefing and the airport sheet show the same times.
    static func sunTimes(for coordinate: CLLocationCoordinate2D, on date: Date = Date()) -> (sunrise: Date, sunset: Date)? {
        let lonSeconds = coordinate.longitude / 360 * 86400
        let localDay = floor((date.timeIntervalSince1970 + lonSeconds) / 86400)
        let localNoon = Date(timeIntervalSince1970: localDay * 86400 + 43200 - lonSeconds)
        let r = Solar.sunriseSunset(lat: coordinate.latitude, lon: coordinate.longitude, date: localNoon)
        guard let rise = r.sunrise, let set = r.sunset else { return nil }
        return (rise, set)
    }
}

// MARK: - Coordinate Extensions

extension CLLocationCoordinate2D {
    /// Format coordinate as degrees-minutes-seconds
    func formattedDMS() -> String {
        let latDeg = Int(abs(latitude))
        let latMin = Int((abs(latitude) - Double(latDeg)) * 60)
        let latSec = ((abs(latitude) - Double(latDeg) - Double(latMin)/60) * 3600).rounded()
        let latDir = latitude >= 0 ? "N" : "S"

        let lonDeg = Int(abs(longitude))
        let lonMin = Int((abs(longitude) - Double(lonDeg)) * 60)
        let lonSec = ((abs(longitude) - Double(lonDeg) - Double(lonMin)/60) * 3600).rounded()
        let lonDir = longitude >= 0 ? "E" : "W"

        return String(format: "%02d°%02d'%02d\"%@ %03d°%02d'%02d\"%@",
                      latDeg, latMin, Int(latSec), latDir,
                      lonDeg, lonMin, Int(lonSec), lonDir)
    }

    /// Format coordinate as degrees-minutes
    func formattedDM() -> String {
        let latDeg = Int(abs(latitude))
        let latMin = (abs(latitude) - Double(latDeg)) * 60
        let latDir = latitude >= 0 ? "N" : "S"

        let lonDeg = Int(abs(longitude))
        let lonMin = (abs(longitude) - Double(lonDeg)) * 60
        let lonDir = longitude >= 0 ? "E" : "W"

        return String(format: "%02d°%05.2f'%@ %03d°%05.2f'%@",
                      latDeg, latMin, latDir,
                      lonDeg, lonMin, lonDir)
    }
}
