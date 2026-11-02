import CoreLocation

/// One airport row from the OurAirports dataset (public domain).
struct Airport: Identifiable, Hashable, Codable {
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

    enum CodingKeys: String, CodingKey {
        case id, name, type, icao, iata, municipality, elevationFt, latitude, longitude
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        type = try container.decode(String.self, forKey: .type)
        icao = try container.decodeIfPresent(String.self, forKey: .icao)
        iata = try container.decodeIfPresent(String.self, forKey: .iata)
        municipality = try container.decodeIfPresent(String.self, forKey: .municipality)
        elevationFt = try container.decodeIfPresent(Int.self, forKey: .elevationFt)
        let latitude = try container.decode(Double.self, forKey: .latitude)
        let longitude = try container.decode(Double.self, forKey: .longitude)
        coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encode(type, forKey: .type)
        try container.encodeIfPresent(icao, forKey: .icao)
        try container.encodeIfPresent(iata, forKey: .iata)
        try container.encodeIfPresent(municipality, forKey: .municipality)
        try container.encodeIfPresent(elevationFt, forKey: .elevationFt)
        try container.encode(coordinate.latitude, forKey: .latitude)
        try container.encode(coordinate.longitude, forKey: .longitude)
    }

    init(id: String, name: String, type: String, icao: String?, iata: String?, municipality: String?, elevationFt: Int?, coordinate: CLLocationCoordinate2D) {
        self.id = id
        self.name = name
        self.type = type
        self.icao = icao
        self.iata = iata
        self.municipality = municipality
        self.elevationFt = elevationFt
        self.coordinate = coordinate
    }
}

extension Airport {
    /// Great-circle distance in nautical miles to a point.
    func distanceNM(to c: CLLocationCoordinate2D) -> Double {
        Haversine.nauticalMiles(coordinate, c)
    }
}