import Foundation
import CoreLocation
import Observation

/// Live flight-following engine. Polls the open ADS-B networks for one
/// aircraft, detects takeoff and landing, records the flown track, and
/// exposes Flighty-style progress numbers for the UI.
@Observable
@MainActor
final class FlightTracker {

    enum Phase: String, Equatable, Codable {
        case idle
        case searching          // polling, aircraft not seen yet
        case preflight          // seen on the ground, waiting for takeoff
        case enroute
        case arrived
        case signalLost         // reception gone mid-flight; awaiting manual landing

        var label: String {
            switch self {
            case .idle: return "Idle"
            case .searching: return "Looking for aircraft"
            case .preflight: return "On ground"
            case .enroute: return "En route"
            case .arrived: return "Arrived"
            case .signalLost: return "Signal lost"
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
    /// Other aircraft near the tracked plane (display-only traffic layer).
    private(set) var nearbyTraffic: [NearbyAircraft] = []

    /// Set by the app so completed flights land in the logbook.
    var logbook: LogbookStore?
    /// Set by the app so landings can auto-detect the actual airport.
    var airports: AirportStore?

    private var pollTask: Task<Void, Never>?
    private var discoveredHex: String?
    /// Takeoff, landing, touch-and-go and signal-loss decisions.
    private var detector = FlightPhaseDetector()
    /// The flight as it was before a landing was declared, so a
    /// touch-and-go or stop-and-go can undo what the landing changed.
    private var preLanding: PreLandingState?
    private var lastPersisted: Date?
    private var lastRecordedPointTime: Date?
    private var didBackfillHistory = false
    private var backfillAttempts = 0
    private var lastTrafficFetch: Date?
    /// Via stops already overflown (or stopped at), so the distance-left
    /// math stops routing through them.
    private var visitedViaIdents: Set<String> = []
    /// Radio log bookkeeping: the transponder code last logged, a new code
    /// waiting to prove it's stable, and whether the arrival ATIS is in.
    private var lastSquawk: String?
    private var pendingSquawk: String?
    private var pendingSquawkReports = 0
    private var loggedArrivalATIS = false
    private let client = ADSBClient()
    private let liveActivity = FlightLiveActivity()

    /// UserDefaults key for the traffic layer toggle (defaults to on).
    static let nearbyTrafficKey = "showNearbyTraffic"

    static var trafficLayerEnabled: Bool {
        UserDefaults.standard.object(forKey: nearbyTrafficKey) as? Bool ?? true
    }

    /// After a landing, keep listening this long: a takeoff inside it is a
    /// touch-and-go or stop-and-go on the same flight, not a new one.
    private static let postLandingWatch: TimeInterval = 10 * 60
    /// Recovered flights older than this are left in the logbook as-is.
    private static let resumeWindow: TimeInterval = 12 * 3600

    var isActive: Bool { phase != .idle }

    // MARK: - Control

    func start(aircraft: Aircraft, departure: Airport?, destination: Airport?,
               via: [Airport] = []) {
        cancelPolling()
        self.aircraft = aircraft
        targetCallsign = nil
        discoveredHex = aircraft.resolvedHex
        detector = FlightPhaseDetector()
        preLanding = nil
        lastRecordedPointTime = nil
        didBackfillHistory = false
        backfillAttempts = 0
        lastTrafficFetch = nil
        nearbyTraffic = []
        visitedViaIdents = []
        latest = nil
        statusDetail = "Contacting ADS-B networks…"

        flight = Flight(
            tailNumber: NNumber.normalize(aircraft.tailNumber),
            typeCode: aircraft.typeCode,
            icaoHex: discoveredHex,
            departure: departure,
            destination: destination,
            via: via.isEmpty ? nil : via,
            startedTracking: Date()
        )
        resetRadioLog()
        phase = .searching
        NotificationManager.requestAuthorization()
        persistActiveFlight(force: true)

        pollTask = Task { [weak self] in
            await self?.runPollLoop()
        }
    }

    /// Common IATA airline codes → the ICAO prefix that ADS-B callsigns
    /// actually use, so "AA776" finds AAL776 without the user knowing the
    /// difference.
    private static let iataToICAOAirline: [String: String] = [
        "AA": "AAL", "DL": "DAL", "UA": "UAL", "WN": "SWA", "B6": "JBU",
        "AS": "ASA", "NK": "NKS", "F9": "FFT", "HA": "HAL", "G4": "AAY",
        "SY": "SCX", "AC": "ACA", "WS": "WJA", "AM": "AMX", "AV": "AVA",
        "CM": "CMP", "BA": "BAW", "VS": "VIR", "LH": "DLH", "AF": "AFR",
        "KL": "KLM", "IB": "IBE", "AY": "FIN", "EI": "EIN", "TK": "THY",
        "EK": "UAE", "QR": "QTR", "QF": "QFA", "NZ": "ANZ", "SQ": "SIA",
        "CX": "CPA", "JL": "JAL", "NH": "ANA", "KE": "KAL", "OZ": "AAR",
    ]

    static func normalizeCallsign(_ raw: String) -> String {
        let s = raw.uppercased().replacingOccurrences(of: " ", with: "")
        guard s.count >= 3 else { return s }
        let prefix = String(s.prefix(2))
        let rest = String(s.dropFirst(2))
        if let icao = iataToICAOAirline[prefix], rest.first?.isNumber == true {
            return icao + rest
        }
        return s
    }

    /// Crew mode: follow an airline flight by callsign (DAL123, AAL456) or
    /// plain flight number (AA776, DL123). Same engine, no aircraft
    /// profile needed.
    func startCrewFlight(callsign: String, departure: Airport?, destination: Airport?) {
        cancelPolling()
        aircraft = nil
        let normalized = Self.normalizeCallsign(callsign)
        targetCallsign = normalized
        discoveredHex = nil
        detector = FlightPhaseDetector()
        preLanding = nil
        lastRecordedPointTime = nil
        didBackfillHistory = false
        backfillAttempts = 0
        lastTrafficFetch = nil
        nearbyTraffic = []
        visitedViaIdents = []
        latest = nil
        statusDetail = "Contacting ADS-B networks…"

        flight = Flight(
            tailNumber: normalized,
            typeCode: "",
            departure: departure,
            destination: destination,
            startedTracking: Date()
        )
        resetRadioLog()
        phase = .searching
        NotificationManager.requestAuthorization()
        persistActiveFlight(force: true)

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
            captureWeather(for: f)
        }
        reset()
    }

    /// Dismisses the arrival summary card.
    func reset() {
        cancelPolling()
        // A flight ended by hand mid-flight must not leave a live-looking
        // countdown frozen on the Lock Screen for the dismissal window.
        var finalState = liveActivityState()
        if phase != .arrived && phase != .signalLost {
            finalState.etaEpoch = nil
            finalState.phaseLabel = "Flight ended"
        }
        liveActivity.end(finalState)
        ActiveFlightStore.clear()
        detector = FlightPhaseDetector()
        preLanding = nil
        phase = .idle
        flight = nil
        latest = nil
        aircraft = nil
        targetCallsign = nil
        nearbyTraffic = []
        statusDetail = ""
    }

    private func cancelPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Poll loop

    private func runPollLoop() async {
        while !Task.isCancelled {
            // After landing, keep listening only for the watch window:
            // flying again inside it is a touch-and-go or stop-and-go, but
            // a takeoff after it is a new flight, never part of this one.
            if phase == .arrived, !isWithinPostLandingWatch(at: Date()) {
                ActiveFlightStore.clear()
                break
            }
            await poll()
            if Task.isCancelled || phase == .signalLost { break }
            let seconds: Double
            switch phase {
            case .searching: seconds = 5   // find the aircraft fast
            case .enroute: seconds = 8
            default: seconds = 15
            }
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
                await backfillHistoryIfNeeded()
            } else {
                handleNotSeen()
            }
            await refreshNearbyTraffic()
        } catch {
            statusDetail = error.localizedDescription
        }
    }

