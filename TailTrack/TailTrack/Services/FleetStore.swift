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

    func add(_ plane: Aircraft) {
        aircraft.append(plane)
        save()
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
