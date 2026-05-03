import SwiftUI

@Observable
final class AdminDashboardViewModel {
    var reports: [Report] = []
    var isLoading = false
    var errorMessage: String?
    var statusFilter: StatusStage? = nil
    var typeFilter: ReportType? = nil
    var sortNewestFirst = true

    var filtered: [Report] {
        var result = reports
        if let s = statusFilter {
            result = result.filter { $0.statusStage == s }
        }
        if let t = typeFilter {
            result = result.filter { $0.reportType == t }
        }
        return sortNewestFirst ? result : result.reversed()
    }

    func load() async {
        isLoading = true
        errorMessage = nil
        do {
            reports = try await SupabaseService.shared.fetchAllReports()
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }

    func delete(_ report: Report) async {
        do {
            try await SupabaseService.shared.deleteReport(report.id)
            reports.removeAll { $0.id == report.id }
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

struct AdminDashboardView: View {
    @State private var vm = AdminDashboardViewModel()
    @State private var showLogoutConfirm = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let err = vm.errorMessage {
                Section {
                    Label(err, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                        .font(.footnote)
                }
            }

            if vm.isLoading && vm.reports.isEmpty {
                ProgressView("Loading reports…")
                    .frame(maxWidth: .infinity)
            } else if vm.filtered.isEmpty {
                ContentUnavailableView(
                    "No Reports",
                    systemImage: "tray",
                    description: Text("No reports match the current filter.")
                )
            } else {
                ForEach(vm.filtered) { report in
                    NavigationLink {
                        AdminReportDetailView(report: report) {
                            Task { await vm.load() }
                        }
                    } label: {
                        AdminReportRowView(report: report)
                    }
                }
                .onDelete { indexSet in
                    for idx in indexSet {
                        let report = vm.filtered[idx]
                        Task { await vm.delete(report) }
                    }
                }
            }
        }
        .navigationTitle("Admin Dashboard")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Menu("Filter by Status") {
                        Button("All") { vm.statusFilter = nil }
                        ForEach(StatusStage.allCases) { stage in
                            Button(stage.label) { vm.statusFilter = stage }
                        }
                    }
                    Menu("Filter by Type") {
                        Button("All") { vm.typeFilter = nil }
                        ForEach(ReportType.allCases) { type in
                            Button(type.displayName) { vm.typeFilter = type }
                        }
                    }
                    Divider()
                    Button(vm.sortNewestFirst ? "Sort: Oldest First" : "Sort: Newest First") {
                        vm.sortNewestFirst.toggle()
                    }
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle")
                }
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Sign Out") { showLogoutConfirm = true }
                    .foregroundStyle(.red)
            }
        }
        .refreshable { await vm.load() }
        .task { await vm.load() }
        .confirmationDialog(
            "Sign out of admin?",
            isPresented: $showLogoutConfirm,
            titleVisibility: .visible
        ) {
            Button("Sign Out", role: .destructive) {
                Task {
                    try? await SupabaseService.shared.adminSignOut()
                    dismiss()
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}

struct AdminReportRowView: View {
    let report: Report

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack {
                if let type = report.reportType {
                    Label(type.displayName, systemImage: type.icon)
                        .font(.subheadline.bold())
                        .lineLimit(1)
                }
                Spacer()
                StatusBadgeView(stage: report.statusStage)
            }
            if let desc = report.description {
                Text(desc)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 4) {
                Image(systemName: "mappin.and.ellipse")
                    .foregroundStyle(.tertiary)
                Text(String(format: "%.4f, %.4f",
                            report.locationLat, report.locationLng))
                    .font(.caption2.monospaced())
                    .foregroundStyle(.tertiary)
                Spacer()
                Text(report.createdAt, style: .date)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 2)
    }
}