    /// Display-only traffic layer: other aircraft near the tracked plane,
    /// refreshed on a slower cadence than the own-ship poll and only while
    /// the user has the layer switched on.
    private func refreshNearbyTraffic() async {
        guard Self.trafficLayerEnabled, isActive, let latest else {
            if !nearbyTraffic.isEmpty { nearbyTraffic = [] }
            return
        }
        if let last = lastTrafficFetch, Date().timeIntervalSince(last) < 20 { return }
        lastTrafficFetch = Date()
        let traffic = await client.nearbyAircraft(
            latitude: latest.latitude,
            longitude: latest.longitude,
            radiusNM: 30,
            excludingHex: discoveredHex ?? latest.hex
        )
        guard !Task.isCancelled, isActive else { return }
        nearbyTraffic = traffic
    }

    /// Joining a flight already in the air: pull the trail flown so far
    /// (breadcrumbs) from the networks' trace archives, so the map shows the
    /// whole flight and wheels-up/distance reflect the real departure, not
    /// the moment tracking started.
    private func backfillHistoryIfNeeded() async {
        guard !didBackfillHistory, detector.hasFlown,
              let hex = discoveredHex, !hex.isEmpty else { return }
        backfillAttempts += 1

        let history = await client.historicalTrack(hex: hex)
        if history.isEmpty {
            // Network hiccup or archive briefly missing — retry on the next
            // few polls before giving up on the trail.
            if backfillAttempts >= 4 { didBackfillHistory = true }
            return
        }
        didBackfillHistory = true
        guard var updated = flight else { return }

        let cutoff = updated.track.first?.time ?? Date()
        var older = history.filter { $0.time < cutoff }.sorted { $0.time < $1.time }

        // A full-day trace can contain earlier flights; keep only from the
        // most recent on-ground period onward (this flight's taxi-out).
        if let lastGroundIndex = older.lastIndex(where: { $0.onGround }) {
            older = Array(older[lastGroundIndex...])
        }
        guard older.count > 1 else { return }

        // Thin very dense traces so the saved flight stays light.
        if older.count > 1500 {
            let step = older.count / 1500 + 1
            older = older.enumerated().compactMap { $0.offset % step == 0 ? $0.element : nil }
        }

        updated.track = older + updated.track

        // True wheels-up: the first airborne point after the last on-ground
        // point; if the trace starts already airborne, the earliest point
        // known is the best available estimate.
        if let lastGround = updated.track.lastIndex(where: { $0.onGround }),
           lastGround + 1 < updated.track.count {
            updated.takeoffTime = updated.track[lastGround + 1].time
        } else if let first = updated.track.first, !first.onGround {
            updated.takeoffTime = min(updated.takeoffTime ?? first.time, first.time)
        }

        flight = updated
        autoFillDeparture()
        statusDetail = "Live · flight history loaded"
    }

