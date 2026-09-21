import SwiftUI
import AuthenticationServices

/// First-launch account creation, shown right after the legal gate — the
/// tabs stay locked until the pilot card exists. The "account" is the
/// on-device profile (App Review forbids demanding a server login for a
/// local-first app), with Apple / Google sign-in offered where the build
/// supports it.
struct CreateAccountView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(AirportStore.self) private var airports
    let onComplete: () -> Void

    @State private var name = ""
    @State private var certificateLine = "Student Pilot"
    @State private var homeAirport: Airport?
    @State private var pickingHome = false
    @State private var signInErrorMessage: String?

    private var appleSignInEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "TTAppleSignInEnabled") as? Bool) == true
    }

    private var googleSignInEnabled: Bool {
        GoogleAuth.isAvailable && GoogleAuth.isConfigured
    }

    private var trimmedName: String {
        name.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 10) {
                        Image(systemName: "person.crop.circle.badge.checkmark")
                            .font(.system(size: 52))
                            .foregroundStyle(.tint)
                        Text("Create your pilot account")
                            .font(.system(.title2, design: .rounded).weight(.bold))
                        Text("Your account lives on this iPhone — no email, no password, no cloud. It's your pilot card.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Pilot") {
                    TextField("Your name", text: $name)
                        .textContentType(.name)
                    Picker("Certificate", selection: $certificateLine) {
                        ForEach(PilotProfile.certificatePresets, id: \.self) { preset in
                            Text(preset).tag(preset)
                        }
                        Text("I'll add this later").tag("")
                    }
                }

                Section {
                    Button {
                        pickingHome = true
                    } label: {
                        HStack {
                            Text("Home airport")
                                .foregroundStyle(.primary)
                            Spacer()
                            if let homeAirport {
                                Text(homeAirport.ident).bold()
                            } else {
                                Text("Optional")
                                    .foregroundStyle(.tertiary)
                            }
                        }
                    }
                }

                if appleSignInEnabled || googleSignInEnabled {
                    Section {
                        if appleSignInEnabled {
                            SignInWithAppleButton(.signUp) { request in
                                request.requestedScopes = [.fullName]
                            } onCompletion: { result in
                                handleAppleSignIn(result)
                            }
                            .signInWithAppleButtonStyle(.black)
                            .frame(height: 48)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                        if googleSignInEnabled {
                            Button {
                                Task { await signInWithGoogle() }
                            } label: {
                                Label("Sign up with Google", systemImage: "g.circle.fill")
                                    .font(.headline)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                            }
                            .buttonStyle(.bordered)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                        }
                    } footer: {
                        Text("Signing in attaches an identity for future sync features — everything still stays on your device.")
                    }
                }

                Section {
                    Button {
                        complete()
                    } label: {
                        Text("Create Account")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .disabled(trimmedName.isEmpty)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } footer: {
                    Text(trimmedName.isEmpty
                         ? "Just your name — that's all it takes."
                         : "Welcome aboard, \(trimmedName)!")
                        .frame(maxWidth: .infinity)
                        .multilineTextAlignment(.center)
                }
            }
        }
        .interactiveDismissDisabled()
        .sheet(isPresented: $pickingHome) {
            AirportPickerView(title: "Home Airport") { homeAirport = $0 }
        }
        .alert("Sign-in failed", isPresented: Binding(
            get: { signInErrorMessage != nil },
            set: { if !$0 { signInErrorMessage = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signInErrorMessage ?? "")
        }
    }

    /// Saves the profile and unlocks the app. Sign-in isn't required —
    /// the account is the on-device pilot card.
    private func complete() {
        guard !trimmedName.isEmpty else { return }
        var updated = profileStore.profile
        updated.name = trimmedName
        if updated.certificateLine.isEmpty { updated.certificateLine = certificateLine }
        if let homeAirport { updated.addHomeAirport(homeAirport.ident) }
        profileStore.profile = updated
        onComplete()
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            var updated = profileStore.profile
            updated.appleUserID = credential.user
            profileStore.profile = updated
            if trimmedName.isEmpty, let components = credential.fullName {
                let fetched = [components.givenName, components.familyName]
                    .compactMap { $0 }.joined(separator: " ")
                if !fetched.isEmpty { name = fetched }
            }
            if !trimmedName.isEmpty { complete() }
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            signInErrorMessage = error.localizedDescription
        }
    }

    private func signInWithGoogle() async {
        do {
            let result = try await GoogleAuth.signIn()
            var updated = profileStore.profile
            updated.googleUserID = result.id
            profileStore.profile = updated
            if trimmedName.isEmpty, let fetched = result.name, !fetched.isEmpty {
                name = fetched
            }
            if !trimmedName.isEmpty { complete() }
        } catch {
            signInErrorMessage = error.localizedDescription
        }
    }
}
