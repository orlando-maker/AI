import SwiftUI

/// Type in a past flight — the free way to bring your paper logbook over.
struct ManualFlightEntryView: View {
    @Environment(LogbookStore.self) private var logbook
    @Environment(FleetStore.self) private var fleet
    @Environment(AirportStore.self) private var airports
    @Environment(ProStore.self) private var pro
    @Environment(\.dismiss) private var dismiss

    @State private var date = Date()
    @State private var tailNumber = ""
    @State private var departure: Airport?
    @State private var destination: Airport?
    @State private var hoursText = "1.0"
    @State private var notes = ""
    @State private var pickingDeparture = false
    @State private var pickingDestination = false
    @State private var prefilled = false
    /// Exact time is optional: most paper logbooks only have the date.
    @State private var knowsTime = false

    private var hours: Double { Double(hoursText) ?? 0 }

    var body: some View {
        Form {
            Section("Flight") {
                DatePicker("Date", selection: $date, displayedComponents: .date)
                Toggle("I know my takeoff time", isOn: $knowsTime.animation())
                if knowsTime {
                    DatePicker("Takeoff", selection: $date, displayedComponents: .hourAndMinute)
                }
                TextField("Tail number", text: $tailNumber)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                airportRow("From", airport: departure) { pickingDeparture = true }
                airportRow("To", airport: destination) { pickingDestination = true }
                HStack {
                    Text("Flight time")
                    Spacer()
                    TextField("1.0", text: $hoursText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 70)
                    Text("h")
                        .foregroundStyle(.secondary)
                }
            }
            Section("Notes") {
                TextField("Remarks…", text: $notes, axis: .vertical)
                    .lineLimit(2...5)
            }
        }
        .navigationTitle("Add Past Flight")
        .scrollContentBackground(.hidden)
        .background(Theme.paper)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Add") {
                    let flight = makeFlight()
                    logbook.add(flight)
                    if pro.isPro {
                        PastFlightPathFinder.shared.findPaths(for: [flight.id], logbook: logbook,
                                                              fleet: fleet, airports: airports)
                    }
                    dismiss()
                }
                .disabled(tailNumber.trimmingCharacters(in: .whitespaces).isEmpty || hours <= 0)
            }
        }
        .sheet(isPresented: $pickingDeparture) {
            AirportPickerView(title: "Departure") { departure = $0 }
        }
        .sheet(isPresented: $pickingDestination) {
            AirportPickerView(title: "Destination") { destination = $0 }
        }
        .onAppear {
            if !prefilled {
                prefilled = true
                tailNumber = fleet.aircraft.first.map { NNumber.normalize($0.tailNumber) } ?? ""
            }
        }
    }

    private func airportRow(_ label: String, airport: Airport?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Text(label)
                Spacer()
                Text(airport?.ident ?? "Choose")
                    .foregroundStyle(airport == nil ? .tertiary : .secondary)
            }
        }
        .foregroundStyle(.primary)
    }

    private func makeFlight() -> Flight {
        let tail = NNumber.normalize(tailNumber)
        let type = fleet.aircraft.first {
            NNumber.normalize($0.tailNumber) == tail
        }?.typeCode ?? ""
        // No time known: midday on that date, so the day can't slip.
        let start = knowsTime ? date
            : Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: date) ?? date
        return Flight(
            tailNumber: tail,
            typeCode: type,
            departure: departure,
            destination: destination,
            startedTracking: start,
            takeoffTime: start,
            landingTime: start.addingTimeInterval(hours * 3600),
            notes: notes
        )
    }
}
