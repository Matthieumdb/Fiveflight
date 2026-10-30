import Foundation

struct Runway: Identifiable, Hashable {
    let id = UUID()
    let leIdent: String       // e.g. "08L"
    let heIdent: String       // e.g. "26R"
    let lengthFt: Int?
    let widthFt: Int?
    let surface: String?
    let lighted: Bool
    let closed: Bool

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

struct Frequency: Identifiable, Hashable {
    let id = UUID()
    let type: String          // TWR, GND, ATIS, CTAF, ...
    let description: String
    let mhz: String           // kept as string to preserve "118.700"
}
