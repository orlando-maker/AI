import XCTest
@testable import TailTrack

/// Recorded-style ADS-B sequences replayed through the flight-phase
/// detector: the situations that can quietly ruin a real flight record.
/// Reports arrive every 8 seconds unless a scenario says otherwise.
final class FlightPhaseDetectorTests: XCTestCase {

    private let base = Date(timeIntervalSince1970: 1_790_000_000)
    private let ksql = 5.0
    private lazy var atField = FieldContext(nearbyFieldElevationFt: ksql, referenceElevationFt: ksql)
    private lazy var practiceArea = FieldContext(nearbyFieldElevationFt: nil, referenceElevationFt: ksql)

    private enum Poll {
        case report(PositionSample, FieldContext)
        case silence(at: TimeInterval)
    }

    private func sample(_ t: TimeInterval, gs: Double?, alt: Double? = nil, geo: Double? = nil,
                        vr: Double = 0, ground: Bool = false, receivedAt: TimeInterval? = nil) -> PositionSample {
        PositionSample(positionTime: base + t, receivedAt: base + (receivedAt ?? t + 1),
                       latitude: 37.5, longitude: -122.25, baroAltitudeFt: alt, geoAltitudeFt: geo,
                       groundSpeedKt: gs, verticalRateFpm: vr, onGround: ground)
    }

    private func reports(_ range: StrideTo<TimeInterval>, _ context: FieldContext,
                         _ make: (TimeInterval) -> PositionSample) -> [Poll] {
        range.map { .report(make($0), context) }
    }

    private func run(_ polls: [Poll]) -> (FlightPhaseDetector, [FlightPhaseDetector.Event]) {
        var detector = FlightPhaseDetector()
        var events: [FlightPhaseDetector.Event] = []
        for poll in polls {
            switch poll {
            case .report(let sample, let context): events += detector.ingest(sample, context: context)
            case .silence(let t): events += detector.noContact(at: base + t)
            }
        }
        return (detector, events)
    }

    private func kinds(_ events: [FlightPhaseDetector.Event]) -> [String] {
        events.map {
            switch $0 {
            case .takeoff: return "takeoff"
            case .landed: return "landed"
            case .touchAndGo: return "touchAndGo"
            case .resumedAfterLanding: return "resumed"
            case .signalLost: return "signalLost"
            }
        }
    }

    func testNormalDepartureAndLanding() {
        var polls = reports(stride(from: 0, to: 120, by: 8), atField) { self.sample($0, gs: 8, ground: true) }
        polls += reports(stride(from: 120, to: 136, by: 8), atField) { self.sample($0, gs: 45, ground: true) }
        polls += reports(stride(from: 136, to: 1800, by: 8), practiceArea) {
            self.sample($0, gs: 105, alt: 3500, vr: $0 < 400 ? 500 : 0)
        }
        polls += reports(stride(from: 1800, to: 1900, by: 8), atField) { self.sample($0, gs: 70, alt: 600, vr: -500) }
        polls += reports(stride(from: 1904, to: 2100, by: 8), atField) { self.sample($0, gs: 20, ground: true) }
        let (_, events) = run(polls)
        XCTAssertEqual(kinds(events), ["takeoff", "landed"])
        XCTAssertEqual(events.first, .takeoff(at: base + 136))
        if case .landed(let at, _, _) = events.last { XCTAssertEqual(at, base + 1904) }
    }

    /// The transponder never sets its ground flag; three touch-and-goes and
    /// a full stop must stay ONE flight with four landings.
    func testPatternWorkWithoutGroundFlag() {
        var polls = reports(stride(from: 0, to: 60, by: 8), atField) { self.sample($0, gs: 5, alt: 0, geo: 0) }
        polls += reports(stride(from: 60, to: 400, by: 8), atField) { self.sample($0, gs: 75, alt: 900, geo: 880, vr: 600) }
        var t: TimeInterval = 400
        for _ in 0..<3 {
            polls.append(.report(sample(t, gs: 30, alt: 10, geo: 8), atField))
            polls += reports(stride(from: t + 8, to: t + 400, by: 8), atField) {
                self.sample($0, gs: 75, alt: 900, geo: 880, vr: 500)
            }
            t += 400
        }
        polls += reports(stride(from: t, to: t + 200, by: 8), atField) { self.sample($0, gs: 15, alt: 8, geo: 6) }
        let (detector, events) = run(polls)
        XCTAssertEqual(kinds(events), ["takeoff", "touchAndGo", "touchAndGo", "touchAndGo", "landed"])
        XCTAssertEqual(detector.landingCount, 4)
    }

