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
    private static let deg2rad = Double.pi / 180.0
    private static let rad2deg = 180.0 / Double.pi

    /// Calculate sunrise/sunset times for a coordinate on a given date
    static func sunTimes(for coordinate: CLLocationCoordinate2D, on date: Date = Date()) -> (sunrise: Date, sunset: Date)? {
        let calendar = Calendar.current
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else { return nil }

        let latitude = coordinate.latitude
        let longitude = coordinate.longitude

        // Day of year
        let dayOfYear = dayOfYear(year: year, month: month, day: day)

        // Julian day
        let jd = julianDay(year: year, month: month, day: day)

        // Solar noon
        let solarNoon = solarNoonUTC(julianDay: jd, longitude: longitude)

        // Sun declination
        let declination = sunDeclination(julianDay: jd)

        // Hour angle
        let hourAngle = hourAngle(latitude: latitude, declination: declination)

        // Sunrise/sunset in UTC
        let sunriseUTC = solarNoon - hourAngle / 15.0
        let sunsetUTC = solarNoon + hourAngle / 15.0

        // Convert to local time (simplified - would need timezone lookup for accuracy)
        let sunrise = Date(timeIntervalSince1970: sunriseUTC * 3600)
        let sunset = Date(timeIntervalSince1970: sunsetUTC * 3600)

        return (sunrise, sunset)
    }

    private static func dayOfYear(year: Int, month: Int, day: Int) -> Int {
        let calendar = Calendar.current
        let startOfYear = calendar.date(from: DateComponents(year: year, month: 1, day: 1))!
        let date = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return calendar.dateComponents([.day], from: startOfYear, to: date).day! + 1
    }

    private static func julianDay(year: Int, month: Int, day: Int) -> Double {
        var y = Double(year)
        var m = Double(month)
        let d = Double(day)

        if m <= 2 {
            y -= 1
            m += 12
        }

        let a = floor(y / 100)
        let b = 2 - a + floor(a / 4)

        return floor(365.25 * (y + 4716)) + floor(30.6001 * (m + 1)) + d + b - 1524.5
    }

    private static func solarNoonUTC(julianDay: Double, longitude: Double) -> Double {
        let n = julianDay - 2451545.0
        let meanLong = fmod(280.460 + 0.9856474 * n, 360.0)
        let meanAnomaly = fmod(357.528 + 0.9856003 * n, 360.0)
        let eclipticLong = meanLong + 1.915 * sin(meanAnomaly * deg2rad) + 0.020 * sin(2 * meanAnomaly * deg2rad)
        let eqTime = 4 * (meanLong - 0.0057183 - eclipticLong + 1.915 * sin(meanAnomaly * deg2rad) + 0.020 * sin(2 * meanAnomaly * deg2rad))
        let solarNoon = 12.0 - eqTime / 60.0 - longitude / 15.0
        return solarNoon
    }

    private static func sunDeclination(julianDay: Double) -> Double {
        let n = julianDay - 2451545.0
        let meanLong = fmod(280.460 + 0.9856474 * n, 360.0)
        let meanAnomaly = fmod(357.528 + 0.9856003 * n, 360.0)
        let eclipticLong = meanLong + 1.915 * sin(meanAnomaly * deg2rad) + 0.020 * sin(2 * meanAnomaly * deg2rad)
        let obliquity = 23.439 - 0.0000004 * n
        return asin(sin(obliquity * deg2rad) * sin(eclipticLong * deg2rad)) * rad2deg
    }

    private static func hourAngle(latitude: Double, declination: Double) -> Double {
        let latRad = latitude * deg2rad
        let decRad = declination * deg2rad

        let cosHourAngle = (sin(-0.833 * deg2rad) - sin(latRad) * sin(decRad)) / (cos(latRad) * cos(decRad))

        if cosHourAngle > 1.0 { return 0 } // Polar day
        if cosHourAngle < -1.0 { return 180 } // Polar night

        return acos(cosHourAngle) * rad2deg
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