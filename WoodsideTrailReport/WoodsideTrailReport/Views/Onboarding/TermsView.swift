import SwiftUI

struct TermsView: View {
    @AppStorage("hasAgreedToTerms") private var hasAgreedToTerms = false
    @State private var showDisagreeDialog = false
    @State private var showDeleteInstructions = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    // Header
                    VStack(spacing: 8) {
                        Image(systemName: "leaf.fill")
                            .font(.system(size: 48))
                            .foregroundStyle(.green)
                        Text("Woodside Trail Report")
                            .font(.largeTitle.bold())
                        Text("Please Review Legal Terms & Conditions")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 20)

                    Divider()

                    // Terms body
                    VStack(alignment: .leading, spacing: 16) {
                        termSection(
                            title: "Not Affiliated with the Town of Woodside",
                            body: "This app is not made by or affiliated with the Town of Woodside, California. It is provided as a community tool and may contain errors. If you notice any errors, please notify \(Config.supportEmail) and we will try to correct the issue in a timely manner."
                        )
                        termSection(
                            title: "Provided As-Is",
                            body: "This app is provided as-is with no warranty of any kind. No customer service is provided unless the issue is a software-related problem within the app itself."
                        )
                        termSection(
                            title: "Free of Charge",
                            body: "This app is free of charge and may not be redistributed or resold in any form. It is owned and licensed by orlandonell.com."
                        )
                        termSection(
                            title: "Privacy",
                            body: "This app does not track users. A randomly generated device ID is stored locally on your device to allow you to view your past reports without creating an account. Your location is used only to place a pin on the map and is not stored beyond what you submit in your report."
                        )

                        HStack(spacing: 4) {
                            Text("For more information, visit")
                            Link("orlandonell.com", destination: Config.websiteURL)
                                .foregroundStyle(.blue)
                            Text("(opens in Safari).")
                        }
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                    }
                    .padding(.horizontal, 4)

                    Divider()

                    // Action buttons
                    VStack(spacing: 12) {
                        Button {
                            hasAgreedToTerms = true
                        } label: {
                            Text("I Agree")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.green)
                                .foregroundStyle(.white)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }

                        Button(role: .destructive) {
                            showDisagreeDialog = true
                        } label: {
                            Text("I Disagree")
                                .font(.headline)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(.red.opacity(0.1))
                                .foregroundStyle(.red)
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                    }
                    .padding(.bottom, 32)
                }
                .padding(.horizontal, 24)
            }
            .navigationBarHidden(true)
        }
        .confirmationDialog(
            "To remove this app, press and hold the Woodside Trail Report icon on your Home Screen, then tap Remove App.",
            isPresented: $showDisagreeDialog,
            titleVisibility: .visible
        ) {
            Button("Cancel", role: .cancel) {}
        }
        .interactiveDismissDisabled(true)
    }

    @ViewBuilder
    private func termSection(title: String, body: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(.subheadline.bold())
            Text(body)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}