    func testSlowFlightInThePracticeAreaIsNotALanding() {
        var polls: [Poll] = [.report(sample(0, gs: 90, alt: 3000, vr: 600), practiceArea)]
        polls += reports(stride(from: 8, to: 600, by: 8), practiceArea) { self.sample($0, gs: 28, alt: 3000) }
        // The old detector called this a landing at 2,000 ft.
        polls += reports(stride(from: 600, to: 900, by: 8), practiceArea) { self.sample($0, gs: 28, alt: 2000) }
        let (detector, events) = run(polls)
        XCTAssertEqual(kinds(events), ["takeoff"])
        XCTAssertEqual(detector.mode, .airborne)
    }

    func testSlowFlightOverAnAirportIsNotALanding() {
        var polls: [Poll] = [.report(sample(0, gs: 90, alt: 2000, geo: 1990, vr: 600), atField)]
        polls += reports(stride(from: 8, to: 300, by: 8), atField) { self.sample($0, gs: 30, alt: 2005, geo: 1995) }
        let (detector, events) = run(polls)
        XCTAssertEqual(kinds(events), ["takeoff"])
        XCTAssertEqual(detector.mode, .airborne)
    }

    func testSlowAndLowWithNoAirportNearbyIsNotALanding() {
        var polls: [Poll] = [.report(sample(0, gs: 90, alt: 1500, vr: 600), .none)]
        polls += reports(stride(from: 8, to: 600, by: 8), .none) { self.sample($0, gs: 25, alt: 1500) }
        let (_, events) = run(polls)
        XCTAssertEqual(kinds(events), ["takeoff"])
    }

    func testShortCoverageGapKeepsFlying() {
        var polls: [Poll] = [.report(sample(0, gs: 100, alt: 3500, vr: 600), practiceArea)]
        polls += stride(from: 8.0, to: 300.0, by: 8.0).map { Poll.silence(at: $0) }
        polls += reports(stride(from: 300, to: 400, by: 8), practiceArea) { self.sample($0, gs: 100, alt: 3500) }
        let (detector, events) = run(polls)
        XCTAssertEqual(kinds(events), ["takeoff"])
        XCTAssertEqual(detector.mode, .airborne)
    }

    func testSignalLossIsTimedFromTheLastFreshPosition() {
        var polls: [Poll] = [.report(sample(0, gs: 100, alt: 3500, vr: 600), practiceArea)]
        polls += stride(from: 8.0, to: 600.0, by: 8.0).map { Poll.silence(at: $0) }
        let (_, events) = run(polls)
        XCTAssertEqual(events, [.takeoff(at: base), .signalLost(lastFresh: base)])
    }

    /// An aggregator that keeps serving the same old airborne position with
    /// a brand-new fetch time must still end in signal loss, never a hang.
    func testStalePositionServedForeverEndsInSignalLoss() {
        var polls: [Poll] = [.report(sample(0, gs: 100, alt: 3500, vr: 600), practiceArea)]
        polls += stride(from: 8.0, to: 600.0, by: 8.0).map {
            Poll.report(self.sample(0, gs: 100, alt: 3500, receivedAt: $0), self.practiceArea)
        }
        let (_, events) = run(polls)
        XCTAssertEqual(kinds(events), ["takeoff", "signalLost"])
    }

    func testJoiningMidFlight() {
        let polls = reports(stride(from: 5000, to: 5200, by: 8), practiceArea) { self.sample($0, gs: 110, alt: 4500) }
        let (_, events) = run(polls)
        XCTAssertEqual(events, [.takeoff(at: base + 5000)])
    }

