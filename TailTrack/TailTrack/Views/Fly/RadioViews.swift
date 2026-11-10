import SwiftUI

// MARK: - Live screen card

/// The radio side of the live flight: the latest radio log lines, and the
/// live receiver if one is playing. Tapping opens the full log.
struct RadioLogCard: View {
    @Environment(FlightTracker.self) private var tracker
    @Environment(RadioPlayer.self) private var radio
    @State private var showingLog = false

    private var latestFirst: [RadioLogEntry] { (tracker.flight?.radioLog ?? []).reversed() }

    var body: some View {
        Button {
            showingLog = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Label("Radio", systemImage: "dot.radiowaves.left.and.right")
                        .font(.headline)
                    Spacer()
                    if let playing = radio.playing {
                        Text("LIVE · \(playing.name)")
                            .font(.caption2.weight(.heavy).monospaced())
                            .lineLimit(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.accent.opacity(0.15), in: Capsule())
                            .foregroundStyle(Theme.accent)
                    }
                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                }
                if latestFirst.isEmpty {
                    Text("Squawk codes and ATIS log themselves. Tap to log a frequency, clearance or note.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(latestFirst.prefix(3)) { entry in
                        RadioEntryRow(entry: entry, compact: true)
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .cardSurface()
        }
        .buttonStyle(.pressable)
        .foregroundStyle(.primary)
        .sheet(isPresented: $showingLog) { RadioLogSheet() }
    }
}

/// One radio log line: what was said or set, when, and at what altitude.
struct RadioEntryRow: View {
    let entry: RadioLogEntry
    var compact = false

    private var tint: Color {
        if entry.kind == .squawk, Squawk.isEmergency(entry.text.filter(\.isNumber)) { return .red }
        return entry.kind == .atis || entry.kind == .squawk ? Theme.accent : .secondary
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.kind.symbol)
                .foregroundStyle(tint)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.text)
                        .font(.callout.weight(.semibold))
                    if entry.isAutomatic {
                        Text("AUTO")
                            .font(.caption2.weight(.heavy).monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                if let detail = entry.detail, !detail.isEmpty {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(compact ? 1 : nil)
                }
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(Format.clockTime(entry.time))
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
                if !compact, let altitude = entry.altitudeFt {
                    Text(Format.feet(altitude))
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.tertiary)
                }
            }
        }
    }
}

// MARK: - Full log

struct RadioLogSheet: View {
    @Environment(FlightTracker.self) private var tracker
    @Environment(RadioPlayer.self) private var radio
    @Environment(\.dismiss) private var dismiss
    @State private var composing: RadioLogEntry.Kind?

    private static let quickKinds: [RadioLogEntry.Kind] = [.frequency, .clearance, .squawk, .atis, .altimeter, .note]

    private var latestFirst: [RadioLogEntry] { (tracker.flight?.radioLog ?? []).reversed() }
    private var routeIdents: [String] { tracker.flight?.plannedRouteAirports.map(\.ident) ?? [] }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            ForEach(Self.quickKinds) { kind in
                                Button {
                                    composing = kind
                                } label: {
                                    VStack(spacing: 6) {
                                        Image(systemName: kind.symbol)
                                            .font(.title3)
                                            .foregroundStyle(Theme.accent)
                                        Text(kind.label)
                                            .font(.caption.weight(.semibold))
                                    }
                                    .frame(width: 86, height: 66)
                                    .cardSurface(12)
                                }
                                .buttonStyle(.pressable)
                                .foregroundStyle(.primary)
                            }
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    Text("Log")
                } footer: {
                    Text("Squawk codes log themselves from ADS-B. Where the airport publishes a digital ATIS, it logs itself at departure and about 40 nm out; elsewhere, tap ATIS to note the letter you heard.")
                }

                listenSection

                Section("Timeline") {
                    if latestFirst.isEmpty {
                        Text("Nothing logged yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(latestFirst) { entry in
                        RadioEntryRow(entry: entry)
                    }
                    .onDelete { offsets in
                        let doomed = offsets.map { latestFirst[$0].id }
                        doomed.forEach { tracker.deleteRadioEntry(id: $0) }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .navigationTitle("Radio")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(item: $composing) { kind in
                RadioEntryForm(kind: kind)
            }
        }
    }

    private var listenSection: some View {
        Section {
            ForEach(radio.streams) { stream in
                let isPlaying = radio.playing?.id == stream.id
                Button {
                    radio.toggle(stream)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: isPlaying ? "stop.circle.fill" : "play.circle.fill")
                            .font(.title2)
                            .foregroundStyle(Theme.accent)
                            .contentTransition(.symbolEffect(.replace))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(stream.name)
                            Text(stream.url.host ?? stream.url.absoluteString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if isPlaying && radio.isBuffering {
                            ProgressView()
                        }
                    }
                }
                .foregroundStyle(.primary)
                .sensoryFeedback(.selection, trigger: isPlaying)
            }
            if let error = radio.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            NavigationLink {
                ReceiversView()
            } label: {
                Label(radio.streams.isEmpty ? "Add your own receiver" : "Manage receivers",
                      systemImage: "antenna.radiowaves.left.and.right")
            }
            ForEach(routeIdents, id: \.self) { ident in
                if let url = RadioPlayer.liveATCURL(for: ident) {
                    Link(destination: url) {
                        Label("\(ident) on LiveATC.net", systemImage: "arrow.up.right.square")
                    }
                }
            }
        } header: {
            Text("Listen live")
        } footer: {
            Text("LiveATC opens in its own app or website; its terms don't allow other apps to play its streams. Your own receivers play right here, even with the screen locked.")
        }
    }
}

