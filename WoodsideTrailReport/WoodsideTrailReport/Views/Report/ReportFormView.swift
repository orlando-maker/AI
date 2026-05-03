import CoreLocation
import PhotosUI
import SwiftUI

@Observable
final class ReportFormViewModel {
    var description = ""
    var crossStreets = ""
    var selectedPhotoItems: [PhotosPickerItem] = []
    var photoData: [Data] = []
    var isLoadingPhotos = false
    var isSubmitting = false
    var submittedReportID: UUID?
    var errorMessage: String?

    // Contact info
    var phone = ""
    var countryDialCode = "+1"
    var phoneType = "cell"
    var contactOk: Bool? = nil
    var email = ""
    var isPhoneSelected = false

    var isValid: Bool {
        !description.trimmingCharacters(in: .whitespaces).isEmpty &&
        (isPhoneSelected || EmailValidator.isValid(email))
    }
}

struct ReportFormView: View {
    let coordinate: CLLocationCoordinate2D
    let geocodeResult: ReverseGeocodeResult?
    let reportType: ReportType
    let onDismiss: () -> Void

    @State private var vm = ReportFormViewModel()
    @State private var verificationQuestion = HumanVerificationBank.random()
    @State private var verificationAnswer = ""
    @State private var verificationPassed = false
    @State private var showSubmissionConfirmation = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // 50% opacity background image
            if let uiImage = UIImage(named: "FormBackground") {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .opacity(0.5)
            } else {
                // Fallback: gentle green gradient when image is not yet added to Assets
                LinearGradient(
                    colors: [Color.green.opacity(0.3), Color.teal.opacity(0.2)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .ignoresSafeArea()
            }

            Form {
                // Report type + location summary
                Section {
                    LabeledContent("Type") {
                        Label(reportType.displayName, systemImage: reportType.icon)
                            .foregroundStyle(.green)
                    }
                    if let addr = geocodeResult?.formattedAddress {
                        LabeledContent("Near", value: addr)
                    }
                    LabeledContent("Coordinates") {
                        Text(String(format: "%.5f, %.5f",
                                    coordinate.latitude,
                                    coordinate.longitude))
                            .font(.caption.monospaced())
                    }
                }
                .listRowBackground(Color(.systemBackground).opacity(0.85))

                // Description
                Section("Description") {
                    TextEditor(text: $vm.description)
                        .frame(minHeight: 80)
                    HStack {
                        Spacer()
                        Text("\(vm.description.count)/1000")
                            .font(.caption2)
                            .foregroundStyle(vm.description.count > 950 ? .orange : .secondary)
                    }
                }
                .listRowBackground(Color(.systemBackground).opacity(0.85))
                .onChange(of: vm.description) { _, new in
                    if new.count > 1000 {
                        vm.description = String(new.prefix(1000))
                    }
                }

                // Cross streets
                Section("Cross Streets (optional)") {
                    TextField("Between [Street A] and [Street B]", text: $vm.crossStreets)
                }
                .listRowBackground(Color(.systemBackground).opacity(0.85))

                // Photos
                Section("Photos (optional)") {
                    PhotosPicker(
                        selection: $vm.selectedPhotoItems,
                        maxSelectionCount: 5,
                        matching: .images
                    ) {
                        Label(
                            vm.photoData.isEmpty
                                ? "Add Photos (up to 5)"
                                : "\(vm.photoData.count) photo\(vm.photoData.count == 1 ? "" : "s") selected",
                            systemImage: "camera.fill"
                        )
                    }
                    .onChange(of: vm.selectedPhotoItems) { _, newItems in
                        Task { await loadPhotos(newItems) }
                    }

                    if !vm.photoData.isEmpty {
                        ScrollView(.horizontal) {
                            HStack {
                                ForEach(vm.photoData.indices, id: \.self) { idx in
                                    if let img = UIImage(data: vm.photoData[idx]) {
                                        Image(uiImage: img)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 72, height: 72)
                                            .clipShape(RoundedRectangle(cornerRadius: 8))
                                    }
                                }
                            }
                        }
                    }
                }
                .listRowBackground(Color(.systemBackground).opacity(0.85))

                // Contact info
                ContactInfoSection(vm: vm)

                // Human verification
                if !verificationPassed {
                    Section("Verification") {
                        Text(verificationQuestion.question)
                            .font(.subheadline)
                        TextField("Your answer", text: $verificationAnswer)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                        if !verificationAnswer.isEmpty &&
                           !verificationQuestion.isCorrect(verificationAnswer) {
                            Text("That doesn't seem right. Try again.")
                                .font(.caption)
                                .foregroundStyle(.red)
                        }
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.85))
                } else {
                    Section {
                        Label("Verification passed", systemImage: "checkmark.circle.fill")
                            .foregroundStyle(.green)
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.85))
                }

