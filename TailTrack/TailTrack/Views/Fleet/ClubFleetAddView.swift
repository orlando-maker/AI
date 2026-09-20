import SwiftUI

/// Quick-add for flying-club fleets: type or paste every tail number in
/// the club — "N610SP N152CS N738GG…" — and each one becomes a trackable
/// plane, no full profile needed. Type, photo, and cruise speed can be
/// filled in later by editing the plane.
struct ClubFleetAddView: View {
    @Environment(FleetStore.self) private var fleet
    @Environment(\.dismiss) private var dismiss

    @State private var text = ""

    private var parsed: [String] { FleetStore.parseRegistrations(text) }

    private var existing: Set<String> {
        Set(fleet.aircraft.map { NNumber.normalize($0.tailNumber) })
    }

    private var newCount: Int {
        parsed.filter { !existing.contains($0) }.count
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("N610SP N152CS C-GABC …", text: $text, axis: .vertical)
                        .lineLimit(3...8)
                        .textInputAutocapitalization(.characters)
                        .autocorrectionDisabled()
                        .font(.body.monospaced())
                } header: {
                    Text("Tail numbers")
                } footer: {
                    Text("Separate with spaces, commas, or new lines — paste the whole club roster at once. US N-numbers get their ADS-B identity instantly; anything else is found by live registration lookup.")
                }

                if !parsed.isEmpty {
                    Section("Adding \(newCount) plane\(newCount == 1 ? "" : "s")") {
                        ForEach(parsed, id: \.self) { registration in
                            HStack {
                                Text(registration)
                                    .font(.callout.monospaced().weight(.semibold))
                                Spacer()
                                if existing.contains(registration) {
                                    Text("Already in fleet")
                                        .font(.caption)
                                        .foregroundStyle(.tertiary)
                                } else if let hex = NNumber.icaoHex(for: registration) {
                                    Text(hex.uppercased())
                                        .font(.caption.monospaced())
                                        .foregroundStyle(.secondary)
                                } else {
                                    Text("live lookup")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Add Club Planes")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(newCount > 0 ? "Add \(newCount)" : "Add") {
                        fleet.addClubPlanes(from: text)
                        dismiss()
                    }
                    .disabled(newCount == 0)
                }
            }
        }
    }
}
