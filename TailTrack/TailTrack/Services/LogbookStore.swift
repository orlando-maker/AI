import Foundation
import Observation

/// Completed flights, newest first, persisted as JSON in Documents so the
/// logbook is included in device backups.
@Observable
@MainActor
final class LogbookStore {

    private(set) var flights: [Flight] = []

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return dir.appendingPathComponent("logbook.json")
    }

    init() {
        load()
    }

    var totalFlightTime: TimeInterval {
        flights.compactMap(\.flightTime).reduce(0, +)
    }

    var totalDistanceNM: Double {
        flights.map(\.distanceFlownNM).reduce(0, +)
    }

    func add(_ flight: Flight) {
        // Replace rather than duplicate if the same flight gets finalized twice.
        flights.removeAll { $0.id == flight.id }
        flights.insert(flight, at: 0)
        // Imported historical entries land in date order, not import order.
        flights.sort { $0.startedTracking > $1.startedTracking }
        save()
    }

    func delete(at offsets: IndexSet) {
        flights.remove(atOffsets: offsets)
        save()
    }

    func delete(_ flight: Flight) {
        flights.removeAll { $0.id == flight.id }
        save()
    }

    func updateNotes(for flightID: UUID, notes: String) {
        guard let idx = flights.firstIndex(where: { $0.id == flightID }) else { return }
        flights[idx].notes = notes
        save()
    }

    func attachWeather(flightID: UUID, departure: String?, arrival: String?) {
        guard let idx = flights.firstIndex(where: { $0.id == flightID }) else { return }
        if let departure { flights[idx].departureMetar = departure }
        if let arrival { flights[idx].arrivalMetar = arrival }
        save()
    }

    /// Gives a logbook entry (typed in or scanned) its real ADS-B flight
    /// path. The pilot's own airports win over the ADS-B guesses, and the
    /// originally logged time is kept in the notes, since the logbook
    /// figure is often Hobbs time while ADS-B measures wheels-up to
    /// touchdown.
    func attachHistoricalTrack(flightID: UUID, segment: FlightSegment,
                               departure: Airport?, destination: Airport?, hex: String) {
        guard let idx = flights.firstIndex(where: { $0.id == flightID }) else { return }
        var flight = flights[idx]
        if flight.landingTime != nil, let logged = flight.flightTime,
           abs(logged - segment.duration) >= 6 * 60 {
            let hours = String(format: "%.1f", logged / 3600)
            let line = "Logbook entry: \(hours) h. Times below are from ADS-B."
            flight.notes = flight.notes.isEmpty ? line : flight.notes + "\n" + line
        }
        flight.track = FlightSegmenter.thinned(segment.points)
        flight.takeoffTime = segment.takeoff
        flight.landingTime = segment.landing
        flight.startedTracking = segment.points.first?.time ?? segment.takeoff
        flight.firstContact = segment.points.first?.time
        flight.icaoHex = hex
        if flight.departure == nil { flight.departure = departure }
        if flight.destination == nil { flight.destination = destination }
        flights[idx] = flight
        flights.sort { $0.startedTracking > $1.startedTracking }
        save()
    }

    func updateLandings(for flightID: UUID, landings: Int) {
        guard let idx = flights.firstIndex(where: { $0.id == flightID }) else { return }
        flights[idx].landingsCount = max(0, landings)
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([Flight].self, from: data) else { return }
        flights = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(flights) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
