import SwiftUI

/// Pre-flight setup: pick an aircraft, optionally a route, see the plan
/// numbers, and start tracking.
struct FlightSetupView: View {
    @Environment(FlightTracker.self) private var tracker
    @Environment(FleetStore.self) private var fleet
    @Environment(AirportStore.self) private var airports
    @Environment(ProStore.self) private var pro
    @Environment(ProfileStore.self) private var profileStore

    enum TrackMode: String, CaseIterable {
        case personal = "My Plane"
        case crew = "Crew / Airline"
    }

    @State private var mode: TrackMode = .personal
    @State private var callsign = ""
    @State private var selectedAircraftID: UUID?
    @State private var departure: Airport?
    @State private var destination: Airport?
    @State private var viaAirports: [Airport] = []
    @State private var pickingDeparture = false
    @State private var pickingDestination = false
    @State private var pickingVia = false
    @State private var addingAircraft = false
    @State private var addingClubPlanes = false
    @State private var showingPaywall = false

    private var selectedAircraft: Aircraft? {
        fleet.aircraft.first { $0.id == selectedAircraftID } ?? fleet.aircraft.first
    }

    var body: some View {
        Form {
            Section {
                Picker("Mode", selection: $mode) {
                    ForEach(TrackMode.allCases, id: \.self) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            if mode == .personal {
                aircraftSection
            } else {
                crewSection
            }
            routeSection
            if let plan = planSummary {
                planSection(plan)
            }
            startSection
        }
        .sheet(isPresented: $pickingDeparture) {
            AirportPickerView(title: "Departure") { departure = $0 }
        }
        .sheet(isPresented: $pickingDestination) {
            AirportPickerView(title: "Destination") { destination = $0 }
        }
        .sheet(isPresented: $pickingVia) {
            AirportPickerView(title: "Stop Along the Way") { airport in
                if !viaAirports.contains(where: { $0.ident == airport.ident }) {
                    viaAirports.append(airport)
                }
            }
        }
        .sheet(isPresented: $addingAircraft) {
            NavigationStack {
                AircraftEditView(aircraft: Aircraft()) { newPlane in
                    fleet.add(newPlane)
                    selectedAircraftID = newPlane.id
                }
            }
        }
        .sheet(isPresented: $addingClubPlanes) { ClubFleetAddView() }
        .sheet(isPresented: $showingPaywall) { PaywallView() }
        .onAppear { prefillDeparture() }
        .onChange(of: selectedAircraftID) { _, _ in prefillDeparture() }
        .onChange(of: mode) { _, newMode in
            // The home-field prefill makes no sense for an airline flight;
            // clear it (only if it was auto-filled) when switching to crew
            // mode, and restore it when switching back.
            switch newMode {
            case .crew:
                if departure?.ident == autofilledDepartureIdent { departure = nil }
            case .personal:
                prefillDeparture()
            }
        }
    }

    @State private var autofilledDepartureIdent: String?

    /// Renters' shortcut: departure defaults to the selected plane's base
    /// airport, falling back to the pilot's primary home airport.
    private func prefillDeparture() {
        guard mode == .personal, departure == nil else { return }
        let baseIdent = selectedAircraft?.homeAirportIdent
            ?? profileStore.profile.primaryHomeAirportIdent
        guard let baseIdent, let airport = airports.lookup(baseIdent) else { return }
        departure = airport
        autofilledDepartureIdent = airport.ident
    }

    // MARK: - Sections

    private func pickerLabel(_ plane: Aircraft) -> String {
        let tail = NNumber.normalize(plane.tailNumber)
        return plane.typeCode.isEmpty ? tail : "\(tail) · \(plane.typeCode)"
    }

    private var aircraftSection: some View {
        Section("Aircraft") {
            if fleet.aircraft.isEmpty {
                Button {
                    addingAircraft = true
                } label: {
                    Label("Add your aircraft", systemImage: "plus.circle.fill")
                }
                Button {
                    addingClubPlanes = true
                } label: {
                    Label("Add a club fleet (tail numbers only)", systemImage: "person.3")
                }
            } else {
                Picker("Aircraft", selection: Binding(
                    get: { selectedAircraft?.id },
                    set: { selectedAircraftID = $0 }
                )) {
                    if !fleet.myAircraft.isEmpty {
                        Section("My Aircraft") {
                            ForEach(fleet.myAircraft) { plane in
                                Text(pickerLabel(plane)).tag(Optional(plane.id))
                            }
                        }
                    }
                    if !fleet.clubPlanes.isEmpty {
                        Section("Club Fleet") {
                            ForEach(fleet.clubPlanes) { plane in
                                Text(pickerLabel(plane)).tag(Optional(plane.id))
                            }
                        }
                    }
                }
                if let plane = selectedAircraft {
                    LabeledContent("Tracking by") {
                        if let hex = plane.resolvedHex {
                            Text("\(NNumber.normalize(plane.tailNumber)) · \(hex.uppercased())")
                                .foregroundStyle(.secondary)
                                .font(.callout.monospaced())
                        } else {
                            // Non-US registrations (C-ABCD, G-…, D-…) are
                            // found live by registration — still just the
                            // tail number, no setup needed.
                            Text("\(NNumber.normalize(plane.tailNumber)) · live lookup")
                                .foregroundStyle(.secondary)
                                .font(.callout)
                        }
                    }
                }
                Button {
                    // The first full personal profile is free; more need
                    // Pro. Club planes never count against that.
                    if !pro.isPro && !fleet.myAircraft.isEmpty {
                        showingPaywall = true
                    } else {
                        addingAircraft = true
                    }
                } label: {
                    Label("Add another aircraft", systemImage: "plus")
                        .font(.callout)
                }
                Button {
                    addingClubPlanes = true
                } label: {
                    Label("Add club planes", systemImage: "person.3")
                        .font(.callout)
                }
            }
        }
    }

    private var crewSection: some View {
        Section {
            HStack {
                TextField("Callsign (e.g. DAL123)", text: $callsign)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                if !pro.isPro {
                    Text("PRO")
                        .font(.caption2.weight(.heavy))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Theme.proGold.opacity(0.2), in: Capsule())
                        .foregroundStyle(Theme.proGold)
                }
            }
        } header: {
            Text("Airline flight")
        } footer: {
            Text("Type the flight number as you know it — AA776, DL123, WN2011 — or the ICAO callsign (AAL776); both work. The aircraft type and the flown trail so far fill in automatically once it's found.")
        }
    }

    private var routeSection: some View {
        Section {
            airportRow(label: "From", airport: departure) { pickingDeparture = true }

            if mode == .personal {
                ForEach(viaAirports, id: \.ident) { stop in
                    HStack {
                        Text("Via")
                            .foregroundStyle(.primary)
                        Spacer()
                        VStack(alignment: .trailing) {
                            Text(stop.ident).bold()
                            Text(stop.name)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Button {
                            viaAirports.removeAll { $0.ident == stop.ident }
                        } label: {
                            Image(systemName: "minus.circle.fill")
                                .foregroundStyle(.red)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            airportRow(label: "To", airport: destination) { pickingDestination = true }

            if mode == .personal, departure != nil, destination != nil {
                Button {
                    pickingVia = true
                } label: {
                    Label("Add a stop along the way", systemImage: "plus.circle")
                        .font(.callout)
                }
            }

            if departure != nil || destination != nil {
                Button {
                    let previousDeparture = departure
                    departure = destination
                    destination = previousDeparture
                    viaAirports.reverse()
                } label: {
                    Label("Swap", systemImage: "arrow.up.arrow.down")
                        .font(.callout)
                }
            }
        } header: {
            Text("Route")
        } footer: {
            Text("Optional — leave blank to just follow the aircraft. Add stops for multi-leg days (KSQL → KPAO → KSLC); the planned line, distance, and time follow the whole path. TailTrack fills in the departure and arrival airports automatically from where you take off and land.")
        }
    }

    private func airportRow(label: String, airport: Airport?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                    .foregroundStyle(.primary)
                Spacer()
                if let airport {
                    VStack(alignment: .trailing) {
                        Text(airport.ident).bold()
                        Text(airport.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                } else {
                    Text("Choose")
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private struct PlanSummary {
        let distanceNM: Double
        let courseDeg: Double
        let eteSeconds: Double?
    }

    private var planSummary: PlanSummary? {
        guard let departure, let destination else { return nil }
        let stops = [departure] + (mode == .personal ? viaAirports : []) + [destination]
        var dist = 0.0
        for i in 1..<stops.count {
            dist += GreatCircle.distanceNM(from: stops[i - 1].coordinate,
                                           to: stops[i].coordinate)
        }
        let course = GreatCircle.initialBearing(from: departure.coordinate,
                                                to: stops[1].coordinate)
        var ete: Double?
        // Cruise-speed planning only applies to your own aircraft — a crew
        // flight's ETE comes from live groundspeed once it's airborne.
        if mode == .personal, let cruise = selectedAircraft?.cruiseSpeedKt, cruise > 10 {
            ete = dist / cruise * 3600
        }
        return PlanSummary(distanceNM: dist, courseDeg: course, eteSeconds: ete)
    }

    private func planSection(_ plan: PlanSummary) -> some View {
        Section("Plan") {
            if mode == .personal, !viaAirports.isEmpty {
                LabeledContent("Route",
                               value: ([departure?.ident] + viaAirports.map { $0.ident }
                                       + [destination?.ident])
                                   .compactMap { $0 }.joined(separator: " → "))
            }
            LabeledContent("Distance", value: Format.nm(plan.distanceNM))
            LabeledContent("Initial course", value: Format.degrees(plan.courseDeg) + " true")
            if let ete = plan.eteSeconds {
                LabeledContent("Time enroute", value: Format.duration(ete))
                LabeledContent("Arrive (if wheels up now)",
                               value: Format.localTime(Date().addingTimeInterval(ete)))
            }
        }
    }

    private var canStart: Bool {
        switch mode {
        case .personal: return selectedAircraft != nil
        case .crew: return !callsign.trimmingCharacters(in: .whitespaces).isEmpty
        }
    }

    private var startSection: some View {
        Section {
            Button {
                switch mode {
                case .personal:
                    guard let plane = selectedAircraft else { return }
                    tracker.start(aircraft: plane, departure: departure,
                                  destination: destination, via: viaAirports)
                case .crew:
                    guard pro.isPro else {
                        showingPaywall = true
                        return
                    }
                    tracker.startCrewFlight(callsign: callsign,
                                            departure: departure,
                                            destination: destination)
                }
            } label: {
                Label("Start Tracking", systemImage: "dot.radiowaves.left.and.right")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .listRowInsets(EdgeInsets())
            .disabled(!canStart)
        } footer: {
            Text("Uses free community ADS-B networks (adsb.lol, adsb.fi, OpenSky). Coverage over remote terrain can be spotty — gaps fill in as the aircraft returns to coverage.")
        }
    }
}
