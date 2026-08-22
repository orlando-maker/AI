import Foundation
import CoreLocation
import Observation

/// Airport database. Ships with a curated starter list so the app works out
/// of the box, and can download the full worldwide OurAirports dataset
/// (public domain, ~80k airports) on demand, cached locally as JSON.
@Observable
@MainActor
final class AirportStore {

    private(set) var airports: [Airport] = []
    private(set) var byIdent: [String: Airport] = [:]
    private(set) var usingFullDatabase = false
    private(set) var isDownloading = false
    private(set) var downloadError: String?
    private(set) var lastUpdated: Date?

    private static let csvURL = URL(string: "https://davidmegginson.github.io/ourairports-data/airports.csv")!

    private static var cacheURL: URL {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("airports-full.json")
    }

    var statusDescription: String {
        if usingFullDatabase {
            let when = lastUpdated.map { " · updated \($0.formatted(date: .abbreviated, time: .omitted))" } ?? ""
            return "\(airports.count.formatted()) airports (OurAirports)\(when)"
        }
        return "\(airports.count.formatted()) built-in airports — download the full database for worldwide coverage"
    }

    init() {
        loadCachedOrStarter()
    }

    // MARK: - Lookup

    /// Exact lookup by ICAO/GPS ident (KSQL) or IATA code (SQL → best effort).
    func lookup(_ code: String) -> Airport? {
        let c = code.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !c.isEmpty else { return nil }
        if let hit = byIdent[c] { return hit }
        return airports.first { $0.iata == c }
    }

    /// Ranked substring search over ident, IATA, name, and municipality.
    func search(_ query: String, limit: Int = 40) -> [Airport] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !q.isEmpty else { return [] }

        var exact: [Airport] = []
        var identPrefix: [Airport] = []
        var other: [Airport] = []

        for airport in airports {
            let ident = airport.ident.uppercased()
            if ident == q || airport.iata?.uppercased() == q {
                exact.append(airport)
            } else if ident.hasPrefix(q) || ident.hasPrefix("K" + q) {
                identPrefix.append(airport)
            } else if airport.name.uppercased().contains(q) ||
                      (airport.municipality?.uppercased().contains(q) ?? false) {
                other.append(airport)
            }
            if exact.count + identPrefix.count + other.count > limit * 8 { break }
        }

