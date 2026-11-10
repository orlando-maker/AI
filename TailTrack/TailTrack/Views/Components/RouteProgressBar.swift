import SwiftUI

/// Flighty-style route progress: departure and destination idents with a
/// little airplane sliding along the bar between them.
struct RouteProgressBar: View {
    let departureIdent: String
    let destinationIdent: String
    /// 0…1, or nil when progress is unknown (no route set / not airborne).
    let progress: Double?

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(departureIdent)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .tracking(-0.2)
                Spacer()
                Text(destinationIdent)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                    .tracking(-0.2)
            }

            GeometryReader { geo in
                let p = progress ?? 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.tint.opacity(0.25))
                        .frame(height: 4)
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(4, geo.size.width * p), height: 4)
                    Image(systemName: "airplane")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)
                        .shadow(color: .black.opacity(0.35), radius: 2)
                        .offset(x: max(0, min(geo.size.width - 18, geo.size.width * p - 9)))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 22)
            // A slow critically-damped glide; under Reduce Motion the plane
            // simply steps to its new spot.
            .animation(reduceMotion ? nil : Motion.glide, value: progress)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
    }

    private var accessibilityText: String {
        guard let progress else { return "\(departureIdent) to \(destinationIdent)" }
        return "\(departureIdent) to \(destinationIdent), \(Int((progress * 100).rounded())) percent of the way"
    }
}
