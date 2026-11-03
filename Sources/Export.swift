import Foundation
import CoreLocation

/// GPX and KML files for a flight plan and/or a flown track, written to the temp dir for sharing.
enum FlightExport {
    struct Point { let name: String; let coordinate: CLLocationCoordinate2D }

    static func gpx(name: String, route: [Point], track: [CLLocationCoordinate2D]) -> URL? {
        var s = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        s += #"<gpx version="1.1" creator="Fiveflight" xmlns="http://www.topografix.com/GPX/1/1">"# + "\n"
        if !route.isEmpty {
            s += "<rte><name>\(escape(name))</name>\n"
            for p in route {
                s += String(format: #"<rtept lat="%.6f" lon="%.6f"><name>%@</name></rtept>"#,
                            p.coordinate.latitude, p.coordinate.longitude, escape(p.name)) + "\n"
            }
            s += "</rte>\n"
        }
        if !track.isEmpty {
            s += "<trk><name>\(escape(name))</name><trkseg>\n"
            for c in track { s += String(format: #"<trkpt lat="%.6f" lon="%.6f"/>"#, c.latitude, c.longitude) + "\n" }
            s += "</trkseg></trk>\n"
        }
        s += "</gpx>\n"
        return write(s, file: name, ext: "gpx")
    }

    static func kml(name: String, route: [Point], track: [CLLocationCoordinate2D]) -> URL? {
        func line(_ title: String, _ coords: [CLLocationCoordinate2D], color: String) -> String {
            "<Placemark><name>\(escape(title))</name><Style><LineStyle><color>\(color)</color><width>3</width></LineStyle></Style>"
                + "<LineString><tessellate>1</tessellate><coordinates>"
                + coords.map { String(format: "%.6f,%.6f,0", $0.longitude, $0.latitude) }.joined(separator: " ")
                + "</coordinates></LineString></Placemark>\n"
        }
        var s = #"<?xml version="1.0" encoding="UTF-8"?>"# + "\n"
        s += #"<kml xmlns="http://www.opengis.net/kml/2.2"><Document>"# + "<name>\(escape(name))</name>\n"
        if route.count >= 2 { s += line("Route", route.map(\.coordinate), color: "ffff8800") }
        for p in route {
            s += String(format: "<Placemark><name>%@</name><Point><coordinates>%.6f,%.6f,0</coordinates></Point></Placemark>\n",
                        escape(p.name), p.coordinate.longitude, p.coordinate.latitude)
        }
        if track.count >= 2 { s += line("Trace", track, color: "ffff00ff") }
        s += "</Document></kml>\n"
        return write(s, file: name, ext: "kml")
    }

    private static func write(_ text: String, file: String, ext: String) -> URL? {
        let safe = file.replacingOccurrences(of: "[^A-Za-z0-9_-]+", with: "-", options: .regularExpression)
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("fiveflight-\(safe).\(ext)")
        do { try text.write(to: url, atomically: true, encoding: .utf8); return url } catch { return nil }
    }

    private static func escape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
    }
}
