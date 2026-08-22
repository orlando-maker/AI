import SwiftUI

/// Personal flight log: totals up top, then every tracked flight.
struct LogbookView: View {
    @Environment(LogbookStore.self) private var logbook

    var body: some View {
        NavigationStack {
            Group {
                if logbook.flights.isEmpty {
                    ContentUnavailableView(
                        "No flights yet",
                        systemImage: "book.closed",
                        description: Text("Track a flight from the Fly tab and it lands here automatically.")
                    )
                } else {
                    List {
                        Section {
                            totalsCard
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        Section("Flights") {
                            ForEach(logbook.flights) { flight in
                                NavigationLink(value: flight.id) {
                                    LogbookRow(flight: flight)
                                }
                            }
                            .onDelete { logbook.delete(at: $0) }
                        }
                    }
                    .navigationDestination(for: UUID.self) { id in
                        if let flight = logbook.flights.first(where: { $0.id == id }) {
                            FlightDetailView(flight: flight)
                        }
                    }
                }
            }
            .navigationTitle("Logbook")
        }
    }

    private var totalsCard: some View {
        HStack(spacing: 10) {
            totalTile(value: "\(logbook.flights.count)", label: "Flights")
            totalTile(value: Format.logbookHours(logbook.totalFlightTime), label: "Time")
            totalTile(value: Format.nm(logbook.totalDistanceNM), label: "Distance")
        }
    }

    private func totalTile(value: String, label: String) -> some View {
        VStack(spacing: 4) {
            Text(value)
                .font(.system(.title3, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label.uppercased())
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white.opacity(0.65))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 14)
        .background(Theme.sky, in: RoundedRectangle(cornerRadius: 14))
    }
}

private struct LogbookRow: View {
    let flight: Flight

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(flight.routeTitle)
                    .font(.system(.headline, design: .rounded))
                Spacer()
                if let time = flight.flightTime {
                    Text(Format.duration(time))
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.tint)
                }
            }
            HStack(spacing: 10) {
                Text(flight.startedTracking.formatted(date: .abbreviated, time: .omitted))
                Text(flight.tailNumber)
                Text(Format.nm(flight.distanceFlownNM))
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
