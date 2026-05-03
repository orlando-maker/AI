import SwiftUI

@Observable
final class PastReportsViewModel {
    var reports: [Report] = []
    var isLoading = false
    var errorMessage: String?

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            reports = try await SupabaseService.shared.fetchMyReports(deviceID: DeviceID.shared.id)
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

struct PastReportsView: View {
    @State private var vm = PastReportsViewModel()

    var body: some View {
        Group {
            if vm.isLoading && vm.reports.isEmpty {
                ProgressView("Loading your reports…")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if vm.reports.isEmpty && !vm.isLoading {
                ContentUnavailableView(
                    "No Reports Yet",
                    systemImage: "list.bullet.clipboard",
                    description: Text("Reports you submit will appear here.")
                )
            } else {
                List(vm.reports) { report in
                    NavigationLink {
                        ReportDetailView(report: report)
                    } label: {
                        ReportRowView(report: report)
                    }
                }
                .refreshable { await vm.load() }
            }
        }
        .navigationTitle("My Reports")
        .task { await vm.load() }
        .overlay(alignment: .bottom) {
            if let err = vm.errorMessage {
                Text(err)
                    .font(.footnote)
                    .foregroundStyle(.white)
                    .padding(10)
                    .background(.red.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding()
            }
        }
    }
}

// MARK: - Row

struct ReportRowView: View {
    let report: Report

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                if let type = report.reportType {
                    Label(type.displayName, systemImage: type.icon)
                        .font(.subheadline.bold())
                } else {
                    Text(report.type.replacingOccurrences(of: "_", with: " ").capitalized)
                        .font(.subheadline.bold())
                }
                Spacer()
                StatusBadgeView(stage: report.statusStage)
            }
            if let desc = report.description, !desc.isEmpty {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            Text(report.createdAt, style: .date)
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Detail

struct ReportDetailView: View {
    let report: Report
    @State private var timeline: [StatusHistoryEntry] = []
    @State private var isLoadingTimeline = false

    var body: some View {
        List {
            Section("Report Info") {
                if let type = report.reportType {
                    LabeledContent("Type") {
                        Label(type.displayName, systemImage: type.icon)
                            .foregroundStyle(.green)
                    }
                }
                LabeledContent("Submitted", value: report.createdAt, format: .dateTime)
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
            }

            if let desc = report.description, !desc.isEmpty {
                Section("Description") {
                    Text(desc)
                        .font(.body)
                }
            }

            // Photos
            if !report.photoUrls.isEmpty {
                Section("Photos") {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(report.photoUrls, id: \.self) { urlString in
                                AsyncImage(url: URL(string: urlString)) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 90)
                                        .clipShape(RoundedRectangle(cornerRadius: 8))
                                } placeholder: {
                                    RoundedRectangle(cornerRadius: 8)
                                        .fill(Color(.systemGray5))
                                        .frame(width: 120, height: 90)
                                        .overlay { ProgressView() }
                                }
                            }
                        }
                    }
                }
            }

            // Status Timeline
            Section("Status") {
                if isLoadingTimeline {
                    HStack {
                        ProgressView()
                        Text("Loading status…")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    ReportStatusTimelineView(
                        entries: timeline,
                        currentStage: report.statusStage
                    )
                }
            }
        }
        .navigationTitle("Report Details")
        .navigationBarTitleDisplayMode(.inline)
        .task {
            isLoadingTimeline = true
            timeline = (try? await SupabaseService.shared.fetchTimeline(reportID: report.id)) ?? []
            isLoadingTimeline = false
        }
    }
}
