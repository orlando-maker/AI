import SwiftUI
import PhotosUI
import AuthenticationServices

/// The pilot card: photo, name, certificate line, home airport, and primary
/// aircraft — plus Sign in with Apple to attach an identity.
struct ProfileView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(FleetStore.self) private var fleet
    @Environment(AirportStore.self) private var airports
    @Environment(ProStore.self) private var pro

    @State private var editing = false
    @State private var showingTraining = false
    @State private var signInErrorMessage: String?

    private var profile: PilotProfile { profileStore.profile }

    /// Apple sign-in surfaces only in builds where its capability is on
    /// (paid developer account) — the TTAppleSignInEnabled flag is set in
    /// project.yml alongside the entitlement. Everywhere else the button
    /// would only ever produce error 1000, so it stays hidden.
    private var appleSignInEnabled: Bool {
        (Bundle.main.object(forInfoDictionaryKey: "TTAppleSignInEnabled") as? Bool) == true
    }

    private var primaryHomeAirport: Airport? {
        profile.primaryHomeAirportIdent.flatMap { airports.lookup($0) }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    pilotCard
                    trainingCard
                    signInSection
                }
                .padding()
                .readableContentWidth()
            }
            .background(Color(uiColor: .systemGroupedBackground))
            .navigationTitle("Profile")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button("Edit") { editing = true }
                }
            }
            .sheet(isPresented: $editing) {
                NavigationStack { ProfileEditView() }
            }
            .sheet(isPresented: $showingTraining) {
                NavigationStack { TrainingView() }
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
    }

    // MARK: - Pilot card

    private var pilotCard: some View {
        VStack(spacing: 14) {
            avatar
                .frame(width: 110, height: 110)

            VStack(spacing: 4) {
                HStack(spacing: 8) {
                    Text(profile.name.isEmpty ? "Add your name" : profile.name.uppercased())
                        .font(.system(.title2, design: .rounded).weight(.heavy))
                        .foregroundStyle(.white)
                    if pro.isPro {
                        Text("PRO")
                            .font(.caption2.weight(.heavy))
                            .tracking(1)
                            .padding(.horizontal, 7)
                            .padding(.vertical, 3)
                            .background(Theme.proGold, in: Capsule())
                            .foregroundStyle(.black)
                    }
                }
                if !profile.certificateLine.isEmpty {
                    Text(profile.certificateLine.uppercased())
                        .font(.caption.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(Theme.proGold)
                }
            }

            Divider().overlay(.white.opacity(0.3))

            VStack(spacing: 8) {
                cardRow(label: "HOME", value: homeLineText)
                if profile.homeAirportIdents.count > 1 {
                    cardRow(label: "ALSO FLIES FROM",
                            value: profile.homeAirportIdents.dropFirst().joined(separator: " · "))
                }
                cardRow(label: "AIRCRAFT", value: aircraftLineText)
            }
        }
        .padding(22)
        .frame(maxWidth: .infinity)
        .background(pro.isPro ? Theme.proSky : Theme.sky, in: RoundedRectangle(cornerRadius: 24))
        .overlay(
            RoundedRectangle(cornerRadius: 24)
                .strokeBorder(Theme.proGold.opacity(pro.isPro ? 0.55 : 0), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.25), radius: 12, y: 6)
    }

    private var homeLineText: String {
        guard let primary = profile.primaryHomeAirportIdent else { return "Set home airport" }
        if let airport = primaryHomeAirport, let city = airport.municipality {
            return "\(airport.ident) (\(city.uppercased()))"
        }
        return primary.uppercased()
    }

    private var aircraftLineText: String {
        guard let plane = fleet.aircraft.first else { return "Add an aircraft" }
        let typeName = AircraftLibrary.preset(for: plane.typeCode)?.name ?? plane.typeCode
        return "\(NNumber.normalize(plane.tailNumber)) (\(typeName))"
    }

    private func cardRow(label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(.white.opacity(0.6))
            Spacer()
            Text(value)
                .font(.system(.subheadline, design: .rounded).weight(.semibold))
                .foregroundStyle(.white)
                .multilineTextAlignment(.trailing)
        }
    }

    @ViewBuilder
    private var avatar: some View {
        if let image = ImageStore.load(profile.avatarFileName) {
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .clipShape(Circle())
                .overlay(Circle().strokeBorder(.white.opacity(0.8), lineWidth: 3))
        } else {
            ZStack {
                Circle().fill(.white.opacity(0.15))
                Image(systemName: "person.fill")
                    .font(.system(size: 44))
                    .foregroundStyle(.white.opacity(0.7))
            }
            .overlay(Circle().strokeBorder(.white.opacity(0.4), lineWidth: 2))
        }
    }

    // MARK: - Training card

    private var trainingCard: some View {
        Button {
            showingTraining = true
        } label: {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Label("Training & Ratings", systemImage: "graduationcap.fill")
                        .font(.headline)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                let milestones = profile.milestones
                let done = milestones.filter(\.completed).count
                if !milestones.isEmpty {
                    ProgressView(value: Double(done) / Double(milestones.count))
                        .tint(Theme.proGold)
                    if let next = milestones.first(where: { !$0.completed }) {
                        Text("\(done) of \(milestones.count) complete · next: \(next.title)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("All \(milestones.count) milestones complete 🎉")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                if !profile.ratings.isEmpty {
                    Text(profile.ratings.map(\.name).joined(separator: " · "))
                        .font(.caption.weight(.medium))
                        .foregroundStyle(Theme.proGold)
                        .lineLimit(2)
                }
            }
            .padding(16)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
        }
        .foregroundStyle(.primary)
    }

    // MARK: - Sign in

    @ViewBuilder
    private var signInSection: some View {
        if profile.isSignedIn {
            HStack {
                Label("Signed in with \(profile.signedInProviders)", systemImage: "checkmark.seal.fill")
                    .foregroundStyle(.green)
                Spacer()
                Button("Sign Out", role: .destructive) {
                    profileStore.signOut()
                }
                .font(.callout)
            }
            .padding()
            .background(.background, in: RoundedRectangle(cornerRadius: 14))
        } else {
            VStack(spacing: 10) {
                if appleSignInEnabled {
                    SignInWithAppleButton(.continue) { request in
                        request.requestedScopes = [.fullName]
                    } onCompletion: { result in
                        handleAppleSignIn(result)
                    }
                    .signInWithAppleButtonStyle(.black)
                    .frame(height: 48)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                }

                if GoogleAuth.isAvailable && GoogleAuth.isConfigured {
                    Button {
                        Task { await signInWithGoogle() }
                    } label: {
                        HStack(spacing: 10) {
                            Text("G")
                                .font(.system(size: 20, weight: .bold, design: .rounded))
                                .foregroundStyle(
                                    LinearGradient(colors: [.blue, .red, .yellow, .green],
                                                   startPoint: .topLeading,
                                                   endPoint: .bottomTrailing)
                                )
                            Text("Continue with Google")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(.primary)
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Color(uiColor: .systemBackground),
                                    in: RoundedRectangle(cornerRadius: 12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .strokeBorder(Color.secondary.opacity(0.35))
                        )
                    }
                }

                let anySignInVisible = appleSignInEnabled ||
                    (GoogleAuth.isAvailable && GoogleAuth.isConfigured)

                VStack(spacing: 6) {
                    if anySignInVisible {
                        Text("By signing up you agree to the Terms of Service and Privacy Policy.")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    NavigationLink {
                        LegalView()
                    } label: {
                        Text("Read Terms · Privacy · Legal")
                            .font(.caption2.weight(.semibold))
                    }
                }

                Text(anySignInVisible
                     ? "Optional — your profile and logbook live on this device either way. Signing in attaches an identity for future sync features."
                     : "Your profile and logbook live safely on this device — no account needed. Sign-in options appear in builds made with a paid Apple Developer account (see README).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        switch result {
        case .success(let auth):
            guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
            var updated = profileStore.profile
            updated.appleUserID = credential.user
            if updated.name.isEmpty, let nameComponents = credential.fullName {
                let name = [nameComponents.givenName, nameComponents.familyName]
                    .compactMap { $0 }.joined(separator: " ")
                if !name.isEmpty { updated.name = name }
            }
            profileStore.profile = updated
        case .failure(let error):
            if let authError = error as? ASAuthorizationError, authError.code == .canceled {
                return
            }
            signInErrorMessage = """
            \(error.localizedDescription)

            If this build doesn't have the Sign in with Apple capability \
            (it's off by default so free Apple accounts can build), enable \
            it per the README — it needs a paid Apple Developer account.
            """
        }
    }

    private func signInWithGoogle() async {
        do {
            let result = try await GoogleAuth.signIn()
            var updated = profileStore.profile
            updated.googleUserID = result.id
            if updated.name.isEmpty, let name = result.name, !name.isEmpty {
                updated.name = name
            }
            profileStore.profile = updated
        } catch {
            signInErrorMessage = error.localizedDescription
        }
    }
}

/// Edit sheet for the pilot card.
struct ProfileEditView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(\.dismiss) private var dismiss

    @State private var draft = PilotProfile()
    @State private var photoSelection: PhotosPickerItem?
    @State private var pickingHome = false
    @State private var loaded = false

    var body: some View {
        Form {
            Section("Photo") {
                PhotosPicker(selection: $photoSelection, matching: .images) {
                    Label("Choose profile photo", systemImage: "person.crop.circle.badge.plus")
                }
            }
            Section("Pilot") {
                TextField("Name", text: $draft.name)
                Picker("Certificate", selection: certificateBinding) {
                    Text("Custom…").tag("")
                    ForEach(PilotProfile.certificatePresets, id: \.self) { preset in
                        Text(preset).tag(preset)
                    }
                }
                if !PilotProfile.certificatePresets.contains(draft.certificateLine) {
                    TextField("Certificate / ratings (e.g. Student Pilot)", text: $draft.certificateLine)
                }
            }
            Section {
                ForEach(draft.homeAirportIdents, id: \.self) { ident in
                    Button {
                        draft.makePrimaryHomeAirport(ident)
                    } label: {
                        HStack {
                            Text(ident)
                            if ident == draft.primaryHomeAirportIdent {
                                Text("PRIMARY")
                                    .font(.caption2.weight(.heavy))
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(Theme.proGold.opacity(0.2), in: Capsule())
                                    .foregroundStyle(Theme.proGold)
                            }
                            Spacer()
                        }
                    }
                    .foregroundStyle(.primary)
                }
                .onDelete { offsets in
                    draft.homeAirportIdents.remove(atOffsets: offsets)
                }
                Button {
                    pickingHome = true
                } label: {
                    Label("Add home airport", systemImage: "plus")
                }
            } header: {
                Text("Home airports")
            } footer: {
                Text("Add every field you fly from — flying clubs, rentals, your tiedown. Tap one to make it primary; swipe to remove.")
            }
        }
        .navigationTitle("Edit Profile")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    var updated = draft
                    updated.avatarFileName = profileStore.profile.avatarFileName
                    updated.appleUserID = profileStore.profile.appleUserID
                    profileStore.profile = updated
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $pickingHome) {
            AirportPickerView(title: "Add Home Airport") { draft.addHomeAirport($0.ident) }
        }
        .onChange(of: photoSelection) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    profileStore.setAvatar(imageData: data)
                }
            }
        }
        .onAppear {
            if !loaded {
                draft = profileStore.profile
                loaded = true
            }
        }
    }

    private var certificateBinding: Binding<String> {
        Binding(
            get: {
                PilotProfile.certificatePresets.contains(draft.certificateLine) ? draft.certificateLine : ""
            },
            set: { newValue in
                if !newValue.isEmpty { draft.certificateLine = newValue }
                else if PilotProfile.certificatePresets.contains(draft.certificateLine) {
                    draft.certificateLine = ""
                }
            }
        )
    }
}
