import SwiftUI
import MapKit

/// The airport passport: every field you've flown from or landed at,
/// stamped with first visit, visit count, and the aircraft that took you
/// there — plus the all-time spiderweb map of every track flown.
struct PassportView: View {
    @Environment(LogbookStore.self) private var logbook
    @Environment(AirportStore.self) private var airports
    @Environment(FleetStore.self) private var fleet

    enum Scope: String, CaseIterable {
        case all = "All Time"
        case year = "This Year"
    }

    @State private var scope: Scope = .all
    @State private var aircraftFilter: String?   // nil = all aircraft

    private var filteredFlights: [Flight] {
        logbook.flights.filter { flight in
            let scopeOK = scope == .all ||
                Calendar.current.isDate(flight.startedTracking, equalTo: Date(), toGranularity: .year)
            let tailOK = aircraftFilter == nil || flight.tailNumber == aircraftFilter
            return scopeOK && tailOK
        }
    }

    struct Stamp: Identifiable {
        let ident: String
        var count = 0
        var firstVisit: Date
        var tails = Set<String>()
        var airport: Airport?
        var id: String { ident }
    }

    private var stamps: [Stamp] {
        var byIdent: [String: Stamp] = [:]
        for flight in filteredFlights.sorted(by: { $0.startedTracking < $1.startedTracking }) {
            for ident in [flight.departure?.ident, flight.destination?.ident].compactMap({ $0 }) {
                var stamp = byIdent[ident] ?? Stamp(ident: ident,
                                                    firstVisit: flight.startedTracking,
                                                    airport: airports.lookup(ident))
                stamp.count += 1
                stamp.tails.insert(flight.tailNumber)
                byIdent[ident] = stamp
            }
        }
        return byIdent.values.sorted { $0.count > $1.count }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                filters
                visitedMap
                    .frame(height: 280)
                    .clipShape(RoundedRectangle(cornerRadius: 22))
                    .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
                summaryLine
                stampsGrid
            }
            .padding()
            .readableContentWidth()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Airport Passport")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var filters: some View {
        HStack {
            Picker("Scope", selection: $scope) {
                ForEach(Scope.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)

            Menu {
                Button("All Aircraft") { aircraftFilter = nil }
                ForEach(allTails, id: \.self) { tail in
                    Button(tail) { aircraftFilter = tail }
                }
            } label: {
                Label(aircraftFilter ?? "All Aircraft", systemImage: "airplane")
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
            }
        }
    }

    private var allTails: [String] {
        Array(Set(logbook.flights.map(\.tailNumber))).sorted()
    }

    private var visitedMap: some View {
        Map {
            ForEach(filteredFlights) { flight in
                let coords = thinned(flight.track)
                if coords.count > 1 {
                    MapPolyline(coordinates: coords)
                        .stroke(Color.blue.opacity(0.55), lineWidth: 2)
                }
            }
            ForEach(stamps) { stamp in
                if let airport = stamp.airport {
                    Marker(stamp.ident, systemImage: "airplane", coordinate: airport.coordinate)
                        .tint(Theme.proGold)
                }
            }
        }
        .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
    }

    private func thinned(_ track: [TrackPoint]) -> [CLLocationCoordinate2D] {
        guard track.count > 120 else { return track.map(\.coordinate) }
        let step = track.count / 120 + 1
        return track.enumerated().compactMap { $0.offset % step == 0 ? $0.element.coordinate : nil }
    }

    private var summaryLine: some View {
        Text("\(stamps.count) airports · \(filteredFlights.count) flights")
            .font(.caption.weight(.semibold))
            .textCase(.uppercase)
            .foregroundStyle(.secondary)
    }

    private var stampsGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)],
                  spacing: 12) {
            ForEach(stamps) { stamp in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(stamp.ident)
                            .font(.system(.title3, design: .rounded).weight(.heavy))
                        Spacer()
                        Image(systemName: "airplane.circle.fill")
                            .foregroundStyle(Theme.proGold)
                    }
                    if let city = stamp.airport?.municipality {
                        Text(city)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    Text("\(stamp.count) \(stamp.count == 1 ? "visit" : "visits") · since \(stamp.firstVisit.formatted(.dateTime.month(.abbreviated).year()))")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text(stamp.tails.sorted().joined(separator: " · "))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.tint)
                        .lineLimit(1)
                }
                .padding(12)
                .background(.background, in: RoundedRectangle(cornerRadius: 14))
            }
        }
    }
}
