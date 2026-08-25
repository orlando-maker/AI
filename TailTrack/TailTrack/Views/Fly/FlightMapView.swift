import SwiftUI
import MapKit

/// Shared map for live tracking and logbook detail: the flown track colored
/// by altitude band, the planned great-circle route, airport pins, the
/// aircraft's current position, and a follow-aircraft mode.
struct FlightMapView: View {
    let track: [TrackPoint]
    let departure: Airport?
    let destination: Airport?
    let currentPosition: CLLocationCoordinate2D?
    let currentTrackDeg: Double?
    let tailNumber: String
    var useHybridStyle = false

    @State private var camera: MapCameraPosition = .automatic
    @State private var followAircraft = false

    private var plannedRoute: [CLLocationCoordinate2D] {
        guard let departure, let destination else { return [] }
        return GreatCircle.routePoints(from: departure.coordinate, to: destination.coordinate)
    }

    // MARK: - Altitude-banded track segments

    private struct TrackSegment: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    private static let bandColors: [Color] = [.green, .teal, .blue, .indigo]

    private static func band(_ altitudeFt: Double?) -> Int {
        guard let altitudeFt else { return 0 }
        if altitudeFt < 2000 { return 0 }
        if altitudeFt < 6000 { return 1 }
        if altitudeFt < 10000 { return 2 }
        return 3
    }

    private var trackSegments: [TrackSegment] {
        guard track.count > 1 else { return [] }
        var segments: [TrackSegment] = []
        var coords: [CLLocationCoordinate2D] = [track[0].coordinate]
        var currentBand = Self.band(track[0].altitudeFt)
        for point in track.dropFirst() {
            let pointBand = Self.band(point.altitudeFt)
            coords.append(point.coordinate)
            if pointBand != currentBand {
                segments.append(TrackSegment(id: segments.count,
                                             coordinates: coords,
                                             color: Self.bandColors[currentBand]))
                coords = [point.coordinate]
                currentBand = pointBand
            }
        }
        segments.append(TrackSegment(id: segments.count,
                                     coordinates: coords,
                                     color: Self.bandColors[currentBand]))
        return segments
    }

    var body: some View {
        Map(position: $camera) {
            if plannedRoute.count > 1 {
                MapPolyline(coordinates: plannedRoute)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [7, 7]))
            }

            ForEach(trackSegments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(segment.color,
                            style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round))
            }

            if let departure {
                Annotation(departure.ident, coordinate: departure.coordinate) {
                    Image(systemName: "airplane.departure")
                        .font(.caption)
                        .padding(5)
                        .background(.background, in: Circle())
                        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4)))
                }
            }

            if let destination {
                Annotation(destination.ident, coordinate: destination.coordinate) {
                    Image(systemName: "airplane.arrival")
                        .font(.caption)
                        .padding(5)
                        .background(.background, in: Circle())
                        .overlay(Circle().strokeBorder(Color.secondary.opacity(0.4)))
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
        .mapStyle(useHybridStyle
                  ? .hybrid(elevation: .realistic)
                  : .standard(elevation: .realistic, emphasis: .muted,
                              pointsOfInterest: .excludingAll))
        .mapControls {
            MapCompass()
            MapScaleView()
        }
        .overlay(alignment: .bottomTrailing) {
            if currentPosition != nil {
                Button {
                    followAircraft.toggle()
                    if followAircraft {
                        updateFollowCamera(animated: true)
                    } else {
                        withAnimation { camera = .automatic }
                    }
                } label: {
                    Image(systemName: followAircraft ? "location.fill.viewfinder" : "location.viewfinder")
                        .font(.body.weight(.semibold))
                        .padding(9)
                        .background(.thinMaterial, in: Circle())
                        .foregroundStyle(followAircraft ? Color.blue : Color.primary)
                }
                .padding(10)
            }
        }
        .onChange(of: currentPosition?.latitude) { _, _ in
            updateFollowCamera(animated: true)
        }
    }

    private func updateFollowCamera(animated: Bool) {
        guard followAircraft, let currentPosition else { return }
        let newCamera = MapCameraPosition.camera(
            MapCamera(centerCoordinate: currentPosition, distance: 45_000)
        )
        if animated {
            withAnimation(.easeInOut(duration: 0.6)) { camera = newCamera }
        } else {
            camera = newCamera
        }
    }
}
