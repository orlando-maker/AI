import XCTest
import CoreLocation
@testable import TailTrack

final class NNumberTests: XCTestCase {

    /// Spot values cross-checked against a reference implementation of the
    /// FAA sequential allocation, including the documented block anchors
    /// (N1 = A00001, N99999 = ADF7C7).
    func testKnownMappings() {
        let expected: [String: String] = [
            "N1": "a00001",
            "N1A": "a00002",
            "N1AA": "a00003",
            "N12": "a05158",
            "N123": "a05ed6",
            "N1234": "a061bb",
            "N12345": "a061d9",
            "N1234C": "a061be",
            "N152TT": "a0d358",
            "N5AB": "a63540",
            "N747": "aa0c8a",
            "N800BW": "aae20b",
            "N99999": "adf7c7",
        ]
        for (tail, hex) in expected {
            XCTAssertEqual(NNumber.icaoHex(for: tail), hex, "wrong hex for \(tail)")
            XCTAssertEqual(NNumber.tailNumber(forICAOHex: hex), tail, "wrong tail for \(hex)")
        }
    }

    func testNormalization() {
        XCTAssertEqual(NNumber.icaoHex(for: "n1234c"), "a061be")
        XCTAssertEqual(NNumber.icaoHex(for: " 1234C "), "a061be")
        XCTAssertEqual(NNumber.normalize("n12"), "N12")
    }

    func testInvalidInputs() {
        XCTAssertNil(NNumber.icaoHex(for: ""))
        XCTAssertNil(NNumber.icaoHex(for: "N"))
        XCTAssertNil(NNumber.icaoHex(for: "N0123"))    // leading 0 not allowed
        XCTAssertNil(NNumber.icaoHex(for: "NI23"))     // I not allowed
        XCTAssertNil(NNumber.icaoHex(for: "N12O4"))    // O not allowed
        XCTAssertNil(NNumber.icaoHex(for: "NAB12"))    // letters only at the end
        XCTAssertNil(NNumber.icaoHex(for: "N123456"))  // too long
        XCTAssertNil(NNumber.tailNumber(forICAOHex: "a00000"))  // below block
        XCTAssertNil(NNumber.tailNumber(forICAOHex: "adf7c8"))  // above block
        XCTAssertNil(NNumber.tailNumber(forICAOHex: "c01234"))  // not US
    }

    /// Round-trips a spread of the whole US block through both directions.
    func testRoundTripSample() {
        var value = 1
        while value <= 0xDF7C7 {
            let hex = String(format: "a%05x", value)
            guard let tail = NNumber.tailNumber(forICAOHex: hex) else {
                XCTFail("no tail for \(hex)")
                return
            }
            XCTAssertEqual(NNumber.icaoHex(for: tail), hex, "roundtrip failed at \(hex) (\(tail))")
            value += 997  // prime stride: ~919 samples across the block
        }
    }
}

final class GreatCircleTests: XCTestCase {

    func testKnownDistance() {
        // KSQL → KSLC direct is ~517 nm.
        let ksql = CLLocationCoordinate2D(latitude: 37.5119, longitude: -122.2495)
        let kslc = CLLocationCoordinate2D(latitude: 40.7884, longitude: -111.9778)
        XCTAssertEqual(GreatCircle.distanceNM(from: ksql, to: kslc), 516.7, accuracy: 2.0)
        XCTAssertEqual(GreatCircle.distanceNM(from: ksql, to: ksql), 0, accuracy: 0.001)
    }

    func testRoutePointsEndpoints() {
        let a = CLLocationCoordinate2D(latitude: 37.5119, longitude: -122.2495)
        let b = CLLocationCoordinate2D(latitude: 40.7884, longitude: -111.9778)
        let pts = GreatCircle.routePoints(from: a, to: b, count: 32)
        XCTAssertEqual(pts.count, 32)
        XCTAssertEqual(pts.first!.latitude, a.latitude, accuracy: 0.0001)
        XCTAssertEqual(pts.last!.longitude, b.longitude, accuracy: 0.0001)
    }
}

final class CSVParsingTests: XCTestCase {

    func testQuotedFields() {
        let fields = AirportStore.splitCSVLine(#"123,KSQL,"San Carlos, CA","He said ""hi""",37.5"#)
        XCTAssertEqual(fields, ["123", "KSQL", "San Carlos, CA", "He said \"hi\"", "37.5"])
    }

    func testOurAirportsRows() {
        let csv = """
        id,ident,type,name,latitude_deg,longitude_deg,elevation_ft,continent,iso_country,iso_region,municipality,scheduled_service,gps_code,iata_code
        1,KSQL,small_airport,San Carlos Airport,37.5119,-122.2495,5,NA,US,US-CA,San Carlos,no,KSQL,SQL
        2,KSLC,large_airport,"Salt Lake City International Airport",40.7884,-111.9778,4227,NA,US,US-UT,Salt Lake City,yes,KSLC,SLC
        3,XCLS,closed,Old Field,10.0,10.0,,NA,US,US-CA,,no,,
        """
        let airports = AirportStore.parseOurAirportsCSV(csv)
        XCTAssertEqual(airports.count, 2)
        XCTAssertEqual(airports[0].ident, "KSQL")
        XCTAssertEqual(airports[0].iata, "SQL")
        XCTAssertEqual(airports[1].elevationFt, 4227)
    }
}
