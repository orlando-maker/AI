import SwiftUI
import CoreLocation

/// Edge-to-edge map for the live flight: the whole screen is chart, with a
/// floating glass header and stat strip over it.
struct FullScreenFlightMapView: View {
    @Binding var hybridMap: Bool

    @Environment(FlightTracker.self) private var tracker
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false

    var body: some View {
        ZStack {
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
            .ignoresSafeArea()

            VStack {
                header
                Spacer()
                statStrip
            }
            .padding()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
            }
            .foregroundStyle(.primary)

            HStack(spacing: 8) {
                Text(tracker.flight?.departure?.ident ?? "———")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                Image(systemName: "airplane")
                    .font(.caption)
                Text(tracker.flight?.destination?.ident ?? "———")
                    .font(.system(.subheadline, design: .rounded).weight(.heavy))
                if let progress = tracker.progress {
                    Text("\(Int((progress * 100).rounded()))%")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .background(.thinMaterial, in: Capsule())

            Spacer()

            Button {
                if pro.isPro {
                    hybridMap.toggle()
                } else {
                    showingPaywall = true
                }
            } label: {
                Image(systemName: hybridMap ? "map.fill" : "globe.americas.fill")
                    .font(.body.weight(.semibold))
                    .padding(10)
                    .background(.thinMaterial, in: Circle())
            }
            .foregroundStyle(.primary)
        }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
    }

    private var statStrip: some View {
        HStack(spacing: 0) {
            fullMapStat("ALT", tracker.latest?.baroAltitudeFt.map(Format.feet) ?? "—")
            fullMapStat("GS", tracker.latest?.groundSpeedKt.map(Format.knots) ?? "—")
            fullMapStat("LEFT", tracker.remainingNM.map(Format.nm) ?? "—")
            fullMapStat("ETA", tracker.eta.map(Format.localTime) ?? "—")
        }
        .padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16))
    }

    private func fullMapStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.secondary)
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}
