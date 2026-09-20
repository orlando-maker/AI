import SwiftUI
import CoreLocation

/// Black-box playback for a saved flight: scrub (or press play) and the
/// airplane moves along the track while altitude, groundspeed, and vertical
/// rate read out live. The altitude profile below is tappable — touch the
/// climb and the plane jumps there on the map.
struct FlightReplaySection: View {
    let flight: Flight

    @State private var scrubIndex: Double = 0
    @State private var isPlaying = false

    private var track: [TrackPoint] { flight.track }

    private var currentPoint: TrackPoint? {
        guard !track.isEmpty else { return nil }
        return track[min(track.count - 1, max(0, Int(scrubIndex)))]
    }

    var body: some View {
        VStack(spacing: 12) {
            FlightMapView(
                track: track,
                departure: flight.departure,
                destination: flight.destination,
                currentPosition: currentPoint?.coordinate,
                currentTrackDeg: currentPoint?.trackDeg,
                tailNumber: flight.tailNumber
            )
            .frame(height: 300)
            .clipShape(RoundedRectangle(cornerRadius: 22))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)

            if track.count > 5 {
                replayControls
                AltitudeProfileView(track: track, scrubIndex: $scrubIndex)
                    .frame(height: 120)
            }
        }
    }

    private var replayControls: some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    isPlaying.toggle()
                } label: {
                    Image(systemName: isPlaying ? "pause.circle.fill" : "play.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.tint)
                }
                .buttonStyle(.plain)

                VStack(alignment: .leading, spacing: 2) {
                    Text(currentPoint.map { Format.localTime($0.time) } ?? "—")
                        .font(.subheadline.weight(.bold))
                        .monospacedDigit()
                    if let takeoff = flight.takeoffTime, let time = currentPoint?.time,
                       time >= takeoff {
                        Text("T+\(Format.duration(time.timeIntervalSince(takeoff)))")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                    }
                }
                Spacer()
                replayStat("ALT", currentPoint?.altitudeFt.map(Format.feet)
                           ?? (currentPoint?.onGround == true ? "Ground" : "—"))
                replayStat("GS", currentPoint?.groundSpeedKt.map(Format.knots) ?? "—")
                replayStat("V/S", currentPoint?.verticalRateFpm.map(Format.fpm) ?? "—")
            }

            Slider(value: $scrubIndex, in: 0...Double(max(1, track.count - 1)))
        }
        .padding(14)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .task(id: isPlaying) {
            guard isPlaying, track.count > 1 else { return }
            let maxIndex = Double(track.count - 1)
            if scrubIndex >= maxIndex { scrubIndex = 0 }
            // The whole flight replays in about 25 seconds.
            let step = maxIndex / (25.0 / 0.05)
            while isPlaying && !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(50))
                scrubIndex = min(maxIndex, scrubIndex + step)
                if scrubIndex >= maxIndex { isPlaying = false }
            }
        }
    }

    private func replayStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(label)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(minWidth: 52)
    }
}

/// The whole flight as an altitude-over-time area chart — taxi, climb,
/// cruise, descent, pattern, landing — with a gold scrub cursor. Drag
/// anywhere and the replay jumps there.
struct AltitudeProfileView: View {
    let track: [TrackPoint]
    @Binding var scrubIndex: Double

    var body: some View {
        GeometryReader { geo in
            let altitudes = track.map { $0.altitudeFt ?? 0 }
            let maxAlt = max(altitudes.max() ?? 100, 100)
            let width = geo.size.width
            let height = geo.size.height
            let stepX = width / CGFloat(max(1, track.count - 1))

            ZStack(alignment: .topLeading) {
                Path { path in
                    path.move(to: CGPoint(x: 0, y: height))
                    for (index, altitude) in altitudes.enumerated() {
                        path.addLine(to: CGPoint(x: CGFloat(index) * stepX,
                                                 y: yFor(altitude, height: height, maxAlt: maxAlt)))
                    }
                    path.addLine(to: CGPoint(x: width, y: height))
                    path.closeSubpath()
                }
                .fill(LinearGradient(colors: [.blue.opacity(0.40), .blue.opacity(0.04)],
                                     startPoint: .top, endPoint: .bottom))

                Path { path in
                    for (index, altitude) in altitudes.enumerated() {
                        let point = CGPoint(x: CGFloat(index) * stepX,
                                            y: yFor(altitude, height: height, maxAlt: maxAlt))
                        if index == 0 { path.move(to: point) } else { path.addLine(to: point) }
                    }
                }
                .stroke(Color.blue, lineWidth: 2)

                Rectangle()
                    .fill(Theme.proGold)
                    .frame(width: 2, height: height)
                    .offset(x: CGFloat(scrubIndex) * stepX - 1)

                Text(Format.feet(maxAlt))
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(.leading, 6)
                    .padding(.top, 4)
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        // stepX is 0 before the first real layout pass; a
                        // divide-by-zero here would poison scrubIndex with
                        // NaN and crash the index clamp.
                        guard stepX > 0 else { return }
                        let index = value.location.x / stepX
                        scrubIndex = Double(min(max(0, index), CGFloat(track.count - 1)))
                    }
            )
        }
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func yFor(_ altitude: Double, height: CGFloat, maxAlt: Double) -> CGFloat {
        height - height * CGFloat(altitude / maxAlt) * 0.88 - 4
    }
}