    func testOneBogusGroundFlagInCruiseIsIgnored() {
        var polls: [Poll] = [
            .report(sample(0, gs: 100, alt: 3500, vr: 600), practiceArea),
            .report(sample(8, gs: 100, alt: 3500, ground: true), practiceArea),
        ]
        polls += reports(stride(from: 16, to: 200, by: 8), practiceArea) { self.sample($0, gs: 100, alt: 3500) }
        let (detector, events) = run(polls)
        XCTAssertEqual(kinds(events), ["takeoff"])
        XCTAssertEqual(detector.landingCount, 0)
    }

    func testStopAndGoContinuesTheSameFlight() {
        var polls: [Poll] = [.report(sample(0, gs: 90, alt: 900, vr: 600), atField)]
        polls += reports(stride(from: 8, to: 128, by: 8), atField) { self.sample($0, gs: 10, ground: true) }
        polls += reports(stride(from: 128, to: 300, by: 8), atField) { self.sample($0, gs: 75, alt: 900, vr: 600) }
        let (detector, events) = run(polls)
        XCTAssertEqual(kinds(events), ["takeoff", "landed", "resumed"])
        XCTAssertEqual(detector.mode, .airborne)
    }

    func testLosingCoverageOnFinalHandsTheDecisionToTheTracker() {
        var polls: [Poll] = [.report(sample(0, gs: 90, alt: 3000, vr: 600), practiceArea)]
        polls += reports(stride(from: 8, to: 200, by: 8), atField) { self.sample($0, gs: 70, alt: 500, vr: -500) }
        polls += stride(from: 200.0, to: 800.0, by: 8.0).map { Poll.silence(at: $0) }
        let (_, events) = run(polls)
        XCTAssertEqual(kinds(events).last, "signalLost")
    }

    func testParkedTransponderNeverTakesOff() {
        let polls = reports(stride(from: 0, to: 900, by: 8), atField) { self.sample($0, gs: 0, alt: 40) }
        let (detector, events) = run(polls)
        XCTAssertTrue(events.isEmpty)
        XCTAssertEqual(detector.mode, .waiting)
    }

    func testFastTaxiWithoutGroundFlagIsNotATakeoff() {
        let polls = reports(stride(from: 0, to: 300, by: 8), atField) { self.sample($0, gs: 30, alt: 20, geo: 10) }
        let (_, events) = run(polls)
        XCTAssertTrue(events.isEmpty)
    }

    func testRepeatedReportsDontCountAsSustainedGround() {
        var polls: [Poll] = [
            .report(sample(0, gs: 90, alt: 900, vr: 600), atField),
            .report(sample(8, gs: 10, ground: true), atField),
        ]
        polls += stride(from: 16.0, to: 120.0, by: 8.0).map {
            Poll.report(self.sample(8, gs: 10, ground: true, receivedAt: $0), self.atField)
        }
        let (detector, events) = run(polls)
        XCTAssertEqual(kinds(events), ["takeoff"])
        XCTAssertEqual(detector.mode, .rollout)
    }

    /// The detector's state survives being saved and restored mid-flight.
    func testStateRoundTripsThroughCodable() throws {
        var detector = FlightPhaseDetector()
        _ = detector.ingest(sample(0, gs: 90, alt: 900, vr: 600), context: atField)
        _ = detector.ingest(sample(8, gs: 10, ground: true), context: atField)
        let restored = try JSONDecoder().decode(FlightPhaseDetector.self,
                                                from: JSONEncoder().encode(detector))
        XCTAssertEqual(restored, detector)
    }

    func testAverageSpeedIsTimeWeightedAndSkipsGaps() {
        func point(_ t: TimeInterval, _ gs: Double) -> TrackPoint {
            TrackPoint(time: base + t, latitude: 0, longitude: 0, altitudeFt: 3000,
                       groundSpeedKt: gs, trackDeg: nil, verticalRateFpm: nil, onGround: false)
        }
        // 60 s at 100 kt sampled every 2 s, then 60 s at 160 kt sampled once,
        // then a 10-minute gap that must not count.
        var points = stride(from: 0.0, to: 60, by: 2).map { point($0, 100) }
        points.append(point(60, 160))
        points.append(point(120, 120))
        points.append(point(720, 120))
        let average = Flight.timeWeightedSpeed(points) ?? 0
        XCTAssertEqual(average, 130, accuracy: 0.01)
    }
}
