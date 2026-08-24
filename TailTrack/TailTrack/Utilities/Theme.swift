import SwiftUI

/// Shared visual language: night-flight gradients and card styling.
enum Theme {

    /// Deep night-sky gradient used on hero cards while enroute.
    static let sky = LinearGradient(
        colors: [
            Color(red: 0.04, green: 0.09, blue: 0.25),
            Color(red: 0.10, green: 0.22, blue: 0.52),
            Color(red: 0.16, green: 0.35, blue: 0.68),
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

/// Translucent stat cell used on top of gradient hero cards.
struct GlassTile: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 3) {
            Text(label)
                .font(.caption2.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.65))
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}
