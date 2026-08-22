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

    /// Looks up the aircraft by Mode S hex if known, otherwise by registration.
    /// Returns nil when the sources are reachable but the aircraft isn't
    /// currently broadcasting; throws when no source could be reached.
    func snapshot(hex: String?, registration: String?) async throws -> ADSBSnapshot? {
        var failures: [String] = []
        var sawEmptyResult = false

        for source in Self.v2Sources {
            guard let url = source.url(hex: hex, registration: registration) else { continue }
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

        func url(hex: String?, registration: String?) -> URL? {
            if let hex, !hex.isEmpty {
                return URL(string: "\(base)/hex/\(hex)")
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
        let (data, response) = try await session.data(from: url)
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
