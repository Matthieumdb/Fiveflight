import XCTest
import CoreLocation
@testable import EFB

final class EFBTests: XCTestCase {

    func testHaversineKnownDistance() {
        // JFK -> LAX is ~2143 NM; allow a small tolerance.
        let jfk = CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781)
        let lax = CLLocationCoordinate2D(latitude: 33.9416, longitude: -118.4085)
        let d = Haversine.nauticalMiles(jfk, lax)
        XCTAssertEqual(d, 2143, accuracy: 20)
    }

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
}
