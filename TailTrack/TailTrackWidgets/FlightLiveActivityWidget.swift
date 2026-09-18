import ActivityKit
import WidgetKit
import SwiftUI

/// The in-flight Live Activity: route progress in the Dynamic Island and a
/// Flighty-style card on the Lock Screen.
struct FlightLiveActivityWidget: Widget {

    var body: some WidgetConfiguration {
        ActivityConfiguration(for: FlightActivityAttributes.self) { context in
            LockScreenFlightView(context: context)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.departureIdent)
                            .font(.headline)
                        Text(context.attributes.tailNumber)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(context.attributes.destinationIdent)
                            .font(.headline)
                        if let eta = context.state.etaEpoch {
                            Text(Date(timeIntervalSince1970: eta), style: .time)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    VStack(spacing: 6) {
                        FlightProgressBar(progress: context.state.progress)
                        HStack {
                            if let alt = context.state.altitudeFt {
                                Text("\(Int(alt).formatted()) ft")
                            }
                            Spacer()
                            Text(context.state.phaseLabel)
                                .foregroundStyle(.secondary)
                            Spacer()
                            if let remaining = context.state.remainingNM {
                                Text("\(Int(remaining)) nm left")
                            }
                        }
                        .font(.caption2)
                        .monospacedDigit()
                    }
                }
            } compactLeading: {
                Image(systemName: "airplane")
                    .foregroundStyle(.cyan)
            } compactTrailing: {
                Text("\(Int((context.state.progress * 100).rounded()))%")
                    .font(.caption2)
                    .monospacedDigit()
                    .foregroundStyle(.cyan)
            } minimal: {
                Image(systemName: "airplane")
                    .foregroundStyle(.cyan)
            }
        }
    }
}

/// Route progress line with a little plane riding it.
private struct FlightProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(.white.opacity(0.25))
                    .frame(height: 3)
                Capsule()
                    .fill(.cyan)
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

private struct LockScreenFlightView: View {
    let context: ActivityViewContext<FlightActivityAttributes>

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                Text(context.attributes.tailNumber)
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                Spacer()
                Text(context.state.phaseLabel)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.cyan)
            }
            HStack {
                Text(context.attributes.departureIdent)
                    .font(.title3.weight(.heavy))
                Spacer()
                Text(context.attributes.destinationIdent)
                    .font(.title3.weight(.heavy))
            }
            .foregroundStyle(.white)
            FlightProgressBar(progress: context.state.progress)
            HStack {
                if let alt = context.state.altitudeFt {
                    Text("\(Int(alt).formatted()) ft")
                }
                if let gs = context.state.groundSpeedKt {
                    Text("· \(Int(gs)) kt")
                }
                Spacer()
                if let eta = context.state.etaEpoch {
                    Text("ETA ")
                    + Text(Date(timeIntervalSince1970: eta), style: .time)
                }
            }
            .font(.caption)
            .monospacedDigit()
            .foregroundStyle(.white.opacity(0.8))
        }
        .padding(14)
        .activityBackgroundTint(Color(red: 0.05, green: 0.10, blue: 0.28))
        .activitySystemActionForegroundColor(.white)
    }
}
