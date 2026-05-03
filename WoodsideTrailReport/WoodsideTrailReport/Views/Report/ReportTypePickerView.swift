import CoreLocation
import SwiftUI

struct ReportTypePickerView: View {
    let coordinate: CLLocationCoordinate2D
    let geocodeResult: ReverseGeocodeResult?
    let onDismiss: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showCaltransAlert = false
    @State private var showEmergencyAlert = false
    @State private var showBoundaryAlert = false
    @State private var selectedType: ReportType?
    @State private var showForm = false

    private var isOutsideBoundary: Bool {
        !BoundaryChecker.shared.contains(coordinate)
    }

    var body: some View {
        NavigationStack {
            List {
                if isOutsideBoundary {
                    Section {
                        Label(
                            "This location appears to be outside Woodside town limits. You may still submit, but the report may not be processed.",
                            systemImage: "exclamationmark.triangle.fill"
                        )
                        .font(.footnote)
                        .foregroundStyle(.orange)
                    }
                }

                Section("Select Report Type") {
                    ForEach(ReportType.allCases) { type in
                        Button {
                            handleSelection(type)
                        } label: {
                            HStack(spacing: 14) {
                                Image(systemName: type.icon)
                                    .font(.title3)
                                    .foregroundStyle(type == .vehicleCollision ? .red : .green)
                                    .frame(width: 28)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(type.displayName)
                                        .foregroundStyle(
                                            type == .vehicleCollision ? .red : .primary
                                        )
                                        .fontWeight(type == .vehicleCollision ? .semibold : .regular)
                                    if let note = type.horseTrailNote {
                                        Text(note)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            .navigationTitle("Report Type")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        onDismiss()
                        dismiss()
                    }
                }
            }
            .navigationDestination(isPresented: $showForm) {
                if let type = selectedType {
                    ReportFormView(
                        coordinate: coordinate,
                        geocodeResult: geocodeResult,
                        reportType: type,
                        onDismiss: {
                            onDismiss()
                            dismiss()
                        }
                    )
                }
            }
        }
        .alert("State Route — Contact Caltrans", isPresented: $showCaltransAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(StateRouteDetector.caltransAlertMessage)
        }
        .alert("Please Call 911", isPresented: $showEmergencyAlert) {
            Button("Call 911") {
                UIApplication.shared.open(URL(string: "tel:911")!)
            }
            Link(
                "Non-Emergency: \(Config.sheriffNonEmergencyFormatted)",
                destination: URL(string: "tel:\(Config.sheriffNonEmergencyPhone)")!
            )
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(
                "Please call 911 for vehicle collisions and emergencies.\n\n" +
                "For non-emergencies, contact the San Mateo County Sheriff at " +
                "\(Config.sheriffNonEmergencyFormatted). When prompted, press 1 to " +
                "speak with a dispatcher."
            )
        }
    }

    private func handleSelection(_ type: ReportType) {
        if type.isEmergencyRoute {
            showEmergencyAlert = true
            return
        }
        if type.isStateRouteBlocked && (geocodeResult?.isStateRoute == true) {
            showCaltransAlert = true
            return
        }
        selectedType = type
        showForm = true
    }
}
