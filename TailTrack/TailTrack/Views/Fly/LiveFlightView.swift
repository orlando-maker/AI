import SwiftUI
import CoreLocation

/// The live tracking screen: gradient hero card with route progress and
/// times, a stats grid, and the moving map.
struct LiveFlightView: View {
    @Environment(FlightTracker.self) private var tracker
    @Environment(ProStore.self) private var pro

    @State private var confirmingEnd = false
    @State private var hybridMap = false
    @State private var showingPaywall = false
    @State private var showingLandingSheet = false

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                heroCard
                statsGrid
                mapCard
                controls
            }
            .padding()
            .readableContentWidth()
        }
        .background(Color(uiColor: .systemGroupedBackground))
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .sheet(isPresented: $showingLandingSheet) {
            NavigationStack {
                LandingDetailsSheet(
                    initialLandingTime: tracker.flight?.landingTime
                        ?? tracker.flight?.track.last?.time ?? Date()
                ) { time, hobbs, tach in
                    tracker.recordLandingDetails(landingTime: time, hobbs: hobbs, tach: tach)
                }
            }
        }
        .confirmationDialog("End this flight?", isPresented: $confirmingEnd, titleVisibility: .visible) {
            Button("End & Save to Logbook") { tracker.endTracking() }
            Button("Discard Flight", role: .destructive) { tracker.reset() }
            Button("Keep Tracking", role: .cancel) {}
        }
    }

    // MARK: - Hero card

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(tracker.flight?.tailNumber ?? "")
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                    Text(tracker.flight?.typeCode ?? "")
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Spacer()
                StatusChip(phase: tracker.phase)
            }

            RouteProgressBar(
                departureIdent: tracker.flight?.departure?.ident ?? "———",
                destinationIdent: tracker.flight?.destination?.ident ?? "———",
                progress: tracker.progress
            )
            .tint(.white)
            .foregroundStyle(.white)

            timesRow

            HStack(spacing: 6) {
                Image(systemName: signalIcon)
                    .font(.caption2)
                Text(tracker.statusDetail)
                    .font(.caption)
                    .lineLimit(2)
                if let age = tracker.contactAgeSeconds, tracker.latest != nil {
                    Text("· \(Format.age(age))")
                        .font(.caption)
                }
                Spacer()
            }
            .foregroundStyle(.white.opacity(0.7))
        }
        .padding(18)
        .background {
            ZStack(alignment: .topTrailing) {
                if pro.isPro && tracker.phase == .enroute {
                    Theme.proSky
                } else {
                    Theme.heroGradient(for: tracker.phase)
                }
                AircraftTopView(category: .category(for: tracker.flight?.typeCode ?? ""))
                    .fill(.white.opacity(0.07))
                    .frame(width: 170, height: 170)
                    .rotationEffect(.degrees(20))
                    .offset(x: 45, y: -30)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22))
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22)
                .strokeBorder(Theme.proGold.opacity(pro.isPro ? 0.45 : 0), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    private var signalIcon: String {
        if tracker.latest == nil { return "antenna.radiowaves.left.and.right.slash" }
        if let age = tracker.contactAgeSeconds, age > 90 { return "wifi.exclamationmark" }
        return "dot.radiowaves.left.and.right"
    }

    private var timesRow: some View {
        HStack(spacing: 8) {
            GlassTile(label: "Wheels up",
                      value: tracker.flight?.takeoffTime.map(Format.localTime) ?? "—")
            GlassTile(label: "Elapsed",
                      value: tracker.elapsed.map(Format.duration) ?? "—")
            GlassTile(label: "ETE left",
                      value: tracker.eteRemaining.map(Format.duration) ?? "—")
            GlassTile(label: "ETA",
                      value: tracker.eta.map(Format.localTime) ??
                             (tracker.phase == .arrived ? tracker.flight?.landingTime.map(Format.localTime) ?? "—" : "—"))
        }
    }

    // MARK: - Stats

    private var statsGrid: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
            StatTile(label: "Altitude",
                     value: tracker.latest?.baroAltitudeFt.map(Format.feet) ??
                            (tracker.latest?.onGround == true ? "Ground" : "—"))
            StatTile(label: "Groundspeed",
                     value: tracker.latest?.groundSpeedKt.map(Format.knots) ?? "—")
            StatTile(label: "Track",
                     value: tracker.latest?.trackDeg.map(Format.degrees) ?? "—")
            StatTile(label: "Vert rate",
                     value: tracker.latest?.verticalRateFpm.map(Format.fpm) ?? "—")
            StatTile(label: "Flown",
                     value: Format.nm(tracker.flight?.distanceFlownNM ?? 0))
            StatTile(label: "Remaining",
                     value: tracker.remainingNM.map(Format.nm) ?? "—")
        }
    }

    // MARK: - Map

    private var mapCard: some View {
        FlightMapView(
            track: tracker.flight?.track ?? [],
            departure: tracker.flight?.departure,
            destination: tracker.flight?.destination,
            currentPosition: tracker.latest.map {
                CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude)
            },
            currentTrackDeg: tracker.latest?.trackDeg,
            tailNumber: tracker.flight?.tailNumber ?? "",
            useHybridStyle: hybridMap
        )
        .frame(height: 340)
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .overlay(alignment: .topTrailing) {
            Button {
                if pro.isPro {
                    hybridMap.toggle()
                } else {
                    showingPaywall = true
                }
            } label: {
                Image(systemName: hybridMap ? "map.fill" : "globe.americas.fill")
                    .font(.body.weight(.semibold))
                    .padding(9)
                    .background(.thinMaterial, in: Circle())
            }
            .padding(10)
        }
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    // MARK: - Controls

    @ViewBuilder
    private var controls: some View {
        switch tracker.phase {
        case .arrived:
            VStack(spacing: 12) {
                if let f = tracker.flight, let time = f.flightTime {
                    Text(f.isMeaningful
                         ? "Flight complete — \(Format.duration(time)), \(Format.nm(f.distanceFlownNM)). Saved to your logbook."
                         : "Flight complete — \(Format.duration(time)). Too little track data was received to save a logbook entry.")
                        .font(.subheadline)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(.secondary)
                }
                Button {
                    showingLandingSheet = true
                } label: {
                    Label("Log Engine Hours / Adjust Landing", systemImage: "engine.combustion")
                        .font(.callout.weight(.semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
                Button {
                    tracker.reset()
                } label: {
                    Text("Done")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        case .signalLost:
            VStack(spacing: 12) {
                Text("Lost the transponder signal — coverage may have dropped, or the flight ended outside receiver range. If you've landed, add the landing time (and engine hours if you keep them). Everything captured so far is saved.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button {
                    showingLandingSheet = true
                } label: {
                    Label("Add Landing Time", systemImage: "airplane.arrival")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
                Button {
                    tracker.reset()
                } label: {
                    Text("Done")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        default:
            Button(role: .destructive) {
                confirmingEnd = true
            } label: {
                Text("End Tracking")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.bordered)
        }
    }
}