                // Submit
                Section {
                    Button {
                        Task { await submit() }
                    } label: {
                        if vm.isSubmitting {
                            HStack {
                                ProgressView()
                                Text("Submitting…")
                            }
                            .frame(maxWidth: .infinity)
                        } else {
                            Text("Submit Report")
                                .frame(maxWidth: .infinity)
                                .fontWeight(.semibold)
                        }
                    }
                    .disabled(!canSubmit)
                    .tint(.green)
                }
                .listRowBackground(Color(.systemBackground).opacity(0.85))

                if let err = vm.errorMessage {
                    Section {
                        Label(err, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.red)
                    }
                    .listRowBackground(Color(.systemBackground).opacity(0.85))
                }
            }
            .scrollContentBackground(.hidden)
        }
        .navigationTitle("Report Details")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    onDismiss()
                    dismiss()
                }
            }
        }
        .navigationDestination(isPresented: $showSubmissionConfirmation) {
            if let reportID = vm.submittedReportID {
                SubmissionConfirmationView(reportID: reportID, reportType: reportType) {
                    onDismiss()
                    dismiss()
                }
            }
        }
    }

    private var canSubmit: Bool {
        let descOk = !vm.description.trimmingCharacters(in: .whitespaces).isEmpty
        let contactOk = vm.isPhoneSelected || EmailValidator.isValid(vm.email)
        let verifyOk = verificationPassed || verificationQuestion.isCorrect(verificationAnswer)
        return descOk && contactOk && verifyOk && !vm.isSubmitting
    }

    private func loadPhotos(_ items: [PhotosPickerItem]) async {
        vm.isLoadingPhotos = true
        var loaded: [Data] = []
        for item in items {
            if let data = try? await item.loadTransferable(type: Data.self),
               let uiImage = UIImage(data: data),
               let jpeg = uiImage.jpegData(compressionQuality: 0.72) {
                loaded.append(jpeg)
            }
        }
        vm.photoData = loaded
        vm.isLoadingPhotos = false
    }

    private func submit() async {
        // Mark verification passed if answer is correct
        if !verificationPassed {
            guard verificationQuestion.isCorrect(verificationAnswer) else {
                vm.errorMessage = "Please answer the verification question correctly."
                return
            }
            verificationPassed = true
        }

        vm.isSubmitting = true
        vm.errorMessage = nil

        do {
            // Upload photos first
            var photoURLs: [String] = []
            if !vm.photoData.isEmpty {
                let tempID = UUID()
                for data in vm.photoData {
                    let url = try await SupabaseService.shared.uploadPhoto(data, reportID: tempID)
                    photoURLs.append(url)
                }
            }

            let phone = vm.isPhoneSelected && !vm.phone.isEmpty
                ? "\(vm.countryDialCode)\(vm.phone.filter { $0.isNumber })"
                : nil

            let report = NewReport(
                type: reportType.rawValue,
                description: vm.description,
                locationLat: coordinate.latitude,
                locationLng: coordinate.longitude,
                nearestStreet: geocodeResult?.thoroughfare,
                crossStreets: vm.crossStreets.isEmpty ? nil : vm.crossStreets,
                phone: phone,
                phoneType: vm.isPhoneSelected ? vm.phoneType : nil,
                contactOk: vm.isPhoneSelected ? vm.contactOk : nil,
                email: !vm.isPhoneSelected ? vm.email : nil,
                deviceId: DeviceID.shared.id,
                routedTo: "woodside",
                photoUrls: photoURLs
            )

            let id = try await SupabaseService.shared.submitReport(report)
            vm.submittedReportID = id
            showSubmissionConfirmation = true
        } catch {
            vm.errorMessage = error.localizedDescription
        }

        vm.isSubmitting = false
    }
}

// MARK: - Contact Info Section (embedded in form)

struct ContactInfoSection: View {
    @Bindable var vm: ReportFormViewModel

    var body: some View {
        Section("Contact Information") {
            Toggle("Provide Phone Number", isOn: $vm.isPhoneSelected)

            if vm.isPhoneSelected {
                PhoneInputView(
                    dialCode: $vm.countryDialCode,
                    number: $vm.phone
                )

                Picker("Phone Type", selection: $vm.phoneType) {
                    Text("Cell Phone").tag("cell")
                    Text("Landline").tag("landline")
                }
                .pickerStyle(.segmented)

                if vm.phoneType == "cell" {
                    Toggle("OK to text or call for more info?", isOn: Binding(
                        get: { vm.contactOk ?? false },
                        set: { vm.contactOk = $0 }
                    ))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("We will call you if we need additional information.")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                        Toggle("That's okay with me", isOn: Binding(
                            get: { vm.contactOk ?? false },
                            set: { vm.contactOk = $0 }
                        ))
                    }
                }
            } else {
                TextField("Email Address (required)", text: $vm.email)
                    .textContentType(.emailAddress)
                    .keyboardType(.emailAddress)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)

                if !vm.email.isEmpty, let err = EmailValidator.errorMessage(for: vm.email) {
                    Label(err, systemImage: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
        }
        .listRowBackground(Color(.systemBackground).opacity(0.85))
    }
}
