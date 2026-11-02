import Foundation

/// Sunrise/sunset for a lat/lon using the standard sunrise equation (NOAA-based).
/// Accurate to ~1 minute, which is plenty for VFR planning.
enum Solar {
    static func sunriseSunset(lat: Double, lon: Double, date: Date = .now) -> (sunrise: Date?, sunset: Date?) {
        let jd2000 = 2451545.0
        // Current Julian day number at local noon-ish.
        let jd = date.timeIntervalSince1970 / 86400 + 2440587.5
        let n = (jd - jd2000 + 0.0008).rounded()

        let Jstar = n - lon / 360.0
        let M = (357.5291 + 0.98560028 * Jstar).truncatingRemainder(dividingBy: 360)
        let Mr = M * .pi / 180
        let C = 1.9148 * sin(Mr) + 0.0200 * sin(2 * Mr) + 0.0003 * sin(3 * Mr)
        let lambda = (M + C + 180 + 102.9372).truncatingRemainder(dividingBy: 360)
        let lr = lambda * .pi / 180
        let Jtransit = jd2000 + Jstar + 0.0053 * sin(Mr) - 0.0069 * sin(2 * lr)

        let sinDecl = sin(lr) * sin(23.4397 * .pi / 180)
        let decl = asin(sinDecl)
        let phi = lat * .pi / 180
        let cosOmega = (sin(-0.833 * .pi / 180) - sin(phi) * sinDecl) / (cos(phi) * cos(decl))
        guard cosOmega >= -1, cosOmega <= 1 else { return (nil, nil) }   // polar day/night
        let omega = acos(cosOmega) * 180 / .pi

        func julianToDate(_ julian: Double) -> Date {
            Date(timeIntervalSince1970: (julian - 2440587.5) * 86400)
        }
        return (julianToDate(Jtransit - omega / 360), julianToDate(Jtransit + omega / 360))
    }
}
