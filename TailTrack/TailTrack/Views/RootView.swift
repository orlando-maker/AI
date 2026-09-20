import SwiftUI

struct RootView: View {
    @Environment(AirportStore.self) private var airports
    @Environment(ProfileStore.self) private var profileStore
    @AppStorage(LegalDocuments.acceptedVersionKey) private var acceptedLegalVersion = 0
    @AppStorage("hasCompletedAccountSetup") private var hasCompletedAccountSetup = false
    @AppStorage(AppearanceSetting.storageKey) private var appearanceRaw = AppearanceSetting.system.rawValue

    /// First-launch gates, in order: agree to the legal terms, then create
    /// the pilot account. Both must clear before the tabs unlock. Users
    /// who already have a profile (builds before accounts existed) skip
    /// the account step.
    private enum Gate: String, Identifiable {
        case terms, account
        var id: String { rawValue }
    }

    private var currentGate: Gate? {
        if acceptedLegalVersion < LegalDocuments.version { return .terms }
        if !hasCompletedAccountSetup && profileStore.profile.name.isEmpty { return .account }
        return nil
    }

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
        .fontDesign(.rounded)
        .preferredColorScheme(AppearanceSetting(rawValue: appearanceRaw)?.colorScheme)
        .onOpenURL { GoogleAuth.handle(url: $0) }
        .fullScreenCover(item: Binding(
            get: { currentGate },
            set: { _ in }  // dismissal is driven by the gate conditions clearing
        )) { gate in
            switch gate {
            case .terms:
                TermsGateView {
                    acceptedLegalVersion = LegalDocuments.version
                }
            case .account:
                CreateAccountView {
                    hasCompletedAccountSetup = true
                }
            }
        }
        .task {
            // Fetch the full worldwide airport database (every US field down
            // to private strips) on first launch, and silently refresh it
            // when the cached copy is more than a month old. A failed
            // download keeps whatever data is already on the device.
            if airports.cacheIsStale {
                await airports.downloadFullDatabase()
            }
        }
    }
}
