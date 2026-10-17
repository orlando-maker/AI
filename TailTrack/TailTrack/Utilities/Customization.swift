import SwiftUI
import UIKit
import Observation

/// "Advanced UI customization" from TailTrack Pro (accent color and app
/// icon), plus the free clock preference. Observable and shared, so every
/// screen that reads `Theme.accent` or `Format.clockTime` re-renders
/// the moment a choice changes, with no view plumbing.
@Observable
final class Customization {
    static let shared = Customization()

    enum Accent: String, CaseIterable, Identifiable {
        case safetyOrange, avgasBlue, thresholdGreen, sunsetGold, navLightRed, twilightPurple

        var id: String { rawValue }

        var name: String {
            switch self {
            case .safetyOrange: return "Safety Orange"
            case .avgasBlue: return "100LL Blue"
            case .thresholdGreen: return "Threshold Green"
            case .sunsetGold: return "Sunset Gold"
            case .navLightRed: return "Nav Light Red"
            case .twilightPurple: return "Twilight Purple"
            }
        }

        var color: Color {
            switch self {
            case .safetyOrange: return Color(red: 0.94, green: 0.33, blue: 0.13)
            case .avgasBlue: return Color(red: 0.13, green: 0.47, blue: 0.86)
            case .thresholdGreen: return Color(red: 0.12, green: 0.56, blue: 0.36)
            case .sunsetGold: return Color(red: 0.82, green: 0.56, blue: 0.06)
            case .navLightRed: return Color(red: 0.84, green: 0.16, blue: 0.22)
            case .twilightPurple: return Color(red: 0.45, green: 0.30, blue: 0.85)
            }
        }

        var deep: Color {
            switch self {
            case .safetyOrange: return Color(red: 0.78, green: 0.24, blue: 0.08)
            case .avgasBlue: return Color(red: 0.08, green: 0.34, blue: 0.68)
            case .thresholdGreen: return Color(red: 0.08, green: 0.42, blue: 0.26)
            case .sunsetGold: return Color(red: 0.64, green: 0.42, blue: 0.02)
            case .navLightRed: return Color(red: 0.66, green: 0.10, blue: 0.16)
            case .twilightPurple: return Color(red: 0.33, green: 0.20, blue: 0.68)
            }
        }

        /// The brand orange is everyone's; the rest come with Pro.
        var requiresPro: Bool { self != .safetyOrange }
    }

    enum AppIcon: String, CaseIterable, Identifiable {
        case paper, ink, sunset, night

        var id: String { rawValue }
        var name: String { rawValue.capitalized }
        /// nil is the primary icon; the rest are alternate icon sets.
        var alternateIconName: String? { self == .paper ? nil : "AppIcon-\(name)" }
        var previewImageName: String { "IconPreview-\(name)" }
        var requiresPro: Bool { self != .paper }
    }

    enum Clock: String, CaseIterable, Identifiable {
        case local, zulu

        var id: String { rawValue }
        var label: String { self == .local ? "Local" : "Zulu (UTC)" }
    }

    private enum Key {
        static let accent = "customAccent"
        static let clock = "clockPreference"
        static let proUnlocked = "lastKnownPro"
    }

    var accent: Accent {
        didSet { UserDefaults.standard.set(accent.rawValue, forKey: Key.accent) }
    }

    var clock: Clock {
        didSet { UserDefaults.standard.set(clock.rawValue, forKey: Key.clock) }
    }

    /// The last Pro status StoreKit confirmed, remembered so a subscriber's
    /// colors don't flash back to orange at launch before StoreKit answers.
    var proUnlocked: Bool {
        didSet { UserDefaults.standard.set(proUnlocked, forKey: Key.proUnlocked) }
    }

    /// What's actually shown: a Pro color falls back to the brand orange
    /// if Pro lapses, and returns if it's renewed.
    var effectiveAccent: Accent {
        accent.requiresPro && !proUnlocked ? .safetyOrange : accent
    }

    private init() {
        let defaults = UserDefaults.standard
        accent = defaults.string(forKey: Key.accent).flatMap(Accent.init(rawValue:)) ?? .safetyOrange
        clock = defaults.string(forKey: Key.clock).flatMap(Clock.init(rawValue:)) ?? .local
        proUnlocked = defaults.bool(forKey: Key.proUnlocked)
    }

    @MainActor
    var currentAppIcon: AppIcon {
        let name = UIApplication.shared.alternateIconName
        return AppIcon.allCases.first { $0.alternateIconName == name } ?? .paper
    }

    @MainActor
    func setAppIcon(_ icon: AppIcon) async throws {
        guard UIApplication.shared.supportsAlternateIcons,
              UIApplication.shared.alternateIconName != icon.alternateIconName else { return }
        try await UIApplication.shared.setAlternateIconName(icon.alternateIconName)
    }
}
