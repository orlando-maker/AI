import MapKit
import SwiftUI

struct LocationPickerSheet: View {
    let coordinate: CLLocationCoordinate2D
    let geocodeResult: ReverseGeocodeResult?
    let lookAroundScene: MKLookAroundScene?
    let onConfirm: (CLLocationCoordinate2D, ReverseGeocodeResult?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showLookAround = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Mini static map thumbnail
                Map(
                    position: .constant(.region(MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
                    )))
                ) {
                    Marker("Selected", coordinate: coordinate).tint(.red)
                }
                .frame(height: 200)
                .disabled(true)
                .overlay(alignment: .bottomTrailing) {
                    if lookAroundScene != nil {
                        Button {
                            showLookAround = true
                        } label: {
                            Label("Look Around", systemImage: "binoculars.fill")
                                .font(.caption.bold())
                                .padding(8)
                                .background(.ultraThinMaterial)
                                .clipShape(Capsule())
                        }
                        .padding(8)
                    }
                }

                // Address info
                VStack(alignment: .leading, spacing: 8) {
                    if let result = geocodeResult {
                        Label(result.formattedAddress, systemImage: "mappin.circle.fill")
                            .font(.subheadline.bold())
                        if result.isStateRoute {
                            Label(
                                "This appears to be a state route. Certain report types will be redirected to Caltrans.",
                                systemImage: "exclamationmark.triangle.fill"
                            )
                            .font(.footnote)
                            .foregroundStyle(.orange)
                        }
                    } else {
                        Label("Determining address…", systemImage: "mappin.circle")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    HStack(spacing: 4) {
                        Text("Coordinates:")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text(String(format: "%.5f, %.5f",
                                    coordinate.latitude,
                                    coordinate.longitude))
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()

                Spacer()

                // Action buttons
                VStack(spacing: 10) {
                    Button {
                        onConfirm(coordinate, geocodeResult)
                        dismiss()
                    } label: {
                        Label("Confirm Location", systemImage: "checkmark.circle.fill")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(.green)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button(role: .cancel) {
                        dismiss()
                    } label: {
                        Text("Choose a Different Location")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("Confirm Location")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .sheet(isPresented: $showLookAround) {
            if let scene = lookAroundScene {
                LookAroundPreview(initialScene: scene)
                    .ignoresSafeArea()
                    .overlay(alignment: .topLeading) {
                        Button {
                            showLookAround = false
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.title2)
                                .foregroundStyle(.white)
                                .padding()
                        }
                    }
            }
        }
    }
}
