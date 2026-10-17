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
            out += "      <trkpt lat=\"\(point.latitude)\" lon=\"\(point.longitude)\">\n"
            // <ele> is optional in GPX — omit it rather than writing a
            // bogus sea-level value for samples with no altitude.
            if let altitudeFt = point.altitudeFt {
                out += "        <ele>\(String(format: "%.1f", altitudeFt * 0.3048))</ele>\n"
            }
            out += "        <time>\(isoFormatter.string(from: point.time))</time>\n"
            out += "      </trkpt>\n"
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

    /// One-row-per-flight CSV of the whole logbook — backup, spreadsheet,
    /// or import into another logbook app.
    static func logbookCSV(_ flights: [Flight]) -> String {
        var out = "date,tail_number,type,from,to,takeoff,landing,flight_time_hours,distance_nm,max_altitude_ft,hobbs,tach,notes\n"
        let dayFormat = Date.ISO8601FormatStyle().year().month().day()
        for f in flights.sorted(by: { $0.startedTracking < $1.startedTracking }) {
            let fields: [String] = [
                f.startedTracking.formatted(dayFormat),
                f.tailNumber,
                f.typeCode,
                f.departure?.ident ?? "",
                f.destination?.ident ?? "",
                f.takeoffTime.map { isoFormatter.string(from: $0) } ?? "",
                f.landingTime.map { isoFormatter.string(from: $0) } ?? "",
                f.flightTime.map { String(format: "%.2f", $0 / 3600) } ?? "",
                String(format: "%.1f", f.track.isEmpty ? (f.routeDistanceNM ?? 0) : f.distanceFlownNM),
                f.maxAltitudeFt.map { String(format: "%.0f", $0) } ?? "",
                f.hobbsTime.map { String(format: "%.1f", $0) } ?? "",
                f.tachTime.map { String(format: "%.1f", $0) } ?? "",
                csvEscape(f.notes),
            ]
            out += fields.joined(separator: ",") + "\n"
        }
        return out
    }

    private static func csvEscape(_ value: String) -> String {
        guard value.contains(",") || value.contains("\"") || value.contains("\n") else { return value }
        return "\"" + value.replacingOccurrences(of: "\"", with: "\"\"") + "\""
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
