import SwiftUI
import MapKit

/// One aircraft's whole life in TailTrack: hours, records, airports, most
/// common route, and every track it has flown on one map.
struct AircraftHistoryView: View {
    let plane: Aircraft

    @Environment(LogbookStore.self) private var logbook
    @Environment(FleetStore.self) private var fleet
    @State private var editing = false

    private var flights: [Flight] {
        let tail = NNumber.normalize(plane.tailNumber)
        return logbook.flights.filter { $0.tailNumber == tail }
    }

    private var totalHours: Double {
        flights.compactMap(\.flightTime).reduce(0, +) / 3600
    }

    private var visitedIdents: Set<String> {
        var idents = Set<String>()
        for flight in flights {
            if let dep = flight.departure?.ident { idents.insert(dep) }
            if let dest = flight.destination?.ident { idents.insert(dest) }
        }
        return idents
    }

    private var mostCommonRoute: String? {
        var counts: [String: Int] = [:]
        for flight in flights {
            guard let dep = flight.departure?.ident, let dest = flight.destination?.ident else { continue }
            counts["\(dep) → \(dest)", default: 0] += 1
        }
        return counts.max { $0.value < $1.value }.flatMap { $0.value > 1 ? $0.key : nil }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                headerCard
                combinedMap
                statsGrid
                if let route = mostCommonRoute {
                    LabeledContent("Most flown route", value: route)
                        .padding(16)
                        .background(.background, in: RoundedRectangle(cornerRadius: 16))
                }
            }
            .padding()
            .readableContentWidth()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(plane.displayName)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Edit") { editing = true }
            }
        }
        .sheet(isPresented: $editing) {
            NavigationStack {
                AircraftEditView(aircraft: plane, isEditing: true) { fleet.update($0) }
            }
        }
    }

    private var headerCard: some View {
        VStack(spacing: 12) {
            if let image = ImageStore.load(plane.photoFileName) {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .frame(height: 160)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            } else {
                AircraftArtView(typeCode: plane.typeCode, inset: 26)
                    .frame(height: 140)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            HStack(spacing: 8) {
                GlassTile(label: "Hours", value: String(format: "%.1f", totalHours))
                GlassTile(label: "Flights", value: "\(flights.count)")
                GlassTile(label: "Airports", value: "\(visitedIdents.count)")
            }
        }
        .padding(14)
        .background(Theme.sky, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }

    private var combinedMap: some View {
        Map {
            ForEach(flights) { flight in
                let coords = thinned(flight.track)
                if coords.count > 1 {
                    MapPolyline(coordinates: coords)
                        .stroke(Theme.brandOrange.opacity(0.55), lineWidth: 2)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        .frame(height: 260)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    private func thinned(_ track: [TrackPoint]) -> [CLLocationCoordinate2D] {
        guard track.count > 120 else { return track.map(\.coordinate) }
        let step = track.count / 120 + 1
        return track.enumerated().compactMap { $0.offset % step == 0 ? $0.element.coordinate : nil }
    }

    private var statsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 2), spacing: 10) {
            StatTile(label: "First flight",
                     value: flights.map(\.startedTracking).min()
                        .map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
            StatTile(label: "Last flight",
                     value: flights.map(\.startedTracking).max()
                        .map { $0.formatted(date: .abbreviated, time: .omitted) } ?? "—")
            StatTile(label: "Longest flight",
                     value: flights.map(\.distanceFlownNM).max().map(Format.nm) ?? "—")
            StatTile(label: "Highest",
                     value: flights.compactMap(\.maxAltitudeFt).max().map(Format.feet) ?? "—")
            StatTile(label: "Landings",
                     value: "\(flights.reduce(0) { $0 + ($1.landingsCount ?? min($1.detectedLandings, 1)) })")
            StatTile(label: "Cruise speed",
                     value: Format.knots(plane.cruiseSpeedKt))
        }
    }
}
