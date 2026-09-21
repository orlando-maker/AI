import ActivityKit
import WidgetKit
import SwiftUI

// TailTrack brand colors for the Live Activity surfaces.
private let ttOrange = Color(red: 0.95, green: 0.56, blue: 0.18)
private let ttPillBackground = Color(red: 0.04, green: 0.05, blue: 0.09)

/// The in-flight Live Activity, styled after the TailTrack brand mock:
/// black pill, orange route line with departure/arrival glyphs, and the
/// time remaining on the right. Remaining time renders as a system-driven
/// countdown from the ETA, so it keeps ticking even when iOS suspends the
/// app and updates stop flowing.
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
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        HStack(spacing: 5) {
                            Text(context.attributes.destinationIdent)
                                .font(.headline.weight(.heavy))
                                .foregroundStyle(.white)
                                .lineLimit(1)
                                .minimumScaleFactor(0.7)
                            Image(systemName: "airplane.arrival")
                                .font(.caption)
                                .foregroundStyle(ttOrange)
                        }
                        if let eta = context.state.etaEpoch {
                            Text(Date(timeIntervalSince1970: eta), style: .time)
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        RouteLine(progress: context.state.progress)
                        HStack {
                            if let alt = context.state.altitudeFt {
                                Text("\(Int(alt.rounded()).formatted()) ft")
                            }
                            if let gs = context.state.groundSpeedKt {
                                Text("\(Int(gs.rounded())) kt")
                            }
                            Spacer()
                            Text(context.state.phaseLabel)
                                .foregroundStyle(.white.opacity(0.6))
                            Spacer()
                            if let remaining = context.state.remainingNM {
                                Text("\(Int(remaining.rounded())) nm left")
                                    .foregroundStyle(ttOrange)
                            }
                        }
                        .font(.caption2)
                        .monospacedDigit()
                        .foregroundStyle(.white.opacity(0.85))
                        .lineLimit(1)
                    }
                }
            } compactLeading: {
                Image(systemName: "airplane")
                    .foregroundStyle(ttOrange)
            } compactTrailing: {
                CountdownText(etaEpoch: context.state.etaEpoch,
                              fallback: "\(Int((context.state.progress * 100).rounded()))%")
                    .font(.caption2.weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(ttOrange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: 48)
            } minimal: {
                Image(systemName: "airplane")
                    .foregroundStyle(ttOrange)
            }
        }
    }
}

/// A self-updating countdown to the ETA; falls back to static text when
/// there's no ETA (or it has passed).
private struct CountdownText: View {
    let etaEpoch: Double?
    let fallback: String

    var body: some View {
        if let etaEpoch, etaEpoch > Date().timeIntervalSince1970 + 1 {
            Text(timerInterval: Date.now...Date(timeIntervalSince1970: etaEpoch),
                 countsDown: true)
        } else {
            Text(fallback)
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
        .frame(minWidth: 50)
    }
}

/// Lock Screen: the brand pill — route line between the idents, a divider,
/// and the live countdown (or the phase once the flight has ended).
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
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                RouteLine(progress: context.state.progress)

                HStack(spacing: 6) {
                    Text(context.attributes.destinationIdent)
                        .font(.system(.headline, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    Image(systemName: "airplane.arrival")
                        .font(.caption)
                        .foregroundStyle(ttOrange)
                }

                Rectangle()
                    .fill(.white.opacity(0.25))
                    .frame(width: 1, height: 22)

                CountdownText(etaEpoch: context.state.etaEpoch,
                              fallback: context.state.phaseLabel)
                    .font(.system(.headline, design: .rounded).weight(.heavy))
                    .monospacedDigit()
                    .foregroundStyle(ttOrange)
                    .lineLimit(1)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: 76, alignment: .trailing)
            }

            HStack {
                Text(context.attributes.tailNumber)
                if let alt = context.state.altitudeFt {
                    Text("· \(Int(alt.rounded()).formatted()) ft")
                }
                if let gs = context.state.groundSpeedKt {
                    Text("· \(Int(gs.rounded())) kt")
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
            .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .activityBackgroundTint(ttPillBackground)
        .activitySystemActionForegroundColor(.white)
    }
}
