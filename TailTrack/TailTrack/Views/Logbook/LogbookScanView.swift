import SwiftUI
import PhotosUI

/// Pro feature: photograph a paper logbook page, let on-device text
/// recognition pull out candidate entries, review, and import.
struct LogbookScanView: View {
    @Environment(LogbookStore.self) private var logbook
    @Environment(AirportStore.self) private var airports
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
        } footer: {
            Text("Take a straight-on, well-lit photo of the page first. Recognition runs entirely on your iPhone. Review every entry before importing — OCR on handwriting is helpful, not perfect.")
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
            .onDelete { entries.remove(atOffsets: $0) }
        }
    }

    // MARK: - Scan pipeline

    private func loadAndScan(_ item: PhotosPickerItem) async {
        errorMessage = nil
        isScanning = true
        defer { isScanning = false }
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            errorMessage = "Couldn't load that photo."
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
        let dateRegex = try! NSRegularExpression(pattern: #"\b(\d{1,2})[/\-.](\d{1,2})[/\-.](\d{2,4})\b"#)
        let hoursRegex = try! NSRegularExpression(pattern: #"\b(\d{1,2}\.\d)\b"#)

        var results: [ScannedEntry] = []
        for row in rows {
            let line = row.uppercased()
            let range = NSRange(line.startIndex..., in: line)

            guard let dateMatch = dateRegex.firstMatch(in: line, range: range),
                  let date = date(from: dateMatch, in: line) else { continue }

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

    private func date(from match: NSTextCheckingResult, in line: String) -> Date? {
        func component(_ index: Int) -> Int? {
            Range(match.range(at: index), in: line).flatMap { Int(line[$0]) }
        }
        guard let month = component(1), let day = component(2), var year = component(3),
              (1...12).contains(month), (1...31).contains(day) else { return nil }
        if year < 100 { year += 2000 }
        guard (1990...2100).contains(year) else { return nil }
        return Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))
    }

    private func importEntries() {
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
        }
    }
}
