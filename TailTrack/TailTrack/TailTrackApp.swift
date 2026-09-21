import SwiftUI

@main
struct TailTrackApp: App {
    @State private var airports = AirportStore()
    @State private var fleet = FleetStore()
    @State private var logbook = LogbookStore()
    @State private var tracker = FlightTracker()
    @State private var profile = ProfileStore()
    @State private var pro = ProStore()

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(airports)
                .environment(fleet)
                .environment(logbook)
                .environment(tracker)
                .environment(profile)
                .environment(pro)
                .task {
                    tracker.logbook = logbook
                    tracker.airports = airports
                }
        }
    }
}
