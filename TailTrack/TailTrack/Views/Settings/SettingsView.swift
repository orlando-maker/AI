import SwiftUI

struct SettingsView: View {
    @Environment(AirportStore.self) private var airports
    @Environment(ProStore.self) private var pro

    @State private var showingPaywall = false

    var body: some View {
        NavigationStack {
            Form {
                proSection
                airportSection
                dataSourcesSection
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    private var proSection: some View {
        Section {
            if pro.isPro {
                Label("TailTrack Pro is active", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(Theme.proGold)
            } else {
                Button {
                    showingPaywall = true
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Upgrade to TailTrack Pro")
                                .font(.headline)
                            Text("Unlimited aircraft, exports, satellite maps")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "sparkles")
                            .foregroundStyle(Theme.proGold)
                    }
                }
                .foregroundStyle(.primary)
                Button("Restore Purchases") {
                    Task { await pro.restorePurchases() }
                }
                .font(.callout)
            }
        }
    }

    private var airportSection: some View {
        Section {
            LabeledContent("Database") {
                Text(airports.statusDescription)
                    .font(.caption)
                    .multilineTextAlignment(.trailing)
            }
            if airports.isDownloading {
                HStack {
                    ProgressView()
                    Text("Downloading OurAirports data…")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            } else {
                Button(airports.usingFullDatabase ? "Update airport database" : "Download full airport database") {
                    Task { await airports.downloadFullDatabase() }
                }
            }
            if let error = airports.downloadError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Airports")
        } footer: {
            Text("Worldwide airport data from OurAirports (public domain, ~10 MB, cached on device). Includes every US field — from private strips and tiny GA fields like E16 or NV82 up to KATL and KSFO. Downloads automatically on first launch and refreshes itself monthly; the button forces an immediate update.")
        }
    }

    private var dataSourcesSection: some View {
        Section {
            Link("adsb.lol — community ADS-B network",
                 destination: URL(string: "https://adsb.lol")!)
            Link("adsb.fi — community ADS-B network",
                 destination: URL(string: "https://adsb.fi")!)
            Link("OpenSky Network",
                 destination: URL(string: "https://opensky-network.org")!)
            Link("OurAirports",
                 destination: URL(string: "https://ourairports.com")!)
        } header: {
            Text("Open data sources")
        } footer: {
            Text("TailTrack reads live positions from free, community-run ADS-B aggregators. Consider feeding them from a Raspberry Pi receiver at your home field — coverage where you fly gets better and the networks stay free.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0")
            NavigationLink("Legal") { LegalView() }
            Link(destination: LegalDocuments.websiteURL) {
                Label("orlandonell.com", systemImage: "globe")
            }
            Link(destination: URL(string: "mailto:\(LegalDocuments.supportEmail)")!) {
                Label("Contact support", systemImage: "envelope")
            }
        } header: {
            Text("About")
        } footer: {
            Text("TailTrack is a logging and flight-following companion. It is not a certified navigation, traffic, or separation tool — never use it for flight-critical decisions. ADS-B coverage of low-altitude GA flight varies by terrain and receiver density.")
        }
    }

    #if DEBUG
    private var debugSection: some View {
        @Bindable var proStore = pro
        return Section("Debug") {
            Toggle("Force Pro entitlement", isOn: $proStore.debugProOverride)
        }
    }
    #endif
}
