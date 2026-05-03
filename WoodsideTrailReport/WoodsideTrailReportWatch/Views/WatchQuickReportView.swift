import CoreLocation
import SwiftUI

struct WatchQuickReportView: View {
    @State private var selectedType: ReportType = .trailDamage
    @State private var isSubmitting = false
    @State private var submitted = false
    @State private var errorMessage: String?
    @State private var locationManager = WatchLocationManager()

    // Types available on Watch (exclude emergency and feedback — those need iPhone).
    private let watchTypes: [ReportType] = [
        .trailDamage, .streetSignDamage, .laneMarking,
        .roadwayDamage, .horseTrailGate, .illegallyParked,
    ]

    var body: some View {
        NavigationStack {
            if submitted {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 36))
                        .foregroundStyle(.green)
                    Text("Submitted!")
                        .font(.headline)
                    Text("Open the iPhone app to add details.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .navigationTitle("Done")
            } else {
                Form {
                    Section("Type") {
                        Picker("Report Type", selection: $selectedType) {
                            ForEach(watchTypes) { type in
                                Text(type.displayName).tag(type)
                            }
                        }
                        .labelsHidden()
                    }

                    Section {
                        Button {
                            Task { await submit() }
                        } label: {
                            if isSubmitting {
                                ProgressView()
                                    .frame(maxWidth: .infinity)
                            } else {
                                Label("Submit", systemImage: "arrow.up.circle.fill")
                                    .font(.headline)
                            }
                        }
                        .disabled(isSubmitting)
                        .tint(.green)
                    }

                    if let err = errorMessage {
                        Text(err)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }
                }
                .navigationTitle("Quick Report")
            }
        }
    }

    private func submit() async {
        isSubmitting = true
        errorMessage = nil

        // Attempt to get GPS location from Watch.
        let coordinate = await locationManager.requestOneShotLocation()

        let report = NewReport(
            type: selectedType.rawValue,
            description: "Submitted via Apple Watch — details pending on iPhone.",
            locationLat: coordinate?.latitude ?? Config.mapCenter.latitude,
            locationLng: coordinate?.longitude ?? Config.mapCenter.longitude,
            nearestStreet: nil,
            crossStreets: nil,
            phone: nil,
            phoneType: nil,
            contactOk: nil,
            email: nil,
            deviceId: DeviceID.shared.id,
            routedTo: "woodside",
            photoUrls: []
        )

        do {
            _ = try await SupabaseService.shared.submitReport(report)
            submitted = true
        } catch {
            errorMessage = "Submit failed. Check iPhone app."
        }

        isSubmitting = false
    }
}

// Minimal CLLocationManager for one-shot Watch GPS.
@Observable
final class WatchLocationManager: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocation?, Never>?

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func requestOneShotLocation() async -> CLLocationCoordinate2D? {
        guard manager.authorizationStatus != .denied,
              manager.authorizationStatus != .restricted else { return nil }

        if manager.authorizationStatus == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }

        let location: CLLocation? = await withCheckedContinuation { cont in
            continuation = cont
            manager.requestLocation()
        }
        return location?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.last)
        continuation = nil
        manager.stopUpdatingLocation()
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: nil)
        continuation = nil
    }
}