        let sizeRank: (Airport) -> Int = {
            switch $0.kind {
            case "large_airport": return 0
            case "medium_airport": return 1
            default: return 2
            }
        }
        identPrefix.sort { ($0.ident.count, sizeRank($0)) < ($1.ident.count, sizeRank($1)) }
        other.sort { sizeRank($0) < sizeRank($1) }
        return Array((exact + identPrefix + other).prefix(limit))
    }

    /// Closest airport to a coordinate, for auto-detecting departure and
    /// landing fields. Excludes nothing by size — GA lands at small fields.
    func nearest(to coordinate: CLLocationCoordinate2D, withinNM: Double = 8) -> Airport? {
        var best: Airport?
        var bestDist = withinNM
        for airport in airports {
            // Cheap bounding-box reject before the trig call.
            if abs(airport.latitude - coordinate.latitude) > 0.6 { continue }
            if abs(airport.longitude - coordinate.longitude) > 0.8 { continue }
            let d = GreatCircle.distanceNM(from: coordinate, to: airport.coordinate)
            if d < bestDist {
                best = airport
                bestDist = d
            }
        }
        return best
    }

    // MARK: - Loading

    private func loadCachedOrStarter() {
        if let data = try? Data(contentsOf: Self.cacheURL),
           let decoded = try? JSONDecoder().decode([Airport].self, from: data),
           decoded.count > 1000 {
            apply(decoded, full: true)
            let attrs = try? FileManager.default.attributesOfItem(atPath: Self.cacheURL.path)
            lastUpdated = attrs?[.modificationDate] as? Date
            return
        }
        loadStarter()
    }

    private func loadStarter() {
        guard let url = Bundle.main.url(forResource: "airports-starter", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([Airport].self, from: data) else {
            apply([], full: false)
            return
        }
        apply(decoded, full: false)
    }

    private func apply(_ list: [Airport], full: Bool) {
        airports = list
        byIdent = Dictionary(list.map { ($0.ident.uppercased(), $0) },
                             uniquingKeysWith: { first, _ in first })
        usingFullDatabase = full
    }

    // MARK: - Full database download

    func downloadFullDatabase() async {
        guard !isDownloading else { return }
        isDownloading = true
        downloadError = nil
        defer { isDownloading = false }

        do {
            let (data, response) = try await URLSession.shared.data(from: Self.csvURL)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else {
                throw URLError(.badServerResponse)
            }
            let parsed = await Task.detached(priority: .userInitiated) {
                Self.parseOurAirportsCSV(text)
            }.value
            guard parsed.count > 1000 else { throw URLError(.cannotParseResponse) }

            let encoded = try JSONEncoder().encode(parsed)
            try encoded.write(to: Self.cacheURL, options: .atomic)
            apply(parsed, full: true)
            lastUpdated = Date()
        } catch {
            downloadError = error.localizedDescription
        }
    }

    // MARK: - CSV parsing

    /// Parses the OurAirports airports.csv. Columns (by header name):
    /// id,ident,type,name,latitude_deg,longitude_deg,elevation_ft,continent,
    /// iso_country,iso_region,municipality,scheduled_service,gps_code,iata_code,...
    nonisolated static func parseOurAirportsCSV(_ text: String) -> [Airport] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)[...]
        guard let headerLine = lines.first else { return [] }
        lines = lines.dropFirst()

        let header = splitCSVLine(String(headerLine))
        func col(_ name: String) -> Int? { header.firstIndex(of: name) }
        guard let identCol = col("ident"), let typeCol = col("type"), let nameCol = col("name"),
              let latCol = col("latitude_deg"), let lonCol = col("longitude_deg") else {
            return []
        }
        let elevCol = col("elevation_ft")
        let regionCol = col("iso_region")
        let muniCol = col("municipality")
        let iataCol = col("iata_code")

        let keepTypes: Set<String> = ["small_airport", "medium_airport", "large_airport", "seaplane_base"]

        var result: [Airport] = []
        result.reserveCapacity(60_000)

        let requiredColumns = [identCol, typeCol, nameCol, latCol, lonCol].max()!

        for line in lines {
            let fields = splitCSVLine(String(line))
            guard fields.count > requiredColumns,
                  keepTypes.contains(fields[typeCol]),
                  let lat = Double(fields[latCol]),
                  let lon = Double(fields[lonCol]) else { continue }
            let ident = fields[identCol]
            guard !ident.isEmpty else { continue }

            func field(_ index: Int?) -> String? {
                guard let index, index < fields.count else { return nil }
                let v = fields[index]
                return v.isEmpty ? nil : v
            }

            result.append(Airport(
                ident: ident,
                name: fields[nameCol],
                latitude: lat,
                longitude: lon,
                elevationFt: field(elevCol).flatMap { Double($0) }.map { Int($0) },
                iata: field(iataCol),
                municipality: field(muniCol),
                region: field(regionCol),
                kind: fields[typeCol]
            ))
        }
        return result
    }

    /// Minimal RFC-4180 style field splitter (handles quoted fields with
    /// embedded commas and doubled quotes).
    nonisolated static func splitCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var inQuotes = false
        var iterator = line.makeIterator()

        while let ch = iterator.next() {
            if inQuotes {
                if ch == "\"" {
                    // Either a closing quote or an escaped quote ("").
                    if let next = iterator.next() {
                        if next == "\"" {
                            current.append("\"")
                        } else {
                            inQuotes = false
                            if next == "," {
                                fields.append(current)
                                current = ""
                            } else {
                                current.append(next)
                            }
                        }
                    } else {
                        inQuotes = false
                    }
                } else {
                    current.append(ch)
                }
            } else if ch == "\"" {
                inQuotes = true
            } else if ch == "," {
                fields.append(current)
                current = ""
            } else if ch != "\r" {
                current.append(ch)
            }
        }
        fields.append(current)
        return fields
    }
}
