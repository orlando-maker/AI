import Foundation

/// Logbook export formats: GPX 1.1 track files (open in ForeFlight, Google
/// Earth, etc.) and CSV of the raw samples.
enum FlightExport {

    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

    static func gpx(for flight: Flight) -> String {
        var out = """
        <?xml version="1.0" encoding="UTF-8"?>
        <gpx version="1.1" creator="TailTrack" xmlns="http://www.topografix.com/GPX/1/1">
          <trk>
            <name>\(xmlEscape(flight.routeTitle)) \(xmlEscape(flight.tailNumber))</name>
            <trkseg>

        """
        for point in flight.track {
            let elevationMeters = (point.altitudeFt ?? 0) * 0.3048
            out += """
                  <trkpt lat="\(point.latitude)" lon="\(point.longitude)">
                    <ele>\(String(format: "%.1f", elevationMeters))</ele>
                    <time>\(isoFormatter.string(from: point.time))</time>
                  </trkpt>

            """
        }
        out += """
            </trkseg>
          </trk>
        </gpx>
        """
        return out
    }

    static func csv(for flight: Flight) -> String {
        var out = "time,latitude,longitude,altitude_ft,groundspeed_kt,track_deg,vertical_rate_fpm,on_ground\n"
        for p in flight.track {
            let fields: [String] = [
                isoFormatter.string(from: p.time),
                String(p.latitude),
                String(p.longitude),
                p.altitudeFt.map { String(format: "%.0f", $0) } ?? "",
                p.groundSpeedKt.map { String(format: "%.1f", $0) } ?? "",
                p.trackDeg.map { String(format: "%.1f", $0) } ?? "",
                p.verticalRateFpm.map { String(format: "%.0f", $0) } ?? "",
                p.onGround ? "1" : "0",
            ]
            out += fields.joined(separator: ",") + "\n"
        }
        return out
    }

    /// Writes export content to a temp file and returns its URL for ShareLink.
    static func temporaryFile(named name: String, contents: String) -> URL? {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(name)
        do {
            try contents.write(to: url, atomically: true, encoding: .utf8)
            return url
        } catch {
            return nil
        }
    }

    static func baseFileName(for flight: Flight) -> String {
        let day = flight.startedTracking.formatted(.iso8601.year().month().day())
        let route = flight.routeTitle.replacingOccurrences(of: " → ", with: "-")
            .replacingOccurrences(of: "———", with: "X")
        return "\(day)_\(flight.tailNumber)_\(route)"
    }

    private static func xmlEscape(_ s: String) -> String {
        s.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
