import Foundation

/// One decoded live position report for an aircraft.
struct ADSBSnapshot: Sendable {
    let hex: String
    let registration: String?
    let callsign: String?
    let latitude: Double
    let longitude: Double
    let baroAltitudeFt: Double?     // nil when the aircraft reports "ground"
    let geoAltitudeFt: Double?
    let groundSpeedKt: Double?
    let trackDeg: Double?
    let verticalRateFpm: Double?
    let onGround: Bool
    let squawk: String?
    let typeCode: String?
    let positionAgeSeconds: TimeInterval
    let fetchedAt: Date
    let source: String
}

/// Another aircraft near the tracked one — the live traffic layer.
struct NearbyAircraft: Identifiable, Sendable, Equatable {
    let hex: String
    /// Callsign, else registration, else the hex — whatever reads best.
    let label: String
    let latitude: Double
    let longitude: Double
    let altitudeFt: Double?
    let groundSpeedKt: Double?
    let trackDeg: Double?
    let onGround: Bool

    var id: String { hex }
}

enum ADSBError: LocalizedError {
    case notBroadcasting
    case allSourcesFailed(String)

    var errorDescription: String? {
        switch self {
        case .notBroadcasting:
            return "Aircraft is not currently visible to the ADS-B networks."
        case .allSourcesFailed(let detail):
            return "Could not reach ADS-B data sources (\(detail))."
        }
    }
}

/// Fetches live state from community ADS-B networks.
///
/// Licensing decides the source list. adsb.lol publishes its data under the
/// Open Database License, which allows a paid app with attribution.
/// adsb.fi's open-data API is for personal, non-commercial use, and the
/// OpenSky Network requires a license for live commercial products, so a
/// paid TailTrack uses adsb.lol alone until another network agrees in
/// writing. Flip `adsbFiPermitted` once adsb.fi grants permission.
struct ADSBClient {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        // Short timeout: a slow source shouldn't stall the search — the
        // sources are queried in parallel and the fastest answer wins.
        config.timeoutIntervalForRequest = 6
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    /// Looks up the aircraft by Mode S hex if known, else by airline
    /// callsign (crew mode), else by registration. Both community sources
    /// are queried in parallel and the first live answer wins. Returns nil
    /// when the sources are reachable but the aircraft isn't currently
    /// broadcasting; throws when no source could be reached.
    func snapshot(hex: String?, registration: String?, callsign: String? = nil) async throws -> ADSBSnapshot? {
        enum Outcome {
            case found(ADSBSnapshot)
            case notBroadcasting
            case failed(String)
        }

        var failures: [String] = []
        var sawEmptyResult = false

        let raced: ADSBSnapshot? = await withTaskGroup(of: Outcome.self) { group in
            for source in Self.v2Sources {
                guard let url = source.url(hex: hex, registration: registration, callsign: callsign) else { continue }
                let name = source.name
                group.addTask {
                    do {
                        if let snap = try await self.fetchV2(url: url, sourceName: name) {
                            return .found(snap)
                        }
                        return .notBroadcasting
                    } catch {
                        return .failed("\(name): \(error.localizedDescription)")
                    }
                }
            }
            for await outcome in group {
                switch outcome {
                case .found(let snap):
                    group.cancelAll()
                    return snap
                case .notBroadcasting:
                    sawEmptyResult = true
                case .failed(let message):
                    failures.append(message)
                }
            }
            return nil
        }
        if let raced { return raced }

        if sawEmptyResult { return nil }
        throw ADSBError.allSourcesFailed(failures.joined(separator: "; "))
    }

    // MARK: - readsb v2 sources (adsb.lol, adsb.fi)

    private struct V2Source {
        let name: String
        let base: String

        func url(hex: String?, registration: String?, callsign: String?) -> URL? {
            if let hex, !hex.isEmpty {
                return URL(string: "\(base)/hex/\(hex)")
            }
            if let callsign, !callsign.isEmpty {
                return URL(string: "\(base)/callsign/\(callsign)")
            }
            if let registration, !registration.isEmpty {
                return URL(string: "\(base)/registration/\(registration)")
            }
            return nil
        }
    }

