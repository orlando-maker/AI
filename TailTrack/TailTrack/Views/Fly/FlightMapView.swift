import SwiftUI
import MapKit

/// Shared map for live tracking and logbook detail: flown track, planned
/// great-circle route, airport pins, and the aircraft's current position.
struct FlightMapView: View {
    let track: [TrackPoint]
    let departure: Airport?
    let destination: Airport?
    let currentPosition: CLLocationCoordinate2D?
    let currentTrackDeg: Double?
    let tailNumber: String
    var useHybridStyle = false

    @State private var camera: MapCameraPosition = .automatic

    private var plannedRoute: [CLLocationCoordinate2D] {
        guard let departure, let destination else { return [] }
        return GreatCircle.routePoints(from: departure.coordinate, to: destination.coordinate)
    }

    private var flownCoordinates: [CLLocationCoordinate2D] {
        track.map(\.coordinate)
    }

    var body: some View {
        Map(position: $camera) {
            if plannedRoute.count > 1 {
                MapPolyline(coordinates: plannedRoute)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [7, 7]))
            }

            if flownCoordinates.count > 1 {
                MapPolyline(coordinates: flownCoordinates)
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            }

            if let departure {
                Annotation(departure.ident, coordinate: departure.coordinate) {
                    Image(systemName: "airplane.departure")
                        .font(.caption)
                        .padding(5)
                        .background(.background, in: Circle())
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.4)))
                }
            }

            if let destination {
                Annotation(destination.ident, coordinate: destination.coordinate) {
                    Image(systemName: "airplane.arrival")
                        .font(.caption)
                        .padding(5)
                        .background(.background, in: Circle())
                        .overlay(Circle().strokeBorder(.secondary.opacity(0.4)))
                }
            }

            if let currentPosition {
                Annotation(tailNumber, coordinate: currentPosition) {
                    Image(systemName: "airplane")
                        .font(.title3.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(radius: 2)
                        .rotationEffect(.degrees((currentTrackDeg ?? 90) - 90))
                        .padding(7)
                        .background(Color.blue, in: Circle())
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                }
            }
        }
        .mapStyle(useHybridStyle ? .hybrid(elevation: .realistic) : .standard(elevation: .flat))
    }
}
