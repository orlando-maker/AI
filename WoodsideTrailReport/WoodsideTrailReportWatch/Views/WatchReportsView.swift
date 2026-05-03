import SwiftUI

struct WatchReportsView: View {
    @State private var reports: [Report] = []
    @State private var isLoading = false

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView()
                } else if reports.isEmpty {
                    Text("No reports yet.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding()
                } else {
                    List(reports) { report in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(report.reportType?.displayName ?? report.type)
                                .font(.headline)
                                .lineLimit(2)
                            Text(report.statusStage.label)
                                .font(.caption2)
                                .foregroundStyle(report.statusStage.color)
                            Text(report.createdAt, style: .date)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            .navigationTitle("My Reports")
        }
        .task { await load() }
    }

    private func load() async {
        isLoading = true
        reports = (try? await SupabaseService.shared.fetchMyReports(deviceID: DeviceID.shared.id)) ?? []
        isLoading = false
    }
}
