import Foundation

struct Runway: Identifiable, Hashable, Codable {
    let id = UUID()
    let leIdent: String       // e.g. "08L"
    let heIdent: String       // e.g. "26R"
    let lengthFt: Int?
    let widthFt: Int?
    let surface: String?
    let lighted: Bool
    let closed: Bool
    /// True headings and threshold positions of the two ends, when OurAirports has them (1.0.47).
    var leHeadingT: Double? = nil
    var heHeadingT: Double? = nil
    var leLat: Double? = nil, leLon: Double? = nil
    var heLat: Double? = nil, heLon: Double? = nil

    /// Each usable end: ident and true heading (from the data, else ident × 10° ± 180°).
    var ends: [(ident: String, headingT: Double)] {
        func number(_ ident: String) -> Double? {
            let digits = ident.prefix { $0.isNumber }
            return Double(digits).map { $0 * 10 }
        }
        var out: [(String, Double)] = []
        if !leIdent.isEmpty, let h = leHeadingT ?? number(leIdent) ?? heHeadingT.map({ ($0 + 180).truncatingRemainder(dividingBy: 360) }) {
            out.append((leIdent, h))
        }
        if !heIdent.isEmpty, let h = heHeadingT ?? number(heIdent) ?? leHeadingT.map({ ($0 + 180).truncatingRemainder(dividingBy: 360) }) {
            out.append((heIdent, h))
        }
        return out
    }

    /// Paved (asphalt/concrete) or not, from the OurAirports surface code.
    var isPaved: Bool {
        let s = (surface ?? "").uppercased()
        return ["ASP", "CON", "PEM", "BIT", "TAR"].contains { s.hasPrefix($0) || s.contains($0) }
    }

    /// "08L/26R" (falls back to whichever end exists).
    var name: String {
        switch (leIdent.isEmpty, heIdent.isEmpty) {
        case (false, false): return "\(leIdent)/\(heIdent)"
        case (false, true):  return leIdent
        case (true, false):  return heIdent
        case (true, true):   return "RWY"
        }
    }
}

struct Frequency: Identifiable, Hashable, Codable {
    let id = UUID()
    let type: String          // TWR, GND, ATIS, CTAF, ...
    let description: String
    let mhz: String           // kept as string to preserve "118.700"
}