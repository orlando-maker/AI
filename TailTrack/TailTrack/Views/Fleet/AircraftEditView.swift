import SwiftUI
import PhotosUI

/// Add/edit an aircraft: tail number, type (with presets), cruise speed,
/// photo, and an optional manual Mode S hex override.
struct AircraftEditView: View {
    @State var aircraft: Aircraft
    var isEditing = false
    let onSave: (Aircraft) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var photoSelection: PhotosPickerItem?
    @State private var photoPreview: UIImage?
    @State private var findingOpenPhoto = false
    // Photo files written during this edit session. Nothing already
    // persisted is deleted until Save, so Cancel never destroys data.
    @State private var originalPhotoFileName: String?
    @State private var originalCaptured = false
    @State private var sessionPicks: [String] = []

    private var derivedHex: String? {
        NNumber.icaoHex(for: aircraft.tailNumber)
    }

    private var canSave: Bool {
        !aircraft.tailNumber.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        Form {
            photoSection
            identitySection
            performanceSection
            transponderSection
        }
        .navigationTitle(isEditing ? "Edit Aircraft" : "Add Aircraft")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    // Discard any photos picked during this edit session.
                    for name in sessionPicks { ImageStore.delete(name) }
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    aircraft.tailNumber = NNumber.normalize(aircraft.tailNumber)
                    // Keep only the final pick; drop intermediate picks and
                    // the previously saved photo it replaces.
                    for name in sessionPicks where name != aircraft.photoFileName {
                        ImageStore.delete(name)
                    }
                    if let original = originalPhotoFileName,
                       original != aircraft.photoFileName {
                        ImageStore.delete(original)
                    }
                    onSave(aircraft)
                    dismiss()
                }
                .disabled(!canSave)
            }
        }
        .onChange(of: photoSelection) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self) {
                    setPhoto(data)
                }
            }
        }
        .sheet(isPresented: $findingOpenPhoto) {
            OpenPhotoPickerView(initialQuery: openPhotoQuery) { data in
                setPhoto(data)
            }
        }
        .onAppear {
            // onAppear re-fires when pushed pickers pop; capture once.
            if !originalCaptured {
                originalCaptured = true
                originalPhotoFileName = aircraft.photoFileName
                photoPreview = ImageStore.load(aircraft.photoFileName)
            }
        }
    }

    private var openPhotoQuery: String {
        let typeName = AircraftLibrary.preset(for: aircraft.typeCode)?.name
            ?? (aircraft.typeCode.isEmpty ? "small airplane" : aircraft.typeCode)
        return "\(typeName) aircraft"
    }

    private func setPhoto(_ data: Data) {
        guard let name = ImageStore.save(data) else { return }
        sessionPicks.append(name)
        aircraft.photoFileName = name
        photoPreview = ImageStore.load(name)
    }

    private var photoSection: some View {
        Section {
            VStack(spacing: 10) {
                Group {
                    if let photoPreview {
                        Image(uiImage: photoPreview)
                            .resizable()
                            .scaledToFill()
                    } else {
                        ZStack(alignment: .bottom) {
                            AircraftArtView(typeCode: aircraft.typeCode, inset: 22)
                            Text("Built-in artwork — add your own photo below")
                                .font(.caption2)
                                .foregroundStyle(.white.opacity(0.75))
                                .padding(.bottom, 8)
                        }
                    }
                }
                .frame(height: 160)
                .frame(maxWidth: .infinity)
                .clipShape(RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 20) {
                    PhotosPicker(selection: $photoSelection, matching: .images) {
                        Label(photoPreview == nil ? "Choose Photo" : "Change Photo",
                              systemImage: "photo.on.rectangle.angled")
                            .font(.callout)
                    }
                    Button {
                        findingOpenPhoto = true
                    } label: {
                        Label("Find Open Photo", systemImage: "magnifyingglass")
                            .font(.callout)
                    }
                }
            }
            .listRowInsets(EdgeInsets(top: 8, leading: 8, bottom: 8, trailing: 8))
            .listRowBackground(Color.clear)
        }
    }

    private var identitySection: some View {
        Section("Identity") {
            TextField("Tail number (N1234C)", text: $aircraft.tailNumber)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Nickname (optional)", text: $aircraft.nickname)
            Picker("Type", selection: typePickerBinding) {
                Text("Custom…").tag("")
                ForEach(AircraftLibrary.presets) { preset in
                    Text("\(preset.typeCode) — \(preset.name)").tag(preset.typeCode)
                }
            }
            if AircraftLibrary.preset(for: aircraft.typeCode) == nil {
                TextField("Type code (e.g. C152)", text: $aircraft.typeCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
            }
        }
    }

    /// Selecting a preset also pre-fills the cruise speed.
    private var typePickerBinding: Binding<String> {
        Binding(
            get: { AircraftLibrary.preset(for: aircraft.typeCode)?.typeCode ?? "" },
            set: { newValue in
                if let preset = AircraftLibrary.preset(for: newValue) {
                    aircraft.typeCode = preset.typeCode
                    aircraft.cruiseSpeedKt = preset.cruiseKt
                } else {
                    aircraft.typeCode = ""
                }
            }
        )
    }

    private var performanceSection: some View {
        Section {
            Stepper(value: $aircraft.cruiseSpeedKt, in: 40...400, step: 1) {
                LabeledContent("Cruise speed", value: Format.knots(aircraft.cruiseSpeedKt))
            }
        } header: {
            Text("Performance")
        } footer: {
            Text("Used for time-enroute planning and as a fallback when live groundspeed isn't available.")
        }
    }

    private var transponderSection: some View {
        Section {
            LabeledContent("Derived Mode S hex") {
                Text(derivedHex?.uppercased() ?? "—")
                    .font(.callout.monospaced())
                    .foregroundStyle(.secondary)
            }
            TextField("Manual hex override (optional)", text: $aircraft.icaoHexOverride)
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
                .font(.body.monospaced())
        } header: {
            Text("Transponder")
        } footer: {
            Text("US N-numbers map to their ICAO 24-bit address automatically. For non-US registrations, enter the hex code from your transponder paperwork or adsbexchange.com.")
        }
    }
}
