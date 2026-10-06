import Foundation
import Observation

/// One flight the aircraft made on a logbook entry's day, with its
/// airports resolved once up front (a nearest-airport lookup scans the
/// whole database).
struct PastFlightCandidate: Identifiable {
    let segment: FlightSegment
    let from: Airport?
    let to: Airport?
    var id: UUID { segment.id }
}

/// Matching a typed-in or scanned logbook entry to the real flight in the
/// ADS-B networks' daily archives. Shared by the one-flight picker
/// (HistoricalTrackMatchView) and the bulk PastFlightPathFinder.
@MainActor
enum PastFlightPaths {

    /// The flight's own hex, else the fleet's (which honors a manual
    /// override), else the derivation from the registration.
    static func hex(for flight: Flight, fleet: FleetStore) -> String? {
        if let own = flight.icaoHex, !own.isEmpty { return own.lowercased() }
        let tail = NNumber.normalize(flight.tailNumber)
        if let plane = fleet.aircraft.first(where: { NNumber.normalize($0.tailNumber) == tail }) {
            return plane.resolvedHex
        }
        return NNumber.icaoHex(for: tail) ?? ForeignRegistration.canadianHex(for: tail)
    }

    /// Every flight the aircraft made on that local day, and whether the
    /// archives had any trace of it at all.
    static func candidates(hex: String, day: Date,
                           airports: AirportStore) async -> (sawAircraft: Bool, flights: [PastFlightCandidate]) {
        let points = await ADSBClient().dayTrack(hex: hex, localDay: day)
        let dayStart = Calendar.current.startOfDay(for: day)
        let dayEnd = dayStart.addingTimeInterval(24 * 3600)
        let flights = FlightSegmenter.flights(in: points)
            .filter { $0.takeoff >= dayStart && $0.takeoff < dayEnd }
            .map { segment in
                PastFlightCandidate(segment: segment,
                                    from: segment.firstPoint.flatMap { airports.nearest(to: $0.coordinate) },
                                    to: segment.lastPoint.flatMap { airports.nearest(to: $0.coordinate) })
            }
        return (!points.isEmpty, flights)
    }

    /// Another logbook entry for this tail already owns this stretch of sky.
    static func isAlreadyLogged(_ segment: FlightSegment, for flight: Flight, in flights: [Flight]) -> Bool {
        let tail = NNumber.normalize(flight.tailNumber)
        return flights.contains { other in
            other.id != flight.id
                && NNumber.normalize(other.tailNumber) == tail
                && other.track.count > 1
                && (other.takeoffTime.map { abs($0.timeIntervalSince(segment.takeoff)) < 5 * 60 } ?? false)
        }
    }

    /// Whether a candidate agrees with everything the entry says: the same
    /// airports where the entry names them, and a similar length. Logged
    /// time is usually Hobbs or block time, a few tenths longer than the
    /// airborne time ADS-B sees, so the tolerance is generous.
    static func fits(_ candidate: PastFlightCandidate, _ flight: Flight) -> Bool {
        if let dep = flight.departure?.ident, candidate.from?.ident != dep { return false }
        if let dest = flight.destination?.ident, candidate.to?.ident != dest { return false }
        if flight.landingTime != nil, let logged = flight.flightTime {
            let tolerance = max(30 * 60, logged * 0.4)
            if abs(logged - candidate.segment.duration) > tolerance { return false }
        }
        return true
    }
}

/// Pro: finds the real flight path for many past logbook entries at once,
/// right after a logbook page is scanned, a past flight is typed in, or
/// from the Logbook menu. A path is attached only when exactly one flight
/// that day fits the entry; days with several possible flights wait for
/// the pilot to pick on the flight's own Find the flight path screen.
@Observable
@MainActor
final class PastFlightPathFinder {
    static let shared = PastFlightPathFinder()

    struct Report: Equatable {
        var found = 0
        var needsPick = 0
        var notFound = 0

        var summary: String {
            var parts = [found == 1 ? "Found 1 flight path." : "Found \(found) flight paths."]
            if needsPick > 0 {
                parts.append(needsPick == 1
                    ? "1 flight had more than one possible match that day. Open it and tap Find the flight path to pick."
                    : "\(needsPick) flights had more than one possible match that day. Open them and tap Find the flight path to pick.")
            }
            if notFound > 0 {
                parts.append(notFound == 1
                    ? "1 flight has no ADS-B history: no coverage there, or it's older than the archives."
                    : "\(notFound) flights have no ADS-B history: no coverage there, or they're older than the archives.")
            }
            return parts.joined(separator: " ")
        }
    }

    private enum Outcome { case found, needsPick, notFound }

    private(set) var isRunning = false
    private(set) var done = 0
    private(set) var total = 0
    /// The last finished run, shown in the Logbook until dismissed.
    private(set) var lastReport: Report?

    private var queue: [UUID] = []
    private var current: UUID?
    /// One archive download per aircraft-day, however many entries share it.
    private var dayCache: [String: [PastFlightCandidate]] = [:]

    private init() {}

    /// Whether this flight is waiting for, or in the middle of, a lookup.
    func isPending(_ flightID: UUID) -> Bool {
        current == flightID || queue.contains(flightID)
    }

    func dismissReport() {
        lastReport = nil
    }

    func findPaths(for flightIDs: [UUID], logbook: LogbookStore, fleet: FleetStore, airports: AirportStore) {
        let fresh = flightIDs.filter { !isPending($0) }
        guard !fresh.isEmpty else { return }
        queue += fresh
        total += fresh.count
        lastReport = nil
        guard !isRunning else { return }
        isRunning = true
        Task {
            var report = Report()
            while !queue.isEmpty {
                let id = queue.removeFirst()
                current = id
                switch await findPath(for: id, logbook: logbook, fleet: fleet, airports: airports) {
                case .found?: report.found += 1
                case .needsPick?: report.needsPick += 1
                case .notFound?: report.notFound += 1
                case nil: break
                }
                done += 1
            }
            current = nil
            dayCache = [:]
            done = 0
            total = 0
            isRunning = false
            if report != Report() {
                lastReport = report
            }
        }
    }

    /// nil when there was nothing to do: the flight was deleted, or it got
    /// a path some other way in the meantime.
    private func findPath(for id: UUID, logbook: LogbookStore, fleet: FleetStore,
                          airports: AirportStore) async -> Outcome? {
        guard let flight = logbook.flights.first(where: { $0.id == id }), flight.track.count < 2 else { return nil }
        guard let hex = PastFlightPaths.hex(for: flight, fleet: fleet) else { return .notFound }

        let day = Calendar.current.startOfDay(for: flight.startedTracking)
        let key = "\(hex)|\(Int(day.timeIntervalSince1970))"
        let candidates: [PastFlightCandidate]
        if let cached = dayCache[key] {
            candidates = cached
        } else {
            candidates = await PastFlightPaths.candidates(hex: hex, day: flight.startedTracking,
                                                          airports: airports).flights
            dayCache[key] = candidates
        }

        // The logbook may have changed while the archive was loading.
        guard let entry = logbook.flights.first(where: { $0.id == id }), entry.track.count < 2 else { return nil }
        let open = candidates.filter {
            !PastFlightPaths.isAlreadyLogged($0.segment, for: entry, in: logbook.flights)
        }
        let fitting = open.filter { PastFlightPaths.fits($0, entry) }
        if fitting.count == 1, let match = fitting.first {
            logbook.attachHistoricalTrack(flightID: id, segment: match.segment,
                                          departure: match.from, destination: match.to, hex: hex)
            return .found
        }
        return open.isEmpty ? .notFound : .needsPick
    }
}
