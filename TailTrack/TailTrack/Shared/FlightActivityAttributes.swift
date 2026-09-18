import Foundation
import ActivityKit

/// Live Activity payload shared between the app and the widget extension —
/// this is what the Dynamic Island and Lock Screen render during a flight.
struct FlightActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var progress: Double          // 0…1 along the route
        var altitudeFt: Double?
        var groundSpeedKt: Double?
        var remainingNM: Double?
        var etaEpoch: Double?
        var phaseLabel: String
    }

    var tailNumber: String
    var departureIdent: String
    var destinationIdent: String
}
