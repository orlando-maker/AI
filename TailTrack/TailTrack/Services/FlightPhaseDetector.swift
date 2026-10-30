import Foundation

/// One position report, reduced to what flight-phase decisions need.
struct PositionSample: Equatable {
    /// When the aircraft was actually at this position.
    var positionTime: Date
    /// When TailTrack received the report.
    var receivedAt: Date
    var latitude: Double
    var longitude: Double
    var baroAltitudeFt: Double?
    /// GNSS altitude; tracks field elevation far better than barometric
    /// altitude, which is off by however far the day's pressure is from
    /// standard.
    var geoAltitudeFt: Double?
    var groundSpeedKt: Double?
    var verticalRateFpm: Double?
    /// The transponder's own air/ground flag. Many GA installs never set it.
    var onGround: Bool
}

/// What TailTrack knows about airports around one sample.
struct FieldContext: Equatable {
    /// Elevation of an airport close enough to be landing at (≈2.5 nm).
    var nearbyFieldElevationFt: Double?
    /// Ground reference for "clearly flying": the departure field, else the
    /// nearest airport within ~10 nm.
    var referenceElevationFt: Double?

    static let none = FieldContext()
}

/// Decides takeoff, landing, touch-and-goes and signal loss from a stream
/// of ADS-B reports. Pure and deterministic: no networking, timers or UI, so
/// recorded sequences can be replayed through it in tests and after the app
/// restarts.
///
/// The rules are built to be hard to fool:
/// - Stale reports (older than `maxPositionAge`, or the same old position
///   served again) never change state; they only count as silence.
/// - "On the ground" needs the ground flag, or slow + near an airport +
///   close to that airport's elevation. Slow flight in a headwind away
///   from a field is never a landing.
/// - A landing needs `sustainedGroundSeconds` of ground evidence across
///   at least two reports. A brief touch is a touch-and-go.
/// - A declared landing isn't final: flying again turns it into a
///   stop-and-go and the same flight continues.
/// - Signal loss is measured from the last *fresh* position, not from the
///   last network response.
struct FlightPhaseDetector: Codable, Equatable {

    enum Mode: String, Codable {
        /// Not airborne yet this flight.
        case waiting
        case airborne
        /// Ground evidence seen after flying; not yet long enough to call it
        /// a landing.
        case rollout
        case landed
    }

    enum Event: Equatable {
        case takeoff(at: Date)
        /// Touchdown time and place of a sustained landing.
        case landed(at: Date, latitude: Double, longitude: Double)
        /// Brief ground contact, then flying again.
        case touchAndGo(at: Date)
        /// Airborne again after a declared landing (stop-and-go, taxi-back,
        /// or a landing call that was wrong).
        case resumedAfterLanding(landedAt: Date)
        /// No fresh position for `signalLossSeconds` while flying.
        case signalLost(lastFresh: Date)
    }

    enum Classification: Equatable {
        case airborne, ground, unclear
    }

    static let maxPositionAge: TimeInterval = 60
    static let airborneSpeedKt = 55.0
    static let taxiSpeedCeilingKt = 35.0
    static let liftAboveReferenceFt = 1200.0
    static let geoHeightToleranceFt = 250.0
    static let baroHeightToleranceFt = 600.0
    static let sustainedGroundSeconds: TimeInterval = 20
    static let signalLossSeconds: TimeInterval = 480

    private(set) var mode: Mode = .waiting
    private(set) var lastFreshPosition: Date?
    /// Touchdowns this flight: touch-and-goes plus landings.
    private(set) var landingCount = 0
    private(set) var landedAt: Date?

    private var lastPositionTime: Date?
    private var rolloutStart: Date?
    private var rolloutLatitude = 0.0
    private var rolloutLongitude = 0.0
    private var rolloutSamples = 0
    private var rolloutNearField = false
    private var signalLossReported = false

    var hasFlown: Bool { mode != .waiting }

