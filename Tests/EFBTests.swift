import XCTest
import CoreLocation
@testable import Fiveflight

final class EFBTests: XCTestCase {

    func testHaversineKnownDistance() {
        // JFK -> LAX is ~2143 NM; allow a small tolerance.
        let jfk = CLLocationCoordinate2D(latitude: 40.6413, longitude: -73.7781)
        let lax = CLLocationCoordinate2D(latitude: 33.9416, longitude: -118.4085)
        let d = Haversine.nauticalMiles(jfk, lax)
        XCTAssertEqual(d, 2143, accuracy: 20)
    }
}
