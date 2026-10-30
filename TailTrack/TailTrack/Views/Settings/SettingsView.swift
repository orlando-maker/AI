import SwiftUI

struct SettingsView: View {
    @Environment(AirportStore.self) private var airports
    @Environment(ProStore.self) private var pro

    @State private var showingPaywall = false
    /// Hidden hangar: tap the version number seven times.
    @State private var versionTaps = 0
    @State private var showingEgg = false
    @State private var quip = ""
    @AppStorage(AppearanceSetting.storageKey) private var appearanceRaw = AppearanceSetting.system.rawValue

    var body: some View {
        NavigationStack {
            Form {
                appearanceSection
                proSection
                airportSection
                radioSection
                dataSourcesSection
                aboutSection
                #if DEBUG
                debugSection
                #endif
            }
            .navigationTitle("Settings")
            .scrollContentBackground(.hidden)
            .background(Theme.paper)
            .sheet(isPresented: $showingPaywall) { PaywallView() }
        }
    }

    private var appearanceSection: some View {
        Section("Appearance") {
            Picker("Theme", selection: $appearanceRaw) {
                ForEach(AppearanceSetting.allCases) { setting in
                    Text(setting.label).tag(setting.rawValue)
                }
            }
            .pickerStyle(.segmented)
            NavigationLink {
                CustomizeView()
            } label: {
                Label("Customize", systemImage: "paintpalette")
            }
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

    private var radioSection: some View {
        Section {
            NavigationLink {
                ReceiversView()
            } label: {
                Label("My receivers", systemImage: "antenna.radiowaves.left.and.right")
            }
        } header: {
            Text("Radio")
        } footer: {
            Text("Play live ATC from a receiver you run yourself. LiveATC.net is linked from each airport, but its terms don't allow other apps to play its streams.")
        }
    }

    private var dataSourcesSection: some View {
        Section {
            Link("adsb.lol — community ADS-B network",
                 destination: URL(string: "https://adsb.lol")!)
            if ADSBClient.adsbFiPermitted {
                Link("adsb.fi — community ADS-B network",
                     destination: URL(string: "https://adsb.fi")!)
            }
            Link("OurAirports",
                 destination: URL(string: "https://ourairports.com")!)
        } header: {
            Text("Open data sources")
        } footer: {
            Text("TailTrack reads live positions from adsb.lol, a free, community-run ADS-B network (data under the Open Database License). Consider feeding them from a Raspberry Pi receiver at your home field — coverage where you fly gets better and the networks stay free.")
        }
    }

    private static let quips = [
        "A good landing is any landing you can walk away from. A great one is when the airplane can fly again.",
        "Remember: the three most useless things in aviation are altitude above you, runway behind you, and fuel in the truck.",
        "Takeoffs are optional. Landings are mandatory.",
        "Aviate, navigate, communicate. In that order.",
        "Your logbook never lies. Your hobbs meter occasionally does.",
        "The pattern is full of Cessnas, and one of them is you.",
        "Always keep your airspeed up, and your sense of humor higher.",
    ]

    /// "1.0 (1)": the version people see, then the build number.
    private static var versionLabel: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(version) (\(build))"
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: Self.versionLabel)
                .contentShape(Rectangle())
                .onTapGesture {
                    versionTaps += 1
                    if versionTaps >= 7 {
                        versionTaps = 0
                        quip = Self.quips.randomElement() ?? Self.quips[0]
                        showingEgg = true
                    }
                }
                .sensoryFeedback(.success, trigger: showingEgg) { _, shown in shown }
                .alert("Cleared for takeoff ✈️", isPresented: $showingEgg) {
                    Button("Roger") {}
                } message: {
                    Text("\(quip)\n\nTailTrack was designed and built by a student pilot at KSQL. Blue skies.")
                }
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