    /// Set to true only with adsb.fi's written permission for TailTrack.
    static let adsbFiPermitted = false

    private static var v2Sources: [V2Source] {
        var sources = [V2Source(name: "adsb.lol", base: "https://api.adsb.lol/v2")]
        if adsbFiPermitted {
            sources.append(V2Source(name: "adsb.fi", base: "https://opendata.adsb.fi/api/v2"))
        }
        return sources
    }

    /// The tar1090 "globe" hosts that serve trace and history files.
    private static var globeHosts: [String] {
        adsbFiPermitted ? ["https://globe.adsb.lol", "https://globe.adsb.fi"] : ["https://globe.adsb.lol"]
    }

    private struct V2Response: Decodable {
        let ac: [V2Aircraft]?
    }

    /// Barometric altitude in the readsb JSON is either a number of feet
    /// or the literal string "ground".
    private enum V2Altitude: Decodable {
        case feet(Double)
        case ground

        init(from decoder: Decoder) throws {
            let container = try decoder.singleValueContainer()
            if let value = try? container.decode(Double.self) {
                self = .feet(value)
            } else if let text = try? container.decode(String.self), text == "ground" {
                self = .ground
            } else {
                throw DecodingError.dataCorruptedError(
                    in: container, debugDescription: "Unexpected alt_baro value")
            }
        }
    }

    private struct V2Aircraft: Decodable {
        let hex: String
        let r: String?
        let flight: String?
        let t: String?
        let lat: Double?
        let lon: Double?
        let altBaro: V2Altitude?
        let altGeom: Double?
        let gs: Double?
        let track: Double?
        let baroRate: Double?
        let geomRate: Double?
        let squawk: String?
        let seenPos: Double?

        enum CodingKeys: String, CodingKey {
            case hex, r, flight, t, lat, lon, gs, track, squawk
            case altBaro = "alt_baro"
            case altGeom = "alt_geom"
            case baroRate = "baro_rate"
            case geomRate = "geom_rate"
            case seenPos = "seen_pos"
        }
    }

