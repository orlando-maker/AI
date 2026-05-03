import SwiftUI

@main
struct WoodsideTrailReportWatchApp: App {
    init() {
        _ = DeviceID.shared
    }

    var body: some Scene {
        WindowGroup {
            WatchTabView()
        }
    }
}

struct WatchTabView: View {
    var body: some View {
        TabView {
            WatchReportsView()
                .tabItem { Label("Reports", systemImage: "list.clipboard") }
            WatchQuickReportView()
                .tabItem { Label("Report", systemImage: "plus.circle.fill") }
        }
    }
}
