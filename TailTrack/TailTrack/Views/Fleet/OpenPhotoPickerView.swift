import SwiftUI

/// Searches Openverse for CC0 / public-domain photos (no credit required)
/// and lets the user pick one as their aircraft's photo.
struct OpenPhotoPickerView: View {
    let initialQuery: String
    let onPicked: (Data) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var query: String
    @State private var results: [OpenImageResult] = []
    @State private var isSearching = false
    @State private var errorMessage: String?
    @State private var downloadingID: String?

    private let client = OpenImageClient()

    init(initialQuery: String, onPicked: @escaping (Data) -> Void) {
        self.initialQuery = initialQuery
        self.onPicked = onPicked
        _query = State(initialValue: initialQuery)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 12) {
                    header
                    if isSearching {
                        ProgressView("Searching Openverse…")
                            .padding(.top, 40)
                    } else if let errorMessage {
                        ContentUnavailableView("Search failed", systemImage: "wifi.exclamationmark",
                                               description: Text(errorMessage))
                    } else if results.isEmpty {
                        ContentUnavailableView.search(text: query)
                            .padding(.top, 20)
                    } else {
                        grid
                    }
                }
                .padding()
            }
            .navigationTitle("Open Photos")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Cessna 152 aircraft")
            .onSubmit(of: .search) {
                Task { await search() }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .task { await search() }
        }
    }

    private var header: some View {
        Text("Results are limited to CC0 and Public Domain images — free to use with no credit required.")
            .font(.caption)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var grid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], spacing: 8) {
            ForEach(results) { result in
                Button {
                    pick(result)
                } label: {
                    ZStack(alignment: .bottomLeading) {
                        AsyncImage(url: result.thumbnailURL) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFill()
                            case .failure:
                                Color.gray.opacity(0.2)
                                    .overlay(Image(systemName: "photo").foregroundStyle(.secondary))
                            default:
                                Color.gray.opacity(0.1)
                                    .overlay(ProgressView())
                            }
                        }
                        .frame(height: 110)
                        .frame(maxWidth: .infinity)
                        .clipped()

                        Text(result.licenseBadge)
                            .font(.system(size: 9, weight: .bold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 2)
                            .background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white)
                            .padding(5)

                        if downloadingID == result.id {
                            Color.black.opacity(0.4)
                            ProgressView()
                                .tint(.white)
                                .frame(maxWidth: .infinity, maxHeight: .infinity)
                        }
                    }
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .disabled(downloadingID != nil)
            }
        }
    }

    private func search() async {
        isSearching = true
        errorMessage = nil
        do {
            results = try await client.search(query)
        } catch {
            results = []
            errorMessage = error.localizedDescription
        }
        isSearching = false
    }

    private func pick(_ result: OpenImageResult) {
        downloadingID = result.id
        Task {
            defer { downloadingID = nil }
            if let data = try? await client.downloadImageData(from: result.fullURL) {
                onPicked(data)
                dismiss()
            } else {
                errorMessage = "Couldn't download that image — try another."
            }
        }
    }
}
