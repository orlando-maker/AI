import SwiftUI

/// Switches between the flight setup form and the live tracking screen.
struct FlyView: View {
    @Environment(FlightTracker.self) private var tracker

    var body: some View {
        NavigationStack {
            Group {
                if tracker.isActive {
                    LiveFlightView()
                } else {
                    FlightSetupView()
                }
            }
            .navigationTitle(tracker.isActive ? "" : "TailTrack")
            .navigationBarTitleDisplayMode(tracker.isActive ? .inline : .large)
        }
    }
}
