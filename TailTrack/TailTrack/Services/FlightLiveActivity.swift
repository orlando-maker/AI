import Foundation
import ActivityKit

/// Starts, updates, and ends the flight Live Activity (Dynamic Island +
/// Lock Screen). Updates flow from the tracker's poll loop while the app
/// runs; the island keeps showing the last state if iOS suspends the app.
@MainActor
final class FlightLiveActivity {

    private var activity: Activity<FlightActivityAttributes>?

    func start(tailNumber: String, departureIdent: String, destinationIdent: String,
               state: FlightActivityAttributes.ContentState) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let attributes = FlightActivityAttributes(
            tailNumber: tailNumber,
            departureIdent: departureIdent,
            destinationIdent: destinationIdent
        )
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: Date().addingTimeInterval(600))
        )
    }

    func update(_ state: FlightActivityAttributes.ContentState) {
        guard let activity else { return }
        Task {
            await activity.update(
                ActivityContent(state: state, staleDate: Date().addingTimeInterval(600))
            )
        }
    }

    func end(_ finalState: FlightActivityAttributes.ContentState) {
        guard let activity else { return }
        self.activity = nil
        Task {
            await activity.end(
                ActivityContent(state: finalState, staleDate: nil),
                dismissalPolicy: .after(Date().addingTimeInterval(900))
            )
        }
    }
}
