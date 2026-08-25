import SwiftUI

/// Searchable airport chooser backed by the local airport database.
struct AirportPickerView: View {
    let title: String
    let onSelect: (Airport) -> Void

    @Environment(AirportStore.self) private var airports
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""

    private var results: [Airport] {
        airports.search(query)
    }

    var body: some View {
        NavigationStack {
            List {
                if !airports.usingFullDatabase {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Using the built-in starter list. The full worldwide database (free, ~10 MB) covers every field down to private strips.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if airports.isDownloading {
                                HStack(spacing: 8) {
                                    ProgressView()
                                    Text("Downloading…")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            } else {
                                Button("Download now") {
                                    Task { await airports.downloadFullDatabase() }
                                }
                                .font(.caption.weight(.semibold))
                            }
                        }
                    }
                }
                Section {
                    ForEach(results) { airport in
                        Button {
                            onSelect(airport)
                            dismiss()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                HStack {
                                    Text(airport.ident).bold()
                                    if let iata = airport.iata {
                                        Text(iata)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                                Text(airport.name)
                                    .font(.subheadline)
                                    .lineLimit(1)
                                Text(airport.locationDescription)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                    if !query.isEmpty && results.isEmpty {
                        Text("No matches for “\(query)”")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .searchable(text: $query, prompt: "KSQL, San Carlos, SLC…")
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}
