import Foundation
import CoreLocation

/// One ADS-B position sample recorded during tracking.
struct TrackPoint: Codable, Hashable {
    var time: Date
    var latitude: Double
    var longitude: Double
    var altitudeFt: Double?      // barometric; nil while on the ground
    var groundSpeedKt: Double?
    var trackDeg: Double?
    var verticalRateFpm: Double?
    var onGround: Bool

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

/// A tracked flight — live while in progress, then saved to the logbook.
struct Flight: Codable, Identifiable {
    var id = UUID()
    var tailNumber: String
    var typeCode: String
    var icaoHex: String?
    var departure: Airport?
    var destination: Airport?
    var startedTracking: Date
    var firstContact: Date?
    var takeoffTime: Date?
    var landingTime: Date?
    var track: [TrackPoint] = []
    var notes: String = ""
    /// Optional engine times logged at shutdown (Hobbs / tach reading).
    var hobbsTime: Double?
    var tachTime: Double?

    // MARK: - Derived stats

    var routeDistanceNM: Double? {
        guard let departure, let destination else { return nil }
        return GreatCircle.distanceNM(from: departure.coordinate, to: destination.coordinate)
    }

    /// Block-style flight time: first airborne sample to landing (or now while live).
    var flightTime: TimeInterval? {
        guard let takeoffTime else { return nil }
        return (landingTime ?? Date()).timeIntervalSince(takeoffTime)
    }

    private var airbornePoints: [TrackPoint] { track.filter { !$0.onGround } }

    /// Distance actually flown, summed over consecutive airborne samples.
    var distanceFlownNM: Double {
        let pts = airbornePoints
        guard pts.count > 1 else { return 0 }
        var total = 0.0
        for i in 1..<pts.count {
            total += GreatCircle.distanceNM(from: pts[i - 1].coordinate, to: pts[i].coordinate)
        }
        return total
    }

    var maxAltitudeFt: Double? {
        airbornePoints.compactMap(\.altitudeFt).max()
    }

    var maxGroundSpeedKt: Double? {
        airbornePoints.compactMap(\.groundSpeedKt).max()
    }

    var averageGroundSpeedKt: Double? {
        let speeds = airbornePoints.compactMap(\.groundSpeedKt)
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    /// Average groundspeed while in the cruise band (within 85% of max altitude).
    var cruiseGroundSpeedKt: Double? {
        guard let maxAlt = maxAltitudeFt, maxAlt > 0 else { return nil }
        let cruisePts = airbornePoints.filter { ($0.altitudeFt ?? 0) >= maxAlt * 0.85 }
        let speeds = cruisePts.compactMap(\.groundSpeedKt)
        guard !speeds.isEmpty else { return nil }
        return speeds.reduce(0, +) / Double(speeds.count)
    }

    var routeTitle: String {
        let dep = departure?.ident ?? "———"
        let dest = destination?.ident ?? "———"
        return "\(dep) → \(dest)"
    }

    /// Whether this flight captured enough to be worth keeping in the logbook.
    var isMeaningful: Bool {
        takeoffTime != nil && airbornePoints.count >= 2
    }
}
