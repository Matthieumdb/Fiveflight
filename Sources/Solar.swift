import Foundation

/// Sunrise/sunset for a lat/lon using the standard sunrise equation (NOAA-based).
/// Accurate to ~1 minute, which is plenty for VFR planning.
enum Solar {
    /// `angle` is the sun's altitude at the event: −0.833° for sunrise/sunset, −6° for civil twilight.
    static func sunriseSunset(lat: Double, lon: Double, date: Date = .now, angle: Double = -0.833) -> (sunrise: Date?, sunset: Date?) {
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
        let cosOmega = (sin(angle * .pi / 180) - sin(phi) * sinDecl) / (cos(phi) * cos(decl))
        guard cosOmega >= -1, cosOmega <= 1 else { return (nil, nil) }   // polar day/night
        let omega = acos(cosOmega) * 180 / .pi

        func julianToDate(_ julian: Double) -> Date {
            Date(timeIntervalSince1970: (julian - 2440587.5) * 86400)
        }
        return (julianToDate(Jtransit - omega / 360), julianToDate(Jtransit + omega / 360))
    }

    /// Minutes of [start, end] flown at night in the 14 CFR 1.1 sense (between evening and morning civil twilight).
    static func nightMinutes(lat: Double, lon: Double, start: Date, end: Date) -> Int {
        guard end > start else { return 0 }
        var minutes = 0
        var t = start
        var cache: (day: Int, rise: Date?, set: Date?)?
        while t < end {
            let day = Int(t.timeIntervalSince1970 / 86400)
            if cache?.day != day {
                let r = sunriseSunset(lat: lat, lon: lon, date: t, angle: -6)
                cache = (day, r.sunrise, r.sunset)
            }
            if let rise = cache?.rise, let set = cache?.set, t < rise || t > set { minutes += 1 }
            t = t.addingTimeInterval(60)
        }
        return minutes
    }

    /// Night for landing currency (14 CFR 61.57(b)): from 1 h after sunset to 1 h before sunrise.
    static func isNightForLanding(lat: Double, lon: Double, at date: Date) -> Bool {
        let r = sunriseSunset(lat: lat, lon: lon, date: date)
        guard let rise = r.sunrise, let set = r.sunset else { return false }
        return date < rise.addingTimeInterval(-3600) || date > set.addingTimeInterval(3600)
    }
}