    private func fetchV2(url: URL, sourceName: String) async throws -> ADSBSnapshot? {
        var request = URLRequest(url: url)
        request.setValue("TailTrack iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(V2Response.self, from: data)
        guard let ac = decoded.ac?.first(where: { $0.lat != nil && $0.lon != nil }),
              let lat = ac.lat, let lon = ac.lon else {
            return nil
        }

        var baroFt: Double?
        var onGround = false
        switch ac.altBaro {
        case .feet(let value): baroFt = value
        case .ground: onGround = true
        case nil: break
        }

        return ADSBSnapshot(
            hex: ac.hex.lowercased(),
            registration: ac.r?.trimmingCharacters(in: .whitespaces),
            callsign: ac.flight?.trimmingCharacters(in: .whitespaces),
            latitude: lat,
            longitude: lon,
            baroAltitudeFt: baroFt,
            geoAltitudeFt: ac.altGeom,
            groundSpeedKt: ac.gs,
            trackDeg: ac.track,
            verticalRateFpm: ac.baroRate ?? ac.geomRate,
            onGround: onGround,
            squawk: ac.squawk,
            typeCode: ac.t,
            positionAgeSeconds: ac.seenPos ?? 0,
            fetchedAt: Date(),
            source: sourceName
        )
    }

    // MARK: - Nearby traffic

    /// All aircraft within `radiusNM` of a point, for the live traffic
    /// layer. Both community sources are raced and the first non-empty
    /// answer wins; failures just mean an empty layer this cycle.
    func nearbyAircraft(latitude: Double, longitude: Double, radiusNM: Double,
                        excludingHex: String?) async -> [NearbyAircraft] {
        let radius = Int(min(250, max(1, radiusNM)))
        let urls = Self.v2Sources
            .compactMap { URL(string: "\($0.base)/lat/\(latitude)/lon/\(longitude)/dist/\(radius)") }

        return await withTaskGroup(of: [NearbyAircraft].self) { group in
            for url in urls {
                group.addTask {
                    (try? await self.fetchNearby(url: url, excludingHex: excludingHex)) ?? []
                }
            }
            for await result in group where !result.isEmpty {
                group.cancelAll()
                return result
            }
            return []
        }
    }

    private func fetchNearby(url: URL, excludingHex: String?) async throws -> [NearbyAircraft] {
        var request = URLRequest(url: url)
        request.setValue("TailTrack iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let decoded = try JSONDecoder().decode(V2Response.self, from: data)
        let own = excludingHex?.lowercased()
        var result: [NearbyAircraft] = []
        for ac in decoded.ac ?? [] {
            guard let lat = ac.lat, let lon = ac.lon else { continue }
            let hex = ac.hex.lowercased()
            if hex == own { continue }

            var altitudeFt: Double?
            var onGround = false
            switch ac.altBaro {
            case .feet(let value): altitudeFt = value
            case .ground: onGround = true
            case nil: break
            }

            let callsign = ac.flight?.trimmingCharacters(in: .whitespaces) ?? ""
            let registration = ac.r?.trimmingCharacters(in: .whitespaces) ?? ""
            let label = !callsign.isEmpty ? callsign
                : (!registration.isEmpty ? registration : hex.uppercased())

            result.append(NearbyAircraft(
                hex: hex,
                label: label,
                latitude: lat,
                longitude: lon,
                altitudeFt: altitudeFt ?? ac.altGeom,
                groundSpeedKt: ac.gs,
                trackDeg: ac.track,
                onGround: onGround
            ))
            // The map gets cluttered (and slow) past a few dozen targets.
            if result.count >= 30 { break }
        }
        return result
    }

    // MARK: - Historical track (breadcrumb backfill)

    /// Fetches the flight's trail so far, so joining a flight mid-air shows
    /// the whole breadcrumb path and the true wheels-up time — not just the
    /// points seen since tracking started, from the tar1090 trace files the
    /// networks publish.
    func historicalTrack(hex: String) async -> [TrackPoint] {
        let h = hex.lowercased()
        let subdir = String(h.suffix(2))
        var urls: [URL] = []
        for host in Self.globeHosts {
            for kind in ["full", "recent"] {
                if let url = URL(string: "\(host)/data/traces/\(subdir)/trace_\(kind)_\(h).json") {
                    urls.append(url)
                }
            }
        }
        for url in urls {
            if let points = try? await fetchTar1090Trace(url: url), points.count > 1 {
                return points
            }
        }
        return []
    }

    // MARK: - Past days (logbook backfill)

    /// Every position the networks recorded for this aircraft around one
    /// local calendar day, from the daily tar1090 history archives adsb.lol
    /// and adsb.fi publish. A local day straddles two UTC archive days, so
    /// each overlapping one is fetched, and the window runs a few hours
    /// past midnight so a late-evening flight keeps its landing. Today's
    /// UTC day isn't archived yet, so it comes from the live trace.
    func dayTrack(hex: String, localDay: Date, calendar: Calendar = .current) async -> [TrackPoint] {
        let h = hex.lowercased()
        let start = calendar.startOfDay(for: localDay)
        guard let end = calendar.date(byAdding: .day, value: 1, to: start) else { return [] }
        let windowEnd = end.addingTimeInterval(4 * 3600)

        let utc: Calendar = {
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
            return calendar
        }()
        let todayUTC = utc.startOfDay(for: Date())
        var archiveDays: [Date] = []
        var day = utc.startOfDay(for: start)
        while day < windowEnd, day <= todayUTC {
            archiveDays.append(day)
            guard let next = utc.date(byAdding: .day, value: 1, to: day) else { break }
            day = next
        }

        let fetched = await withTaskGroup(of: [TrackPoint].self) { group in
            for archiveDay in archiveDays {
                group.addTask {
                    if archiveDay >= todayUTC {
                        return await historicalTrack(hex: h)
                    }
                    return await archivedTrace(hex: h, utcDay: archiveDay, utc: utc)
                }
            }
            var all: [TrackPoint] = []
            for await chunk in group { all += chunk }
            return all
        }

        // The live trace and yesterday's archive overlap; keep one sample
        // per timestamp.
        var seen = Set<Int>()
        return fetched
            .filter { $0.time >= start && $0.time < windowEnd }
            .sorted { $0.time < $1.time }
            .filter { seen.insert(Int($0.time.timeIntervalSince1970)).inserted }
    }

    private func archivedTrace(hex: String, utcDay: Date, utc: Calendar) async -> [TrackPoint] {
        let c = utc.dateComponents([.year, .month, .day], from: utcDay)
        guard let y = c.year, let m = c.month, let d = c.day else { return [] }
        let date = String(format: "%04d/%02d/%02d", y, m, d)
        let path = "globe_history/\(date)/traces/\(hex.suffix(2))/trace_full_\(hex).json"
        for host in Self.globeHosts {
            if let url = URL(string: "\(host)/\(path)"),
               let points = try? await fetchTar1090Trace(url: url), !points.isEmpty {
                return points
            }
        }
        return []
    }

    /// Some mirrors serve archived traces as raw .gz bytes without a
    /// Content-Encoding header, so URLSession hands them over compressed.
    /// Strips the gzip wrapper (RFC 1952) and inflates the DEFLATE body;
    /// anything that isn't gzip passes through untouched.
    static func gunzipIfNeeded(_ data: Data) -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18, bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 8 else {
            return data
        }
        let flags = bytes[3]
        var offset = 10
        if flags & 0x04 != 0 {                      // FEXTRA
            let extraLength = Int(bytes[offset]) | (Int(bytes[offset + 1]) << 8)
            offset += 2 + extraLength
        }
        for flag: UInt8 in [0x08, 0x10] where flags & flag != 0 {   // FNAME, FCOMMENT
            while offset < bytes.count, bytes[offset] != 0 { offset += 1 }
            offset += 1
        }
        if flags & 0x02 != 0 { offset += 2 }        // FHCRC
        guard offset < bytes.count - 8 else { return data }
        let body = Data(bytes[offset..<(bytes.count - 8)])
        // Apple's .zlib is raw DEFLATE (RFC 1951) — exactly gzip's payload.
        guard let inflated = try? (body as NSData).decompressed(using: .zlib) else {
            return data
        }
        return inflated as Data
    }

    /// tar1090 trace format: {"timestamp": base, "trace": [[secondsOffset,
    /// lat, lon, alt_baro|"ground", gs, track, flags, verticalRate, …], …]}
    private func fetchTar1090Trace(url: URL) async throws -> [TrackPoint] {
        var request = URLRequest(url: url)
        request.setValue("TailTrack iOS", forHTTPHeaderField: "User-Agent")
        let (rawData, response) = try await session.data(for: request)
        let data = Self.gunzipIfNeeded(rawData)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let base = (root["timestamp"] as? NSNumber)?.doubleValue,
              let rows = root["trace"] as? [[Any]] else {
            throw URLError(.cannotParseResponse)
        }
        var points: [TrackPoint] = []
        points.reserveCapacity(rows.count)
        for row in rows where row.count >= 6 {
            guard let offset = (row[0] as? NSNumber)?.doubleValue,
                  let lat = (row[1] as? NSNumber)?.doubleValue,
                  let lon = (row[2] as? NSNumber)?.doubleValue else { continue }
            var altitudeFt: Double?
            var onGround = false
            if let alt = (row[3] as? NSNumber)?.doubleValue {
                altitudeFt = alt
            } else if let text = row[3] as? String, text == "ground" {
                onGround = true
            }
            points.append(TrackPoint(
                time: Date(timeIntervalSince1970: base + offset),
                latitude: lat,
                longitude: lon,
                altitudeFt: altitudeFt,
                groundSpeedKt: (row[4] as? NSNumber)?.doubleValue,
                trackDeg: (row[5] as? NSNumber)?.doubleValue,
                verticalRateFpm: row.count > 7 ? (row[7] as? NSNumber)?.doubleValue : nil,
                onGround: onGround
            ))
        }
        return points
    }
}
