import XCTest
@testable import TailTrack

final class FlightSegmenterTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_759_000_000)
    private let hour: TimeInterval = 3600

    private func air(_ from: TimeInterval, _ to: TimeInterval) -> [TrackPoint] {
        stride(from: from, to: to, by: 30).map {
            TrackPoint(time: base + $0, latitude: 37.5, longitude: -122.2, altitudeFt: 2500,
                       groundSpeedKt: 95, trackDeg: 180, verticalRateFpm: 0, onGround: false)
        }
    }

    private func ground(_ from: TimeInterval, _ to: TimeInterval) -> [TrackPoint] {
        stride(from: from, to: to, by: 30).map {
            TrackPoint(time: base + $0, latitude: 37.5, longitude: -122.2, altitudeFt: nil,
                       groundSpeedKt: 5, trackDeg: nil, verticalRateFpm: nil, onGround: true)
        }
    }

    /// A busy day: a pattern session, a turnaround, a coverage gap, a
    /// glitch, and an evening flight should read as four logbook entries.
    func testSplitsADayTheWayAPilotLogsIt() {
        var day: [TrackPoint] = []
        day += ground(8 * hour, 9 * hour)
        // Parked transponder reporting an altitude but no speed.
        day.append(TrackPoint(time: base + 8 * hour + 900, latitude: 37.5, longitude: -122.2,
                              altitudeFt: 100, groundSpeedKt: 0, trackDeg: nil,
                              verticalRateFpm: nil, onGround: false))
        // Touch-and-go, then a 5-minute taxi-back: still one flight.
        day += air(9 * hour, 9 * hour + 600) + ground(9 * hour + 600, 9 * hour + 640)
        day += air(9 * hour + 640, 9 * hour + 1200) + ground(9 * hour + 1200, 9 * hour + 1500)
        day += air(9 * hour + 1500, 9 * hour + 2400)
        // 40-minute full stop ends it.
        day += ground(9 * hour + 2400, 10 * hour + 600)
        day += air(10 * hour + 600, 11 * hour)
        // 30 minutes of silence: landed somewhere out of coverage.
        day += air(11 * hour + 1800, 12 * hour) + ground(12 * hour, 12 * hour + 60)
        // Two-minute blip is noise.
        day += air(18 * hour, 18 * hour + 120)
        day += ground(19 * hour, 19 * hour + 60) + air(19 * hour + 60, 20 * hour + 300)
        day += ground(20 * hour + 300, 20 * hour + 400)

        let flights = FlightSegmenter.flights(in: day.shuffled())
        XCTAssertEqual(flights.count, 4)
        XCTAssertEqual(flights.map { $0.takeoff.timeIntervalSince(base) },
                       [9 * hour, 10 * hour + 600, 11 * hour + 1800, 19 * hour + 60])
        // Landing snaps to the first ground sample after touchdown.
        XCTAssertEqual(flights[0].landing.timeIntervalSince(base), 9 * hour + 2400)
        // One ground sample either side is kept for airport detection.
        XCTAssertTrue(flights[3].points.first?.onGround ?? false)
        XCTAssertTrue(flights[3].points.last?.onGround ?? false)
    }

    func testEmptyAndGroundOnlyDaysHaveNoFlights() {
        XCTAssertTrue(FlightSegmenter.flights(in: []).isEmpty)
        XCTAssertTrue(FlightSegmenter.flights(in: ground(0, hour)).isEmpty)
    }

    func testThinningKeepsTheLastPoint() {
        let dense = air(0, 5 * hour)          // 600 points
        let thinned = FlightSegmenter.thinned(dense, limit: 100)
        XCTAssertLessThanOrEqual(thinned.count, 101)
        XCTAssertEqual(thinned.last?.time, dense.last?.time)
        XCTAssertEqual(FlightSegmenter.thinned(dense, limit: 1000).count, dense.count)
    }

    // MARK: - gzip

    private let payload = #"{"timestamp":1759000000,"trace":[[0,37.5,-122.2,2500,95,180,0,0]]}"#

    func testGunzipPlainHeader() throws {
        let gz = try XCTUnwrap(Data(base64Encoded: "H4sIAAAAAAACA6tWKsnMTS0uScwtULIyNDe1NAADHaWSosTkVCWr6GgDHWNzPVMdXUMjIz0jHSNToKSlqY6hhYEOEMbG1gIA5S1LMEIAAAA="))
        XCTAssertEqual(String(data: ADSBClient.gunzipIfNeeded(gz), encoding: .utf8), payload)
    }

    func testGunzipWithFilenameHeader() throws {
        let gz = try XCTUnwrap(Data(base64Encoded: "H4sICAAAAAAC/3RyYWNlX2Z1bGxfYTBkMzU4Lmpzb24Aq1YqycxNLS5JzC1QsjI0N7U0AAMdpZKixORUJavoaAMdY3M9Ux1dQyMjPSMdI1OgpKWpjqGFgQ4QxsbWAgDlLUswQgAAAA=="))
        XCTAssertEqual(String(data: ADSBClient.gunzipIfNeeded(gz), encoding: .utf8), payload)
    }

    func testPlainJSONPassesThrough() {
        let json = Data(payload.utf8)
        XCTAssertEqual(ADSBClient.gunzipIfNeeded(json), json)
    }
}
