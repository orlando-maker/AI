import SwiftUI

/// Colored pill showing the current tracking phase. While enroute the dot
/// pulses like a radar sweep so "live" actually feels live.
struct StatusChip: View {
    let phase: FlightTracker.Phase

    private var color: Color {
        switch phase {
        case .idle: return .gray
        case .searching: return .gray
        case .preflight: return .orange
        case .enroute: return Theme.brandOrange
        case .arrived: return .green
        case .signalLost: return .red
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
                .overlay {
                    if phase == .enroute {
                        PulseRing(color: color)
                    }
                }
            Text(phase.label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }
}

/// The radar-sweep ring. It owns its animation state, so it starts pulsing
/// the moment it enters the hierarchy — including when the phase flips to
/// enroute long after the chip first appeared.
private struct PulseRing: View {
    let color: Color
    @State private var pulsing = false

    var body: some View {
        Circle()
            .stroke(color, lineWidth: 1.5)
            .scaleEffect(pulsing ? 2.4 : 1)
            .opacity(pulsing ? 0 : 0.8)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    pulsing = true
                }
            }
    }
}