    private func handle(_ snap: ADSBSnapshot) {
        if discoveredHex == nil || discoveredHex?.isEmpty == true {
            discoveredHex = snap.hex
            flight?.icaoHex = snap.hex
        }
        if flight?.typeCode.isEmpty == true, let type = snap.typeCode {
            flight?.typeCode = type
        }

        // An old position (or the same one served again with a new fetch
        // time) must never move the flight's state, the traffic layer or the
        // radio log. It only counts as silence.
        let sample = PositionSample(snap)
        guard detector.isFresh(sample),
              sample.positionTime > (detector.lastFreshPosition ?? .distantPast) else {
            handleNotSeen(stale: snap)
            return
        }

        latest = snap
        if flight?.firstContact == nil { flight?.firstContact = snap.fetchedAt }
        trackSquawk(snap)
        if phase == .enroute, !loggedArrivalATIS, let left = remainingNM, left < 40,
           let destination = flight?.destination {
            loggedArrivalATIS = true
            logATIS(for: destination.ident, arriving: true)
        }

        // Passing within a few miles of a planned via stop checks it off,
        // so distance-left and ETA route through what's actually ahead.
        if let via = flight?.via, !via.isEmpty {
            let here = CLLocationCoordinate2D(latitude: snap.latitude, longitude: snap.longitude)
            for stop in via where !visitedViaIdents.contains(stop.ident) {
                if GreatCircle.distanceNM(from: here, to: stop.coordinate) < 3 {
                    visitedViaIdents.insert(stop.ident)
                }
            }
        }

        let context = fieldContext(latitude: sample.latitude, longitude: sample.longitude)
        let classification = FlightPhaseDetector.classify(sample, context: context)
        let events = detector.ingest(sample, context: context)
        record(snap, at: sample.positionTime, onGround: classification == .ground
               || (classification == .unclear && (detector.mode == .waiting || detector.mode == .landed)))
        updatePhase(source: snap.source)
        apply(events)
        persistActiveFlight()
    }

