import SwiftUI
import PhotosUI
import AuthenticationServices

/// The pilot card: photo, name, certificate line, home airport, and primary
/// aircraft — plus Sign in with Apple to attach an identity.
struct ProfileView: View {
    @Environment(ProfileStore.self) private var profileStore
    @Environment(FleetStore.self) private var fleet
    @Environment(AirportStore.self) private var airports

    @State private var editing = false
    @State private var showingTraining = false

    private var profile: PilotProfile { profileStore.profile }

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
        }
    }

    // MARK: - Pilot card

    private var pilotCard: some View {
        VStack(spacing: 14) {
            avatar
                .frame(width: 110, height: 110)

            VStack(spacing: 4) {
                Text(profile.name.isEmpty ? "Add your name" : profile.name.uppercased())
                    .font(.system(.title2, design: .rounded).weight(.heavy))
                    .foregroundStyle(.white)
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
        .background(Theme.sky, in: RoundedRectangle(cornerRadius: 24))
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
        if profile.isSignedInWithApple {
            HStack {
                Label("Signed in with Apple", systemImage: "checkmark.seal.fill")
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
                SignInWithAppleButton(.continue) { request in
                    request.requestedScopes = [.fullName]
                } onCompletion: { result in
                    handleAppleSignIn(result)
                }
                .signInWithAppleButtonStyle(.black)
                .frame(height: 48)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                VStack(spacing: 6) {
                    Text("By signing up you agree to the Terms of Service and Privacy Policy.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                    NavigationLink {
                        LegalView()
                    } label: {
                        Text("Read Terms · Privacy · Legal")
                            .font(.caption2.weight(.semibold))
                    }
                }

                Text("Optional — your profile and logbook live on this device either way. Signing in needs the Sign in with Apple capability enabled in project.yml plus a paid Apple Developer account (see README); without it this button reports an error and the app works normally. Google sign-in requires the GoogleSignIn SDK.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private func handleAppleSignIn(_ result: Result<ASAuthorization, Error>) {
        guard case .success(let auth) = result,
              let credential = auth.credential as? ASAuthorizationAppleIDCredential else { return }
        var updated = profileStore.profile
        updated.appleUserID = credential.user
        if updated.name.isEmpty, let nameComponents = credential.fullName {
            let name = [nameComponents.givenName, nameComponents.familyName]
                .compactMap { $0 }.joined(separator: " ")
            if !name.isEmpty { updated.name = name }
        }
        profileStore.profile = updated
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
