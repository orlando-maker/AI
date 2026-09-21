import SwiftUI

/// The pretty summary image rendered for sharing a flight (Pro).
struct FlightShareCard: View {
    let flight: Flight

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(flight.tailNumber)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                Spacer()
                Text(flight.startedTracking.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }

            Text(flight.routeTitle)
                .font(.system(size: 40, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.5)

            HStack(spacing: 10) {
                GlassTile(label: "Time",
                          value: flight.flightTime.map(Format.duration) ?? "—")
                GlassTile(label: "Distance",
                          value: Format.nm(flight.track.isEmpty
                                           ? (flight.routeDistanceNM ?? 0)
                                           : flight.distanceFlownNM))
                GlassTile(label: "Max alt",
                          value: flight.maxAltitudeFt.map(Format.feet) ?? "—")
            }

            HStack(spacing: 6) {
                Image(systemName: "airplane")
                Text("Tracked with TailTrack")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(26)
        .frame(width: 430)
        .background(Theme.sky)
    }
}
