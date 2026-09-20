import Foundation
import Observation

/// The user's saved aircraft, persisted as JSON in Application Support.
@Observable
@MainActor
final class FleetStore {

    private(set) var aircraft: [Aircraft] = []

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("fleet.json")
    }

    init() {
        load()
    }

    /// Personal planes with full profiles.
    var myAircraft: [Aircraft] { aircraft.filter { !$0.isClubPlane } }

    /// Quick-added club planes (tail number only).
    var clubPlanes: [Aircraft] { aircraft.filter(\.isClubPlane) }

    func add(_ plane: Aircraft) {
        aircraft.append(plane)
        save()
    }

    /// Pulls plausible registrations out of free-typed text — spaces,
    /// commas, semicolons, and new lines all separate; duplicates collapse.
    static func parseRegistrations(_ text: String) -> [String] {
        let separators = CharacterSet(charactersIn: " ,;\n\t")
        var seen = Set<String>()
        var registrations: [String] = []
        for raw in text.uppercased().components(separatedBy: separators) {
            let cleaned = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            guard (3...8).contains(cleaned.count),
                  cleaned.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "-" })
            else { continue }
            let normalized = NNumber.normalize(cleaned)
            if seen.insert(normalized).inserted { registrations.append(normalized) }
        }
        return registrations
    }

    /// Bulk-adds club planes from a blob of tail numbers ("N610SP, N152CS…").
    /// Registrations already in the fleet are skipped. Returns how many
    /// were added.
    @discardableResult
    func addClubPlanes(from text: String) -> Int {
        let existing = Set(aircraft.map { NNumber.normalize($0.tailNumber) })
        var added = 0
        for registration in Self.parseRegistrations(text) where !existing.contains(registration) {
            var plane = Aircraft()
            plane.tailNumber = registration
            plane.isClubPlane = true
            aircraft.append(plane)
            added += 1
        }
        if added > 0 { save() }
        return added
    }

    func update(_ plane: Aircraft) {
        guard let idx = aircraft.firstIndex(where: { $0.id == plane.id }) else { return }
        aircraft[idx] = plane
        save()
    }

    func delete(at offsets: IndexSet) {
        for index in offsets where index < aircraft.count {
            ImageStore.delete(aircraft[index].photoFileName)
        }
        aircraft.remove(atOffsets: offsets)
        save()
    }

    func delete(_ plane: Aircraft) {
        ImageStore.delete(plane.photoFileName)
        aircraft.removeAll { $0.id == plane.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: Self.fileURL),
              let decoded = try? JSONDecoder().decode([Aircraft].self, from: data) else { return }
        aircraft = decoded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(aircraft) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
