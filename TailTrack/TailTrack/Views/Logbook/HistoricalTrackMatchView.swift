import SwiftUI

/// Finds the real ADS-B flight path for a logbook entry that was typed in
/// or scanned. Pulls every flight the aircraft made that day from the
/// history archives, and when there were several, the pilot's takeoff time
/// picks the right one.
struct HistoricalTrackMatchView: View {
    let flight: Flight

    @Environment(LogbookStore.self) private var logbook
    @Environment(FleetStore.self) private var fleet
    @Environment(AirportStore.self) private var airports
    @Environment(\.dismiss) private var dismiss

    private enum LoadState { case loading, loaded, failed(String) }

    /// A flight from that day, with its airports resolved once up front
    /// (a nearest-airport lookup scans the whole database).
    private struct Candidate: Identifiable {
        let segment: FlightSegment
        let from: Airport?
        let to: Airport?
        var id: UUID { segment.id }
    }

    @State private var state: LoadState = .loading
    @State private var candidates: [Candidate] = []
    @State private var selectedID: UUID?
    @State private var matchByTime = false
    @State private var takeoffAround = Date()

    private var tail: String { NNumber.normalize(flight.tailNumber) }

    /// The flight's own hex, else the fleet's (which honors a manual
    /// override), else the FAA N-number derivation.
    private var hex: String? {
        if let own = flight.icaoHex, !own.isEmpty { return own.lowercased() }
        if let plane = fleet.aircraft.first(where: { NNumber.normalize($0.tailNumber) == tail }) {
            return plane.resolvedHex
        }
        return NNumber.icaoHex(for: tail) ?? ForeignRegistration.canadianHex(for: tail)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    LabeledContent("Aircraft", value: tail)
                    LabeledContent("Date",
                                   value: flight.startedTracking.formatted(date: .abbreviated, time: .omitted))
                    Toggle("I know roughly when I took off", isOn: $matchByTime.animation())
                    if matchByTime {
                        DatePicker("Takeoff around", selection: $takeoffAround,
                                   displayedComponents: .hourAndMinute)
                    }
                } footer: {
                    Text("Flew this aircraft more than once that day? Set your takeoff time and the closest flight moves to the top.")
                }