    /// Nothing usable this poll: no answer at all, or only a stale position.
    private func handleNotSeen(stale: ADSBSnapshot? = nil) {
        let now = stale?.fetchedAt ?? Date()
        switch phase {
        case .searching:
            if let stale {
                statusDetail = "Only an old position so far (\(Format.age(stale.positionAgeSeconds)) old) — waiting for a live one."
            } else {
                statusDetail = "Not broadcasting yet — waiting for the transponder to come alive."
            }
        case .preflight, .enroute:
            let ago = detector.lastFreshPosition.map { now.timeIntervalSince($0) } ?? 0
            statusDetail = "Signal lost · last contact \(Format.age(ago))"
            apply(detector.noContact(at: now))
        default:
            break
        }
        persistActiveFlight()
    }

    /// The airports around a position: one close enough to be landing at,
    /// and the local ground reference for "clearly flying". Always the
    /// airports actually below the airplane, never the planned destination.
    private func fieldContext(latitude: Double, longitude: Double) -> FieldContext {
        let here = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let landingField = airports?.nearest(to: here, withinNM: 2.5)
        let localField = airports?.nearest(to: here, withinNM: 10)
        return FieldContext(
            nearbyFieldElevationFt: landingField?.elevationFt.map(Double.init),
            referenceElevationFt: (localField?.elevationFt ?? flight?.departure?.elevationFt).map(Double.init)
        )
    }

    private func updatePhase(source: String) {
        switch detector.mode {
        case .waiting:
            phase = .preflight
            statusDetail = "On ground via \(source)"
        case .airborne:
            phase = .enroute
            statusDetail = "Live via \(source)"
            liveActivity.update(liveActivityState())
        case .rollout:
            phase = .enroute
            statusDetail = "Rolling out…"
            liveActivity.update(liveActivityState())
        case .landed:
            phase = .arrived
        }
    }

    private func apply(_ events: [FlightPhaseDetector.Event]) {
        for event in events {
            switch event {
            case .takeoff(let time):
                if flight?.takeoffTime == nil { flight?.takeoffTime = time }
                autoFillDeparture()
                startLiveActivity()
            case .touchAndGo:
                statusDetail = "Touch-and-go · landing \(detector.landingCount)"
            case .landed(let time, let latitude, let longitude):
                declareLanding(at: time, coordinate: CLLocationCoordinate2D(latitude: latitude,
                                                                          longitude: longitude))
            case .resumedAfterLanding:
                resumeAfterLanding()
            case .signalLost:
                resolveSignalLoss()
            }
        }
    }

    /// No fresh position for eight minutes while flying. If the airplane was
    /// last seen low and right at an airport, it almost certainly landed
    /// there (judged against that field's elevation, so mountain airports
    /// work). Otherwise the flight ends as "signal lost" and the pilot is
    /// asked for the landing time and engine hours.
    private func resolveSignalLoss() {
        guard let last = flight?.track.last else {
            endDueToSignalLoss()
            return
        }
        let field = airports?.nearest(to: last.coordinate, withinNM: 3)
        let lowAtField = last.altitudeFt.flatMap { altitude in
            field.map { altitude < Double($0.elevationFt ?? 0) + 1200 }
        } ?? false
        if last.onGround || lowAtField {
            detector.markLanded(at: last.time)
            declareLanding(at: last.time, coordinate: last.coordinate)
        } else {
            endDueToSignalLoss()
        }
    }

