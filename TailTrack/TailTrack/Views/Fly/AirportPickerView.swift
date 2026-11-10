import SwiftUI

/// Searchable airport chooser backed by the local airport database.
struct AirportPickerView: View {
    let title: String
    let onSelect: (Airport) -> Void

    @Environment(AirportStore.self) private var airports
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @FocusState private var searchFocused: Bool

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
                    HStack(spacing: 8) {
                        Image(systemName: "magnifyingglass")
                            .foregroundStyle(.secondary)
                        TextField("KSQL, San Carlos, SLC…", text: $query)
                            .focused($searchFocused)
                            .textInputAutocapitalization(.characters)
                            .autocorrectionDisabled()
                            .submitLabel(.search)
                    }
                }
                Section {
                    ForEach(results) { airport in
                        Button {
                            choose(airport)
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
            .navigationTitle(title)
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    /// The keyboard has to let go before the sheet closes: dismissing
    /// with the text field still focused crashes recent iOS ("Accessing
    /// the focus system through UIScreen is no longer supported").
    private func choose(_ airport: Airport) {
        searchFocused = false
        onSelect(airport)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { dismiss() }
    }
}
