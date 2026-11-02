import XCTest
import CoreLocation
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
}