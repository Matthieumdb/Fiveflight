import Foundation

/// Minimal RFC-4180-ish CSV: handles quoted fields, embedded commas, and "" escapes.
/// Enough for the OurAirports export; not a general-purpose parser.
enum CSV {
    static func parseLine(_ line: Substring) -> [String] {
        var fields: [String] = []
        var field = ""
        var inQuotes = false
        var i = line.startIndex
        while i < line.endIndex {
            let ch = line[i]
            if inQuotes {
                if ch == "\"" {
                    let next = line.index(after: i)
                    if next < line.endIndex && line[next] == "\"" {
                        field.append("\"")   // escaped quote
                        i = next
                    } else {
                        inQuotes = false
                    }
                } else {
                    field.append(ch)
                }
            } else {
                switch ch {
                case "\"": inQuotes = true
                case ",":  fields.append(field); field = ""
                default:   field.append(ch)
                }
            }
            i = line.index(after: i)
        }
        fields.append(field)
        return fields
    }
}
