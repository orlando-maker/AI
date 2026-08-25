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

/// Fetches live state from free, open ADS-B aggregators. Tries adsb.lol
/// first, then adsb.fi (both community readsb networks with open APIs),
/// then the OpenSky Network as a last resort.
struct ADSBClient {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        session = URLSession(configuration: config)
    }

    /// Looks up the aircraft by Mode S hex if known, else by airline
    /// callsign (crew mode), else by registration. Returns nil when the
    /// sources are reachable but the aircraft isn't currently broadcasting;
    /// throws when no source could be reached.
    func snapshot(hex: String?, registration: String?, callsign: String? = nil) async throws -> ADSBSnapshot? {
        var failures: [String] = []
        var sawEmptyResult = false

        for source in Self.v2Sources {
            guard let url = source.url(hex: hex, registration: registration, callsign: callsign) else { continue }
            do {
                if let snap = try await fetchV2(url: url, sourceName: source.name) {
                    return snap
                }
                sawEmptyResult = true
            } catch {
                failures.append("\(source.name): \(error.localizedDescription)")
            }
        }

        if let hex, !hex.isEmpty {
            do {
                if let snap = try await fetchOpenSky(hex: hex) {
                    return snap
                }
                sawEmptyResult = true
            } catch {
                failures.append("OpenSky: \(error.localizedDescription)")
            }
        }

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

    private static let v2Sources = [
        V2Source(name: "adsb.lol", base: "https://api.adsb.lol/v2"),
        V2Source(name: "adsb.fi", base: "https://opendata.adsb.fi/api/v2"),
    ]

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

    // MARK: - Historical track (breadcrumb backfill)

    /// Fetches the flight's trail so far, so joining a flight mid-air shows
    /// the whole breadcrumb path and the true wheels-up time — not just the
    /// points seen since tracking started. Tries the tar1090 trace files
    /// that adsb.lol and adsb.fi publish, then OpenSky's track endpoint.
    func historicalTrack(hex: String) async -> [TrackPoint] {
        let h = hex.lowercased()
        let subdir = String(h.suffix(2))
        var urls: [URL] = []
        for host in ["https://globe.adsb.lol", "https://globe.adsb.fi"] {
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
        if let points = try? await fetchOpenSkyTrack(hex: h), points.count > 1 {
            return points
        }
        return []
    }

    /// tar1090 trace format: {"timestamp": base, "trace": [[secondsOffset,
    /// lat, lon, alt_baro|"ground", gs, track, flags, verticalRate, …], …]}
    private func fetchTar1090Trace(url: URL) async throws -> [TrackPoint] {
        var request = URLRequest(url: url)
        request.setValue("TailTrack iOS", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
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

    /// OpenSky /tracks: {"path": [[time, lat, lon, baroAltMeters, track,
    /// onGround], …]} — sparser waypoints, still a real trail.
    private func fetchOpenSkyTrack(hex: String) async throws -> [TrackPoint] {
        guard let url = URL(string: "https://opensky-network.org/api/tracks/all?icao24=\(hex)&time=0") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let path = root["path"] as? [[Any]] else {
            throw URLError(.cannotParseResponse)
        }
        var points: [TrackPoint] = []
        for row in path where row.count >= 6 {
            guard let time = (row[0] as? NSNumber)?.doubleValue,
                  let lat = (row[1] as? NSNumber)?.doubleValue,
                  let lon = (row[2] as? NSNumber)?.doubleValue else { continue }
            let onGround = (row[5] as? NSNumber)?.boolValue ?? false
            points.append(TrackPoint(
                time: Date(timeIntervalSince1970: time),
                latitude: lat,
                longitude: lon,
                altitudeFt: onGround ? nil : (row[3] as? NSNumber).map { $0.doubleValue * 3.28084 },
                groundSpeedKt: nil,
                trackDeg: (row[4] as? NSNumber)?.doubleValue,
                verticalRateFpm: nil,
                onGround: onGround
            ))
        }
        return points
    }

    // MARK: - OpenSky fallback

    /// Anonymous OpenSky state vector. The response is a heterogeneous JSON
    /// array, so it's decoded with JSONSerialization. Units are metric.
    private func fetchOpenSky(hex: String) async throws -> ADSBSnapshot? {
        guard let url = URL(string: "https://opensky-network.org/api/states/all?icao24=\(hex.lowercased())") else {
            throw URLError(.badURL)
        }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let states = root["states"] as? [[Any]],
              let s = states.first, s.count >= 12 else {
            return nil
        }

        func number(_ index: Int) -> Double? {
            guard index < s.count else { return nil }
            return (s[index] as? NSNumber)?.doubleValue
        }

        guard let lon = number(5), let lat = number(6) else { return nil }
        let onGround = (s[8] as? NSNumber)?.boolValue ?? false
        let metersToFeet = 3.28084
        let msToKt = 1.94384

        let lastPosition = number(3)
        let age = lastPosition.map { max(0, Date().timeIntervalSince1970 - $0) } ?? 0

        return ADSBSnapshot(
            hex: hex.lowercased(),
            registration: nil,
            callsign: (s[1] as? String)?.trimmingCharacters(in: .whitespaces),
            latitude: lat,
            longitude: lon,
            baroAltitudeFt: onGround ? nil : number(7).map { $0 * metersToFeet },
            geoAltitudeFt: number(13).map { $0 * metersToFeet },
            groundSpeedKt: number(9).map { $0 * msToKt },
            trackDeg: number(10),
            verticalRateFpm: number(11).map { $0 * metersToFeet * 60 },
            onGround: onGround,
            squawk: s.count > 14 ? s[14] as? String : nil,
            typeCode: nil,
            positionAgeSeconds: age,
            fetchedAt: Date(),
            source: "OpenSky"
        )
    }
}
