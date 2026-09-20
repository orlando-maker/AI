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

    // MARK: - Altitude-colored track segments

    private struct TrackSegment: Identifiable {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    /// Low → high color ramp. Colors are assigned relative to THIS flight's
    /// altitude spread, so pattern work at 1,000 ft shows its climbs and
    /// descents just as vividly as a cross-country at 10,500.
    private static let rampColors: [Color] = [.green, .teal, .blue, .indigo, .purple]

    /// The flight's altitude spread, or nil when it's too small to color
    /// meaningfully (taxi-only, or no altitude data yet).
    private var altitudeRange: ClosedRange<Double>? {
        let altitudes = track.compactMap(\.altitudeFt)
        guard let low = altitudes.min(), let high = altitudes.max(),
              high - low >= 400 else { return nil }
        return low...high
    }

    private func bandIndex(_ altitudeFt: Double?, in range: ClosedRange<Double>?) -> Int {
        guard let altitudeFt, let range else { return 0 }
        let fraction = (altitudeFt - range.lowerBound) / (range.upperBound - range.lowerBound)
        return min(Self.rampColors.count - 1,
                   max(0, Int(fraction * Double(Self.rampColors.count))))
    }

    private var trackCoordinates: [CLLocationCoordinate2D] {
        track.map(\.coordinate)
    }

    private var trackSegments: [TrackSegment] {
        guard track.count > 1 else { return [] }
        let range = altitudeRange
        var segments: [TrackSegment] = []
        var coords: [CLLocationCoordinate2D] = [track[0].coordinate]
        var currentBand = bandIndex(track[0].altitudeFt, in: range)
        for point in track.dropFirst() {
            let pointBand = bandIndex(point.altitudeFt, in: range)
            coords.append(point.coordinate)
            if pointBand != currentBand {
                segments.append(TrackSegment(id: segments.count,
                                             coordinates: coords,
                                             color: Self.rampColors[currentBand]))
                coords = [point.coordinate]
                currentBand = pointBand
            }
        }
        segments.append(TrackSegment(id: segments.count,
                                     coordinates: coords,
                                     color: Self.rampColors[currentBand]))
        return segments
    }

    var body: some View {
        Map(position: $camera) {
            if plannedRoute.count > 1 {
                MapPolyline(coordinates: plannedRoute)
                    .stroke(Color.secondary, style: StrokeStyle(lineWidth: 2, dash: [7, 7]))
            }

            // A soft dark casing under the colored trail keeps it crisp
            // over any terrain — city grid, water, or satellite imagery.
            if trackCoordinates.count > 1 {
                MapPolyline(coordinates: trackCoordinates)
                    .stroke(Color.black.opacity(0.28),
                            style: StrokeStyle(lineWidth: 6, lineCap: .round, lineJoin: .round))
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
                        .background(
                            LinearGradient(colors: [Theme.brandOrange, Theme.brandOrangeDeep],
                                           startPoint: .top, endPoint: .bottom),
                            in: Circle()
                        )
                        .overlay(Circle().strokeBorder(.white, lineWidth: 2))
                        .shadow(color: Theme.brandOrange.opacity(0.55), radius: 6)
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
        .overlay(alignment: .topLeading) {
            if let range = altitudeRange {
                HStack(spacing: 5) {
                    Text(Format.feet(range.lowerBound))
                    LinearGradient(colors: Self.rampColors,
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: 42, height: 5)
                        .clipShape(Capsule())
                    Text(Format.feet(range.upperBound))
                }
                .font(.system(size: 9, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.thinMaterial, in: Capsule())
                .padding(8)
            }
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
