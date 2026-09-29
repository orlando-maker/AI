import SwiftUI
import UIKit

/// Shared visual language: the TailTrack print-shop palette — cream paper,
/// ink navy, and the landing page's red-orange — plus night-flight
/// gradients and card styling.
enum Theme {

    /// TailTrack brand orange — the landing page / Dynamic Island
    /// red-orange.
    static let brandOrange = Color(red: 0.94, green: 0.33, blue: 0.13)
    static let brandOrangeDeep = Color(red: 0.78, green: 0.24, blue: 0.08)

    /// Screen background: warm cream paper in light mode, ink-navy black
    /// at night — the website's palette.
    static let paper = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.055, green: 0.063, blue: 0.090, alpha: 1)
            : UIColor(red: 0.937, green: 0.918, blue: 0.863, alpha: 1)
    })

    /// Card surface on top of the paper: lighter cream by day, raised ink
    /// by night.
    static let card = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.106, green: 0.118, blue: 0.157, alpha: 1)
            : UIColor(red: 0.980, green: 0.965, blue: 0.925, alpha: 1)
    })

    /// Deep night-sky gradient used on hero cards while enroute — near-black
    /// navy so the orange route line glows against it, like the Dynamic
    /// Island pill.
    static let sky = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.05, blue: 0.14),
            Color(red: 0.07, green: 0.13, blue: 0.36),
            Color(red: 0.12, green: 0.25, blue: 0.54),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Sunset gradient for the arrived state.
    static let sunset = LinearGradient(
        colors: [
            Color(red: 0.10, green: 0.30, blue: 0.24),
            Color(red: 0.05, green: 0.45, blue: 0.34),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Pre-takeoff / searching gradient.
    static let tarmac = LinearGradient(
        colors: [
            Color(red: 0.15, green: 0.16, blue: 0.20),
            Color(red: 0.25, green: 0.27, blue: 0.34),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    /// Premium gold accent for Pro branding.
    static let proGold = Color(red: 0.95, green: 0.75, blue: 0.25)

    /// Richer midnight-indigo gradient shown to Pro members on hero cards.
    static let proSky = LinearGradient(
        colors: [
            Color(red: 0.03, green: 0.05, blue: 0.16),
            Color(red: 0.10, green: 0.12, blue: 0.38),
            Color(red: 0.24, green: 0.18, blue: 0.52),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing
    )

    static func heroGradient(for phase: FlightTracker.Phase) -> LinearGradient {
        switch phase {
        case .enroute: return sky
        case .arrived: return sunset
        default: return tarmac
        }
    }
}

/// User-selectable appearance: follow the system, or force light/dark.
enum AppearanceSetting: String, CaseIterable, Identifiable {
    case system, light, dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "System"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var colorScheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }

    static let storageKey = "appearancePreference"
}

extension View {
    /// Keeps card layouts a readable width on iPad instead of stretching
    /// edge to edge.
    func readableContentWidth() -> some View {
        frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
    }
}

/// Translucent stat cell used on top of gradient hero cards.
struct GlassTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold).monospaced())
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
                .animation(.snappy, value: value)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
