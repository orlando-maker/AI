import MapKit
import SwiftUI

@Observable
final class MapViewModel {
    var cameraPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: Config.mapCenter,
            span: MKCoordinateSpan(
                latitudeDelta: Config.mapDefaultSpan,
                longitudeDelta: Config.mapDefaultSpan
            )
        )
    )
    var mapStyleKey: MapStyle = .standard
    var droppedPin: CLLocationCoordinate2D?
    var showPinConfirmation = false
    var showLocationPicker = false
    var lookAroundScene: MKLookAroundScene?
    var geocodeResult: ReverseGeocodeResult?
    var isGeocoding = false
    var boundaryCoordinates: [CLLocationCoordinate2D] = []

    init() {
        loadBoundary()
    }

    private func loadBoundary() {
        guard
            let url = Bundle.main.url(forResource: "woodside_boundary", withExtension: "geojson"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return }

        if let features = json["features"] as? [[String: Any]],
           let feature = features.first,
           let geometry = feature["geometry"] as? [String: Any],
           geometry["type"] as? String == "Polygon",
           let rings = geometry["coordinates"] as? [[[Double]]],
           let outer = rings.first {
            boundaryCoordinates = outer.compactMap { pair in
                guard pair.count >= 2 else { return nil }
                return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
            }
        }
    }
}

struct MainMapView: View {
    @State private var vm = MapViewModel()
    @State private var locationService = LocationService()
    @AppStorage("preferredMapStyle") private var mapStyleRaw = "standard"
    @State private var showCaltransAlert = false
    @State private var showOutsideBoundaryAlert = false
    @State private var pendingReportType: ReportType?
    @State private var showReportSheet = false
    @State private var confirmedCoordinate: CLLocationCoordinate2D?
    @State private var confirmedGeocode: ReverseGeocodeResult?
    @State private var locationError: String?

    var body: some View {
        ZStack(alignment: .topTrailing) {
            MapReader { proxy in
                Map(position: $vm.cameraPosition) {
                    if let pin = vm.droppedPin {
                        Marker("Report Location", coordinate: pin)
                            .tint(.red)
                    }
                    if vm.boundaryCoordinates.count >= 3 {
                        MapPolygon(coordinates: vm.boundaryCoordinates)
                            .foregroundStyle(.green.opacity(0.12))
                            .stroke(.green.opacity(0.55), lineWidth: 2)
                    }
                    UserAnnotation()
                }
                .mapStyle(currentMapStyle)
                .gesture(
                    LongPressGesture(minimumDuration: 0.5)
                        .sequenced(before: DragGesture(minimumDistance: 0))
                        .onEnded { value in
                            if case .second(true, let drag) = value,
                               let point = drag?.location,
                               let coord = proxy.convert(point, from: .local) {
                                vm.droppedPin = coord
                                vm.showPinConfirmation = true
                            }
                        }
                )
            }
            .ignoresSafeArea()

            // Map style + location toolbar overlay
            VStack(spacing: 8) {
                MapStylePicker(selection: $mapStyleRaw)
                Button {
                    Task { await goToCurrentLocation() }
                } label: {
                    Image(systemName: "location.fill")
                        .padding(10)
                        .background(.ultraThickMaterial)
                        .clipShape(Circle())
                }
            }
            .padding(.trailing, 12)
            .padding(.top, 12)
        }
        .navigationTitle("Woodside Trail Report")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Is this the correct location?", isPresented: $vm.showPinConfirmation) {
            Button("Yes") {
                Task { await confirmPin() }
            }
            Button("No", role: .cancel) { vm.droppedPin = nil }
        } message: {
            Text("Long-press a different spot to move the pin.")
        }
        .sheet(isPresented: $vm.showLocationPicker) {
            if let coord = vm.droppedPin {
                LocationPickerSheet(
                    coordinate: coord,
                    geocodeResult: vm.geocodeResult,
                    lookAroundScene: vm.lookAroundScene
                ) { confirmedCoord, geocode in
                    confirmedCoordinate = confirmedCoord
                    confirmedGeocode = geocode
                    showReportSheet = true
                }
            }
        }
        .sheet(isPresented: $showReportSheet) {
            if let coord = confirmedCoordinate {
                ReportTypePickerView(
                    coordinate: coord,
                    geocodeResult: confirmedGeocode
                ) {
                    // On dismiss, clear the pin
                    vm.droppedPin = nil
                    confirmedCoordinate = nil
                    confirmedGeocode = nil
                }
            }
        }
        .alert("State Route — Contact Caltrans", isPresented: $showCaltransAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(StateRouteDetector.caltransAlertMessage)
        }
        .alert("Location Error", isPresented: Binding(
            get: { locationError != nil },
            set: { if !$0 { locationError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(locationError ?? "")
        }
    }

    private var currentMapStyle: MapStyle {
        switch mapStyleRaw {
        case "imagery": return .imagery
        case "hybrid":  return .hybrid
        default:        return .standard
        }
    }

    private func confirmPin() async {
        guard let coord = vm.droppedPin else { return }
        vm.isGeocoding = true
        do {
            let result = try await GeocodingService.reverseGeocode(coord)
            vm.geocodeResult = result
            // Fetch Look Around scene concurrently
            let request = MKLookAroundSceneRequest(coordinate: coord)
            vm.lookAroundScene = try? await request.scene
        } catch {
            vm.geocodeResult = nil
        }
        vm.isGeocoding = false
        vm.showLocationPicker = true
    }

    private func goToCurrentLocation() async {
        do {
            let loc = try await locationService.requestCurrentLocation()
            withAnimation {
                vm.cameraPosition = .region(MKCoordinateRegion(
                    center: loc.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                ))
            }
        } catch {
            locationError = error.localizedDescription
        }
    }
}

// MARK: - Map Style Picker

struct MapStylePicker: View {
    @Binding var selection: String

    var body: some View {
        Menu {
            Button { selection = "standard" } label: {
                Label("Standard", systemImage: selection == "standard" ? "checkmark" : "map")
            }
            Button { selection = "imagery" } label: {
                Label("Satellite", systemImage: selection == "imagery" ? "checkmark" : "globe")
            }
            Button { selection = "hybrid" } label: {
                Label("Hybrid", systemImage: selection == "hybrid" ? "checkmark" : "map.fill")
            }
        } label: {
            Image(systemName: "map")
                .padding(10)
                .background(.ultraThickMaterial)
                .clipShape(Circle())
        }
    }
}
