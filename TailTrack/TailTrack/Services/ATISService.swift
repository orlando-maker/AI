import Foundation

/// One digital ATIS broadcast. Big airports with split ATIS publish an
/// arrival and a departure broadcast; everyone else publishes one.
struct ATISReport: Identifiable, Equatable {
    enum Kind: String { case combined, arrival, departure }

    let airport: String
    let kind: Kind
    /// The information letter, "B".
    let letter: String?
    let text: String

    var id: String { "\(airport)-\(kind.rawValue)" }

    var title: String {
        switch kind {
        case .combined: return "ATIS"
        case .arrival: return "Arrival ATIS"
        case .departure: return "Departure ATIS"
        }
    }

    var decoded: DecodedATIS { ATISDecoder.decode(text) }
}

/// Digital ATIS from the FAA's D-ATIS feed, via the free community mirror
/// at datis.clowd.io (no key). D-ATIS only exists at roughly eighty larger
/// US airports; every other field broadcasts ATIS/AWOS by voice only, and
/// gets an empty answer here.
struct ATISService {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config)
    }

    func reports(for idents: [String]) async -> [String: [ATISReport]] {
        let unique = Array(Set(idents.map { $0.uppercased() }))
        return await withTaskGroup(of: (String, [ATISReport]).self) { group in
            for ident in unique {
                group.addTask { (ident, await reports(for: ident)) }
            }
            var result: [String: [ATISReport]] = [:]
            for await (ident, reports) in group where !reports.isEmpty {
                result[ident] = reports
            }
            return result
        }
    }

    func reports(for ident: String) async -> [ATISReport] {
        let code = ident.uppercased()
        // Only FAA airports can have D-ATIS: the lower 48 (K), Alaska,
        // Hawaii, Guam and the Northern Marianas (P), Puerto Rico and the
        // US Virgin Islands (TJ, TI). Skip strips like E16 and non-US fields.
        guard code.range(of: "^(K[A-Z]{3}|P[A-Z]{3}|TJ[A-Z]{2}|TI[A-Z]{2})$",
                         options: .regularExpression) != nil,
              let url = URL(string: "https://datis.clowd.io/api/\(code)") else { return [] }
        var request = URLRequest(url: url)
        request.setValue("TailTrack iOS", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let json = try? JSONSerialization.jsonObject(with: data) else { return [] }

        // Normally an array of broadcasts; tolerate a single object too. An
        // airport without D-ATIS answers with an object holding "error".
        let rows: [[String: Any]] = (json as? [[String: Any]])
            ?? (json as? [String: Any]).map { [$0] } ?? []
        return rows.compactMap { row in
            guard let text = (row["datis"] ?? row["text"]) as? String,
                  !text.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
            let type = ((row["type"] as? String) ?? "").lowercased()
            let kind: ATISReport.Kind = type.hasPrefix("arr") ? .arrival
                : type.hasPrefix("dep") ? .departure : .combined
            let code = (row["code"] as? String)?.uppercased()
            return ATISReport(airport: ident.uppercased(), kind: kind,
                              letter: code ?? Self.letter(in: text), text: text)
        }
        .sorted { $0.kind.rawValue < $1.kind.rawValue }
    }

    /// "SFO ATIS INFO B 1856Z" → "B".
    static func letter(in text: String) -> String? {
        let upper = text.uppercased()
        guard let regex = try? NSRegularExpression(pattern: #"\bINFO(?:RMATION)?\s+([A-Z])\b"#),
              let m = regex.firstMatch(in: upper, range: NSRange(upper.startIndex..., in: upper)),
              let range = Range(m.range(at: 1), in: upper) else { return nil }
        return String(upper[range])
    }
}

// MARK: - Frequencies

struct AirportFrequency: Codable, Hashable, Identifiable {
    let type: String          // "ATIS", "AWOS", "TWR", "CTAF"…
    let description: String
    let mhz: Double

    var id: String { "\(type)-\(mhz)-\(description)" }

    /// Voice weather broadcasts: where a field without D-ATIS keeps its
    /// ATIS, or its automated AWOS/ASOS.
    var isWeatherBroadcast: Bool {
        let haystack = (type + " " + description).uppercased()
        return ["ATIS", "AWOS", "ASOS", "AWIS"].contains { haystack.contains($0) }
    }

    /// "125.90", "135.275", "119.65" — the way pilots write them.
    var formatted: String {
        var text = String(format: "%.3f", mhz)
        while text.hasSuffix("0"), text.split(separator: ".").last.map({ $0.count > 2 }) == true {
            text.removeLast()
        }
        return text
    }

    /// The name a pilot would use: "ATIS", "Tower", "AWOS 1".
    var label: String {
        let names = ["TWR": "Tower", "GND": "Ground", "CLD": "Clearance", "CTAF": "CTAF",
                     "UNIC": "UNICOM", "ATIS": "ATIS", "AWOS": "AWOS", "ASOS": "ASOS"]
        let trimmed = description.trimmingCharacters(in: .whitespaces)
        if ["AWOS", "ASOS", "ATIS"].contains(type), trimmed.uppercased().hasPrefix(type) {
            return trimmed.uppercased()
        }
        return names[type] ?? (trimmed.isEmpty ? type : trimmed.capitalized)
    }

    /// Display order: weather first, then the frequencies you'd call.
    var sortRank: Int {
        if isWeatherBroadcast { return 0 }
        return ["CLD": 1, "GND": 2, "TWR": 3, "CTAF": 4, "UNIC": 5][type] ?? 6
    }
}

/// Airport radio frequencies from OurAirports (public domain), downloaded
/// once, cached on the phone, and refreshed monthly — same source and
/// cadence as the airport database. Lookups never touch the network once
/// the cache exists.
actor FrequencyDirectory {
    static let shared = FrequencyDirectory()

    private static let sources = [
        "https://davidmegginson.github.io/ourairports-data/airport-frequencies.csv",
        "https://raw.githubusercontent.com/davidmegginson/ourairports-data/main/airport-frequencies.csv",
    ].compactMap(URL.init(string:))
    private static let keptTypes: Set<String> = [
        "ATIS", "AWOS", "ASOS", "AWIS", "CLD", "GND", "TWR", "CTAF", "UNIC",
    ]
    private static let maxAge: TimeInterval = 30 * 24 * 3600

    private var table: [String: [AirportFrequency]]?
    private var loading: Task<[String: [AirportFrequency]], Never>?

    private static var cacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("airport-frequencies.json")
    }

    func frequencies(for ident: String) async -> [AirportFrequency] {
        let table = await loadTable()
        return (table[ident.uppercased()] ?? []).sorted {
            ($0.sortRank, $0.mhz) < ($1.sortRank, $1.mhz)
        }
    }

    private func loadTable() async -> [String: [AirportFrequency]] {
        if let table { return table }
        if let loading { return await loading.value }
        let task = Task { await Self.cachedOrDownloaded() }
        loading = task
        let result = await task.value
        loading = nil
        // An empty answer means offline with no cache; try again next time.
        table = result.isEmpty ? nil : result
        return result
    }

    private static func cachedOrDownloaded() async -> [String: [AirportFrequency]] {
        let cached = (try? Data(contentsOf: cacheURL))
            .flatMap { try? JSONDecoder().decode([String: [AirportFrequency]].self, from: $0) }
        let modified = (try? FileManager.default.attributesOfItem(atPath: cacheURL.path))?[.modificationDate] as? Date
        if let cached, let modified, Date().timeIntervalSince(modified) < maxAge {
            return cached
        }
        for url in sources {
            guard let (data, response) = try? await URLSession.shared.data(from: url),
                  let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let text = String(data: data, encoding: .utf8) else { continue }
            let parsed = parse(text)
            guard parsed.count > 1000 else { continue }
            if let encoded = try? JSONEncoder().encode(parsed) {
                try? encoded.write(to: cacheURL, options: .atomic)
            }
            return parsed
        }
        // Offline: a month-old frequency list beats none.
        return cached ?? [:]
    }

    /// airport-frequencies.csv: id,airport_ref,airport_ident,type,description,frequency_mhz
    static func parse(_ text: String) -> [String: [AirportFrequency]] {
        var lines = text.split(separator: "\n", omittingEmptySubsequences: true)[...]
        guard let headerLine = lines.first else { return [:] }
        lines = lines.dropFirst()
        let header = AirportStore.splitCSVLine(String(headerLine))
        guard let identCol = header.firstIndex(of: "airport_ident"),
              let typeCol = header.firstIndex(of: "type"),
              let mhzCol = header.firstIndex(of: "frequency_mhz") else { return [:] }
        let descCol = header.firstIndex(of: "description")
        let needed = max(identCol, typeCol, mhzCol)

        var table: [String: [AirportFrequency]] = [:]
        for line in lines {
            let fields = AirportStore.splitCSVLine(String(line.trimmingCharacters(in: .whitespacesAndNewlines)))
            guard fields.count > needed, let mhz = Double(fields[mhzCol]), mhz > 100 else { continue }
            let type = fields[typeCol].uppercased()
            let description = descCol.flatMap { $0 < fields.count ? fields[$0] : nil } ?? ""
            let frequency = AirportFrequency(type: type, description: description, mhz: mhz)
            guard keptTypes.contains(type) || frequency.isWeatherBroadcast else { continue }
            let ident = fields[identCol].uppercased()
            if table[ident]?.contains(frequency) != true {
                table[ident, default: []].append(frequency)
            }
        }
        return table
    }
}
