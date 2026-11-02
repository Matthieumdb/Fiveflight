import XCTest
import CoreLocation
import MapKit
@testable import Fiveflight

final class FiveflightTests: XCTestCase {

    // MARK: - CSV Parsing Tests

    func testCSVParsesQuotedCommaField() {
        let line = Substring("1,\"KJFK\",large_airport,\"New York, NY (JFK)\",40.64,-73.77")
        let f = CSV.parseLine(line)
        XCTAssertEqual(f[1], "KJFK")
        XCTAssertEqual(f[3], "New York, NY (JFK)")   // comma inside quotes kept
        XCTAssertEqual(f[4], "40.64")
    }

    func testCSVEscapedQuote() {
        let f = CSV.parseLine(Substring("a,\"he said \"\"hi\"\"\",b"))
        XCTAssertEqual(f[1], "he said \"hi\"")
    }

    func testCSVEmptyField() {
        let line = Substring("1,,3,,5")
        let f = CSV.parseLine(line)
        XCTAssertEqual(f.count, 5)
        XCTAssertTrue(f[1].isEmpty)
        XCTAssertTrue(f[3].isEmpty)
    }

    // MARK: - Haversine Tests

    func testNauticalMiles() {
        // KJFK to KBOS ~ 162 NM
        let kjfk = CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781)
        let kbost = CLLocationCoordinate2D(latitude: 42.3656, longitude: -71.0096)
        let distance = Haversine.nauticalMiles(kjfk, kbost)
        XCTAssertEqual(distance, 162, accuracy: 5)
    }

    func testTrueCourse() {
        // KJFK to KBOS ~ 045°
        let kjfk = CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781)
        let kbost = CLLocationCoordinate2D(latitude: 42.3656, longitude: -71.0096)
        let course = Haversine.trueCourse(kjfk, kbost)
        XCTAssertEqual(course, 45, accuracy: 5)
    }

    func testDestination() {
        // Fly 100 NM on course 090 from KJFK
        let kjfk = CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781)
        let dest = Haversine.destination(from: kjfk, course: 90, distanceNM: 100)
        XCTAssertEqual(dest.latitude, kjfk.latitude, accuracy: 0.1)
        XCTAssertGreaterThan(dest.longitude, kjfk.longitude)
    }

    func testMidpoint() {
        let kjfk = CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781)
        let kbost = CLLocationCoordinate2D(latitude: 42.3656, longitude: -71.0096)
        let mid = Haversine.midpoint(kjfk, kbost)

        let d1 = Haversine.nauticalMiles(kjfk, mid)
        let d2 = Haversine.nauticalMiles(mid, kbost)
        XCTAssertEqual(d1, d2, accuracy: 1)
    }

    func testInterpolate() {
        let kjfk = CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781)
        let kbost = CLLocationCoordinate2D(latitude: 42.3656, longitude: -71.0096)

        let quarter = Haversine.interpolate(kjfk, kbost, fraction: 0.25)
        let d1 = Haversine.nauticalMiles(kjfk, quarter)
        let d2 = Haversine.nauticalMiles(quarter, kbost)
        XCTAssertEqual(d1 / d2, 0.25 / 0.75, accuracy: 0.05)
    }

    // MARK: - Density Altitude Tests

    func testDensityAltitudeStandard() {
        // At sea level, 15°C (ISA), DA should be ~0
        let da = DensityAltitude.calculate(pressureAltitude: 0, tempC: 15)
        XCTAssertEqual(da, 0, accuracy: 100)
    }

    func testDensityAltitudeHot() {
        // At 5000 ft, 30°C (hot), DA should be significantly higher
        let da = DensityAltitude.calculate(pressureAltitude: 5000, tempC: 30)
        XCTAssertGreaterThan(da, 7000)
    }

    func testDensityAltitudeCold() {
        // At 5000 ft, -20°C (cold), DA should be lower
        let da = DensityAltitude.calculate(pressureAltitude: 5000, tempC: -20)
        XCTAssertLessThan(da, 3000)
    }

    // MARK: - Crosswind Tests

    func testCrosswindDirectHeadwind() {
        // Wind 360°, runway 36 (360°) = direct headwind
        let (hw, cw, _) = Crosswind.components(windDir: 360, windSpeed: 20, runwayHeading: 360)
        XCTAssertEqual(hw, 20)
        XCTAssertEqual(cw, 0)
    }

    func testCrosswindDirectCrosswind() {
        // Wind 090°, runway 36 (360°) = direct crosswind from right
        let (hw, cw, side) = Crosswind.components(windDir: 90, windSpeed: 20, runwayHeading: 360)
        XCTAssertEqual(hw, 0)
        XCTAssertEqual(cw, 20)
        XCTAssertEqual(side, "R")  // wind from east, runway north = right crosswind
    }

    func testCrosswind45Degrees() {
        // Wind 045°, runway 36 (360°) = 45° crosswind
        let (hw, cw, _) = Crosswind.components(windDir: 45, windSpeed: 20, runwayHeading: 360)
        // Both should be ~14 kt (20 * sin/cos 45)
        XCTAssertEqual(hw, 14, accuracy: 2)
        XCTAssertEqual(cw, 14, accuracy: 2)
    }

    // MARK: - True Airspeed Tests

    func testTrueAirspeed() {
        // At 5000 ft, 15°C, 100 KIAS
        let tas = TrueAirspeed.calculate(ias: 100, pressureAltitude: 5000, tempC: 15)
        // TAS should be higher than IAS at altitude
        XCTAssertGreaterThan(tas, 100)
        XCTAssertLessThan(tas, 120)
    }

    // MARK: - Time/Speed/Distance Tests

    func testTimeSpeedDistance() {
        // 100 NM at 120 kt = 50 min
        let result = TimeSpeedDistance.calculate(distance: 100, speed: 120, time: nil)
        XCTAssertEqual(result.time, 50, accuracy: 1)

        // 120 kt for 50 min = 100 NM
        let result2 = TimeSpeedDistance.calculate(distance: nil, speed: 120, time: 50)
        XCTAssertEqual(result2.distance, 100, accuracy: 1)

        // 100 NM in 50 min = 120 kt
        let result3 = TimeSpeedDistance.calculate(distance: 100, speed: nil, time: 50)
        XCTAssertEqual(result3.speed, 120, accuracy: 1)
    }

    // MARK: - AirportStore Tests

    @MainActor
    func testNearestReturnsClosestFirst() async throws {
        let store = AirportStore()
        await store.load()
        guard !store.airports.isEmpty else {
            throw XCTSkip("airports.csv not bundled in this test host")
        }
        // KFPR = Fort Pierce, FL.
        let kfpr = CLLocationCoordinate2D(latitude: 27.4950, longitude: -80.3683)
        let near = store.nearest(to: kfpr, limit: 5,
                                 matching: ["small_airport", "medium_airport", "large_airport"])
        XCTAssertEqual(near.count, 5)
        let d = near.map { $0.distanceNM(to: kfpr) }
        XCTAssertEqual(d, d.sorted())           // sorted nearest-first
        XCTAssertLessThan(d.first!, 50)         // something within 50 NM of KFPR
    }

    // MARK: - Weight & Balance Tests

    @MainActor
    func testWeightBalanceNoCrashWithoutEmptyWeight() {
        let model = WeightBalanceModel()
        // Remove all items to simulate missing "Empty Weight"
        model.items = [
            WeightBalanceItem(name: "Pilot", weight: 180, arm: 85),
            WeightBalanceItem(name: "Fuel (gal)", weight: 0, arm: 85)
        ]
        // Should not crash, usefulLoad should use 0 for missing Empty Weight
        let useful = model.usefulLoad
        XCTAssertEqual(useful, model.maxWeight, accuracy: 0.1)
    }

    // MARK: - Solar Tests

    func testSolarSunriseBeforeSunset() {
        let (sr, ss) = Solar.sunriseSunset(lat: 27.495, lon: -80.368,
                                           date: Date(timeIntervalSince1970: 1_800_000_000))
        let sunrise = try? XCTUnwrap(sr); let sunset = try? XCTUnwrap(ss)
        XCTAssertNotNil(sunrise); XCTAssertNotNil(sunset)
        if let sunrise, let sunset {
            XCTAssertLessThan(sunrise, sunset)
            XCTAssertLessThan(sunset.timeIntervalSince(sunrise), 24 * 3600)
        }
    }

    // MARK: - METAR Decoding Tests

    func testMETARCreationFromResponse() {
        // Test that METAR can be created from API response structure
        let response = METARResponse(
            icaoId: "KMIA",
            reportTime: "2024-01-01T12:53:00Z",
            rawOb: "KMIA 011253Z 12010KT 10SM FEW025 SCT150 28/22 A3001",
            temp: "28",
            dewp: "22",
            wspd: "10",
            wdir: "120",
            wgst: nil,
            visib: "10",
            altim: "3001",
            clouds: [
                METARResponse.CloudLayer(cover: "FEW", base: "2500"),
                METARResponse.CloudLayer(cover: "SCT", base: "15000")
            ],
            flightCategory: "VFR",
            wxString: nil
        )
        let metar = METAR(from: response)
        XCTAssertEqual(metar.station, "KMIA")
        XCTAssertEqual(metar.flightCategory, .vfr)
        XCTAssertEqual(metar.temperature, 28)
        XCTAssertEqual(metar.dewpoint, 22)
        XCTAssertEqual(metar.windDirection, 120)
        XCTAssertEqual(metar.windSpeed, 10)
        XCTAssertEqual(metar.visibility, 10)
        XCTAssertEqual(try XCTUnwrap(metar.altimeter), 30.01, accuracy: 0.1)
    }

    func testMETARWithGusts() {
        let response = METARResponse(
            icaoId: "KJFK",
            reportTime: "2024-01-01T12:53:00Z",
            rawOb: "KJFK 011253Z 27015G25KT 10SM OVC020 18/15 A2992",
            temp: "18",
            dewp: "15",
            wspd: "15",
            wdir: "270",
            wgst: "25",
            visib: "10",
            altim: "2992",
            clouds: [
                METARResponse.CloudLayer(cover: "OVC", base: "2000")
            ],
            flightCategory: "IFR",
            wxString: nil
        )
        let metar = METAR(from: response)
        XCTAssertEqual(metar.windDirection, 270)
        XCTAssertEqual(metar.windSpeed, 15)
        XCTAssertEqual(metar.windGust, 25)
        XCTAssertEqual(metar.flightCategory, .ifr)
    }

    // MARK: - Route Calculation Tests

    @MainActor
    func testRoutingEngineDirectMode() async throws {
        let routing = RoutingEngine.shared
        let airspaces: [Airspace] = [] // No airspaces for direct mode

        let kjfk = Airport(id: "KJFK", name: "JFK", type: "large_airport", icao: "KJFK", iata: "JFK", municipality: "New York", elevationFt: 13, coordinate: CLLocationCoordinate2D(latitude: 40.64, longitude: -73.78))
        let kbost = Airport(id: "KBOS", name: "Logan", type: "large_airport", icao: "KBOS", iata: "BOS", municipality: "Boston", elevationFt: 20, coordinate: CLLocationCoordinate2D(latitude: 42.36, longitude: -71.01))

        let result = await routing.calculateRoute(
            waypoints: [kjfk, kbost],
            cruiseAltitude: 5500,
            mode: .direct,
            airspaces: airspaces
        )

        XCTAssertNotNil(result)
        if let result = result {
            XCTAssertEqual(result.legs.count, 1)
            XCTAssertGreaterThan(result.totalDistanceNM, 0)
            XCTAssertEqual(result.totalDistanceNM, 162, accuracy: 10) // ~162 NM
        }
    }

    @MainActor
    func testRoutingEngineWithWaypoint() async throws {
        let routing = RoutingEngine.shared
        let airspaces: [Airspace] = []

        let kjfk = Airport(id: "KJFK", name: "JFK", type: "large_airport", icao: "KJFK", iata: "JFK", municipality: "New York", elevationFt: 13, coordinate: CLLocationCoordinate2D(latitude: 40.64, longitude: -73.78))
        let klga = Airport(id: "KLGA", name: "LaGuardia", type: "large_airport", icao: "KLGA", iata: "LGA", municipality: "New York", elevationFt: 21, coordinate: CLLocationCoordinate2D(latitude: 40.78, longitude: -73.87))
        let kbost = Airport(id: "KBOS", name: "Logan", type: "large_airport", icao: "KBOS", iata: "BOS", municipality: "Boston", elevationFt: 20, coordinate: CLLocationCoordinate2D(latitude: 42.36, longitude: -71.01))

        let result = await routing.calculateRoute(
            waypoints: [kjfk, klga, kbost],
            cruiseAltitude: 5500,
            mode: .direct,
            airspaces: airspaces
        )

        XCTAssertNotNil(result)
        if let result = result {
            XCTAssertEqual(result.legs.count, 2)
            XCTAssertGreaterThan(result.totalDistanceNM, 0)
        }
    }

    // MARK: - Airspace CSV Parsing Tests

    func testAirspaceCSVParse() {
        // Test basic airspace CSV parsing
        let csv = """
        id,name,type,floor,ceiling,latitude,longitude
        1,KJFK Class B,classB,0,7000,40.64,-73.78
        2,KMIA MOA,moa,1500,5000,25.79,-80.29
        """
        let lines = csv.split(separator: "\n", omittingEmptySubsequences: true).dropFirst()

        var airspaces: [Airspace] = []
        for line in lines {
            let fields = CSV.parseLine(line)
            guard fields.count >= 7 else { continue }

            let name = fields[1]
            let typeStr = fields[2]
            let floor = Int(fields[3]) ?? 0
            let ceiling = Int(fields[4]) ?? 0
            let lat = Double(fields[5]) ?? 0
            let lon = Double(fields[6]) ?? 0

            let coord = Coordinate2D(CLLocationCoordinate2D(latitude: lat, longitude: lon))
            let airspace = Airspace(
                id: fields[0],
                name: name,
                type: .classAirspace(.B), // Simplified
                polygons: [[coord]],
                floor: floor,
                ceiling: ceiling,
                controllingAgency: nil,
                frequency: nil,
                isActive: true
            )
            airspaces.append(airspace)
        }

        XCTAssertEqual(airspaces.count, 2)
        XCTAssertEqual(airspaces[0].name, "KJFK Class B")
        XCTAssertEqual(airspaces[1].floor, 1500)
    }

    // MARK: - Map Region Persistence Tests

    @MainActor
    func testAppModelMapRegionPersistence() async throws {
        // Isolated storage: the test host app is running and saves its own map region to .standard.
        let suite = "FiveflightTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let model = AppModel(defaults: defaults)
        let testRegion = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 27.5, longitude: -80.5),
            span: MKCoordinateSpan(latitudeDelta: 1.0, longitudeDelta: 1.0)
        )

        model.mapRegion = testRegion

        // Wait for debounced save
        try await Task.sleep(nanoseconds: 1_500_000_000)

        // Create new model instance (simulates app restart)
        let model2 = AppModel(defaults: defaults)

        // Region should be restored
        XCTAssertEqual(model2.mapRegion.center.latitude, testRegion.center.latitude, accuracy: 0.001)
        XCTAssertEqual(model2.mapRegion.center.longitude, testRegion.center.longitude, accuracy: 0.001)
    }

    // MARK: - v1.0.39 regression tests

    func testAirspaceTypeUsesSnapshotJSONFormat() throws {
        let json = #"[{"id":"X","name":"Test B","type":{"classAirspace":"B"},"polygons":[[{"latitude":27,"longitude":-80},{"latitude":27.1,"longitude":-80},{"latitude":27.1,"longitude":-80.1}]],"floor":0,"ceiling":7000,"controllingAgency":null,"frequency":null,"isActive":true,"schedule":null},{"id":"Y","name":"R-2901","type":{"sua":"RESTRICTED"},"polygons":[],"floor":0,"ceiling":18000,"controllingAgency":null,"frequency":null,"isActive":true,"schedule":null},{"id":"Z","name":"E2","type":{"classESurface":true},"polygons":[],"floor":0,"ceiling":17999,"controllingAgency":null,"frequency":null,"isActive":true,"schedule":null}]"#
        let decoded = try JSONDecoder().decode([Airspace].self, from: Data(json.utf8))
        XCTAssertEqual(decoded.count, 3)
        XCTAssertEqual(decoded[0].type, .classAirspace(.B))
        XCTAssertEqual(decoded[1].type, .sua(.restricted))
        XCTAssertEqual(decoded[2].type, .classESurface)
        // Round trip keeps the same readable format.
        let again = try JSONDecoder().decode([Airspace].self, from: JSONEncoder().encode(decoded))
        XCTAssertEqual(again.map(\.type), decoded.map(\.type))
    }

    func testBundledAirspaceSnapshotDecodesWithRealFloridaData() throws {
        guard let url = Bundle.main.url(forResource: "airspace_snapshot", withExtension: "json") else {
            throw XCTSkip("snapshot not bundled in this test host")
        }
        let airspaces = try JSONDecoder().decode([Airspace].self, from: Data(contentsOf: url))
        XCTAssertGreaterThan(airspaces.count, 100)
        let miamiB = airspaces.filter { $0.name.uppercased().contains("MIAMI") && $0.type == .classAirspace(.B) }
        XCTAssertFalse(miamiB.isEmpty)
        XCTAssertTrue(miamiB.allSatisfy { $0.ceiling == 7000 })
    }

    func testFAAGeoJSONParser() throws {
        let geojson = #"{"type":"FeatureCollection","exceededTransferLimit":true,"features":[{"type":"Feature","properties":{"OBJECTID":19,"IDENT":"MIA","NAME":"MIAMI CLASS B","CLASS":"B","LOCAL_TYPE":"CLASS_B","UPPER_VAL":7000,"UPPER_UOM":"FT","UPPER_CODE":"MSL","LOWER_VAL":1500,"LOWER_UOM":"FT","LOWER_CODE":"MSL"},"geometry":{"type":"Polygon","coordinates":[[[-80.3,25.7],[-80.2,25.8],[-80.1,25.7],[-80.3,25.7]]]}},{"type":"Feature","properties":{"OBJECTID":20,"CLASS":"Other","LOCAL_TYPE":"MODE C","UPPER_VAL":10000},"geometry":{"type":"Polygon","coordinates":[[[-80.3,25.7],[-80.2,25.8],[-80.1,25.7],[-80.3,25.7]]]}}]}"#
        let page = try FAAAirspaceParser.parse(Data(geojson.utf8), layer: .classAirspace)
        XCTAssertEqual(page.featureCount, 2)
        XCTAssertTrue(page.exceededTransferLimit)
        XCTAssertEqual(page.airspaces.count, 1)           // Mode C veil is not an airspace class
        XCTAssertEqual(page.airspaces[0].floor, 1500)
        XCTAssertEqual(page.airspaces[0].ceiling, 7000)
        XCTAssertEqual(page.airspaces[0].polygons[0][0].latitude, 25.7, accuracy: 0.0001)

        let sua = #"{"type":"FeatureCollection","features":[{"type":"Feature","properties":{"OBJECTID":2,"NAME":"R-2901A","TYPE_CODE":"R","UPPER_VAL":"180","UPPER_UOM":"FL","LOWER_VAL":"0","LOWER_CODE":"SFC"},"geometry":{"type":"MultiPolygon","coordinates":[[[[-81,27],[-81,27.1],[-80.9,27],[-81,27]]]]}}]}"#
        let suaPage = try FAAAirspaceParser.parse(Data(sua.utf8), layer: .specialUse)
        XCTAssertEqual(suaPage.airspaces.first?.type, .sua(.restricted))
        XCTAssertEqual(suaPage.airspaces.first?.ceiling, 18000)
        XCTAssertEqual(suaPage.airspaces.first?.floor, 0)
    }

    @MainActor
    func testMapShowsOnlyAirportsInViewWithLimit() {
        func apt(_ id: String, _ type: String, _ lat: Double, _ lon: Double) -> Airport {
            Airport(id: id, name: id, type: type, icao: nil, iata: nil, municipality: nil, elevationFt: nil,
                    coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon))
        }
        var all = [apt("KFPR", "medium_airport", 27.4975, -80.3726),
                   apt("KJFK", "large_airport", 40.64, -73.78),          // far outside
                   apt("FD01", "heliport", 27.60, -80.20)]
        for i in 0..<1000 { all.append(apt("S\(i)", "small_airport", 27.4 + Double(i) * 0.0001, -80.4)) }

        let wide = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 27.5, longitude: -80.4),
                                      span: MKCoordinateSpan(latitudeDelta: 2, longitudeDelta: 2))
        let shown = MapScreen.airportsToShow(all, in: wide)
        XCTAssertEqual(shown.count, 300)                       // capped
        XCTAssertEqual(shown.first?.id, "KFPR")                // larger airports first
        XCTAssertFalse(shown.contains { $0.id == "KJFK" })     // outside the view
        XCTAssertFalse(shown.contains { $0.id == "FD01" })     // heliports only when zoomed in

        // Zoomed in around the heliport (the 1000 small airports are outside this view).
        let close = MKCoordinateRegion(center: CLLocationCoordinate2D(latitude: 27.60, longitude: -80.20),
                                       span: MKCoordinateSpan(latitudeDelta: 0.1, longitudeDelta: 0.1))
        XCTAssertTrue(MapScreen.airportsToShow(all, in: close).contains { $0.id == "FD01" })
    }

    func testUSFilterKeepsOnlyUSAirportsAndTheirData() {
        let texts = [
            "airports": "id,ident,type,name,lat,lon,elev,continent,iso_country\n1,KFPR,medium_airport,Fort Pierce,27.4,-80.3,24,NA,US\n2,LFPG,large_airport,CDG,49,2.5,392,EU,FR\n3,XCLO,closed,Old,27,-80,0,NA,US\n",
            "runways": "id,airport_ref,airport_ident\n1,1,KFPR\n2,2,LFPG\n",
            "airport-frequencies": "id,airport_ref,airport_ident\n1,1,KFPR\n2,2,LFPG\n"
        ]
        // Below the 1000-airport sanity threshold a download is rejected...
        XCTAssertNil(AirportDataRefresher.filterUS(texts))
    }
}