// MARK: - Entry forms

struct RadioEntryForm: View {
    let kind: RadioLogEntry.Kind

    @Environment(FlightTracker.self) private var tracker
    @Environment(\.dismiss) private var dismiss

    private struct Suggestion: Identifiable {
        let ident: String
        let frequency: AirportFrequency
        var id: String { ident + frequency.id }
    }

    @State private var frequency = ""
    @State private var facility = ""
    @State private var squawk = ""
    @State private var altimeter = ""
    @State private var atisAirport = ""
    @State private var atisLetter = "A"
    @State private var clearanceLimit = ""
    @State private var route = ""
    @State private var altitude = ""
    @State private var departureFrequency = ""
    @State private var transponder = ""
    @State private var note = ""
    @State private var suggestions: [Suggestion] = []

    var body: some View {
        NavigationStack {
            Form { fields }
                .scrollContentBackground(.hidden)
                .background(Theme.paper)
                .navigationTitle(kind.label)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Log") { save() }
                            .disabled(entry == nil)
                    }
                }
                .task { await prepare() }
        }
        .presentationDetents([.medium, .large])
    }

    @ViewBuilder
    private var fields: some View {
        switch kind {
        case .frequency:
            Section {
                TextField("Frequency, e.g. 135.65", text: $frequency)
                    .keyboardType(.decimalPad)
                    .font(.title3.monospacedDigit())
                TextField("Who, e.g. NorCal Approach", text: $facility)
            }
            if !suggestions.isEmpty {
                Section("On your route") {
                    ForEach(suggestions) { suggestion in
                        Button {
                            frequency = suggestion.frequency.formatted
                            facility = "\(suggestion.ident) \(suggestion.frequency.label)"
                        } label: {
                            HStack {
                                Text("\(suggestion.ident) \(suggestion.frequency.label)")
                                Spacer()
                                Text(suggestion.frequency.formatted)
                                    .monospacedDigit()
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .foregroundStyle(.primary)
                    }
                }
            }
        case .squawk:
            Section {
                TextField("Code, e.g. 4521", text: $squawk)
                    .keyboardType(.numberPad)
                    .font(.title3.monospacedDigit())
            } footer: {
                if Squawk.isValid(squawk) {
                    Text(Squawk.meaning(squawk))
                } else if !squawk.isEmpty {
                    Text("Four digits, each 0 to 7.")
                        .foregroundStyle(.red)
                }
            }
        case .altimeter:
            Section {
                TextField("29.92 (or 1013 hPa)", text: $altimeter)
                    .keyboardType(.decimalPad)
                    .font(.title3.monospacedDigit())
            }
        case .atis:
            Section {
                TextField("Airport", text: $atisAirport)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                Picker("Information", selection: $atisLetter) {
                    ForEach(ATISDecoder.phonetic.keys.sorted(), id: \.self) { letter in
                        Text("\(letter) · \(ATISDecoder.phonetic[letter] ?? "")").tag(letter)
                    }
                }
                TextField("Altimeter (optional)", text: $altimeter)
                    .keyboardType(.decimalPad)
            }
        case .clearance:
            Section {
                TextField("Cleared to", text: $clearanceLimit)
                TextField("Route", text: $route)
                TextField("Altitude", text: $altitude)
                TextField("Departure frequency", text: $departureFrequency)
                    .keyboardType(.decimalPad)
                TextField("Squawk", text: $transponder)
                    .keyboardType(.numberPad)
            } footer: {
                Text("C·R·A·F·T: clearance limit, route, altitude, frequency, transponder.")
            }
        case .note:
            Section {
                TextField("What you heard or did", text: $note, axis: .vertical)
                    .lineLimit(3...8)
            }
        }
    }

    /// The finished line, or nil while the form isn't valid yet.
    private var entry: (text: String, detail: String?)? {
        switch kind {
        case .frequency:
            guard let mhz = Double(frequency), (108...137).contains(mhz) else { return nil }
            let shown = AirportFrequency(type: "", description: "", mhz: mhz).formatted
            let who = facility.trimmingCharacters(in: .whitespaces)
            return (who.isEmpty ? shown : "\(who) \(shown)", nil)
        case .squawk:
            guard Squawk.isValid(squawk) else { return nil }
            return ("Squawk \(squawk)", "Assigned · \(Squawk.meaning(squawk))")
        case .altimeter:
            guard let setting = Self.altimeterText(altimeter) else { return nil }
            return ("Altimeter \(setting)", nil)
        case .atis:
            let ident = atisAirport.trimmingCharacters(in: .whitespaces).uppercased()
            guard !ident.isEmpty, let word = ATISDecoder.phonetic[atisLetter] else { return nil }
            let detail = Self.altimeterText(altimeter).map { "Altimeter \($0)" }
            return ("\(ident) ATIS \(word)", detail)
        case .clearance:
            let limit = clearanceLimit.trimmingCharacters(in: .whitespaces)
            let parts = [
                route.isEmpty ? nil : "Route \(route)",
                altitude.isEmpty ? nil : "Altitude \(altitude)",
                departureFrequency.isEmpty ? nil : "Departure \(departureFrequency)",
                transponder.isEmpty ? nil : "Squawk \(transponder)",
            ].compactMap { $0 }
            guard !limit.isEmpty || !parts.isEmpty else { return nil }
            return (limit.isEmpty ? "Clearance" : "Cleared to \(limit)",
                    parts.isEmpty ? nil : parts.joined(separator: " · "))
        case .note:
            let text = note.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return (text, nil)
        }
    }

    /// "29.92" → "29.92 inHg"; "1013" → "1013 hPa"; nonsense → nil.
    private static func altimeterText(_ raw: String) -> String? {
        guard let value = Double(raw.trimmingCharacters(in: .whitespaces)) else { return nil }
        if (26...32).contains(value) { return String(format: "%.2f inHg", value) }
        if (900...1100).contains(value) { return String(format: "%.0f hPa", value) }
        return nil
    }

    private func save() {
        guard let entry else { return }
        tracker.logRadio(kind: kind, text: entry.text, detail: entry.detail)
        dismiss()
    }

    private func prepare() async {
        let route = tracker.flight?.plannedRouteAirports.map(\.ident) ?? []
        if kind == .atis, atisAirport.isEmpty {
            // On the way out it's the departure ATIS; once airborne, the
            // destination's.
            atisAirport = (tracker.phase == .enroute ? route.last : route.first) ?? ""
        }
        guard kind == .frequency else { return }
        var found: [Suggestion] = []
        for ident in route {
            for frequency in await FrequencyDirectory.shared.frequencies(for: ident) {
                found.append(Suggestion(ident: ident, frequency: frequency))
            }
        }
        suggestions = found
    }
}

// MARK: - Receivers

/// The pilot's own live airband receivers.
struct ReceiversView: View {
    @Environment(RadioPlayer.self) private var radio
    @State private var name = ""
    @State private var address = ""
    @State private var invalid = false

    var body: some View {
        Form {
            Section("Your receivers") {
                if radio.streams.isEmpty {
                    Text("None yet.")
                        .foregroundStyle(.secondary)
                }
                ForEach(radio.streams) { stream in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(stream.name)
                        Text(stream.url.absoluteString)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .onDelete { radio.delete(at: $0) }
            }

            Section {
                TextField("Name, e.g. KSQL Tower", text: $name)
                TextField("Stream address", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                Button("Add Receiver") {
                    invalid = !radio.add(name: name, address: address)
                    if !invalid {
                        name = ""
                        address = ""
                    }
                }
                .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                if invalid {
                    Text("That isn't a stream address. It should start with http:// or https://.")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            } header: {
                Text("Add a receiver")
            } footer: {
                Text("Build your own with RTLSDR-Airband, free and open source: a Raspberry Pi and an RTL-SDR dongle tuned to your field's tower, ground and ATIS, streaming through Icecast. Paste the Icecast address here, like http://192.168.1.20:8000/ksql. Only add streams you own or have permission to use, and follow your country's rules on listening to and sharing ATC audio.")
            }
        }
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationTitle("Receivers")
        .navigationBarTitleDisplayMode(.inline)
    }
}
