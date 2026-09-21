import SwiftUI

/// The gloriously unnecessary feature: a swipeable year-in-review story
/// with a shareable finale. No practical aviation purpose whatsoever.
struct YearWrappedView: View {
    let year: Int
    let flights: [Flight]

    @Environment(\.dismiss) private var dismiss
    @State private var shareURL: URL?

    // MARK: - Year stats

    private var totalHours: Double {
        flights.compactMap(\.flightTime).reduce(0, +) / 3600
    }

    private var airportCount: Int {
        var idents = Set<String>()
        for flight in flights {
            if let dep = flight.departure?.ident { idents.insert(dep) }
            if let dest = flight.destination?.ident { idents.insert(dest) }
        }
        return idents.count
    }

    private var topAircraft: String? {
        mode(flights.map(\.tailNumber))
    }

    private var favoriteAirport: String? {
        mode(flights.flatMap { [$0.departure?.ident, $0.destination?.ident].compactMap { $0 } })
    }

    private var longestFlightNM: Double {
        flights.map(\.distanceFlownNM).max() ?? 0
    }

    private var totalMaxAltFeet: Double {
        flights.compactMap(\.maxAltitudeFt).reduce(0, +)
    }

    private var earliestDeparture: String? {
        let calendar = Calendar.current
        let earliest = flights.compactMap(\.takeoffTime).min { a, b in
            let ca = calendar.dateComponents([.hour, .minute], from: a)
            let cb = calendar.dateComponents([.hour, .minute], from: b)
            return (ca.hour ?? 0, ca.minute ?? 0) < (cb.hour ?? 0, cb.minute ?? 0)
        }
        return earliest.map(Format.localTime)
    }

    private var topMonth: String? {
        let months = flights.map { Calendar.current.component(.month, from: $0.startedTracking) }
        guard let month = mode(months) else { return nil }
        return DateFormatter().monthSymbols[month - 1]
    }

    private func mode<T: Hashable>(_ values: [T]) -> T? {
        var counts: [T: Int] = [:]
        for value in values { counts[value, default: 0] += 1 }
        return counts.max { $0.value < $1.value }?.key
    }

    // MARK: - Story

    var body: some View {
        ZStack {
            Theme.proSky.ignoresSafeArea()
            TabView {
                slide("✈️", "\(year) in the air",
                      "\(flights.count) flights. Let's relive them.")
                slide("⏱️", String(format: "%.1f hours", totalHours),
                      "aloft this year")
                slide("🗺️", "\(airportCount) airports",
                      favoriteAirport.map { "and \($0) was home base — your most visited" } ?? "visited")
                if let tail = topAircraft {
                    slide("🛩️", tail, "the plane you flew the most")
                }
                if longestFlightNM > 1 {
                    slide("📏", Format.nm(longestFlightNM), "your longest flight")
                }
                if totalMaxAltFeet > 0 {
                    slide("⛰️", "\(Int(totalMaxAltFeet).formatted()) ft",
                          "of flight ceilings stacked end to end")
                }
                if let earliest = earliestDeparture {
                    slide("🌅", earliest, "your earliest wheels-up")
                }
                if let month = topMonth {
                    slide("📆", month, "your most-flown month")
                }
                finaleSlide
            }
            .tabViewStyle(.page)

            VStack {
                HStack {
                    Spacer()
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.body.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(10)
                            .background(.white.opacity(0.15), in: Circle())
                    }
                }
                .padding()
                Spacer()
            }
        }
        .onAppear(perform: renderShareCard)
    }

    private func slide(_ emoji: String, _ headline: String, _ caption: String) -> some View {
        VStack(spacing: 14) {
            Text(emoji)
                .font(.system(size: 56))
            Text(headline)
                .font(.system(size: 42, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .minimumScaleFactor(0.5)
            Text(caption)
                .font(.headline)
                .foregroundStyle(Theme.proGold)
                .multilineTextAlignment(.center)
        }
        .padding(36)
    }

    private var finaleSlide: some View {
        VStack(spacing: 20) {
            Text("🏁")
                .font(.system(size: 56))
            Text("That was \(year).")
                .font(.system(size: 36, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
            Text("Fly safe out there.")
                .font(.headline)
                .foregroundStyle(Theme.proGold)
            if let shareURL {
                ShareLink(item: shareURL) {
                    Label("Share your year", systemImage: "square.and.arrow.up")
                        .font(.headline)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 12)
                        .background(Theme.proGold, in: Capsule())
                        .foregroundStyle(.black)
                }
            }
        }
        .padding(36)
    }

    private func renderShareCard() {
        let card = VStack(alignment: .leading, spacing: 14) {
            Text("\(year) IN THE AIR")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .tracking(2)
                .foregroundStyle(Theme.proGold)
            HStack(spacing: 12) {
                GlassTile(label: "Hours", value: String(format: "%.1f", totalHours))
                GlassTile(label: "Flights", value: "\(flights.count)")
                GlassTile(label: "Airports", value: "\(airportCount)")
            }
            HStack(spacing: 12) {
                GlassTile(label: "Top aircraft", value: topAircraft ?? "—")
                GlassTile(label: "Longest", value: Format.nm(longestFlightNM))
                GlassTile(label: "Home base", value: favoriteAirport ?? "—")
            }
            HStack(spacing: 6) {
                Image(systemName: "airplane")
                Text("TailTrack Wrapped")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white.opacity(0.6))
        }
        .padding(28)
        .frame(width: 430)
        .background(Theme.proSky)

        let renderer = ImageRenderer(content: card)
        renderer.scale = 3
        if let image = renderer.uiImage, let data = image.pngData() {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("TailTrack-Wrapped-\(year).png")
            if (try? data.write(to: url, options: .atomic)) != nil {
                shareURL = url
            }
        }
    }
}
