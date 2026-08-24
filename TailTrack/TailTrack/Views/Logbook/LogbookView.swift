import SwiftUI

/// Personal flight log: totals up top, Pro stats, then every flight —
/// tracked live or imported from a paper logbook.
struct LogbookView: View {
    @Environment(LogbookStore.self) private var logbook
    @Environment(ProStore.self) private var pro

    @State private var showingPaywall = false
    @State private var addingManualEntry = false
    @State private var scanningPage = false

    var body: some View {
        NavigationStack {
            Group {
                if logbook.flights.isEmpty {
                    ContentUnavailableView(
                        "No flights yet",
                        systemImage: "book.closed",
                        description: Text("Track a flight from the Fly tab, or add past flights with the + button — type them in or scan a logbook page.")
                    )
                } else {
                    List {
                        Section {
                            totalsCard
                                .listRowInsets(EdgeInsets())
                                .listRowBackground(Color.clear)
                        }
                        Section {
                            statsRow
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Menu {
                        Button {
                            addingManualEntry = true
                        } label: {
                            Label("Add Past Flight", systemImage: "square.and.pencil")
                        }
                        Button {
                            if pro.isPro { scanningPage = true } else { showingPaywall = true }
                        } label: {
                            Label(pro.isPro ? "Scan Logbook Page" : "Scan Logbook Page (Pro)",
                                  systemImage: "doc.viewfinder")
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
            .sheet(isPresented: $addingManualEntry) {
                NavigationStack { ManualFlightEntryView() }
            }
            .sheet(isPresented: $scanningPage) {
                NavigationStack { LogbookScanView() }
            }
        }
    }

    private var statsRow: some View {
        Group {
            if pro.isPro {
                NavigationLink {
                    StatsView()
                } label: {
                    statsLabel
                }
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    HStack {
                        statsLabel
                        Spacer()
                        Text("PRO")
                            .font(.caption2.weight(.heavy))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Theme.proGold.opacity(0.2), in: Capsule())
                            .foregroundStyle(Theme.proGold)
                    }
                }
                .foregroundStyle(.primary)
            }
        }
    }

    private var statsLabel: some View {
        Label("Pilot Stats — hours, records, top airports", systemImage: "chart.bar.fill")
            .font(.subheadline)
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

    private var displayDistanceNM: Double {
        flight.track.isEmpty ? (flight.routeDistanceNM ?? 0) : flight.distanceFlownNM
    }

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
                if displayDistanceNM > 0 {
                    Text(Format.nm(displayDistanceNM))
                }
                if flight.track.isEmpty {
                    Label("Imported", systemImage: "square.and.pencil")
                        .font(.caption2)
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 3)
    }
}
