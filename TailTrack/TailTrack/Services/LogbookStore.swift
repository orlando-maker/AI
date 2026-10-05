import Foundation
import Observation

/// Completed flights, newest first, persisted as JSON in Documents so the
/// logbook is included in device backups.
///
/// A pilot's logbook must never quietly disappear. The last good file is
/// kept as a backup before every save; a file that can't be read is set
/// aside untouched (never overwritten) and the backup restored; and any
/// problem is shown to the pilot instead of an empty logbook.
@Observable
@MainActor
final class LogbookStore {

    private(set) var flights: [Flight] = []
    /// A recovery or save problem to show in the logbook, in plain words.
    private(set) var storageIssue: String?

    private static let schemaVersion = 1

    /// The on-disk format. Files written before the version existed are a
    /// bare array of flights and still load.
    private struct LogbookFile: Codable {
        var schemaVersion: Int
        var flights: [Flight]
    }

    private static var directory: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private static var fileURL: URL { directory.appendingPathComponent("logbook.json") }
    private static var backupURL: URL { directory.appendingPathComponent("logbook.backup.json") }

    /// True once this session has read or written logbook.json
    /// successfully, so it's safe to keep as the backup.
    private var fileIsKnownGood = false
    /// Set if an unreadable file couldn't be set aside: saving would
    /// overwrite the only copy, so it waits until the pilot gets help.
    private var savesBlocked = false

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

    func dismissStorageIssue() {
        storageIssue = nil
    }

    private func load() {
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: Self.fileURL.path) else {
            // First launch, or the main file is gone but a backup survived.
            if let restored = Self.read(Self.backupURL) {
                flights = restored
                storageIssue = "Your logbook file was missing, so TailTrack restored its backup copy."
            }
            return
        }
        if let decoded = Self.read(Self.fileURL) {
            flights = decoded
            fileIsKnownGood = true
            return
        }

        // Unreadable. Set it aside untouched for recovery, so no later save
        // can overwrite it, then fall back to the backup.
        let keptAs = Self.setAsideDamagedFile()
        savesBlocked = keptAs == nil
        let kept = keptAs.map { " The damaged file is kept as \($0) in TailTrack's folder in the Files app." } ?? ""
        if let restored = Self.read(Self.backupURL) {
            flights = restored
            storageIssue = "Your logbook file was damaged, so TailTrack restored the last good copy." + kept
        } else {
            storageIssue = "Your logbook file couldn't be read, and there's no backup yet. Nothing was deleted." + kept
                + " Contact \(LegalDocuments.supportEmail) for help recovering it."
        }
    }

    private static func read(_ url: URL) -> [Flight]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        if let file = try? decoder.decode(LogbookFile.self, from: data) { return file.flights }
        return try? decoder.decode([Flight].self, from: data)
    }

    private static func setAsideDamagedFile() -> String? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let name = "logbook-damaged-\(formatter.string(from: Date())).json"
        let destination = directory.appendingPathComponent(name)
        if (try? FileManager.default.moveItem(at: fileURL, to: destination)) != nil { return name }
        // A copy keeps it just as safe when moving isn't possible.
        if (try? FileManager.default.copyItem(at: fileURL, to: destination)) != nil { return name }
        return nil
    }

    private func save() {
        guard !savesBlocked else {
            storageIssue = "TailTrack isn't saving changes until your damaged logbook file is recovered, so it can't be overwritten. Contact \(LegalDocuments.supportEmail) for help."
            return
        }
        let fileManager = FileManager.default
        do {
            let data = try JSONEncoder().encode(LogbookFile(schemaVersion: Self.schemaVersion,
                                                            flights: flights))
            // The previous good version becomes the backup before it's replaced.
            if fileIsKnownGood, fileManager.fileExists(atPath: Self.fileURL.path) {
                try? fileManager.removeItem(at: Self.backupURL)
                try? fileManager.copyItem(at: Self.fileURL, to: Self.backupURL)
            }
            try data.write(to: Self.fileURL, options: .atomic)
            fileIsKnownGood = true
        } catch {
            storageIssue = "Couldn't save your logbook (\(error.localizedDescription)). Your flights are still here, and TailTrack will try again with the next change."
        }
    }
}
