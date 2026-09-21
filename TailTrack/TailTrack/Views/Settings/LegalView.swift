import SwiftUI

/// Legal hub: Terms of Service, Privacy Policy, acknowledgements, website
/// and support contact.
struct LegalView: View {
    var body: some View {
        List {
            Section {
                NavigationLink("Terms of Service") {
                    LegalDocumentView(title: "Terms of Service",
                                      text: LegalDocuments.termsOfService)
                }
                NavigationLink("Privacy Policy") {
                    LegalDocumentView(title: "Privacy Policy",
                                      text: LegalDocuments.privacyPolicy)
                }
                NavigationLink("Acknowledgements & Data Sources") {
                    LegalDocumentView(title: "Acknowledgements",
                                      text: LegalDocuments.acknowledgements)
                }
            }
            Section {
                Link(destination: LegalDocuments.websiteURL) {
                    Label("orlandonell.com", systemImage: "globe")
                }
                Link(destination: URL(string: "mailto:\(LegalDocuments.supportEmail)")!) {
                    Label(LegalDocuments.supportEmail, systemImage: "envelope")
                }
            } footer: {
                Text("© 2026 Orlando Nell. TailTrack is an independent app and is not affiliated with the FAA or any data provider.")
            }
        }
        .navigationTitle("Legal")
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Scrollable plain-text legal document.
struct LegalDocumentView: View {
    let title: String
    let text: String

    var body: some View {
        ScrollView {
            Text(text)
                .font(.footnote)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Full-screen agreement gate shown on first launch (and again whenever the
/// legal documents' version is bumped) — the app is unusable until agreed.
struct TermsGateView: View {
    let onAgree: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        VStack(spacing: 8) {
                            Image(systemName: "airplane.circle.fill")
                                .font(.system(size: 60))
                                .foregroundStyle(.tint)
                            Text("Welcome to TailTrack")
                                .font(.system(.title, design: .rounded).weight(.heavy))
                            Text("Before you fly, a few things to agree to.")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 24)

                        bullet("exclamationmark.triangle.fill", .orange,
                               "Not for navigation",
                               "TailTrack is a logging companion. Never use it for flight-critical decisions — the pilot in command is always responsible.")
                        bullet("dot.radiowaves.left.and.right", .blue,
                               "Community data",
                               "Positions come from free, community ADS-B networks. Coverage and accuracy are not guaranteed.")
                        bullet("lock.fill", .green,
                               "Your data stays yours",
                               "Profile, logbook, and photos live on your device only. No ads, no analytics, no tracking.")

                        VStack(alignment: .leading, spacing: 8) {
                            Text("By continuing you agree to the TailTrack Terms of Service and acknowledge the Privacy Policy.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            HStack(spacing: 16) {
                                NavigationLink("Read Terms of Service") {
                                    LegalDocumentView(title: "Terms of Service",
                                                      text: LegalDocuments.termsOfService)
                                }
                                NavigationLink("Privacy Policy") {
                                    LegalDocumentView(title: "Privacy Policy",
                                                      text: LegalDocuments.privacyPolicy)
                                }
                            }
                            .font(.caption.weight(.semibold))
                        }
                    }
                    .padding()
                }

                Button {
                    onAgree()
                } label: {
                    Text("Agree & Continue")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                }
                .buttonStyle(.borderedProminent)
                .padding()
            }
        }
        .interactiveDismissDisabled()
    }

    private func bullet(_ icon: String, _ color: Color, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(color)
                .frame(width: 32)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.headline)
                Text(detail).font(.subheadline).foregroundStyle(.secondary)
            }
        }
    }
}
