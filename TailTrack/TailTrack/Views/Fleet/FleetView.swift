import SwiftUI

/// The user's hangar: saved aircraft with photos, type, cruise speed, and
/// the derived Mode S hex.
struct FleetView: View {
    @Environment(FleetStore.self) private var fleet
    @Environment(ProStore.self) private var pro

    @State private var editingAircraft: Aircraft?
    @State private var addingAircraft = false
    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            List {
                ForEach(fleet.aircraft) { plane in
                    Button {
                        editingAircraft = plane
                    } label: {
                        AircraftRow(plane: plane)
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { fleet.delete(at: $0) }

                if fleet.aircraft.isEmpty {
                    ContentUnavailableView(
                        "No aircraft yet",
                        systemImage: "airplane.circle",
                        description: Text("Add the plane you fly — tail number and type — and TailTrack figures out its ADS-B identity automatically.")
                    )
                }
            }
            .navigationTitle("Aircraft")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        if fleet.aircraft.count >= 1 && !pro.isPro {
                            showingPaywall = true
                        } else {
                            addingAircraft = true
                        }
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $addingAircraft) {
                NavigationStack {
                    AircraftEditView(aircraft: Aircraft()) { fleet.add($0) }
                }
            }
            .sheet(item: $editingAircraft) { plane in
                NavigationStack {
                    AircraftEditView(aircraft: plane, isEditing: true) { fleet.update($0) }
                }
            }
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }
}

private struct AircraftRow: View {
    let plane: Aircraft

    var body: some View {
        HStack(spacing: 12) {
            aircraftThumbnail
            VStack(alignment: .leading, spacing: 3) {
                Text(plane.displayName)
                    .font(.system(.headline, design: .rounded))
                Text(plane.subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Label(Format.knots(plane.cruiseSpeedKt), systemImage: "gauge.with.needle")
                    if let base = plane.homeAirportIdent {
                        Label(base, systemImage: "house")
                    }
                    if let hex = plane.resolvedHex {
                        Label(hex.uppercased(), systemImage: "dot.radiowaves.left.and.right")
                            .font(.caption.monospaced())
                    }
                }
                .font(.caption)
                .foregroundStyle(.tertiary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }

    @ViewBuilder
    private var aircraftThumbnail: some View {
        if let image = ImageStore.load(plane.photoFileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: 64, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            AircraftArtView(typeCode: plane.typeCode, inset: 5)
                .frame(width: 64, height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
