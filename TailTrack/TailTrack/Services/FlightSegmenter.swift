import Foundation

/// One flight carved out of a day's ADS-B history.
struct FlightSegment: Identifiable {
    let id = UUID()
    let takeoff: Date
    let landing: Date
    let points: [TrackPoint]

    var duration: TimeInterval { landing.timeIntervalSince(takeoff) }
    var firstPoint: TrackPoint? { points.first }
    var lastPoint: TrackPoint? { points.last }
    var maxAltitudeFt: Double? {
        points.filter { !$0.onGround }.compactMap(\.altitudeFt).max()
    }
}

/// Splits a day of position reports into individual flights, the way a
/// pilot would log them: touch-and-goes and short taxi-backs stay one
/// flight; a full stop of ten minutes or more, or a long silence, starts
/// the next one.
enum FlightSegmenter {

    /// Ground time that ends a flight (a real stop, not a touch-and-go).
    static let fullStop: TimeInterval = 10 * 60
    /// Silence long enough that the aircraft has surely landed somewhere
    /// the networks can't hear.
    static let silenceSplit: TimeInterval = 25 * 60
    /// Shorter "flights" are noise: a hop across the ramp, a glitchy fix.
    static let minimumDuration: TimeInterval = 3 * 60

    static func flights(in raw: [TrackPoint]) -> [FlightSegment] {
        let points = raw.sorted { $0.time < $1.time }
        guard points.count > 2 else { return [] }

        var segments: [FlightSegment] = []
        var firstAirborne: Int?
        var lastAirborne: Int?
        var groundSince: Date?

        func close() {
            guard let first = firstAirborne, let last = lastAirborne else { return }
            // One ground sample either side pins the departure and arrival
            // airports and the true wheels-up / touchdown moments.
            let lower = first > 0 && points[first - 1].onGround ? first - 1 : first
            let upper = last + 1 < points.count && points[last + 1].onGround
                && points[last + 1].time.timeIntervalSince(points[last].time) < 120
                ? last + 1 : last
            let takeoff = points[first].time
            let landing = points[upper].time
            if landing.timeIntervalSince(takeoff) >= minimumDuration, last - first >= 3 {
                segments.append(FlightSegment(takeoff: takeoff, landing: landing,
                                              points: Array(points[lower...upper])))
            }
            firstAirborne = nil
            lastAirborne = nil
        }

        for (index, point) in points.enumerated() {
            if isAirborne(point) {
                if let last = lastAirborne {
                    let silent = point.time.timeIntervalSince(points[last].time) > silenceSplit
                    let stopped = groundSince.map { point.time.timeIntervalSince($0) >= fullStop } ?? false
                    if silent || stopped { close() }
                }
                if firstAirborne == nil { firstAirborne = index }
                lastAirborne = index
                groundSince = nil
            } else if lastAirborne != nil, groundSince == nil {
                groundSince = point.time
            }
        }
        close()
        return segments
    }

    /// Positive evidence of flight. A parked transponder can report a
    /// numeric altitude, so speed is the tiebreaker whenever it's known.
    static func isAirborne(_ point: TrackPoint) -> Bool {
        if point.onGround { return false }
        if let speed = point.groundSpeedKt { return speed >= 40 }
        return point.altitudeFt != nil
    }

    /// Keeps a stored track light: very dense traces drop to about `limit`
    /// points, always keeping the final one.
    static func thinned(_ points: [TrackPoint], limit: Int = 1500) -> [TrackPoint] {
        guard points.count > limit else { return points }
        let step = points.count / limit + 1
        var result = stride(from: 0, to: points.count, by: step).map { points[$0] }
        if let last = points.last, result.last?.time != last.time { result.append(last) }
        return result
    }
}
