import SwiftUI
import PhotosUI
import UniformTypeIdentifiers

/// Pro feature: photograph a paper logbook page, let on-device text
/// recognition pull out candidate entries, review, and import.
struct LogbookScanView: View {
    @Environment(LogbookStore.self) private var logbook
    @Environment(AirportStore.self) private var airports
    @Environment(FleetStore.self) private var fleet
    @Environment(\.dismiss) private var dismiss

    struct ScannedEntry: Identifiable {
        let id = UUID()
        var include = true
        var date: Date
        var tailNumber: String
        var fromIdent: String
        var toIdent: String
        var hours: Double
    }

    @State private var photoSelection: PhotosPickerItem?
    @State private var importingFile = false
    @State private var pageImage: UIImage?
    @State private var isScanning = false
    @State private var entries: [ScannedEntry] = []
    @State private var scanned = false
    @State private var errorMessage: String?

    private var includedCount: Int { entries.filter(\.include).count }

    var body: some View {
        Form {
            photoSection
            if isScanning {
                Section {
                    HStack {
                        ProgressView()
                        Text("Reading the page…")
                            .foregroundStyle(.secondary)
                    }
                }
            }
            if let errorMessage {
                Section { Text(errorMessage).foregroundStyle(.red).font(.callout) }
            }
            if scanned && !isScanning {
                resultsSection
            }
        }
        .navigationTitle("Scan Logbook Page")
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Import \(includedCount)") {
                    importEntries()
                    dismiss()
                }
                .disabled(includedCount == 0)
            }
        }
        .onChange(of: photoSelection) { _, newValue in
            guard let newValue else { return }
            Task { await loadAndScan(newValue) }
        }
    }

    private var photoSection: some View {
        Section {
            if let pageImage {
                Image(uiImage: pageImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxHeight: 180)
                    .frame(maxWidth: .infinity)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .listRowBackground(Color.clear)
            }
            PhotosPicker(selection: $photoSelection, matching: .images) {
                Label(pageImage == nil ? "Choose a photo of a logbook page" : "Choose a different page",
                      systemImage: "doc.viewfinder")
            }
            Button {
                importingFile = true
            } label: {
                Label("Choose from Files or Google Drive", systemImage: "folder")
            }
            .fileImporter(isPresented: $importingFile, allowedContentTypes: [.image]) { result in
                guard case .success(let url) = result else { return }
                Task { await loadAndScan(fileURL: url) }
            }
        } footer: {
            Text("Photo in Google Photos? Open it there, tap Share → Save to Files (or save it to your iPhone), then choose it here. Take a straight-on, well-lit photo of the page first. Recognition runs entirely on your iPhone. Review every entry before importing — OCR on handwriting is helpful, not perfect. After importing, TailTrack looks up each flight's real ADS-B track by itself.")
        }
    }

    private var resultsSection: some View {
        Section(entries.isEmpty ? "No entries recognized" : "Recognized entries — check and fix") {
            if entries.isEmpty {
                Text("Couldn't find rows that look like logbook entries. Try a clearer photo, or add flights manually with Add Past Flight.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            ForEach($entries) { $entry in
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $entry.include) {
                        DatePicker("", selection: $entry.date, displayedComponents: .date)
                            .labelsHidden()
                    }
                    HStack(spacing: 8) {
                        TextField("Tail", text: $entry.tailNumber)
                            .textInputAutocapitalization(.characters)
                        TextField("From", text: $entry.fromIdent)
                            .textInputAutocapitalization(.characters)
                        TextField("To", text: $entry.toIdent)
                            .textInputAutocapitalization(.characters)
                        TextField("Hrs", value: $entry.hours, format: .number)
                            .keyboardType(.decimalPad)
                            .frame(width: 48)
                    }
                    .font(.callout)
                    .autocorrectionDisabled()
                }
                .padding(.vertical, 2)
            }
        }
    }

    // MARK: - Scan pipeline

    private func loadAndScan(_ item: PhotosPickerItem) async {
        errorMessage = nil
        isScanning = true
        defer { isScanning = false }
        guard let data = try? await item.loadTransferable(type: Data.self) else {
            errorMessage = "Couldn't load that photo."
            return
        }
        await scan(data)
    }

    private func loadAndScan(fileURL url: URL) async {
        errorMessage = nil
        isScanning = true
        defer { isScanning = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            errorMessage = "Couldn't open that file."
            return
        }
        await scan(data)
    }

    private func scan(_ data: Data) async {
        guard let image = UIImage(data: data) else {
            errorMessage = "That file isn't a photo TailTrack can read."
            return
        }
        pageImage = image
        do {
            let rows = try await LogbookScanner.recognizeRows(in: image)
            entries = parse(rows: rows)
            scanned = true
        } catch {
            errorMessage = "Text recognition failed: \(error.localizedDescription)"
        }
    }

    /// Heuristic row parser: a row becomes a candidate entry when it has a
    /// date plus at least one more logbook-shaped field (tail number,
    /// airport idents that exist in the database, or a decimal hours value).
    private func parse(rows: [String]) -> [ScannedEntry] {
        // Year optional: many logbooks write "9/2" and put the year once at
        // the top of the column ("2025", then "2026" when it changes).
        // Slash or dash only, so an hours value like "1.3" never reads as a date.
        let dateRegex = try! NSRegularExpression(pattern: #"\b(\d{1,2})[/\-](\d{1,2})(?:[/\-](\d{2,4}))?\b"#)
        let yearRegex = try! NSRegularExpression(pattern: #"\b(20\d{2})\b"#)
        var pageYear: Int?
        let hoursRegex = try! NSRegularExpression(pattern: #"\b(\d{1,2}\.\d)\b"#)

        var results: [ScannedEntry] = []
        for row in rows {
            let line = row.uppercased()
            let range = NSRange(line.startIndex..., in: line)

            if let yearMatch = yearRegex.firstMatch(in: line, range: range),
               let r = Range(yearMatch.range(at: 1), in: line),
               dateRegex.firstMatch(in: line, range: range) == nil {
                pageYear = Int(line[r])
                continue
            }
            guard let dateMatch = dateRegex.firstMatch(in: line, range: range),
                  let date = date(from: dateMatch, in: line, fallbackYear: pageYear) else { continue }

            let tokens = line.split(whereSeparator: { !$0.isLetter && !$0.isNumber })
                .map(String.init)

            let tail = tokens.first { NNumber.isValid($0) && $0.count >= 2 } ?? ""

            var idents: [String] = []
            for token in tokens where (3...4).contains(token.count) && token != tail {
                if airports.lookup(token) != nil && !idents.contains(token) {
                    idents.append(token)
                }
                if idents.count == 2 { break }
            }

            var hours = 0.0
            let hourMatches = hoursRegex.matches(in: line, range: range)
            if let last = hourMatches.last, let r = Range(last.range(at: 1), in: line) {
                hours = Double(line[r]) ?? 0
            }

            let signals = (tail.isEmpty ? 0 : 1) + (idents.isEmpty ? 0 : 1) + (hours > 0 ? 1 : 0)
            guard signals >= 1 else { continue }

            results.append(ScannedEntry(
                date: date,
                tailNumber: tail,
                fromIdent: idents.first ?? "",
                toIdent: idents.count > 1 ? idents[1] : "",
                hours: hours
            ))
        }
        return results
    }

    private func date(from match: NSTextCheckingResult, in line: String, fallbackYear: Int?) -> Date? {
        func component(_ index: Int) -> Int? {
            Range(match.range(at: index), in: line).flatMap { Int(line[$0]) }
        }
        guard let month = component(1), let day = component(2),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        let calendar = Calendar.current
        if var year = component(3) {
            if year < 100 { year += 2000 }
            guard (1990...2100).contains(year) else { return nil }
            return calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
        }
        // No year on the row: the page's year, else the most recent such
        // date that isn't in the future.
        let thisYear = calendar.component(.year, from: Date())
        let year = fallbackYear ?? thisYear
        guard let dated = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) else { return nil }
        if fallbackYear == nil, dated > Date() {
            return calendar.date(from: DateComponents(year: year - 1, month: month, day: day, hour: 12))
        }
        return dated
    }

    private func importEntries() {
        var imported: [UUID] = []
        for entry in entries where entry.include {
            let flight = Flight(
                tailNumber: NNumber.normalize(entry.tailNumber),
                typeCode: "",
                departure: airports.lookup(entry.fromIdent),
                destination: airports.lookup(entry.toIdent),
                startedTracking: entry.date,
                takeoffTime: entry.hours > 0 ? entry.date : nil,
                landingTime: entry.hours > 0 ? entry.date.addingTimeInterval(entry.hours * 3600) : nil,
                notes: "Imported from logbook scan."
            )
            logbook.add(flight)
            imported.append(flight.id)
        }
        PastFlightPathFinder.shared.findPaths(for: imported, logbook: logbook,
                                              fleet: fleet, airports: airports)
    }
}
