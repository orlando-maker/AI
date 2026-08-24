import SwiftUI

/// Pilot-entered landing details: landing time plus optional Hobbs/tach
/// readings — used after a signal-loss ending, or to attach engine times
/// to a normal arrival.
struct LandingDetailsSheet: View {
    let initialLandingTime: Date
    let onSave: (Date, Double?, Double?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var landingTime: Date
    @State private var hobbsText = ""
    @State private var tachText = ""

    init(initialLandingTime: Date, onSave: @escaping (Date, Double?, Double?) -> Void) {
        self.initialLandingTime = initialLandingTime
        self.onSave = onSave
        _landingTime = State(initialValue: initialLandingTime)
    }

    var body: some View {
        Form {
            Section("Landing") {
                DatePicker("Landing time", selection: $landingTime)
            }
            Section {
                HStack {
                    Text("Hobbs")
                    Spacer()
                    TextField("1234.5", text: $hobbsText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
                HStack {
                    Text("Tach")
                    Spacer()
                    TextField("1180.2", text: $tachText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 100)
                }
            } header: {
                Text("Engine times (optional)")
            } footer: {
                Text("Log the shutdown Hobbs/tach readings if you keep them — they're saved with this flight on your iPhone.")
            }
        }
        .navigationTitle("Landing Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    onSave(landingTime, Double(hobbsText), Double(tachText))
                    dismiss()
                }
            }
        }
    }
}
