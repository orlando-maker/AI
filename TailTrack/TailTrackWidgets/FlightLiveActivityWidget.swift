import ActivityKit
import WidgetKit
import SwiftUI

/// The in-flight Live Activity, styled after the TailTrack brand mock:
/// black pill, orange route line with departure/arrival glyphs, and the
/// remaining minutes on the right — KORL ✈——— KSPG | 14m.
private let ttOrange = Color(red: 0.95, green: 0.56, blue: 0.18)
private let ttPillBackground = Color(red: 0.04, green: 0.05, blue: 0.09)

struct FlightLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            LockScreenFlightView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    HStack(spacing: 5) {
                        Image(systemName: "airplane.departure")
                            .font(.caption)
                            .foregroundStyle(ttOrange)
                        Text(context.attributes.departureIdent)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.white)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    HStack(spacing: 5) {
                        Text(context.attributes.destinationIdent)
                            .font(.headline.weight(.heavy))
                            .foregroundStyle(.white)
                        Image(systemName: "airplane.arrival")
                            .font(.caption)
                            .foregroundStyle(ttOrange)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        RouteLine(progress: context.state.progress)
                        HStack {
                            if let alt = context.state.altitudeFt {
                                Text("\(Int(alt).formatted()) ft")
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            if let gs = context.state.groundSpeedKt {
                                Text("\(Int(gs)) kt")
                                    .foregroundStyle(.white.opacity(0.75))
                            }
                            Spacer()
                            if let remaining = context.state.remainingText {
                                Text(remaining)
                                    .font(.caption.weight(.heavy))
                                    .foregroundStyle(ttOrange)
                            } else if let eta = context.state.etaEpoch {
                                Text(Date(timeIntervalSince1970: eta), style: .time)
                                    .foregroundStyle(ttOrange)
                            }
                        }
                        .font(.caption2)
                        .monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: "airplane")
                    .foregroundStyle(ttOrange)
            } compactTrailing: {
                Text(context.state.remainingText ?? "\(Int((context.state.progress * 100).rounded()))%")
                    .font(.caption2.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(ttOrange)
            } minimal: {
                Image(systemName: "airplane")
                    .foregroundStyle(ttOrange)
            }
        }
    }
}

/// The orange route line: faded rail, bright flown segment, plane at the
/// current position.
private struct RouteLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(ttOrange.opacity(0.25))
                    .frame(height: 3)
                Capsule()
                    .fill(LinearGradient(colors: [ttOrange.opacity(0.55), ttOrange],
                                         startPoint: .leading, endPoint: .trailing))
                    .frame(width: max(3, geo.size.width * progress), height: 3)
                Image(systemName: "airplane")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
                    .offset(x: max(0, min(geo.size.width - 12, geo.size.width * progress - 6)),
                            y: -5)
            }
            .frame(maxHeight: .infinity)
        }
        .frame(height: 14)
    }
}

/// Lock Screen: the brand pill — route line between the idents, a divider,
/// and the minutes remaining in orange.
private struct LockScreenFlightView: View {
    let context: ActivityViewContext<FlightActivityAttributes>

    var body: some View {
        VStack(spacing: 10) {
            HStack(spacing: 10) {
                HStack(spacing: 6) {
                    Image(systemName: "airplane.departure")
                        .font(.caption)
                        .foregroundStyle(ttOrange)
                    Text(context.attributes.departureIdent)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                }

                RouteLine(progress: context.state.progress)

                HStack(spacing: 6) {
                    Text(context.attributes.destinationIdent)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                    Image(systemName: "airplane.arrival")
                        .font(.caption)
                        .foregroundStyle(ttOrange)
                }

                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 1, height: 22)

                Text(context.state.remainingText ?? "—")
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(ttOrange)
            }

            HStack {
                Text(context.attributes.tailNumber)
                if let alt = context.state.altitudeFt {
                    Text("· \(Int(alt).formatted()) ft")
                }
                if let gs = context.state.groundSpeedKt {
                    Text("· \(Int(gs)) kt")
                }
                Spacer()
                if let eta = context.state.etaEpoch {
                    Text("ETA ")
                    + Text(Date(timeIntervalSince1970: eta), style: .time)
                } else {
                    Text(context.state.phaseLabel)
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(ttPillBackground)
        .activitySystemActionForegroundColor(.white)
    }
}
