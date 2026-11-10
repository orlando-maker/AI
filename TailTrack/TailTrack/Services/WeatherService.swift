import Foundation

/// Current weather (METAR) and forecast (TAF) for an airport, from the
/// FAA/NWS Aviation Weather Center — free, no API key.
struct AirportWeather: Identifiable {
    let ident: String
    let raw: String
    let flightCategory: String?   // VFR / MVFR / IFR / LIFR
    let windSummary: String?      // "280° at 12 kt (G18)"
    let visibility: String?       // "10+ SM"
    let temperatureC: Double?
    var taf: String?              // raw TAF text, when the field issues one

    var id: String { ident }
}

struct WeatherService {

    private let session: URLSession

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 8
        session = URLSession(configuration: config)
    }

    /// Fetches METARs (and TAFs, where the field issues them) for up to a
    /// handful of idents, in parallel.
    func metars(for idents: [String]) async -> [AirportWeather] {
        let codes = idents
            .map { $0.trimmingCharacters(in: .whitespaces).uppercased() }
            .filter { !$0.isEmpty }
        guard !codes.isEmpty,
              let url = URL(string: "https://aviationweather.gov/api/data/metar?ids=\(codes.joined(separator: ","))&format=json") else {
            return []
        }
        async let tafsByIdent = tafs(for: codes)
        var request = URLRequest(url: url)
        request.setValue("TailTrack iOS", forHTTPHeaderField: "User-Agent")

        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return []
        }

        let forecasts = await tafsByIdent
        return rows.compactMap { row in
            guard let ident = row["icaoId"] as? String,
                  let raw = row["rawOb"] as? String else { return nil }

            var wind: String?
            if let speed = (row["wspd"] as? NSNumber)?.intValue {
                if speed == 0 {
                    wind = "Calm"
                } else {
                    let direction = (row["wdir"] as? NSNumber).map { String(format: "%03d°", $0.intValue) }
                        ?? ((row["wdir"] as? String) == "VRB" ? "Variable" : "—")
                    var text = "\(direction) at \(speed) kt"
                    if let gust = (row["wgst"] as? NSNumber)?.intValue {
                        text += " (G\(gust))"
                    }
                    wind = text
                }
            }

            var visibility: String?
            if let number = (row["visib"] as? NSNumber)?.doubleValue {
                visibility = String(format: "%g SM", number)
            } else if let text = row["visib"] as? String {
                visibility = "\(text) SM"
            }

            return AirportWeather(
                ident: ident,
                raw: raw,
                flightCategory: row["fltCat"] as? String,
                windSummary: wind,
                visibility: visibility,
                temperatureC: (row["temp"] as? NSNumber)?.doubleValue,
                taf: forecasts[ident]
            )
        }
    }

    /// Raw TAF text keyed by ident. Small GA fields don't issue TAFs, so
    /// missing entries are normal; failures just mean no forecast shown.
    private func tafs(for codes: [String]) async -> [String: String] {
        guard let url = URL(string: "https://aviationweather.gov/api/data/taf?ids=\(codes.joined(separator: ","))&format=json") else {
            return [:]
        }
        var request = URLRequest(url: url)
        request.setValue("TailTrack iOS", forHTTPHeaderField: "User-Agent")
        guard let (data, response) = try? await session.data(for: request),
              let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
              let rows = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return [:]
        }
        var result: [String: String] = [:]
        for row in rows {
            if let ident = row["icaoId"] as? String,
               let raw = row["rawTAF"] as? String, !raw.isEmpty {
                result[ident] = raw
            }
        }
        return result
    }
}
