import SwiftUI

/// Pro feature: flying stats computed from the logbook — hours by month,
/// yearly totals, favorite airports, personal records.
struct StatsView: View {
    @Environment(LogbookStore.self) private var logbook

    private var calendar: Calendar { Calendar.current }

    private var thisYearFlights: [Flight] {
        logbook.flights.filter {
            calendar.isDate($0.startedTracking, equalTo: Date(), toGranularity: .year)
        }
    }

    private var monthlyHours: [Double] {
        var buckets = Array(repeating: 0.0, count: 12)
        for flight in thisYearFlights {
            guard let time = flight.flightTime else { continue }
            let month = calendar.component(.month, from: flight.startedTracking) - 1
            if (0..<12).contains(month) { buckets[month] += time / 3600 }
        }
        return buckets
    }

    private var topAirports: [(ident: String, count: Int)] {
        var counts: [String: Int] = [:]
        for flight in logbook.flights {
            for ident in [flight.departure?.ident, flight.destination?.ident].compactMap({ $0 }) {
                counts[ident, default: 0] += 1
            }
        }
        return counts.sorted { $0.value > $1.value }.prefix(5).map { ($0.key, $0.value) }
    }

    private var longestFlight: Flight? {
        logbook.flights.max { ($0.flightTime ?? 0) < ($1.flightTime ?? 0) }
    }

    private var farthestFlight: Flight? {
        logbook.flights.max { $0.distanceFlownNM < $1.distanceFlownNM }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                yearCard
                monthlyChartCard
                if !topAirports.isEmpty { airportsCard }
                recordsCard
            }
            .padding()
            .readableContentWidth()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle("Pilot Stats")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var yearCard: some View {
        VStack(spacing: 12) {
            Text(String(calendar.component(.year, from: Date())))
                .font(.system(.title2, design: .rounded).weight(.heavy))
                .foregroundStyle(.white)
            HStack(spacing: 8) {
                GlassTile(label: "Flights", value: "\(thisYearFlights.count)")
                GlassTile(label: "Hours",
                          value: Format.logbookHours(thisYearFlights.compactMap(\.flightTime).reduce(0, +)))
                GlassTile(label: "Distance",
                          value: Format.nm(thisYearFlights.map(\.distanceFlownNM).reduce(0, +)))
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity)
        .background(Theme.sky, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }

    private var monthlyChartCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Hours by month")
                .font(.headline)
            let maxHours = max(monthlyHours.max() ?? 0, 0.1)
            let labels = ["J", "F", "M", "A", "M", "J", "J", "A", "S", "O", "N", "D"]
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(0..<12, id: \.self) { month in
                    VStack(spacing: 4) {
                        Capsule()
                            .fill(monthlyHours[month] > 0 ? Color.accentColor : Color.gray.opacity(0.25))
                            .frame(height: max(4, 90 * monthlyHours[month] / maxHours))
                        Text(labels[month])
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(height: 110, alignment: .bottom)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var airportsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Most visited airports")
                .font(.headline)
            ForEach(topAirports, id: \.ident) { entry in
                HStack {
                    Text(entry.ident)
                        .font(.system(.subheadline, design: .rounded).weight(.bold))
                    Spacer()
                    Text("\(entry.count) \(entry.count == 1 ? "visit" : "visits")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var recordsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Personal records")
                .font(.headline)
            recordRow("clock.fill", "Longest flight",
                      longestFlight.flatMap { f in f.flightTime.map { "\(Format.duration($0)) · \(f.routeTitle)" } } ?? "—")
            recordRow("arrow.up.right.circle.fill", "Farthest flight",
                      farthestFlight.map { "\(Format.nm($0.distanceFlownNM)) · \($0.routeTitle)" } ?? "—")
            recordRow("mountain.2.fill", "Highest altitude",
                      logbook.flights.compactMap(\.maxAltitudeFt).max().map(Format.feet) ?? "—")
            recordRow("gauge.with.needle.fill", "Fastest groundspeed",
                      logbook.flights.compactMap(\.maxGroundSpeedKt).max().map(Format.knots) ?? "—")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func recordRow(_ icon: String, _ title: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Label(title, systemImage: icon)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .multilineTextAlignment(.trailing)
        }
    }
}
