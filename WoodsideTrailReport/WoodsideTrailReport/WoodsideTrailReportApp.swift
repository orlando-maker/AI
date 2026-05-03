import SwiftUI

@main
struct WoodsideTrailReportApp: App {
    @AppStorage("hasAgreedToTerms") private var hasAgreedToTerms = false

    init() {
        // Ensure device UUID is generated on very first launch.
        _ = DeviceID.shared
        // Warm up the Supabase client.
        _ = SupabaseService.shared
    }

    var body: some Scene {
        WindowGroup {
            if hasAgreedToTerms {
                ContentView()
            } else {
                TermsView()
            }
        }
    }
}

struct ContentView: View {
    var body: some View {
        SidebarView()
    }
}
