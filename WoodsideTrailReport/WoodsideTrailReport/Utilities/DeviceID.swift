import Foundation

// Generates a persistent anonymous UUID on first launch and stores it in the
// shared App Group UserDefaults so both the iOS and watchOS targets read the same ID.
final class DeviceID {
    static let shared = DeviceID()

    private static let key = "app_device_id"
    private static let defaults = UserDefaults(suiteName: Config.appGroupID) ?? .standard

    let id: UUID

    private init() {
        if let stored = Self.defaults.string(forKey: Self.key),
           let uuid = UUID(uuidString: stored) {
            id = uuid
        } else {
            let new = UUID()
            Self.defaults.set(new.uuidString, forKey: Self.key)
            id = new
        }
    }
}
