import SwiftUI

struct RootView: View {
    @Environment(AirportStore.self) private var airports

    var body: some View {
        TabView {
            FlyView()
                .tabItem { Label("Fly", systemImage: "airplane") }

            LogbookView()
                .tabItem { Label("Logbook", systemImage: "book.closed") }

            FleetView()
                .tabItem { Label("Aircraft", systemImage: "airplane.circle") }

            ProfileView()
                .tabItem { Label("Profile", systemImage: "person.crop.circle") }

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .task {
            // Fetch the full worldwide airport database (every US field down
            // to private strips) on first launch; the bundled starter list
            // keeps working if this fails offline.
            if !airports.usingFullDatabase {
                await airports.downloadFullDatabase()
            }
        }
    }
}
