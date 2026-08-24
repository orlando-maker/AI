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

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                summaryCard
                map
                statsGrid
                notesCard
                exportCard
            }
            .padding()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .navigationTitle(flight.routeTitle)
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .onAppear {
            notes = flight.notes
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

    private var map: some View {
        FlightMapView(
            track: flight.track,
            departure: flight.departure,
            destination: flight.destination,
            currentPosition: nil,
            currentTrackDeg: nil,
            tailNumber: flight.tailNumber
        )
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    private var statsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            StatTile(label: "Distance", value: Format.nm(flight.distanceFlownNM))
            StatTile(label: "Direct", value: flight.routeDistanceNM.map(Format.nm) ?? "—")
            StatTile(label: "Max alt", value: flight.maxAltitudeFt.map(Format.feet) ?? "—")
            StatTile(label: "Max GS", value: flight.maxGroundSpeedKt.map(Format.knots) ?? "—")
            StatTile(label: "Avg GS", value: flight.averageGroundSpeedKt.map(Format.knots) ?? "—")
            StatTile(label: "Cruise GS", value: flight.cruiseGroundSpeedKt.map(Format.knots) ?? "—")
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
