import Foundation

/// Everything needed to pick a flight back up after iOS ends the app.
struct ActiveFlightSnapshot: Codable {
    var savedAt: Date
    var phase: FlightTracker.Phase
    var flight: Flight
    var aircraft: Aircraft?
    var targetCallsign: String?
    var discoveredHex: String?
    var detector: FlightPhaseDetector
    var visitedViaIdents: [String]
    var lastSquawk: String?
    var loggedArrivalATIS: Bool
    var preLanding: PreLandingState?
}

/// The flight in progress, kept in Application Support (not the user's
/// Documents) and removed as soon as the flight is finished or discarded.
enum ActiveFlightStore {

    private static var fileURL: URL? {
        guard let dir = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask).first else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("active-flight.json")
    }

    static func save(_ snapshot: ActiveFlightSnapshot) {
        guard let fileURL, let data = try? JSONEncoder().encode(snapshot) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load() -> ActiveFlightSnapshot? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        return try? JSONDecoder().decode(ActiveFlightSnapshot.self, from: data)
    }

    static func clear() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
