import SwiftUI
import CoreLocation

/// A saved flight: route summary, map of the flown track, stats, notes,
/// and (Pro) GPX/CSV export.
struct FlightDetailView: View {
    let flight: Flight

    @Environment(LogbookStore.self) private var logbook
    @Environment(ProStore.self) private var pro
    @State private var notes: String = ""
    @State private var showingPaywall = false
    @State private var gpxURL: URL?
    @State private var csvURL: URL?
    @State private var shareCardURL: URL?
    @State private var suggestedLandings = 0
    @State private var confirmedLandings: Int?

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                FlightReplaySection(flight: flight)
                storyCard
                if flight.landingsCount == nil && confirmedLandings == nil
                    && flight.detectedLandings >= 2 {
                    landingsSuggestionCard
                }
                statsGrid
                if flight.departureMetar != nil || flight.arrivalMetar != nil {
                    weatherCard
                }
                notesCard
                exportCard
            }
            .padding()
            .readableContentWidth()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(flight.routeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .onAppear {
            notes = flight.notes
            suggestedLandings = flight.detectedLandings
            if pro.isPro { prepareExports() }
        }
        .onChange(of: pro.isPro) { _, isPro in
            if isPro { prepareExports() }
        }
    }

    private var summaryCard: some View {
        VStack(spacing: 12) {
            HStack {
                Text(flight.tailNumber)
                    .font(.system(.title3, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                Spacer()
                Text(flight.startedTracking.formatted(date: .abbreviated, time: .omitted))
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.7))
            }
            RouteProgressBar(
                departureIdent: flight.departure?.ident ?? "———",
                destinationIdent: flight.destination?.ident ?? "———",
                progress: 1
            )
            .tint(.white)
            .foregroundStyle(.white)
            HStack(spacing: 8) {
                GlassTile(label: "Wheels up",
                          value: flight.takeoffTime.map(Format.localTime) ?? "—")
                GlassTile(label: "Landed",
                          value: flight.landingTime.map(Format.localTime) ?? "—")
                GlassTile(label: "Time",
                          value: flight.flightTime.map(Format.duration) ?? "—")
            }
        }
        .padding(18)
        .background(Theme.sunset, in: RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
    }

    private var storyCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Flight story")
                    .font(.headline)
                Spacer()
                ShareLink(item: flight.story) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.callout)
                }
            }
            Text(flight.story)
                .font(.callout)
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var landingsSuggestionCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(flight.isLikelyPatternWork
                  ? "Looks like pattern work at \(flight.destination?.ident ?? "the field")"
                  : "Multiple landings detected",
                  systemImage: "arrow.triangle.2.circlepath")
                .font(.headline)
            Text("TailTrack counted \(flight.detectedLandings) landings from the track. ADS-B gets patchy at pattern altitude, so confirm the number before it's recorded — this is your data, not instruction.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Stepper("Landings: \(suggestedLandings)", value: $suggestedLandings, in: 1...50)
                    .font(.callout)
                Button("Confirm") {
                    logbook.updateLandings(for: flight.id, landings: suggestedLandings)
                    confirmedLandings = suggestedLandings
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var weatherCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Weather at the time")
                .font(.headline)
            if let dep = flight.departureMetar {
                Text(dep)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
            if let arr = flight.arrivalMetar, arr != flight.departureMetar {
                Text(arr)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var statsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            StatTile(label: "Distance", value: Format.nm(flight.distanceFlownNM))
            StatTile(label: "Direct", value: flight.routeDistanceNM.map(Format.nm) ?? "—")
            StatTile(label: "Max alt", value: flight.maxAltitudeFt.map(Format.feet) ?? "—")
            StatTile(label: "Max GS", value: flight.maxGroundSpeedKt.map(Format.knots) ?? "—")
            StatTile(label: "Avg GS", value: flight.averageGroundSpeedKt.map(Format.knots) ?? "—")
            StatTile(label: "Cruise GS", value: flight.cruiseGroundSpeedKt.map(Format.knots) ?? "—")
            if let hobbs = flight.hobbsTime {
                StatTile(label: "Hobbs", value: String(format: "%.1f", hobbs))
            }
            if let tach = flight.tachTime {
                StatTile(label: "Tach", value: String(format: "%.1f", tach))
            }
            if let landings = flight.landingsCount ?? confirmedLandings {
                StatTile(label: "Landings", value: "\(landings)")
            }
            if let planned = flight.plannedDestinationIdent {
                StatTile(label: "Planned dest", value: planned)
            }
        }
    }

    private var notesCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Notes")
                .font(.headline)
            TextField("Squawks, conditions, who was aboard…", text: $notes, axis: .vertical)
                .lineLimit(3...8)
                .onSubmit { logbook.updateNotes(for: flight.id, notes: notes) }
            if notes != flight.notes {
                Button("Save Notes") {
                    logbook.updateNotes(for: flight.id, notes: notes)
                }
                .font(.callout.weight(.semibold))
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private var exportCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Export")
                    .font(.headline)
                if !pro.isPro {
                    Text("PRO")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.proGold.opacity(0.2), in: Capsule())
                        .foregroundStyle(Theme.proGold)
                }
                Spacer()
            }
            if pro.isPro {
                HStack(spacing: 12) {
                    if let shareCardURL {
                        ShareLink(item: shareCardURL) {
                            Label("Share card", systemImage: "photo.badge.arrow.down")
                        }
                    }
                    if let gpxURL {
                        ShareLink(item: gpxURL) {
                            Label("GPX", systemImage: "square.and.arrow.up")
                        }
                    }
                    if let csvURL {
                        ShareLink(item: csvURL) {
                            Label("CSV", systemImage: "tablecells")
                        }
                    }
                }
                .font(.callout)
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    Label("Unlock GPX & CSV export with Pro", systemImage: "lock.fill")
                        .font(.callout)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.background, in: RoundedRectangle(cornerRadius: 16))
    }

    private func prepareExports() {
        let base = FlightExport.baseFileName(for: flight)
        gpxURL = FlightExport.temporaryFile(named: base + ".gpx",
                                            contents: FlightExport.gpx(for: flight))
        csvURL = FlightExport.temporaryFile(named: base + ".csv",
                                            contents: FlightExport.csv(for: flight))

        let renderer = ImageRenderer(content: FlightShareCard(flight: flight))
        renderer.scale = 3
        if let image = renderer.uiImage, let data = image.pngData() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent(base + "-card.png")
            if (try? data.write(to: url, options: .atomic)) != nil {
                shareCardURL = url
            }
        }
    }
}
