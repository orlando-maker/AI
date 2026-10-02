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

/// The app's motion vocabulary, after Apple's fluid-interface defaults:
/// springs everywhere (they start from the on-screen value and carry
/// velocity, so any motion can be interrupted mid-flight), critically
/// damped unless the user's own gesture supplied momentum.
enum Motion {
    /// Default for anything that moves: no overshoot, settles calmly.
    static let standard = Animation.spring(response: 0.35, dampingFraction: 1.0)
    /// Press release and small state flips.
    static let quick = Animation.spring(response: 0.25, dampingFraction: 1.0)
    /// Slow, continuous glides such as live progress along the route.
    static let glide = Animation.spring(response: 0.8, dampingFraction: 1.0)
    /// Map camera moves.
    static let camera = Animation.spring(response: 0.6, dampingFraction: 1.0)
}

/// Touch feedback that lands the instant a finger does: the surface dips
/// on touch-down with no animation in the way, then springs back on
/// release. Commit still happens on touch-up, so a drag-away cancels.
struct PressableButtonStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.97

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .brightness(configuration.isPressed ? -0.02 : 0)
            .animation(configuration.isPressed ? nil : Motion.quick,
                       value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableButtonStyle {
    /// Card-sized surfaces.
    static var pressable: PressableButtonStyle { PressableButtonStyle() }
    /// Small glass controls, which need a deeper dip to read as pressed.
    static var pressableControl: PressableButtonStyle { PressableButtonStyle(pressedScale: 0.9) }
}

extension View {
    /// Keeps card layouts a readable width on iPad instead of stretching
    /// edge to edge.
    func readableContentWidth() -> some View {
        frame(maxWidth: 700)
            .frame(maxWidth: .infinity)
    }

    /// A card on the paper: solid cream (ink at night), with a hairline
    /// edge so cream-on-cream still reads as a separate layer.
    func cardSurface(_ cornerRadius: CGFloat = 16) -> some View {
        background(Theme.card, in: RoundedRectangle(cornerRadius: cornerRadius))
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .strokeBorder(Color.primary.opacity(0.07), lineWidth: 0.5)
            )
    }

    /// Floating glass chrome over the map: system material (which turns
    /// solid on its own under Reduce Transparency), a bright rim where
    /// light catches the edge, and a soft shadow lifting it off the map.
    func floatingGlass<S: InsettableShape>(_ shape: S) -> some View {
        background(.thinMaterial, in: shape)
            .overlay(shape.strokeBorder(.white.opacity(0.25), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.14), radius: 6, y: 2)
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
                .tracking(0.6)
                .foregroundStyle(.white.opacity(0.7))
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
