import XCTest
@testable import TailTrack

final class ATISDecoderTests: XCTestCase {

    private let now = ISO8601DateFormatter().date(from: "2026-10-02T19:10:00Z")!

    func testDecodesAFullBroadcast() {
        let atis = ATISDecoder.decode("""
            SFO ATIS INFO B 1856Z. 28012KT 10SM FEW008 SCT200 17/12 A2992 (TWO NINER NINER TWO). \
            SIMUL CHARTED VISUAL FLIGHT PROCEDURES IN USE. LNDG RWYS 28L, 28R. DEPG RWYS 1L, 1R. \
            NOTAMS... TWY F BTN TWY A AND TWY B CLSD. RWY 10/28 CLSD 0600Z TO 1300Z. \
            CTC CLNC DEL ON 118.2. ...ADVS YOU HAVE INFO B.
            """, now: now)

        XCTAssertEqual(atis.information, "Bravo")
        XCTAssertEqual(atis.issuedZulu, "1856Z")
        XCTAssertEqual(atis.issuedAt, ISO8601DateFormatter().date(from: "2026-10-02T18:56:00Z"))
        XCTAssertEqual(atis.wind, "280° at 12 kt")
        XCTAssertEqual(atis.visibility, "10 statute miles")
        XCTAssertEqual(atis.sky, ["Few at 800 ft", "Scattered at 20,000 ft"])
        XCTAssertEqual(atis.temperature, "17°C, dew point 12°C")
        XCTAssertEqual(atis.altimeter, "29.92 inHg")
        XCTAssertEqual(atis.approaches, ["Simultaneous charted visual flight procedures in use."])
        XCTAssertEqual(atis.landing, ["Landing runways 28L, 28R."])
        XCTAssertEqual(atis.departing, ["Departing runways 1L, 1R."])
        // The runway pair and the notice's own Zulu times must not be
        // mistaken for weather, and the frequency keeps its decimal.
        XCTAssertEqual(atis.notices, [
            "Taxiway F between taxiway A and taxiway B closed.",
            "Runway 10/28 closed 0600Z to 1300Z.",
            "Contact clearance delivery on 118.2.",
        ])
    }

    func testGustsVariableWindWeatherAndCeiling() {
        let atis = ATISDecoder.decode("""
            DEN DEP INFO K 2053Z. 18010G22KT 150V210 10SM -TSRA BKN080CB OVC120 24/M01 \
            A3014 (THREE ZERO ONE FOUR). DEPG RWYS 17L, 25. ADVS YOU HAVE INFO K.
            """, now: now)
        XCTAssertEqual(atis.information, "Kilo")
        XCTAssertEqual(atis.wind, "180° at 10 kt, gusting 22 kt, varying 150°–210°")
        XCTAssertEqual(atis.weather, ["Light thunderstorm with rain"])
        XCTAssertEqual(atis.sky.first, "Broken at 8,000 ft (cumulonimbus) · ceiling")
        XCTAssertEqual(atis.temperature, "24°C, dew point -1°C")
        XCTAssertEqual(atis.departing, ["Departing runways 17L, 25."])
        XCTAssertTrue(atis.notices.isEmpty)
    }

    func testLowVisibilityCalmWindAndRemarks() {
        let atis = ATISDecoder.decode("""
            SEA ATIS INFO C 1053Z. 00000KT 1 1/2SM BR OVC004 08/07 A3021 RMK AO2 SLP235. \
            ILS RWY 16R APCH IN USE. ADVISE ON INITIAL CONTACT YOU HAVE INFO C.
            """, now: now)
        XCTAssertEqual(atis.wind, "Calm")
        XCTAssertEqual(atis.visibility, "1 1/2 statute miles")
        XCTAssertEqual(atis.weather, ["Mist"])
        XCTAssertEqual(atis.sky, ["Overcast at 400 ft · ceiling"])
        XCTAssertEqual(atis.approaches, ["ILS runway 16R approach in use."])
    }

    func testIssueTimeJustBeforeMidnightIsYesterday() {
        let justAfterMidnight = ISO8601DateFormatter().date(from: "2026-10-03T00:10:00Z")!
        let atis = ATISDecoder.decode("JFK ATIS INFO Z 2351Z. 31008KT 10SM CLR 12/03 A3010.",
                                      now: justAfterMidnight)
        XCTAssertEqual(atis.issuedAt, ISO8601DateFormatter().date(from: "2026-10-02T23:51:00Z"))
        XCTAssertEqual(atis.sky, ["Clear"])
    }

    func testLetterExtraction() {
        XCTAssertEqual(ATISService.letter(in: "SFO ATIS INFO B 1856Z."), "B")
        XCTAssertEqual(ATISService.letter(in: "ATL ARR INFORMATION W 1952Z"), "W")
        XCTAssertNil(ATISService.letter(in: "INFO ON TWY CLOSURES"))
    }

    func testFrequenciesParseAndFormat() {
        let csv = """
            "id","airport_ref","airport_ident","type","description","frequency_mhz"
            58915,21105,"KSQL","ATIS","ATIS",125.9
            58918,21105,"KSQL","GND","GND",121.6
            58919,21105,"KSQL","TWR","TWR",119
            58914,21105,"KSQL","APP","NORCAL APP",133.95
            58937,20805,"KPAO","ATIS","ATIS",135.275
            """
        let table = FrequencyDirectory.parse(csv)
        let ksql = table["KSQL"] ?? []
        XCTAssertEqual(ksql.count, 3, "approach control isn't kept")
        XCTAssertEqual(ksql.first { $0.isWeatherBroadcast }?.formatted, "125.90")
        XCTAssertEqual(ksql.first { $0.type == "TWR" }?.label, "Tower")
        XCTAssertEqual(table["KPAO"]?.first?.formatted, "135.275")
    }
}
