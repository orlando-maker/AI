import SwiftUI

/// Flighty-style route progress: departure and destination idents with a
/// little airplane sliding along the bar between them.
struct RouteProgressBar: View {
    let departureIdent: String
    let destinationIdent: String
    /// 0…1, or nil when progress is unknown (no route set / not airborne).
    let progress: Double?

    var body: some View {
        VStack(spacing: 6) {
            HStack {
                Text(departureIdent)
                    .font(.system(.title3, design: .rounded).weight(.bold))
                Spacer()
                Text(destinationIdent)
                    .font(.system(.title3, design: .rounded).weight(.bold))
            }

            GeometryReader { geo in
                let p = progress ?? 0
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.quaternary)
                        .frame(height: 4)
                    Capsule()
                        .fill(.tint)
                        .frame(width: max(4, geo.size.width * p), height: 4)
                    Image(systemName: "airplane")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.tint)
                        .offset(x: max(0, min(geo.size.width - 18, geo.size.width * p - 9)))
                }
                .frame(maxHeight: .infinity)
            }
            .frame(height: 22)
        }
    }
}
