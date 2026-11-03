import Foundation
import CoreLocation

/// Whether a special use airspace is in use now, read from its published times of use
/// (e.g. "INTERMITTENT, 0600 - 2400, MON - FRI; 0800 - 1800, SAT - SUN; O/T BY NOTAM").
/// The FAA live SUA status service is not reachable without an agreement, so this is the schedule only:
/// "inactive" never rules out an activation by NOTAM.
enum SUAStatus: Equatable {
    case active, inactive, byNotam

    var label: String {
        switch self {
        case .active: return "Active selon l'horaire"
        case .inactive: return "Inactive selon l'horaire (sauf NOTAM)"
        case .byNotam: return "Activée par NOTAM"
        }
    }

    /// Times are local (Florida: America/New_York) unless the text says otherwise.
    static func of(_ schedule: String?, at date: Date = .now, near point: CLLocationCoordinate2D,
                   timeZone: TimeZone = TimeZone(identifier: "America/New_York")!) -> SUAStatus {
        guard let raw = schedule?.uppercased(), !raw.isEmpty else { return .byNotam }
        if raw.contains("CONTINUOUS") { return .active }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        let weekday = (cal.component(.weekday, from: date) + 5) % 7   // MON = 0 … SUN = 6
        let month = cal.component(.month, from: date)
        let minute = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        let sun = Solar.sunriseSunset(lat: point.latitude, lon: point.longitude, date: date)
        func minutes(_ d: Date?) -> Int? { d.map { cal.component(.hour, from: $0) * 60 + cal.component(.minute, from: $0) } }

        var parsedAny = false
        for segment in raw.split(separator: ";").map(String.init) {
            if let months = monthRange(segment), !months.contains(month) { parsedAny = true; continue }
            let times: (Int, Int)?
            if segment.contains("SUNRISE") || segment.contains("SUNSET") || segment.contains("DAYLIGHT") {
                let start = segment.contains("SUNRISE -") || segment.contains("DAYLIGHT") ? minutes(sun.sunrise) : clock(segment, first: true)
                let end = segment.contains("- SUNSET") || segment.contains("DAYLIGHT") ? minutes(sun.sunset) : clock(segment, first: false)
                times = start.flatMap { s in end.map { (s, $0) } }
            } else if let s = clock(segment, first: true), let e = clock(segment, first: false) {
                times = (s, e)
            } else {
                times = nil
            }
            guard let (start, end) = times, let days = dayRange(segment) else { continue }
            parsedAny = true
            // A window past midnight (0800 - 0100) counts for the next morning of the listed day.
            let yesterday = (weekday + 6) % 7
            if end > start {
                if days.contains(weekday), minute >= start, minute < end { return .active }
            } else {
                if days.contains(weekday), minute >= start { return .active }
                if days.contains(yesterday), minute < end { return .active }
            }
        }
        return parsedAny ? .inactive : .byNotam
    }

    /// "0600 - 2400" → 360 / 1440 (first or second time of the segment).
    private static func clock(_ s: String, first: Bool) -> Int? {
        let regex = try! NSRegularExpression(pattern: #"\b(\d{4})\s*-\s*(\d{4})\b"#)
        guard let m = regex.firstMatch(in: s, range: NSRange(s.startIndex..., in: s)),
              let r = Range(m.range(at: first ? 1 : 2), in: s), let v = Int(s[r]) else { return nil }
        return (v / 100) * 60 + v % 100
    }

    private static let dayNames = ["MON", "TUE", "WED", "THU", "FRI", "SAT", "SUN"]
    private static let monthNames = ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]

    /// Days a segment applies to (MON = 0); nil when it names none.
    private static func dayRange(_ s: String) -> Set<Int>? {
        if s.contains("DAILY") { return Set(0..<7) }
        return range(in: s, names: dayNames)
    }

    /// Months (1…12) for "APR - AUG," style prefixes; nil when the segment names no month.
    private static func monthRange(_ s: String) -> Set<Int>? {
        range(in: s, names: monthNames).map { Set($0.map { $0 + 1 }) }
    }

    private static func range(in s: String, names: [String]) -> Set<Int>? {
        let alternation = names.joined(separator: "|")
        let regex = try! NSRegularExpression(pattern: "\\b(\(alternation))\\b(?:\\s*-\\s*\\b(\(alternation))\\b)?")
        var out = Set<Int>()
        for m in regex.matches(in: s, range: NSRange(s.startIndex..., in: s)) {
            guard let r1 = Range(m.range(at: 1), in: s), let a = names.firstIndex(of: String(s[r1])) else { continue }
            if let r2 = Range(m.range(at: 2), in: s), let b = names.firstIndex(of: String(s[r2])) {
                var i = a
                while true { out.insert(i); if i == b { break }; i = (i + 1) % names.count }
            } else {
                out.insert(a)
            }
        }
        return out.isEmpty ? nil : out
    }
}

extension Airspace {
    /// Schedule-based status for SUA; nil for other airspace (always there).
    func suaStatus(at date: Date = .now) -> SUAStatus? {
        guard case .sua(let type) = self.type, type != .tf else { return nil }
        let p = polygons.first?.first.map(\.clCoordinate) ?? CLLocationCoordinate2D(latitude: 27, longitude: -81)
        return SUAStatus.of(schedule, at: date, near: p)
    }
}
