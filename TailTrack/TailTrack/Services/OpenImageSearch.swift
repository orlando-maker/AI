import Foundation

/// One openly-licensed image hit from Openverse, pre-filtered to licenses
/// that require no attribution (CC0 / Public Domain Mark).
struct OpenImageResult: Identifiable, Hashable {
    let id: String
    let title: String
    let thumbnailURL: URL
    let fullURL: URL
    let license: String   // "cc0" or "pdm"
    let source: String?

    var licenseBadge: String {
        license.lowercased() == "pdm" ? "Public Domain" : "CC0"
    }
}

/// Searches Openverse (openverse.org — the WordPress/Creative Commons image
/// search engine) restricted to no-attribution-required licenses, so any
/// image picked here can ship in the app or a screenshot without credit.
struct OpenImageClient {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        session = URLSession(configuration: config)
    }

    private struct SearchResponse: Decodable {
        let results: [Result]
    }

    private struct Result: Decodable {
        let id: String
        let title: String?
        let url: URL?
        let thumbnail: URL?
        let license: String?
        let source: String?
    }

    func search(_ query: String, pageSize: Int = 30) async throws -> [OpenImageResult] {
        var components = URLComponents(string: "https://api.openverse.org/v1/images/")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            // Only licenses with no attribution requirement.
            URLQueryItem(name: "license", value: "cc0,pdm"),
            URLQueryItem(name: "page_size", value: String(pageSize)),
        ]
        guard let url = components.url else { throw URLError(.badURL) }

        var request = URLRequest(url: url)
        request.setValue("TailTrack iOS", forHTTPHeaderField: "User-Agent")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw URLError(.badServerResponse) }
        guard http.statusCode != 429 else { throw OpenImageError.rateLimited }
        guard (200..<300).contains(http.statusCode) else { throw URLError(.badServerResponse) }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)
        return decoded.results.compactMap { r in
            guard let full = r.url, let thumb = r.thumbnail,
                  let license = r.license,
                  ["cc0", "pdm"].contains(license.lowercased()) else { return nil }
            return OpenImageResult(
                id: r.id,
                title: r.title ?? "Untitled",
                thumbnailURL: thumb,
                fullURL: full,
                license: license,
                source: r.source
            )
        }
    }

    func downloadImageData(from url: URL) async throws -> Data {
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}

enum OpenImageError: LocalizedError {
    case rateLimited

    var errorDescription: String? {
        switch self {
        case .rateLimited:
            return "Openverse is rate-limiting anonymous searches — try again in a minute."
        }
    }
}
