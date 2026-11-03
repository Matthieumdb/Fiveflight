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

    // MARK: - Weather decoding (real aviationweather.gov payloads in Tests/Fixtures)

    private func fixture(_ name: String, _ ext: String) throws -> Data {
        let url = try XCTUnwrap(Bundle(for: FiveflightTests.self).url(forResource: name, withExtension: ext),
                                "missing fixture \(name).\(ext)")
        return try Data(contentsOf: url)
    }

    func testMETARFixtureDecodesWithFlightCategories() throws {
        let data = try fixture("metar", "json")
        let raw = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let decoded = try JSONDecoder().decode([METARResponse].self, from: data)
        XCTAssertEqual(decoded.count, raw.count)
        XCTAssertFalse(decoded.isEmpty)
        for response in decoded {
            let metar = METAR(from: response)
            if response.fltCat != nil { XCTAssertNotEqual(metar.flightCategory, .unknown, metar.station) }
            if let altim = metar.altimeter { XCTAssertEqual(altim, 30, accuracy: 1.5, metar.station) }
            XCTAssertLessThan(abs(metar.observationTime.timeIntervalSinceNow), 400 * 24 * 3600)
        }
    }

    func testMETARDecodesMixedTypes() throws {
        let json = """
        [{"icaoId":"KFPR","obsTime":1793649180,"rawOb":"METAR KFPR 021953Z VRB05KT 3SM RA BR BKN009 OVC015 23/22 A2998",
          "temp":22.8,"dewp":22.2,"wdir":"VRB","wspd":5,"visib":3,"altim":1015.3,
          "clouds":[{"cover":"FEW","base":400},{"cover":"BKN","base":900},{"cover":"OVC","base":1500}],"fltCat":"IFR"},
         {"icaoId":"KMIA","obsTime":1793649180,"rawOb":"KMIA 12010G18KT 10SM FEW025","temp":28,"dewp":22,
          "wdir":120,"wspd":10,"wgst":18,"visib":"10+","altim":1016.3,"clouds":[{"cover":"FEW","base":2500}]}]
        """
        let list = try JSONDecoder().decode([METARResponse].self, from: Data(json.utf8)).map(METAR.init(from:))
        XCTAssertEqual(list[0].flightCategory, .ifr)
        XCTAssertEqual(list[0].ceiling, 900)
        XCTAssertNil(list[0].windDirection)
        XCTAssertEqual(list[0].decoded?.wind, "VRB @ 5kt")
        XCTAssertEqual(list[0].temperature, 23)
        XCTAssertEqual(try XCTUnwrap(list[0].altimeter), 29.98, accuracy: 0.01)
        // No fltCat: computed from visibility 10+ and no ceiling.
        XCTAssertEqual(list[1].flightCategory, .vfr)
        XCTAssertEqual(list[1].windDirection, 120)
        XCTAssertEqual(list[1].windGust, 18)
        XCTAssertEqual(list[1].visibility, 10)
    }

    func testTAFFixtureDecodes() throws {
        let data = try fixture("taf", "json")
        let decoded = try JSONDecoder().decode([TAFResponse].self, from: data)
        XCTAssertFalse(decoded.isEmpty)
        for response in decoded {
            let taf = TAF(from: response)
            XCTAssertGreaterThan(taf.validTo, taf.validFrom)
            XCTAssertFalse(taf.forecasts.isEmpty, taf.station)
        }
    }

    func testFlexValueNumbers() {
        XCTAssertEqual(FlexValue("10+").number, 10)
        XCTAssertEqual(FlexValue("6+").number, 6)
        XCTAssertEqual(FlexValue("1 1/2").number, 1.5)
        XCTAssertEqual(FlexValue("1/4").number, 0.25)
        XCTAssertNil(FlexValue("VRB").number)
    }

    func testWindsAloftFDParsing() throws {
        let text = """
        VALID 030000Z   FOR USE 2000-0300Z. TEMPS NEG ABV 24000

        FT  3000    6000    9000   12000   18000   24000  30000  34000  39000
        MIA 1018 1311+15 1616+10 1827+04 2220-07 2109-18 180533 200844 201657
        PIE      9900+14 7315+09 1512+04 0914-06 0532-18 350534 250645 202358
        """
        let winds = WindsAloftParser.parse(text)
        let mia = try XCTUnwrap(winds.first { $0.station == "MIA" })
        XCTAssertEqual(mia.validTime, "030000Z")
        XCTAssertEqual(mia.levels.map(\.altitude), [3000, 6000, 9000, 12000, 18000])
        XCTAssertEqual(mia.levels[0].direction, 100)
        XCTAssertEqual(mia.levels[0].speed, 18)
        XCTAssertNil(mia.levels[0].temperature)
        XCTAssertEqual(mia.levels[1].temperature, 15)
        XCTAssertEqual(mia.levels[4].temperature, -7)
        let pie = try XCTUnwrap(winds.first { $0.station == "PIE" })
        XCTAssertEqual(pie.levels.first?.altitude, 6000)          // 3000 ft column is blank
        XCTAssertEqual(pie.levels[0].speed, 0)                     // 9900 = light and variable
        XCTAssertEqual(pie.levels[1].direction, 230)               // 73 → 230°, +100 kt
        XCTAssertEqual(pie.levels[1].speed, 115)
        XCTAssertEqual(WindsAloftParser.decode("266537", altitude: 30000)?.temperature, -37)

        let live = WindsAloftParser.parse(String(decoding: try fixture("windtemp", "txt"), as: UTF8.self))
        XCTAssertFalse(live.isEmpty, "no Florida station parsed from the real FD product")
    }

    func testPIREPFixtureDecodes() throws {
        let data = try fixture("pirep", "json")
        let decoded = try JSONDecoder().decode([PIREPResponse].self, from: data)
        let pireps = decoded.map(PIREP.init(from:))
        XCTAssertEqual(pireps.count, decoded.count)
        for p in pireps { XCTAssertFalse(p.location.isEmpty) }
        XCTAssertEqual(PIREPElement.severity("MOD-SEV"), "SEVERE")
        XCTAssertNil(PIREPElement.severity("NEG"))
    }

    func testAdvisoryFixturesDecodeAndFilterToFlorida() throws {
        let sig = try JSONDecoder().decode([AirSigmetResponse].self, from: try fixture("airsigmet", "json"))
        let gair = try JSONDecoder().decode([GAirmetResponse].self, from: try fixture("gairmet", "json"))
        XCTAssertFalse(sig.isEmpty || gair.isEmpty)
        let advisories = WeatherService.floridaAdvisories(sigmets: sig, gairmets: gair)
        let expected = sig.filter { FloridaArea.overlaps($0.coords ?? []) }.count
        XCTAssertGreaterThanOrEqual(advisories.count, expected)

        let maine = AirSigmetResponse.Coord(lat: FlexValue("46.5"), lon: FlexValue("-69.9"))
        XCTAssertFalse(FloridaArea.overlaps([maine]))
        let orlando = AirSigmetResponse.Coord(lat: FlexValue("28.5"), lon: FlexValue("-81.3"))
        XCTAssertTrue(FloridaArea.overlaps([orlando]))
    }

    // MARK: - Map and Direct To

    @MainActor
    func testDirectToStartsFromGPSPosition() {
        let defaults = UserDefaults(suiteName: "test.directTo.\(UUID().uuidString)")!
        let model = AppModel(defaults: defaults)
        let kvrb = Airport(id: "KVRB", name: "Vero Beach", type: "medium_airport", icao: "KVRB", iata: "VRB",
                           municipality: "Vero Beach", elevationFt: 24,
                           coordinate: CLLocationCoordinate2D(latitude: 27.6556, longitude: -80.4179))
        model.directTo(kvrb)
        XCTAssertEqual(model.waypoints.map(\.id), ["KVRB"])     // no GPS fix yet

        model.userLocation = AppModel.homeCoordinate
        model.directTo(kvrb)
        XCTAssertEqual(model.waypoints.map(\.id), [AppModel.gpsWaypointID, "KVRB"])
        XCTAssertGreaterThan(model.totalDistanceNM, 5)
    }

    @MainActor
    func testMoveMapRecentresAndBumpsVersion() {
        let defaults = UserDefaults(suiteName: "test.moveMap.\(UUID().uuidString)")!
        let model = AppModel(defaults: defaults)
        let before = model.mapRegionVersion
        let miami = CLLocationCoordinate2D(latitude: 25.79, longitude: -80.29)
        model.moveMap(to: miami, span: 0.3)
        XCTAssertEqual(model.mapRegionVersion, before + 1)
        XCTAssertEqual(model.mapRegion.center.latitude, 25.79, accuracy: 0.0001)
        XCTAssertEqual(model.mapRegion.span.latitudeDelta, 0.3, accuracy: 0.0001)
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

    /// Avoid mode must really go around Class B/C/D: KFPR → KBCT passes West Palm Beach Class C.
    @MainActor
    func testAvoidControlledRoutesAroundRealAirspace() async throws {
        guard let url = Bundle.main.url(forResource: "airspace_snapshot", withExtension: "json") else {
            throw XCTSkip("snapshot not bundled in this test host")
        }
        let airspaces = try JSONDecoder().decode([Airspace].self, from: Data(contentsOf: url))
        let kfpr = Airport(id: "KFPR", name: "Treasure Coast", type: "medium_airport", icao: "KFPR", iata: nil,
                           municipality: nil, elevationFt: 24, coordinate: CLLocationCoordinate2D(latitude: 27.4975, longitude: -80.3726))
        let kbct = Airport(id: "KBCT", name: "Boca Raton", type: "medium_airport", icao: "KBCT", iata: nil,
                           municipality: nil, elevationFt: 13, coordinate: CLLocationCoordinate2D(latitude: 26.3785, longitude: -80.1077))

        let direct = await RoutingEngine.shared.calculateRoute(waypoints: [kfpr, kbct], cruiseAltitude: 3500,
                                                               mode: .direct, airspaces: airspaces)
        XCTAssertTrue(direct!.legs[0].airspaceWarnings.contains { $0.airspace.name.contains("WEST PALM") })

        for alt in [3500, 5500] {
            let result = await RoutingEngine.shared.calculateRoute(waypoints: [kfpr, kbct], cruiseAltitude: alt,
                                                                   mode: .avoidControlled, airspaces: airspaces)
            let routed = try XCTUnwrap(result)
            let path = routed.legs[0].waypoints
            XCTAssertGreaterThan(path.count, 2, "no detour at \(alt) ft")
            XCTAssertEqual(path.first!.latitude, kfpr.coordinate.latitude, accuracy: 1e-9)
            XCTAssertEqual(path.last!.latitude, kbct.coordinate.latitude, accuracy: 1e-9)
            let blockers = RoutingEngine.blockingRings(airspaces, from: kfpr.coordinate, to: kbct.coordinate,
                                                       altitude: alt, mode: .avoidControlled)
            for i in 1..<path.count {
                XCTAssertFalse(blockers.contains { $0.crosses(path[i - 1], path[i]) }, "segment \(i) enters controlled airspace at \(alt) ft")
            }
            XCTAssertLessThan(routed.totalDistanceNM, direct!.totalDistanceNM * 1.5)
            XCTAssertTrue(routed.summary.hasPrefix("Détour"))
        }
    }

    func testAIRACCycle() {
        func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
            var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "UTC")!
            return c.date(from: DateComponents(year: y, month: m, day: d, hour: 12))!
        }
        XCTAssertEqual(FAADocuments.cycle(on: day(2026, 11, 3)), "2611")
        XCTAssertEqual(FAADocuments.cycle(on: day(2026, 11, 26)), "2612")
        XCTAssertEqual(FAADocuments.cycle(on: day(2027, 1, 22)), "2701")
        XCTAssertEqual(FAADocuments.cycle(on: day(2026, 10, 1)), "2610")
    }

    func testSUASchedule() {
        let ny = TimeZone(identifier: "America/New_York")!
        func at(_ d: Int, _ h: Int, _ m: Int = 0) -> Date {   // November 2026: the 2nd is a Monday
            var c = Calendar(identifier: .gregorian); c.timeZone = ny
            return c.date(from: DateComponents(year: 2026, month: 11, day: d, hour: h, minute: m))!
        }
        let p = CLLocationCoordinate2D(latitude: 27, longitude: -81)
        let weekday = "INTERMITTENT, 0600 - 2400, MON - FRI; 0800 - 1800, SAT - SUN; %OTHER TIMES BY NOTAM"
        XCTAssertEqual(SUAStatus.of(weekday, at: at(2, 7), near: p), .active)       // Monday 07:00
        XCTAssertEqual(SUAStatus.of(weekday, at: at(7, 7), near: p), .inactive)     // Saturday 07:00
        XCTAssertEqual(SUAStatus.of(weekday, at: at(7, 9), near: p), .active)       // Saturday 09:00
        let late = "0800 - 0100, MON - THU; 0800 - 2200, FRI"
        XCTAssertEqual(SUAStatus.of(late, at: at(3, 0, 30), near: p), .active)      // Tuesday 00:30, Monday's window
        XCTAssertEqual(SUAStatus.of(late, at: at(7, 0, 30), near: p), .inactive)    // Saturday 00:30
        XCTAssertEqual(SUAStatus.of("CONTINUOUS", near: p), .active)
        XCTAssertEqual(SUAStatus.of("INTERMITTENT BY NOTAM", near: p), .byNotam)
        XCTAssertEqual(SUAStatus.of("NOV - DEC, 0800 - 1600, MON - FRI", at: at(2, 9), near: p), .active)
        XCTAssertEqual(SUAStatus.of("APR - AUG, 0800 - 1700, DAILY", at: at(2, 9), near: p), .inactive)
    }

    func testGDL90Traffic() {
        // Traffic report: N123AB, 27.2N 80.3W, 3500 ft, 110 kt, track 180, with 0x7E inside the payload escaped.
        func i24(_ v: Double) -> [UInt8] { let x = Int(v.rounded()) & 0xFFFFFF; return [UInt8(x >> 16), UInt8(x >> 8 & 0xFF), UInt8(x & 0xFF)] }
        let alt = (3500 + 1000) / 25
        var body: [UInt8] = [0x14, 0x00, 0xA1, 0x7E, 0xC3] + i24(27.2 / 180 * 8_388_608) + i24(-80.3 / 180 * 8_388_608)
        body += [UInt8(alt >> 4), UInt8((alt & 0xF) << 4 | 0x9), 0x88, UInt8(110 >> 4), UInt8((110 & 0xF) << 4), 0x00, 128, 0x01]
        body += Array("N123AB  ".utf8) + [0x00]
        let crc = GDL90.crc(body[...])
        var framed: [UInt8] = [0x7E]
        for b in body + [UInt8(crc & 0xFF), UInt8(crc >> 8)] {
            if b == 0x7E || b == 0x7D { framed += [0x7D, b ^ 0x20] } else { framed.append(b) }
        }
        framed.append(0x7E)
        guard case .traffic(let t)? = GDL90.decode(Data(framed)).first else { return XCTFail("no traffic decoded") }
        XCTAssertEqual(t.id, 0xA17EC3)
        XCTAssertEqual(t.callsign, "N123AB")
        XCTAssertEqual(t.altitudeFt, 3500)
        XCTAssertEqual(t.speedKt, 110)
        XCTAssertEqual(t.trackDeg, 180)
        XCTAssertEqual(t.coordinate.latitude, 27.2, accuracy: 0.0001)
        XCTAssertEqual(t.coordinate.longitude, -80.3, accuracy: 0.0001)
        framed[framed.count - 3] ^= 0xFF                      // corrupt the CRC
        XCTAssertTrue(GDL90.decode(Data(framed)).isEmpty)
    }

    func testWindTriangle() {
        let head = Navlog.solve(trueCourse: 360, tas: 100, windFrom: 360, windSpeed: 20)
        XCTAssertEqual(head.wca, 0, accuracy: 0.01)
        XCTAssertEqual(head.gs, 80, accuracy: 0.01)
        let cross = Navlog.solve(trueCourse: 360, tas: 100, windFrom: 90, windSpeed: 20)
        XCTAssertEqual(cross.wca, 11.54, accuracy: 0.05)   // crab right into a wind from the right
        XCTAssertEqual(cross.gs, 97.98, accuracy: 0.05)
        let level = { (a: Int, d: Int, s: Int) in WindsAloftLevel(altitude: a, direction: d, speed: s, temperature: nil) }
        let fb = WindsAloft(station: "X", latitude: 27, longitude: -81, validTime: "",
                            levels: [level(3000, 350, 10), level(6000, 10, 10)])
        let w = Navlog.wind(at: .init(latitude: 27, longitude: -81), altitude: 4500, winds: [fb])
        XCTAssertEqual(w?.direction, 0)                     // vector average, not 180
    }

    /// KFPR → KAPF only crosses the departure and arrival Class D: avoid mode keeps the direct line and says so.
    @MainActor
    func testAvoidKeepsDirectWhenNothingToAvoid() async throws {
        guard let url = Bundle.main.url(forResource: "airspace_snapshot", withExtension: "json") else {
            throw XCTSkip("snapshot not bundled in this test host")
        }
        let airspaces = try JSONDecoder().decode([Airspace].self, from: Data(contentsOf: url))
        let kfpr = Airport(id: "KFPR", name: "Treasure Coast", type: "medium_airport", icao: "KFPR", iata: nil,
                           municipality: nil, elevationFt: 24, coordinate: CLLocationCoordinate2D(latitude: 27.4951, longitude: -80.3683))
        let kapf = Airport(id: "KAPF", name: "Naples", type: "medium_airport", icao: "KAPF", iata: nil,
                           municipality: nil, elevationFt: 8, coordinate: CLLocationCoordinate2D(latitude: 26.1526, longitude: -81.7753))
        RoutingEngine.shared.currentMode = .avoidAllSUA
        defer { RoutingEngine.shared.currentMode = .direct }
        let result = await RoutingEngine.shared.calculateRoute(waypoints: [kfpr, kapf], cruiseAltitude: 5500,
                                                               mode: .avoidAllSUA, airspaces: airspaces)
        let routed = try XCTUnwrap(result)
        XCTAssertEqual(routed.legs[0].waypoints.count, 2)
        XCTAssertEqual(routed.detourNM, 0, accuracy: 0.01)
        XCTAssertTrue(routed.summary.hasPrefix("Rien à contourner"))
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