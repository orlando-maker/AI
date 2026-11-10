import Foundation
import UIKit

#if canImport(GoogleSignIn)
import GoogleSignIn

/// Google Sign-In, active when the GoogleSignIn package is added and a
/// GIDClientID is configured (see README → Google Sign-In).
enum GoogleAuth {
    static let isAvailable = true

    static var isConfigured: Bool {
        !((Bundle.main.object(forInfoDictionaryKey: "GIDClientID") as? String) ?? "").isEmpty
    }

    @MainActor
    static func signIn() async throws -> (id: String, name: String?) {
        guard let root = UIApplication.shared.connectedScenes
            .compactMap({ ($0 as? UIWindowScene)?.windows.first(where: \.isKeyWindow) })
            .first?.rootViewController else {
            throw NSError(domain: "TailTrack", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "No window available to present sign-in."])
        }
        let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: root)
        return (result.user.userID ?? UUID().uuidString, result.user.profile?.name)
    }

    static func handle(url: URL) {
        _ = GIDSignIn.sharedInstance.handle(url)
    }

    static func signOut() {
        GIDSignIn.sharedInstance.signOut()
    }
}

#else

/// Stub used when the GoogleSignIn package isn't part of the build.
/// Enable it via the commented package in project.yml (see README).
enum GoogleAuth {
    static let isAvailable = false
    static var isConfigured: Bool { false }

    @MainActor
    static func signIn() async throws -> (id: String, name: String?) {
        throw NSError(domain: "TailTrack", code: 1,
                      userInfo: [NSLocalizedDescriptionKey:
                        "Google Sign-In isn't enabled in this build — see the README to add it."])
    }

    static func handle(url: URL) {}
    static func signOut() {}
}

#endif