    func isFresh(_ sample: PositionSample) -> Bool {
        sample.receivedAt.timeIntervalSince(sample.positionTime) <= Self.maxPositionAge
    }

    static func classify(_ sample: PositionSample, context: FieldContext) -> Classification {
        if sample.onGround { return .ground }
        let speed = sample.groundSpeedKt

        // Slow, low, and right at an airport: on the ground even without a
        // ground flag. Height is judged against the airport actually below,
        // never the planned destination.
        if let field = context.nearbyFieldElevationFt, let speed, speed < taxiSpeedCeilingKt {
            if let geo = sample.geoAltitudeFt {
                if geo - field < geoHeightToleranceFt { return .ground }
            } else if let baro = sample.baroAltitudeFt {
                if baro - field < baroHeightToleranceFt { return .ground }
            } else {
                return .ground
            }
        }

        let climbOrDescent = abs(sample.verticalRateFpm ?? 0) >= 400
        let clearlyAbove: Bool = {
            guard let reference = context.referenceElevationFt,
                  let altitude = sample.baroAltitudeFt ?? sample.geoAltitudeFt else { return false }
            return altitude > reference + liftAboveReferenceFt
        }()
        if (speed ?? 0) >= airborneSpeedKt || climbOrDescent || clearlyAbove {
            return .airborne
        }
        return .unclear
    }

    mutating func ingest(_ sample: PositionSample, context: FieldContext) -> [Event] {
        guard isFresh(sample) else { return noContact(at: sample.receivedAt) }
        if let last = lastPositionTime, sample.positionTime <= last {
            // The same position served again carries no new information.
            return noContact(at: sample.receivedAt)
        }
        lastPositionTime = sample.positionTime
        lastFreshPosition = sample.positionTime
        signalLossReported = false

        let classification = Self.classify(sample, context: context)
        var events: [Event] = []

        switch (mode, classification) {
        case (.waiting, .airborne):
            mode = .airborne
            events.append(.takeoff(at: sample.positionTime))

        case (.airborne, .ground):
            mode = .rollout
            rolloutStart = sample.positionTime
            rolloutLatitude = sample.latitude
            rolloutLongitude = sample.longitude
            rolloutSamples = 1
            rolloutNearField = context.nearbyFieldElevationFt != nil

        case (.rollout, .ground):
            rolloutSamples += 1
            rolloutNearField = rolloutNearField || context.nearbyFieldElevationFt != nil
            if let start = rolloutStart, rolloutSamples >= 2,
               sample.positionTime.timeIntervalSince(start) >= Self.sustainedGroundSeconds {
                mode = .landed
                landedAt = start
                landingCount += 1
                events.append(.landed(at: start, latitude: rolloutLatitude, longitude: rolloutLongitude))
                rolloutStart = nil
            }

        case (.rollout, .airborne):
            // Real ground contact at a field is a touch-and-go; a lone
            // ground flag in mid-air is a transponder glitch.
            if let start = rolloutStart, rolloutNearField || rolloutSamples >= 2 {
                landingCount += 1
                events.append(.touchAndGo(at: start))
            }
            mode = .airborne
            rolloutStart = nil

        case (.landed, .airborne):
            mode = .airborne
            if let landedAt { events.append(.resumedAfterLanding(landedAt: landedAt)) }
            landedAt = nil

        default:
            break
        }
        return events
    }

    /// Nothing fresh this poll: the networks returned nothing, or only a
    /// stale position.
    mutating func noContact(at now: Date) -> [Event] {
        guard mode == .airborne || mode == .rollout, !signalLossReported,
              let last = lastFreshPosition,
              now.timeIntervalSince(last) > Self.signalLossSeconds else { return [] }
        signalLossReported = true
        return [.signalLost(lastFresh: last)]
    }

    /// The tracker concluded a landing on its own (after signal loss, the
    /// airplane was last seen low at an airport).
    mutating func markLanded(at time: Date) {
        mode = .landed
        landedAt = time
        landingCount += 1
        rolloutStart = nil
    }
}