    private func isWithinPostLandingWatch(at time: Date) -> Bool {
        guard let landedAt = detector.landedAt else { return false }
        return time.timeIntervalSince(landedAt) < Self.postLandingWatch
    }

    private func startLiveActivity() {
        liveActivity.start(
            tailNumber: flight?.tailNumber ?? "",
            departureIdent: flight?.departure?.ident ?? "———",
            destinationIdent: flight?.destination?.ident ?? "———",
            state: liveActivityState()
        )
    }

    private func record(_ snap: ADSBSnapshot, at time: Date, onGround: Bool) {
        // Avoid duplicate samples when the aggregator hasn't seen a newer position.
        if let lastTime = lastRecordedPointTime, time.timeIntervalSince(lastTime) < 2 { return }
        lastRecordedPointTime = time

        flight?.track.append(TrackPoint(
            time: time,
            latitude: snap.latitude,
            longitude: snap.longitude,
            altitudeFt: snap.baroAltitudeFt ?? (onGround ? nil : snap.geoAltitudeFt),
            groundSpeedKt: snap.groundSpeedKt,
            trackDeg: snap.trackDeg,
            verticalRateFpm: snap.verticalRateFpm,
            onGround: onGround
        ))
    }

    private func autoFillDeparture() {
        guard flight?.departure == nil,
              let first = flight?.track.first,
              let airport = airports?.nearest(to: first.coordinate) else { return }
        flight?.departure = airport
    }

    private func declareLanding(at time: Date, coordinate: CLLocationCoordinate2D) {
        preLanding = PreLandingState(destination: flight?.destination,
                                     notes: flight?.notes ?? "",
                                     plannedDestinationIdent: flight?.plannedDestinationIdent)
        flight?.landingTime = time

        if let actual = airports?.nearest(to: coordinate) {
            if let planned = flight?.destination {
                if planned.ident != actual.ident {
                    flight?.plannedDestinationIdent = planned.ident
                    if flight?.via?.contains(where: { $0.ident == actual.ident }) == true {
                        // Landing at a planned via stop is the leg ending as
                        // planned — a fuel stop, not a diversion.
                        flight?.notes = "Landed at planned stop \(actual.ident), en route to \(planned.ident)."
                    } else {
                        // Diversion: keep the plan on record, log the reality.
                        flight?.notes = "Landed at \(actual.ident) (planned \(planned.ident))."
                    }
                    flight?.destination = actual
                }
            } else {
                flight?.destination = actual
            }
        }

        phase = .arrived
        statusDetail = "Landed"
        liveActivity.end(liveActivityState())

        if let f = flight, f.isMeaningful {
            logbook?.add(f)
            captureWeather(for: f)
        }
        persistActiveFlight(force: true)
    }

    /// Airborne again after a declared landing: a stop-and-go or taxi-back
    /// in the pattern, or a landing call that was wrong. Same flight; the
    /// landing's changes are undone, and the logbook keeps its landed copy
    /// until the real landing replaces it.
    private func resumeAfterLanding() {
        if let preLanding {
            flight?.destination = preLanding.destination
            flight?.notes = preLanding.notes
            flight?.plannedDestinationIdent = preLanding.plannedDestinationIdent
        }
        preLanding = nil
        flight?.landingTime = nil
        phase = .enroute
        statusDetail = "Off again · landing \(detector.landingCount) logged"
        startLiveActivity()
        persistActiveFlight(force: true)
    }

    // MARK: - Radio log

