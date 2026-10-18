import SwiftUI

/// Personal flight log: totals up top, Pro stats, then every flight —
/// tracked live or imported from a paper logbook.
struct LogbookView: View {
    @Environment(LogbookStore.self) private var logbook
    @Environment(ProStore.self) private var pro
    @Environment(FleetStore.self) private var fleet
    @Environment(AirportStore.self) private var airports

    @State private var showingPaywall = false
    @State private var addingManualEntry = false
    @State private var scanningPage = false
    @State private var logbookExportURL: URL?
    @State private var showingExport = false

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
                            NavigationLink {
                                PassportView()
                            } label: {
                                Label("Airport Passport — every field you've visited",
                                      systemImage: "wallet.pass.fill")
                                    .font(.subheadline)
                            }
                        }
                        if !onThisDay.isEmpty {
                            Section("On this day") {
                                ForEach(onThisDay) { memory in
                                    NavigationLink(value: memory.id) {
                                        memoryRow(memory)
                                    }
                                }
                            }
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
            .safeAreaInset(edge: .top) {
                VStack(spacing: 0) {
                    if let issue = logbook.storageIssue {
                        storageIssueBanner(issue)
                    }
                    pathFinderBanner
                }
            }
            .navigationTitle("Logbook")
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
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
                        if !flightsMissingPaths.isEmpty {
                            Button {
                                if pro.isPro { findMissingPaths() } else { showingPaywall = true }
                            } label: {
                                Label(pro.isPro ? "Find Missing Flight Paths" : "Find Missing Flight Paths (Pro)",
                                      systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            }
                            .disabled(PastFlightPathFinder.shared.isRunning)
                        }
                        if !logbook.flights.isEmpty {
                            Button {
                                if pro.isPro { prepareLogbookExport() } else { showingPaywall = true }
                            } label: {
                                Label(pro.isPro ? "Export Logbook (CSV)" : "Export Logbook (Pro)",
                                      systemImage: "square.and.arrow.up")
                            }
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
            .sheet(isPresented: $showingExport) {
                VStack(spacing: 16) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.largeTitle)
                        .foregroundStyle(.tint)
                    Text("Logbook export ready")
                        .font(.headline)
                    Text("\(logbook.flights.count) flights as one CSV — opens in Numbers, Excel, or any logbook app.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    if let logbookExportURL {
                        ShareLink(item: logbookExportURL) {
                            Label("Share CSV", systemImage: "square.and.arrow.up")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 6)
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }
                .padding(28)
                .presentationDetents([.medium])
            }
        }
    }

    /// Flight Memories: flights from earlier years that happened on
    /// today's date.
    private var onThisDay: [Flight] {
        let calendar = Calendar.current
        let today = calendar.dateComponents([.month, .day], from: Date())
        return logbook.flights.filter { flight in
            let comps = calendar.dateComponents([.month, .day], from: flight.startedTracking)
            let sameDay = comps.month == today.month && comps.day == today.day
            let pastYear = !calendar.isDate(flight.startedTracking, equalTo: Date(), toGranularity: .year)
            return sameDay && pastYear
        }
    }

    private func memoryRow(_ flight: Flight) -> some View {
        let years = Calendar.current.dateComponents(
            [.year], from: flight.startedTracking, to: Date()).year ?? 1
        return HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .foregroundStyle(Theme.proGold)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(max(1, years)) year\(years == 1 ? "" : "s") ago today")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(Theme.proGold)
                Text("\(flight.routeTitle) in \(flight.tailNumber)")
                    .font(.subheadline)
            }
        }
    }

    private func prepareLogbookExport() {
        let day = Date().formatted(.iso8601.year().month().day())
        logbookExportURL = FlightExport.temporaryFile(
            named: "TailTrack-logbook-\(day).csv",
            contents: FlightExport.logbookCSV(logbook.flights)
        )
        showingExport = logbookExportURL != nil
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

    /// Typed-in and scanned flights that don't have their ADS-B track yet.
    private var flightsMissingPaths: [UUID] {
        logbook.flights.filter { $0.track.count < 2 }.map(\.id)
    }

    private func findMissingPaths() {
        PastFlightPathFinder.shared.findPaths(for: flightsMissingPaths, logbook: logbook,
                                              fleet: fleet, airports: airports)
    }

    /// Progress of the bulk path lookup, then what it found.
    @ViewBuilder
    private var pathFinderBanner: some View {
        let finder = PastFlightPathFinder.shared
        if finder.isRunning {
            HStack(spacing: 10) {
                ProgressView()
                Text("Finding flight paths… \(min(finder.done + 1, finder.total)) of \(finder.total)")
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .cardSurface(12)
            .padding(.horizontal)
            .padding(.bottom, 6)
        } else if let report = finder.lastReport {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(Theme.accent)
                Text(report.summary)
                    .font(.footnote)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    finder.dismissReport()
                } label: {
                    Image(systemName: "xmark")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .accessibilityLabel("Dismiss")
            }
            .padding(12)
            .cardSurface(12)
            .padding(.horizontal)
            .padding(.bottom, 6)
        }
    }

    /// Recovery and save problems stay in front of the pilot until read:
    /// a logbook must never look silently empty.
    private func storageIssueBanner(_ issue: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
            Text(issue)
                .font(.footnote)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button {
                logbook.dismissStorageIssue()
            } label: {
                Image(systemName: "xmark")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .accessibilityLabel("Dismiss")
        }
        .padding(12)
        .cardSurface(12)
        .padding(.horizontal)
        .padding(.bottom, 6)
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
