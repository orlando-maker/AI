import SwiftUI

/// Everything a pilot listens for before calling the tower: the decoded
/// ATIS (where the field publishes a digital one), the frequency to hear it
/// on, the METAR and TAF, and the field's radio frequencies.
struct AirportWeatherSheet: View {
    let ident: String
    var initialMetar: AirportWeather?
    var initialATIS: [ATISReport]?

    @Environment(AirportStore.self) private var airports
    @Environment(\.dismiss) private var dismiss

    @State private var metar: AirportWeather?
    @State private var atis: [ATISReport]?
    @State private var frequencies: [AirportFrequency] = []
    @State private var showingRaw: Set<String> = []

    private var airportName: String? { airports.lookup(ident)?.name }
    private var weatherFrequency: AirportFrequency? {
        frequencies.first(where: \.isWeatherBroadcast)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let airportName {
                        Text(airportName)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    if let atis {
                        if atis.isEmpty {
                            noDigitalATISCard
                        } else {
                            ForEach(atis) { report in
                                atisCard(report)
                            }
                        }
                    } else {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Getting the ATIS…")
                                .foregroundStyle(.secondary)
                        }
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .cardSurface()
                    }

                    if let metar {
                        rawCard(title: "METAR", text: metar.raw)
                        if let taf = metar.taf {
                            rawCard(title: "TAF", text: taf)
                        }
                    }

                    if !frequencies.isEmpty {
                        frequenciesCard
                    }

                    if let liveATC = RadioPlayer.liveATCURL(for: ident) {
                        Link(destination: liveATC) {
                            Label("Listen to \(ident) on LiveATC.net", systemImage: "headphones")
                                .font(.callout.weight(.semibold))
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 12)
                                .cardSurface(12)
                        }
                        .buttonStyle(.pressable)
                    }

                    Text("Advisory only. Always listen to the official ATIS and get a proper weather briefing before flight. Digital ATIS via datis.clowd.io; frequencies from OurAirports. Verify them in the Chart Supplement.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding()
                .readableContentWidth()
            }
            .background(Theme.paper)
            .navigationTitle(ident)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .refreshable { await load(refresh: true) }
            .task { await load(refresh: false) }
        }
        .presentationDetents([.medium, .large])
    }

    // MARK: - ATIS

    private func atisCard(_ report: ATISReport) -> some View {
        let decoded = report.decoded
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Text(report.letter ?? "?")
                    .font(.system(.title, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
                    .frame(width: 48, height: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 2) {
                    Text("INFORMATION \((decoded.information ?? report.letter ?? "").uppercased())")
                        .font(.caption.weight(.semibold).monospaced())
                        .tracking(0.6)
                        .foregroundStyle(Theme.accent)
                    Text(report.title + (decoded.issuedZulu.map { " · \($0)" } ?? ""))
                        .font(.headline)
                    if let issued = decoded.issuedAt {
                        issuedLine(issued)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                if let wind = decoded.wind { row("Wind", wind) }
                if let visibility = decoded.visibility { row("Visibility", visibility) }
                if !decoded.weather.isEmpty { row("Weather", decoded.weather.joined(separator: "\n")) }
                if !decoded.sky.isEmpty { row("Clouds", decoded.sky.joined(separator: "\n")) }
                if let temperature = decoded.temperature { row("Temp", temperature) }
                if let altimeter = decoded.altimeter { row("Altimeter", altimeter) }
            }

            if !decoded.landing.isEmpty || !decoded.departing.isEmpty || !decoded.approaches.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 8) {
                    if !decoded.landing.isEmpty { row("Landing", decoded.landing.joined(separator: "\n")) }
                    if !decoded.departing.isEmpty { row("Departing", decoded.departing.joined(separator: "\n")) }
                    if !decoded.approaches.isEmpty { row("Approach", decoded.approaches.joined(separator: "\n")) }
                }
            }

            if !decoded.notices.isEmpty {
                Divider()
                VStack(alignment: .leading, spacing: 6) {
                    label("Notices")
                    ForEach(decoded.notices, id: \.self) { notice in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Circle()
                                .fill(Theme.accent)
                                .frame(width: 5, height: 5)
                                .alignmentGuide(.firstTextBaseline) { $0[.bottom] - 1 }
                            Text(notice)
                                .font(.callout)
                        }
                    }
                }
            }

            if let information = decoded.information {
                Label("On first contact: “…with information \(information).”",
                      systemImage: "headphones")
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }

            DisclosureGroup(isExpanded: Binding(
                get: { showingRaw.contains(report.id) },
                set: { expanded in
                    if expanded { showingRaw.insert(report.id) } else { showingRaw.remove(report.id) }
                }
            )) {
                Text(report.text)
                    .font(.caption.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.top, 6)
            } label: {
                Text("Original broadcast")
                    .font(.subheadline.weight(.medium))
            }
            .tint(.primary)
        }
        .padding(16)
        .cardSurface()
    }

    @ViewBuilder
    private func issuedLine(_ issued: Date) -> some View {
        // D-ATIS is reissued at least hourly; an older one has probably
        // been replaced on frequency.
        if Date().timeIntervalSince(issued) > 75 * 60 {
            Label("Issued \(Format.clockTime(issued)), over an hour ago. The broadcast may have changed.",
                  systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        } else {
            Text("Issued \(Format.clockTime(issued)) · \(issued, style: .relative) ago")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var noDigitalATISCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("No digital ATIS at \(ident)", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
            if let frequency = weatherFrequency {
                Text("Tune \(frequency.label) on \(frequency.formatted) for the current broadcast.")
                    .font(.callout)
                Text(frequency.formatted)
                    .font(.system(.largeTitle, design: .rounded).weight(.heavy).monospacedDigit())
                    .tracking(-0.6)
                    .foregroundStyle(Theme.accent)
                    .textSelection(.enabled)
            } else {
                Text("Only larger airports publish ATIS as text. Check the METAR below, or listen on the nearest AWOS or ASOS.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    // MARK: - METAR / TAF / frequencies

    private func rawCard(title: String, text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            label(title)
            Text(text)
                .font(.callout.monospaced())
                .textSelection(.enabled)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private var frequenciesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            label("Frequencies")
            ForEach(frequencies) { frequency in
                HStack {
                    Text(frequency.label)
                        .font(.callout)
                    Spacer()
                    Text(frequency.formatted)
                        .font(.callout.monospacedDigit().weight(.semibold))
                        .foregroundStyle(frequency.isWeatherBroadcast ? Theme.accent : .primary)
                        .textSelection(.enabled)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .cardSurface()
    }

    private func row(_ title: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            label(title)
                .frame(width: 84, alignment: .leading)
            Text(value)
                .font(.callout)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption2.weight(.semibold).monospaced())
            .tracking(0.6)
            .foregroundStyle(.secondary)
    }

    // MARK: - Loading

    private func load(refresh: Bool) async {
        if !refresh {
            metar = metar ?? initialMetar
            atis = atis ?? initialATIS
        }
        let code = ident
        let needMetar = refresh || metar == nil
        async let freshMetar = Self.fetchMetar(code, needed: needMetar)
        async let freshATIS = ATISService().reports(for: code)
        async let freshFrequencies = FrequencyDirectory.shared.frequencies(for: code)

        let newMetar = await freshMetar
        if let newMetar { metar = newMetar }
        let reports = await freshATIS
        withAnimation(Motion.standard) { atis = reports }
        frequencies = await freshFrequencies
    }

    private static func fetchMetar(_ ident: String, needed: Bool) async -> AirportWeather? {
        guard needed else { return nil }
        return await WeatherService().metars(for: [ident]).first
    }
}
