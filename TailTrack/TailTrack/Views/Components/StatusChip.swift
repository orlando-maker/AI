import SwiftUI

/// Colored pill showing the current tracking phase.
struct StatusChip: View {
    let phase: FlightTracker.Phase

    private var color: Color {
        switch phase {
        case .idle: return .gray
        case .searching: return .gray
        case .preflight: return .orange
        case .enroute: return .blue
        case .arrived: return .green
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(phase.label)
                .font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(color.opacity(0.15), in: Capsule())
        .foregroundStyle(color)
    }
}
