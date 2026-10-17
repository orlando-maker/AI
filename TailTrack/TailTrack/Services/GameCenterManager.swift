import UIKit
import GameKit
import Observation

/// Game Center connection + achievement reporting. Badges always work
/// locally; this layer mirrors them to Game Center when the player signs
/// in (and, for the App Store build, the matching achievement IDs are
/// defined in App Store Connect).
@Observable
@MainActor
final class GameCenterManager {

    private(set) var isAuthenticated = GKLocalPlayer.local.isAuthenticated
    private(set) var statusMessage: String?
    private var reportedIDs = Set<String>()

    func authenticate() {
        statusMessage = "Connecting to Game Center…"
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            Task { @MainActor in
                guard let self else { return }
                if let viewController {
                    Self.presentingController?.present(viewController, animated: true)
                    return
                }
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
                if self.isAuthenticated {
                    self.statusMessage = "Connected as \(GKLocalPlayer.local.displayName)"
                } else if error != nil {
                    self.statusMessage = """
                    Couldn't connect. Make sure you're signed in under \
                    Settings → Game Center, then try again. (Developer \
                    builds installed from Xcode may not connect until the \
                    app exists in App Store Connect — badges still work.)
                    """
                } else {
                    self.statusMessage = "Game Center isn't available on this device."
                }
            }
        }
    }

    /// Mirrors locally unlocked badges to Game Center, once per session.
    func report(unlockedIDs: [String]) {
        guard isAuthenticated else { return }
        let fresh = unlockedIDs.filter { !reportedIDs.contains($0) }
        guard !fresh.isEmpty else { return }
        reportedIDs.formUnion(fresh)

        let achievements = fresh.map { id in
            let achievement = GKAchievement(identifier: id)
            achievement.percentComplete = 100
            achievement.showsCompletionBanner = true
            return achievement
        }
        GKAchievement.report(achievements) { _ in }
    }

    /// The topmost presented controller. Presenting Game Center's sign-in
    /// from the root fails silently whenever any sheet is open — and the
    /// Connect button lives inside the Achievements sheet — so walk up the
    /// presentation chain first.
    private static var presentingController: UIViewController? {
        var top = UIApplication.shared.connectedScenes
            .compactMap { ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) }
            .first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}