                Section {
                    switch state {
                    case .loading:
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Searching the ADS-B history for \(tail)…")
                                .foregroundStyle(.secondary)
                        }
                    case .failed(let message):
                        Text(message)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    case .loaded:
                        let ordered = ranked
                        ForEach(Array(ordered.enumerated()), id: \.element.id) { index, candidate in
                            candidateRow(candidate, isBest: index == 0 && ordered.count > 1)
                        }
                    }
                } header: {
                    if case .loaded = state {
                        Text(candidates.count == 1 ? "1 flight found" : "\(candidates.count) flights found")
                    }
                } footer: {
                    Text("Tracks come from the community ADS-B networks' daily archives. Low-altitude coverage can be patchy, so the path may start or end a little away from the runway.")
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("Find Flight Path")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Attach") { attach() }
                        .disabled(selectedCandidate == nil)
                }
            }
            .task { await load() }
            .sensoryFeedback(.selection, trigger: selectedID) { old, new in old != nil && new != nil }
            .onChange(of: matchByTime) { _, _ in selectBest() }
            .onChange(of: takeoffAround) { _, _ in selectBest() }
        }
    }

    // MARK: - Rows

    private func candidateRow(_ candidate: Candidate, isBest: Bool) -> some View {
        let segment = candidate.segment
        let used = isAlreadyLogged(segment)
        let selected = selectedID == candidate.id
        return Button {
            selectedID = candidate.id
        } label: {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(selected ? Theme.brandOrange : .secondary)
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text("\(Format.localTime(segment.takeoff)) – \(Format.localTime(segment.landing))")
                            .font(.headline.monospacedDigit())
                        if isBest {
                            Text("BEST MATCH")
                                .font(.caption2.weight(.heavy).monospaced())
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Theme.brandOrange.opacity(0.15), in: Capsule())
                                .foregroundStyle(Theme.brandOrange)
                        }
                    }
                    Text("\(candidate.from?.ident ?? "———") → \(candidate.to?.ident ?? "———")")
                        .font(.subheadline)
                    Text(detailText(segment, used: used))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            .contentShape(Rectangle())
        }
        .foregroundStyle(.primary)
    }

    private func detailText(_ segment: FlightSegment, used: Bool) -> String {
        var parts = [Format.duration(segment.duration)]
        if let alt = segment.maxAltitudeFt { parts.append("max \(Format.feet(alt))") }
        if used { parts.append("already in your logbook") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Matching

    private var selectedCandidate: Candidate? {
        candidates.first { $0.id == selectedID }
    }

    /// Best first: closest to the given takeoff time when the pilot set
    /// one; otherwise the flight whose airports and length best fit the
    /// logbook entry. Flights already logged sink to the bottom.
    private var ranked: [Candidate] {
        let scores = Dictionary(uniqueKeysWithValues: candidates.map { ($0.id, score($0)) })
        return candidates.sorted { (scores[$0.id] ?? 0) < (scores[$1.id] ?? 0) }
    }

    /// Lower is better, measured in seconds of mismatch.
    private func score(_ candidate: Candidate) -> Double {
        let segment = candidate.segment
        var score: Double = isAlreadyLogged(segment) ? 1_000_000 : 0
        if matchByTime {
            return score + abs(segment.takeoff.timeIntervalSince(targetTakeoff))
        }
        if let dep = flight.departure?.ident, candidate.from?.ident != dep { score += 7200 }
        if let dest = flight.destination?.ident, candidate.to?.ident != dest { score += 7200 }
        if flight.landingTime != nil, let logged = flight.flightTime {
            score += abs(logged - segment.duration)
        }
        return score
    }

    /// The picked clock time, on the flight's own day.
    private var targetTakeoff: Date {
        let calendar = Calendar.current
        let time = calendar.dateComponents([.hour, .minute], from: takeoffAround)
        return calendar.date(bySettingHour: time.hour ?? 12, minute: time.minute ?? 0, second: 0,
                             of: flight.startedTracking) ?? flight.startedTracking
    }

    /// Another logbook entry for this tail already owns this stretch of sky.
    private func isAlreadyLogged(_ segment: FlightSegment) -> Bool {
        logbook.flights.contains { other in
            other.id != flight.id
                && NNumber.normalize(other.tailNumber) == tail
                && other.track.count > 1
                && (other.takeoffTime.map { abs($0.timeIntervalSince(segment.takeoff)) < 5 * 60 } ?? false)
        }
    }

    private func selectBest() {
        selectedID = ranked.first?.id
    }

    // MARK: - Load / attach

    private func load() async {
        takeoffAround = flight.takeoffTime ?? flight.startedTracking
        guard let hex else {
            state = .failed("TailTrack can't work out the transponder code for \(tail). Add its Mode S hex in the aircraft's settings, then try again.")
            return
        }
        let points = await ADSBClient().dayTrack(hex: hex, localDay: flight.startedTracking)
        let dayStart = Calendar.current.startOfDay(for: flight.startedTracking)
        let dayEnd = dayStart.addingTimeInterval(24 * 3600)
        candidates = FlightSegmenter.flights(in: points)
            .filter { $0.takeoff >= dayStart && $0.takeoff < dayEnd }
            .map { segment in
                Candidate(segment: segment,
                          from: segment.firstPoint.flatMap { airports.nearest(to: $0.coordinate) },
                          to: segment.lastPoint.flatMap { airports.nearest(to: $0.coordinate) })
            }
        if candidates.isEmpty {
            state = .failed(points.isEmpty
                ? "No ADS-B history found for \(tail) on this day. The networks may not have had coverage there, the archive for that day may be unavailable, or the date may be wrong."
                : "\(tail) was seen that day, but never long enough in the air to count as a flight.")
        } else {
            state = .loaded
            selectBest()
        }
    }

    private func attach() {
        guard let candidate = selectedCandidate, let hex else { return }
        logbook.attachHistoricalTrack(
            flightID: flight.id,
            segment: candidate.segment,
            departure: candidate.from,
            destination: candidate.to,
            hex: hex
        )
        dismiss()
    }
}