    /// Adds a pilot-entered line to the radio log, stamped with where the
    /// aircraft was at that moment.
    func logRadio(kind: RadioLogEntry.Kind, text: String, detail: String? = nil) {
        appendRadio(RadioLogEntry(time: Date(), kind: kind, text: text, detail: detail))
        if kind == .squawk {
            // The pilot logged the assignment; ADS-B will confirm the same
            // code shortly and shouldn't add a duplicate line.
            lastSquawk = text.filter(\.isNumber)
            pendingSquawk = nil
        }
    }

    func deleteRadioEntry(id: UUID) {
        flight?.radioLog?.removeAll { $0.id == id }
        persistIfLanded()
    }

    private func resetRadioLog() {
        lastSquawk = nil
        pendingSquawk = nil
        pendingSquawkReports = 0
        loggedArrivalATIS = false
        if let departure = flight?.departure {
            logATIS(for: departure.ident, arriving: false)
        }
    }

    private func appendRadio(_ entry: RadioLogEntry) {
        var entry = entry
        if entry.latitude == nil, let latest {
            entry.latitude = latest.latitude
            entry.longitude = latest.longitude
            entry.altitudeFt = latest.baroAltitudeFt
        }
        guard flight != nil else { return }
        flight?.radioLog = (flight?.radioLog ?? []) + [entry]
        persistIfLanded()
    }

    /// A landed flight is already in the logbook; keep its copy current.
    private func persistIfLanded() {
        guard phase == .arrived || phase == .signalLost,
              let f = flight, f.isMeaningful else { return }
        logbook?.add(f)
    }

    /// Logs the transponder code whenever it changes. Pilots dial through
    /// other codes while setting a new one, so a code is only logged once
    /// two reports in a row agree.
    private func trackSquawk(_ snap: ADSBSnapshot) {
        guard let code = snap.squawk?.trimmingCharacters(in: .whitespaces),
              Squawk.isValid(code) else { return }
        guard code != lastSquawk else {
            pendingSquawk = nil
            return
        }
        if pendingSquawk == code {
            pendingSquawkReports += 1
        } else {
            pendingSquawk = code
            pendingSquawkReports = 1
        }
        guard pendingSquawkReports >= 2 else { return }

        let first = lastSquawk == nil
        lastSquawk = code
        pendingSquawk = nil
        appendRadio(RadioLogEntry(
            time: snap.fetchedAt,
            kind: .squawk,
            text: "Squawk \(code)",
            detail: first ? "\(Squawk.meaning(code)) · code when tracking began" : Squawk.meaning(code),
            isAutomatic: true,
            latitude: snap.latitude,
            longitude: snap.longitude,
            altitudeFt: snap.baroAltitudeFt
        ))
    }

    /// Writes the airport's current ATIS letter and essentials into the
    /// log, where the field publishes a digital ATIS.
    private func logATIS(for ident: String, arriving: Bool) {
        let flightID = flight?.id
        Task { [weak self] in
            let reports = await ATISService().reports(for: ident)
            guard let self, self.flight?.id == flightID else { return }
            let preferred: ATISReport.Kind = arriving ? .arrival : .departure
            guard let report = reports.first(where: { $0.kind == preferred })
                    ?? reports.first(where: { $0.kind == .combined }) ?? reports.first
            else { return }
            let decoded = report.decoded
            let name = decoded.information ?? report.letter ?? "?"
            self.appendRadio(RadioLogEntry(
                time: Date(),
                kind: .atis,
                text: "\(ident) \(report.title) \(name)",
                detail: decoded.kneeboardSummary.isEmpty ? nil : decoded.kneeboardSummary,
                isAutomatic: true
            ))
        }
    }

