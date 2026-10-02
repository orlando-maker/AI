import XCTest
@testable import TailTrack

final class RegionSupportTests: XCTestCase {

    func testNeighborRegistrationsGetTheirHyphen() {
        XCTAssertEqual(NNumber.normalize("cfabc"), "C-FABC")
        XCTAssertEqual(NNumber.normalize("CGKWL"), "C-GKWL")
        XCTAssertEqual(NNumber.normalize("XAABC"), "XA-ABC")
        XCTAssertEqual(NNumber.normalize("c6abc"), "C6-ABC")
        XCTAssertEqual(NNumber.normalize("VPCAB"), "VP-CAB")
        XCTAssertEqual(NNumber.normalize("6YJMR"), "6Y-JMR")
        // Already hyphenated, US, and unknown formats are left alone.
        XCTAssertEqual(NNumber.normalize("C-FABC"), "C-FABC")
        XCTAssertEqual(NNumber.normalize("1234C"), "N1234C")
        XCTAssertEqual(NNumber.normalize("HI1053"), "HI1053")
        XCTAssertEqual(NNumber.normalize("G-ABCD"), "G-ABCD")
    }

    /// Cross-checked against tar1090's reverse mapping for Canada.
    func testCanadianHex() {
        XCTAssertEqual(ForeignRegistration.canadianHex(for: "C-FAAA"), "c00001")
        XCTAssertEqual(ForeignRegistration.canadianHex(for: "C-FZZZ"), "c044a8")
        XCTAssertEqual(ForeignRegistration.canadianHex(for: "C-GAAA"), "c044a9")
        XCTAssertEqual(ForeignRegistration.canadianHex(for: "C-GKWL"), "c06158")
        XCTAssertNil(ForeignRegistration.canadianHex(for: "C-IABC"))
        XCTAssertNil(ForeignRegistration.canadianHex(for: "N1234C"))
    }

    func testSquawkCodes() {
        XCTAssertTrue(Squawk.isValid("1200"))
        XCTAssertTrue(Squawk.isValid("4521"))
        XCTAssertFalse(Squawk.isValid("1280"), "8 isn't an octal digit")
        XCTAssertFalse(Squawk.isValid("120"))
        XCTAssertTrue(Squawk.isEmergency("7700"))
        XCTAssertEqual(Squawk.meaning("1200"), "VFR, not talking to ATC")
    }

    func testRegionDescriptions() {
        func airport(_ region: String) -> Airport {
            Airport(ident: "TEST", name: "Test", latitude: 0, longitude: 0, elevationFt: nil,
                    iata: nil, municipality: nil, region: region, kind: "small_airport")
        }
        XCTAssertEqual(airport("US-CA").regionDescription, "CA")
        XCTAssertTrue(airport("CA-BC").regionDescription?.hasPrefix("BC, ") ?? false)
        XCTAssertNotEqual(airport("MP-U-A").regionDescription, "MP-U-A")
        XCTAssertNotEqual(airport("GU-U-A").regionDescription, "GU-U-A")
    }

    func testHectopascalAltimeter() {
        let atis = ATISDecoder.decode("ABC ATIS INFO D 1200Z. 09010KT 9999 FEW020 28/22 Q1012.")
        XCTAssertEqual(atis.altimeter, "1012 hPa")
    }
}
