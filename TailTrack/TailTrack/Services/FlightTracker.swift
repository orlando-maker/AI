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
        guard let aircraft else { return }
        do {
            let snap = try await client.snapshot(
                hex: discoveredHex,
                registration: NNumber.normalize(aircraft.tailNumber)
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

        // Ignore badly stale positions for track recording, but still show them.
        let positionTime = snap.fetchedAt.addingTimeInterval(-snap.positionAgeSeconds)
        let isFresh = snap.positionAgeSeconds < 90

        // Some GA transponder installs never report the "ground" flag, so a
        // slow, low sample after having been airborne also counts as ground.
        let referenceElevationFt = Double(flight?.destination?.elevationFt
            ?? flight?.departure?.elevationFt ?? 0)
        let slowAndLow = wasAirborne &&
            (snap.groundSpeedKt ?? 999) < 35 &&
            (snap.baroAltitudeFt.map { $0 < referenceElevationFt + 2500 } ?? false)

        let airborne = !snap.onGround && !slowAndLow &&
            (snap.baroAltitudeFt != nil || (snap.groundSpeedKt ?? 0) > Self.airborneSpeedKt)

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
        } else {
            if wasAirborne {
                consecutiveGroundSamples += 1
                if consecutiveGroundSamples >= Self.groundSamplesToLand {
                    declareLanding(at: positionTime, coordinate:
                        CLLocationCoordinate2D(latitude: snap.latitude, longitude: snap.longitude))
                    return
                }
                statusDetail = "Rolling out…"
            } else {
                phase = .preflight
                statusDetail = "On ground via \(snap.source)"
            }
        }
    }

    private func handleNotSeen() {
        switch phase {
        case .searching:
            statusDetail = "Not broadcasting yet — waiting for the transponder to come alive."
        case .preflight, .enroute:
            let ago = latest.map { Date().timeIntervalSince($0.fetchedAt) } ?? 0
            statusDetail = "Signal lost · last contact \(Format.age(ago))"
            // A GA aircraft dropping off coverage at low altitude near the
            // destination very likely landed; require a long quiet period
            // before assuming so.
            if phase == .enroute, ago > 600, let last = flight?.track.last,
               (last.altitudeFt ?? 0) < 4000 {
                declareLanding(at: last.time, coordinate: last.coordinate)
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
