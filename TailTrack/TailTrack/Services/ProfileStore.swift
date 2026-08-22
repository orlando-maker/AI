import Foundation
import Observation

/// Persists the pilot profile as JSON in Application Support.
@Observable
@MainActor
final class ProfileStore {

    var profile = PilotProfile() {
        didSet { save() }
    }

    private static var fileURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("profile.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode(PilotProfile.self, from: data) {
            profile = decoded
        }
    }

    func setAvatar(imageData: Data) {
        ImageStore.delete(profile.avatarFileName)
        profile.avatarFileName = ImageStore.save(imageData, maxDimension: 800)
    }

    func signOut() {
        profile.appleUserID = nil
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(profile) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
