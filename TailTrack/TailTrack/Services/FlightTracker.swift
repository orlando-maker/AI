import Foundation
import CoreLocation
import Observation

/// Live flight-following engine. Polls the open ADS-B networks for one
/// aircraft, detects takeoff and landing, records the flown track, and
/// exposes Flighty-style progress numbers for the UI.
@Observable
@MainActor
final class FlightTracker {

    enum Phase: Equatable {
        case idle
        case searching          // polling, aircraft not seen yet
        case preflight          // seen on the ground, waiting for takeoff
        case enroute
        case arrived

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .searching: return "Looking for aircraft"
            case .preflight: return "On ground"
            case .enroute: return "En route"
            case .arrived: return "Arrived"
            }
        }
    }

    private(set) var phase: Phase = .idle
    private(set) var flight: Flight?
    private(set) var latest: ADSBSnapshot?
    private(set) var statusDetail: String = ""
    private(set) var aircraft: Aircraft?
    /// Set for crew-mode flights tracked by airline callsign (e.g. DAL123).
    private(set) var targetCallsign: String?

    /// Set by the app so completed flights land in the logbook.
    var logbook: LogbookStore?
    /// Set by the app so landings can auto-detect the actual airport.
    var airports: AirportStore?

    private var pollTask: Task<Void, Never>?
    private var discoveredHex: String?
    private var consecutiveGroundSamples = 0
    private var wasAirborne = false
    private var lastRecordedPointTime: Date?
    private let client = ADSBClient()

    // Landing is declared after this many consecutive on-ground samples.
    private static let groundSamplesToLand = 2
    // A sample counts as airborne above this groundspeed even if the
    // transponder hasn't flipped its ground flag (some GA installs never do).
    private static let airborneSpeedKt = 55.0

    var isActive: Bool { phase != .idle }

    // MARK: - Control

    func start(aircraft: Aircraft, departure: Airport?, destination: Airport?) {
        cancelPolling()
        self.aircraft = aircraft
        targetCallsign = nil
        discoveredHex = aircraft.resolvedHex
        consecutiveGroundSamples = 0
        wasAirborne = false
        lastRecordedPointTime = nil
        latest = nil
        statusDetail = "Contacting ADS-B networks…"

        flight = Flight(
            tailNumber: NNumber.normalize(aircraft.tailNumber),
            typeCode: aircraft.typeCode,
            icaoHex: discoveredHex,
            departure: departure,
            destination: destination,
            startedTracking: Date()
        )
        phase = .searching

        pollTask = Task { [weak self] in
            await self?.runPollLoop()
        }
    }

    /// Crew mode: follow an airline flight by its ICAO callsign (DAL123,
    /// AAL456…). Same engine, no aircraft profile needed.
    func startCrewFlight(callsign: String, departure: Airport?, destination: Airport?) {
        cancelPolling()
        aircraft = nil
        let normalized = callsign.uppercased().replacingOccurrences(of: " ", with: "")
        targetCallsign = normalized
        discoveredHex = nil
        consecutiveGroundSamples = 0
        wasAirborne = false
        lastRecordedPointTime = nil
        latest = nil
        statusDetail = "Contacting ADS-B networks…"

        flight = Flight(
            tailNumber: normalized,
            typeCode: "",
            departure: departure,
            destination: destination,
            startedTracking: Date()
        )
        phase = .searching

        pollTask = Task { [weak self] in
            await self?.runPollLoop()
        }
    }

    /// User-initiated stop. Saves the flight if it captured a takeoff.
    func endTracking() {
        cancelPolling()
        if var f = flight, f.isMeaningful {
            if f.landingTime == nil { f.landingTime = f.track.last?.time ?? Date() }
            logbook?.add(f)
        }
        reset()
    }

    /// Dismisses the arrival summary card.
    func reset() {
        cancelPolling()
        phase = .idle
        flight = nil
        latest = nil
        aircraft = nil
        targetCallsign = nil
        statusDetail = ""
    }

    private func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Poll loop

    private func runPollLoop() async {
        while !Task.isCancelled {
            await poll()
            if phase == .arrived || Task.isCancelled { break }
            let seconds: Double = (phase == .enroute) ? 8 : 15
            try? await Task.sleep(for: .seconds(seconds))
        }
    }

    private func poll() async {
        guard aircraft != nil || targetCallsign != nil else { return }
        do {
            let snap = try await client.snapshot(
                hex: discoveredHex,
                registration: aircraft.map { NNumber.normalize($0.tailNumber) },
                callsign: targetCallsign
            )
            guard !Task.isCancelled else { return }
            if let snap {
                handle(snap)
            } else {
                handleNotSeen()
            }
        } catch {
            statusDetail = error.localizedDescription
        }
    }

    private func handle(_ snap: ADSBSnapshot) {
        latest = snap
        if discoveredHex == nil || discoveredHex?.isEmpty == true {
            discoveredHex = snap.hex
            flight?.icaoHex = snap.hex
        }
        if flight?.firstContact == nil { flight?.firstContact = snap.fetchedAt }
        if flight?.typeCode.isEmpty == true, let type = snap.typeCode {
            flight?.typeCode = type
        }

        // Ignore badly stale positions for track recording, but still show them.
        let positionTime = snap.fetchedAt.addingTimeInterval(-snap.positionAgeSeconds)
        let isFresh = snap.positionAgeSeconds < 90

        // Some GA transponder installs never set the air/ground flag, so
        // classification needs positive evidence of flight — speed, a real
        // climb/descent rate, or altitude well above the field. A bare
        // numeric altitude on a parked airplane must NOT count as airborne.
        let gs = snap.groundSpeedKt ?? 0
        let verticalRate = abs(snap.verticalRateFpm ?? 0)
        let takeoffFieldElev = (flight?.departure?.elevationFt
            ?? flight?.destination?.elevationFt).map(Double.init)
        let wellAboveField = snap.baroAltitudeFt.flatMap { alt in
            takeoffFieldElev.map { alt > $0 + 1200 }
        } ?? false

        // After flight, slow and near field elevation counts as landed even
        // if the transponder never flips its ground flag.
        let slowAndLow: Bool = {
            guard wasAirborne, (snap.groundSpeedKt ?? 999) < 35,
                  let alt = snap.baroAltitudeFt else { return false }
            let landingFieldElev = (flight?.destination?.elevationFt
                ?? flight?.departure?.elevationFt).map(Double.init)
                ?? (airports?.nearest(to: CLLocationCoordinate2D(latitude: snap.latitude,
                                                                 longitude: snap.longitude),
                                      withinNM: 6)?.elevationFt).map(Double.init)
            guard let ref = landingFieldElev else { return alt < 2500 }
            return alt < ref + 2500
        }()

        let airborne = !snap.onGround && !slowAndLow &&
            (gs > Self.airborneSpeedKt || verticalRate > 400 || wellAboveField)

        if isFresh {
            record(snap, at: positionTime, airborne: airborne)
        }

        if airborne {
            consecutiveGroundSamples = 0
            if !wasAirborne {
                wasAirborne = true
                if flight?.takeoffTime == nil {
                    flight?.takeoffTime = positionTime
                }
                autoFillDeparture()
            }
            phase = .enroute
            statusDetail = "Live via \(snap.source)"
        } else if wasAirborne {
            // Only clearly ground-like samples count toward a landing; an
            // ambiguous sample (e.g. slow cruise into a headwind with no
            // altitude evidence) keeps the flight alive.
            if snap.onGround || slowAndLow {
                consecutiveGroundSamples += 1
                if consecutiveGroundSamples >= Self.groundSamplesToLand {
                    declareLanding(at: positionTime, coordinate:
                        CLLocationCoordinate2D(latitude: snap.latitude, longitude: snap.longitude))
                    return
                }
                statusDetail = "Rolling out…"
            } else {
                consecutiveGroundSamples = 0
                statusDetail = "Live via \(snap.source)"
            }
        } else {
            phase = .preflight
            statusDetail = "On ground via \(snap.source)"
        }
    }

    private func handleNotSeen() {
        switch phase {
        case .searching:
            statusDetail = "Not broadcasting yet — waiting for the transponder to come alive."
        case .preflight, .enroute:
            let ago = latest.map { Date().timeIntervalSince($0.fetchedAt) } ?? 0
            statusDetail = "Signal lost · last contact \(Format.age(ago))"
            // A long quiet period after the aircraft was last seen slow/low
            // right next to an airport very likely means it landed there.
            // Altitude is judged against that field's elevation, not MSL,
            // so mountain airports work and low-coverage cruise doesn't
            // trigger a false landing.
            if phase == .enroute, ago > 600, wasAirborne, let last = flight?.track.last {
                let nearby = airports?.nearest(to: last.coordinate, withinNM: 6)
                let lowNearField = last.altitudeFt.flatMap { alt in
                    nearby.map { alt < Double($0.elevationFt ?? 0) + 2500 }
                } ?? false
                if last.onGround || lowNearField {
                    declareLanding(at: last.time, coordinate: last.coordinate)
                }
            }
        default:
            break
        }
    }

    private func record(_ snap: ADSBSnapshot, at time: Date, airborne: Bool) {
        // Avoid duplicate samples when the aggregator hasn't seen a newer position.
        if let lastTime = lastRecordedPointTime, time.timeIntervalSince(lastTime) < 2 { return }
        lastRecordedPointTime = time

        flight?.track.append(TrackPoint(
            time: time,
            latitude: snap.latitude,
            longitude: snap.longitude,
            altitudeFt: snap.baroAltitudeFt ?? (airborne ? snap.geoAltitudeFt : nil),
            groundSpeedKt: snap.groundSpeedKt,
            trackDeg: snap.trackDeg,
            verticalRateFpm: snap.verticalRateFpm,
            onGround: !airborne
        ))
    }

    private func autoFillDeparture() {
        guard flight?.departure == nil,
              let first = flight?.track.first,
              let airport = airports?.nearest(to: first.coordinate) else { return }
        flight?.departure = airport
    }

    private func declareLanding(at time: Date, coordinate: CLLocationCoordinate2D) {
        flight?.landingTime = time

        if let actual = airports?.nearest(to: coordinate) {
            if let planned = flight?.destination {
                if planned.ident != actual.ident {
                    flight?.notes = "Landed at \(actual.ident) (planned \(planned.ident))."
                    flight?.destination = actual
                }
            } else {
                flight?.destination = actual
            }
        }

        phase = .arrived
        statusDetail = "Landed"
        cancelPolling()

        if let f = flight, f.isMeaningful {
            logbook?.add(f)
        }
    }

    // MARK: - Live progress numbers

    var routeTotalNM: Double? { flight?.routeDistanceNM }

    var remainingNM: Double? {
        guard let dest = flight?.destination, let latest else { return nil }
        let here = CLLocationCoordinate2D(latitude: latest.latitude, longitude: latest.longitude)
        return GreatCircle.distanceNM(from: here, to: dest.coordinate)
    }

    /// 0…1 along the planned route, for the progress bar.
    var progress: Double? {
        if phase == .arrived { return 1 }
        guard let total = routeTotalNM, total > 0, let remaining = remainingNM else { return nil }
        return min(1, max(0, 1 - remaining / total))
    }

    /// Estimated time enroute remaining, from current groundspeed (falling
    /// back to the aircraft's planning cruise speed).
    var eteRemaining: TimeInterval? {
        guard phase == .enroute, let remaining = remainingNM else { return nil }
        let gs = latest?.groundSpeedKt ?? 0
        let speed = gs > 40 ? gs : (aircraft?.cruiseSpeedKt ?? 0)
        guard speed > 10 else { return nil }
        return remaining / speed * 3600
    }

    var eta: Date? {
        eteRemaining.map { Date().addingTimeInterval($0) }
    }

    var elapsed: TimeInterval? {
        flight?.flightTime
    }

    var contactAgeSeconds: TimeInterval? {
        guard let latest else { return nil }
        return Date().timeIntervalSince(latest.fetchedAt) + latest.positionAgeSeconds
    }
}