    /// Freezes the departure and arrival METARs into the flight, so months
    /// later it still shows the weather it was actually flown in.
    private func captureWeather(for flight: Flight) {
        let depIdent = flight.departure?.ident
        let arrIdent = flight.destination?.ident
        let idents = [depIdent, arrIdent].compactMap { $0 }
        guard !idents.isEmpty else { return }
        let flightID = flight.id

        Task { [weak self] in
            let metars = await WeatherService().metars(for: idents)
            guard let self, !metars.isEmpty else { return }
            let dep = metars.first { $0.ident == depIdent }?.raw
            let arr = metars.first { $0.ident == arrIdent }?.raw
            self.logbook?.attachWeather(flightID: flightID, departure: dep, arrival: arr)
            if self.flight?.id == flightID {
                self.flight?.departureMetar = dep
                self.flight?.arrivalMetar = arr
            }
        }
    }

    private func liveActivityState() -> FlightActivityAttributes.ContentState {
        FlightActivityAttributes.ContentState(
            progress: progress ?? 0,
            altitudeFt: latest?.baroAltitudeFt,
            groundSpeedKt: latest?.groundSpeedKt,
            remainingNM: remainingNM,
            etaEpoch: eta?.timeIntervalSince1970,
            phaseLabel: phase.label
        )
    }

    private func endDueToSignalLoss() {
        phase = .signalLost
        statusDetail = "Transponder signal lost — set the landing time when you're down."
        cancelPolling()
        ActiveFlightStore.clear()
        liveActivity.end(liveActivityState())
        NotificationManager.send(
            title: "Lost transponder signal",
            body: "\(flight?.tailNumber ?? "Your aircraft") hasn't been heard by the ADS-B networks for a while. Open TailTrack to log the landing time."
        )
        if let f = flight, f.isMeaningful {
            logbook?.add(f)
        }
    }

    /// Pilot-entered landing details, used after a signal-loss ending or to
    /// attach engine times to a normal arrival. Passing nil leaves a value
    /// unchanged.
    func recordLandingDetails(landingTime: Date?, hobbs: Double?, tach: Double?) {
        if let landingTime { flight?.landingTime = landingTime }
        if let hobbs { flight?.hobbsTime = hobbs }
        if let tach { flight?.tachTime = tach }
        if phase == .signalLost { phase = .arrived }
        statusDetail = "Landed"
        if let f = flight, f.isMeaningful {
            logbook?.add(f)
        }
    }

    // MARK: - Surviving app termination

    /// Saves the flight in progress, at most every 15 seconds unless forced,
    /// so a relaunch after iOS ends the app can pick it back up.
    private func persistActiveFlight(force: Bool = false) {
        guard phase != .idle, let flight else { return }
        if !force, let last = lastPersisted, Date().timeIntervalSince(last) < 15 { return }
        lastPersisted = Date()
        ActiveFlightStore.save(ActiveFlightSnapshot(
            savedAt: Date(),
            phase: phase,
            flight: flight,
            aircraft: aircraft,
            targetCallsign: targetCallsign,
            discoveredHex: discoveredHex,
            detector: detector,
            visitedViaIdents: Array(visitedViaIdents),
            lastSquawk: lastSquawk,
            loggedArrivalATIS: loggedArrivalATIS,
            preLanding: preLanding
        ))
    }

    /// Called at launch. If the app was ended mid-flight, picks the same
    /// flight back up, replays what the ADS-B networks recorded while
    /// TailTrack was gone through the same detector (so a landing that
    /// happened meanwhile lands at its real time), and keeps tracking.
    func resumeInterruptedFlightIfAny() {
        guard phase == .idle, let saved = ActiveFlightStore.load() else { return }
        let stillCurrent = saved.phase != .arrived || saved.detector.landedAt.map {
            Date().timeIntervalSince($0) < Self.postLandingWatch
        } ?? false
        guard Date().timeIntervalSince(saved.savedAt) < Self.resumeWindow,
              [.searching, .preflight, .enroute, .arrived].contains(saved.phase),
              stillCurrent else {
            ActiveFlightStore.clear()
            return
        }

        flight = saved.flight
        aircraft = saved.aircraft
        targetCallsign = saved.targetCallsign
        discoveredHex = saved.discoveredHex
        detector = saved.detector
        visitedViaIdents = Set(saved.visitedViaIdents)
        lastSquawk = saved.lastSquawk
        pendingSquawk = nil
        loggedArrivalATIS = saved.loggedArrivalATIS
        preLanding = saved.preLanding
        phase = saved.phase
        lastRecordedPointTime = saved.flight.track.last?.time
        didBackfillHistory = false
        backfillAttempts = 0
        lastTrafficFetch = nil
        nearbyTraffic = []
        latest = nil
        statusDetail = "Picked your flight back up — catching up on what TailTrack missed…"
        liveActivity.reattach()

        pollTask = Task { [weak self] in
            await self?.catchUpAfterInterruption()
            await self?.runPollLoop()
        }
    }

