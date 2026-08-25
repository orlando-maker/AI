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
