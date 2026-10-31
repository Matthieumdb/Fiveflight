import XCTest
import CoreLocation
@testable import Fiveflight

final class FiveflightTests: XCTestCase {

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
}