    private func catchUpAfterInterruption() async {
        guard let hex = discoveredHex, !hex.isEmpty,
              let since = flight?.track.last?.time ?? flight?.startedTracking else { return }
        let history = await client.historicalTrack(hex: hex)
        guard !Task.isCancelled else { return }
        let missed = FlightSegmenter.thinned(
            history.filter { $0.time > since }.sorted { $0.time < $1.time }, limit: 2000)
        guard !missed.isEmpty else { return }

        // Nearby-airport lookups scan the whole database; neighbouring
        // points share them (≈1 nm cells).
        var contexts: [String: FieldContext] = [:]
        for point in missed {
            // Once landed, anything after the watch window belongs to a
            // later flight.
            if detector.mode == .landed, !isWithinPostLandingWatch(at: point.time) { break }
            let key = "\(Int((point.latitude * 50).rounded()))/\(Int((point.longitude * 50).rounded()))"
            let context = contexts[key] ?? fieldContext(latitude: point.latitude, longitude: point.longitude)
            contexts[key] = context
            let sample = PositionSample(positionTime: point.time, receivedAt: point.time,
                                        latitude: point.latitude, longitude: point.longitude,
                                        baroAltitudeFt: point.altitudeFt, geoAltitudeFt: nil,
                                        groundSpeedKt: point.groundSpeedKt,
                                        verticalRateFpm: point.verticalRateFpm,
                                        onGround: point.onGround)
            let events = detector.ingest(sample, context: context)
            flight?.track.append(point)
            lastRecordedPointTime = point.time
            updatePhase(source: "flight history")
            apply(events)
        }
        statusDetail = "Caught up · \(missed.count) missed positions recovered"
        persistActiveFlight(force: true)
    }

    // MARK: - Live progress numbers

    var routeTotalNM: Double? { flight?.routeDistanceNM }

    var remainingNM: Double? {
        guard let dest = flight?.destination, let latest else { return nil }
        let here = CLLocationCoordinate2D(latitude: latest.latitude, longitude: latest.longitude)
        // Multi-leg route: fly to the next stop not yet reached, then along
        // the remaining planned legs.
        let pending = (flight?.via ?? []).filter { !visitedViaIdents.contains($0.ident) }
        let stops = pending + [dest]
        var total = GreatCircle.distanceNM(from: here, to: stops[0].coordinate)
        for i in 1..<stops.count {
            total += GreatCircle.distanceNM(from: stops[i - 1].coordinate,
                                            to: stops[i].coordinate)
        }
        return total
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

/// What a landing changed, kept so a touch-and-go can put it back.
struct PreLandingState: Codable, Equatable {
    var destination: Airport?
    var notes: String
    var plannedDestinationIdent: String?
}

extension PositionSample {
    init(_ snap: ADSBSnapshot) {
        self.init(positionTime: snap.fetchedAt.addingTimeInterval(-snap.positionAgeSeconds),
                  receivedAt: snap.fetchedAt,
                  latitude: snap.latitude,
                  longitude: snap.longitude,
                  baroAltitudeFt: snap.baroAltitudeFt,
                  geoAltitudeFt: snap.geoAltitudeFt,
                  groundSpeedKt: snap.groundSpeedKt,
                  verticalRateFpm: snap.verticalRateFpm,
                  onGround: snap.onGround)
    }
}
