import MapKit
import SwiftUI

struct AdminReportDetailView: View {
    let report: Report
    let onStatusUpdated: () -> Void

    @State private var selectedStage: StatusStage = .opened
    @State private var notes = ""
    @State private var isUpdating = false
    @State private var showDeleteConfirm = false
    @State private var errorMessage: String?
    @State private var timeline: [StatusHistoryEntry] = []
    @State private var successMessage: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            // Location map snapshot
            Section {
                Map(
                    position: .constant(.region(MKCoordinateRegion(
                        center: CLLocationCoordinate2D(
                            latitude: report.locationLat,
                            longitude: report.locationLng
                        ),
                        span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                    )))
                ) {
                    Marker("", coordinate: CLLocationCoordinate2D(
                        latitude: report.locationLat,
                        longitude: report.locationLng
                    ))
                    .tint(.red)
                }
                .frame(height: 160)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .disabled(true)
            }

            // Report info
            Section("Report") {
                if let type = report.reportType {
                    LabeledContent("Type") {
                        Label(type.displayName, systemImage: type.icon)
                    }
                }
                LabeledContent("Submitted", value: report.createdAt, format: .dateTime)
                LabeledContent("Status") {
                    StatusBadgeView(stage: report.statusStage)
                }
                if let street = report.nearestStreet {
                    LabeledContent("Near", value: street)
                }
                if let crosses = report.crossStreets {
                    LabeledContent("Cross Streets", value: crosses)
                }
                LabeledContent("Coordinates") {
                    Text(String(format: "%.5f, %.5f",
                                report.locationLat, report.locationLng))
                        .font(.caption.monospaced())
                }
                if let desc = report.description {
                    LabeledContent("Description", value: desc)
                }
            }

            // Contact info
            if report.phone != nil || report.email != nil {
                Section("Contact") {
                    if let phone = report.phone {
                        LabeledContent("Phone", value: phone)
                        if let type = report.phoneType {
                            LabeledContent("Type", value: type.capitalized)
                        }
                        if let ok = report.contactOk {
                            LabeledContent("Contact OK", value: ok ? "Yes" : "No")
                        }
                    }
                    if let email = report.email {
                        LabeledContent("Email", value: email)
                    }
                }
            }

            // Photos
            if !report.photoUrls.isEmpty {
                Section("Photos (\(report.photoUrls.count))") {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(report.photoUrls, id: \.self) { urlString in
                                AsyncImage(url: URL(string: urlString)) { image in
                                    image.resizable().scaledToFill()
                                        .frame(width: 130, height: 100)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray5))
                                        .frame(width: 130, height: 100)
                                        .overlay { ProgressView() }
                                }
                            }
                        }
                    }
                }
            }

            // Timeline
            Section("Status History") {
                ReportStatusTimelineView(entries: timeline, currentStage: report.statusStage)
            }

            // Update status
            Section("Update Status") {
                Picker("New Status", selection: $selectedStage) {
                    ForEach(StatusStage.adminOptions) { stage in
                        Text(stage.label).tag(stage)
                    }
                }
                TextField("Notes (optional)", text: $notes, axis: .vertical)
                    .lineLimit(3)

                if let err = errorMessage {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
                if let ok = successMessage {
                    Label(ok, systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }

                Button {
                    Task { await updateStatus() }
                } label: {
                    if isUpdating {
                        HStack {
                            ProgressView()
                            Text("Updating…")
                        }
                        .frame(maxWidth: .infinity)
                    } else {
                        Text("Save Status Update")
                            .frame(maxWidth: .infinity)
                            .fontWeight(.semibold)
                    }
                }
                .disabled(isUpdating)
                .tint(.green)
            }

            // Delete
            Section {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Label("Delete Report", systemImage: "trash.fill")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Report #\(String(report.id.uuidString.prefix(6)).uppercased())")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            timeline = (try? await SupabaseService.shared.fetchTimeline(reportID: report.id)) ?? []
        }
        .confirmationDialog(
            "Delete this report permanently?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                Task {
                    try? await SupabaseService.shared.deleteReport(report.id)
                    onStatusUpdated()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }

    private func updateStatus() async {
        isUpdating = true
        errorMessage = nil
        successMessage = nil
        do {
            try await SupabaseService.shared.addStatusEntry(
                reportID: report.id,
                stage: selectedStage,
                notes: notes.isEmpty ? nil : notes
            )
            timeline = (try? await SupabaseService.shared.fetchTimeline(reportID: report.id)) ?? []
            successMessage = "Status updated to "\(selectedStage.label)"."
            notes = ""
            onStatusUpdated()
        } catch {
            errorMessage = error.localizedDescription
        }
        isUpdating = false
    }
}
