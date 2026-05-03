import SwiftUI

enum SidebarItem: String, Hashable {
    case home, myReports, settings, about
}

struct SidebarView: View {
    @State private var selectedItem: SidebarItem? = .home

    var body: some View {
        NavigationSplitView {
            List(selection: $selectedItem) {
                NavigationLink(value: SidebarItem.home) {
                    Label("Map", systemImage: "map.fill")
                }
                NavigationLink(value: SidebarItem.myReports) {
                    Label("My Reports", systemImage: "list.bullet.clipboard.fill")
                }
                NavigationLink(value: SidebarItem.settings) {
                    Label("Settings", systemImage: "gearshape.fill")
                }
                NavigationLink(value: SidebarItem.about) {
                    Label("About", systemImage: "info.circle.fill")
                }
            }
            .navigationTitle("Woodside")
            .listStyle(.sidebar)
        } detail: {
            switch selectedItem {
            case .home, nil:
                MainMapView()
            case .myReports:
                PastReportsView()
            case .settings:
                SettingsView()
            case .about:
                AboutView()
            }
        }
    }
}

// MARK: - Settings View

struct SettingsView: View {
    @AppStorage("preferredMapStyle") private var mapStyleRaw = "standard"

    var body: some View {
        Form {
            Section("Map") {
                Picker("Default Map Style", selection: $mapStyleRaw) {
                    Text("Standard").tag("standard")
                    Text("Satellite").tag("imagery")
                    Text("Hybrid").tag("hybrid")
                }
            }
            Section("App") {
                LabeledContent("Version", value: appVersion)
                LabeledContent("Support") {
                    Link(Config.supportEmail,
                         destination: URL(string: "mailto:\(Config.supportEmail)")!)
                        .foregroundStyle(.blue)
                }
            }
        }
        .navigationTitle("Settings")
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// MARK: - About View (contains hidden admin gate)

struct AboutView: View {
    @State private var versionTapCount = 0
    @State private var showCodeEntry = false
    @State private var secretCode = ""
    @State private var showAdminGate = false

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    Image(systemName: "leaf.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("Woodside Trail Report")
                        .font(.headline)
                    Text("A community reporting tool for the Town of Woodside, CA.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }

            Section("Info") {
                LabeledContent("Version") {
                    Text(appVersion)
                        .foregroundStyle(.secondary)
                        .onTapGesture {
                            versionTapCount += 1
                            if versionTapCount >= Config.adminGateTapCount {
                                versionTapCount = 0
                                withAnimation { showCodeEntry = true }
                            }
                        }
                }
                if showCodeEntry {
                    HStack {
                        SecureField("Enter code", text: $secretCode)
                            .keyboardType(.numberPad)
                            .onChange(of: secretCode) { _, new in
                                if new == Config.adminGateCode {
                                    showCodeEntry = false
                                    secretCode = ""
                                    showAdminGate = true
                                }
                            }
                        Button("Cancel") {
                            showCodeEntry = false
                            secretCode = ""
                            versionTapCount = 0
                        }
                        .font(.footnote)
                    }
                }
                LabeledContent("Not affiliated with") {
                    Text("Town of Woodside")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Contact") {
                Link("support@orlandonell.com",
                     destination: URL(string: "mailto:\(Config.supportEmail)")!)
                Link("orlandonell.com", destination: Config.websiteURL)
            }

            Section("Legal") {
                NavigationLink("Terms & Conditions") {
                    TermsTextView()
                }
            }
        }
        .navigationTitle("About")
        .navigationDestination(isPresented: $showAdminGate) {
            AdminLoginView()
        }
    }

    private var appVersion: String {
        let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let b = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(v) (\(b))"
    }
}

// Terms text shown in About → Terms (read-only, no Agree/Disagree buttons).
struct TermsTextView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Group {
                    termBlock(
                        title: "Not Affiliated with the Town of Woodside",
                        body: "This app is not made by or affiliated with the Town of Woodside, California. It is provided as a community tool and may contain errors. If you notice any errors, please notify \(Config.supportEmail)."
                    )
                    termBlock(
                        title: "Provided As-Is",
                        body: "This app is provided as-is with no warranty of any kind. No customer service is provided unless the issue is a software-related problem within the app itself."
                    )
                    termBlock(
                        title: "Free of Charge",
                        body: "This app is free of charge and may not be redistributed or resold in any form. It is owned and licensed by orlandonell.com."
                    )
                    termBlock(
                        title: "Privacy",
                        body: "This app does not track users. A randomly generated device ID is stored locally to let you view past reports without an account. Your location is used only to place a map pin and is not stored beyond what you include in your report."
                    )
                }
                HStack(spacing: 4) {
                    Text("More information:")
                    Link("orlandonell.com", destination: Config.websiteURL)
                        .foregroundStyle(.blue)
                }
                .font(.footnote)
                .foregroundStyle(.secondary)
            }
            .padding()
        }
        .navigationTitle("Terms & Conditions")
        .navigationBarTitleDisplayMode(.inline)
    }

    @ViewBuilder
    private func termBlock(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(title).font(.subheadline.bold())
            Text(body).font(.footnote).foregroundStyle(.secondary)
        }
    }
}
