import CoreLocation
import Foundation

struct ReverseGeocodeResult {
    let thoroughfare: String?    // street name
    let subThoroughfare: String? // house number
    let locality: String?        // city
    let formattedAddress: String
    let isStateRoute: Bool
}

enum GeocodingService {
    static func reverseGeocode(
        _ coordinate: CLLocationCoordinate2D
    ) async throws -> ReverseGeocodeResult {
        let location = CLLocation(latitude: coordinate.latitude,
                                  longitude: coordinate.longitude)
        let geocoder = CLGeocoder()

        let placemarks = try await withCheckedThrowingContinuation {
            (continuation: CheckedContinuation<[CLPlacemark], Error>) in
            geocoder.reverseGeocodeLocation(location) { placemarks, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: placemarks ?? [])
                }
            }
        }

        guard let placemark = placemarks.first else {
            throw GeocodingError.noResults
        }

        let thoroughfare = placemark.thoroughfare
        let formatted = [
            placemark.subThoroughfare,
            placemark.thoroughfare,
            placemark.locality,
            placemark.administrativeArea,
        ]
        .compactMap { $0 }
        .joined(separator: ", ")

        return ReverseGeocodeResult(
            thoroughfare: thoroughfare,
            subThoroughfare: placemark.subThoroughfare,
            locality: placemark.locality,
            formattedAddress: formatted.isEmpty ? "Unknown location" : formatted,
            isStateRoute: StateRouteDetector.isStateRoute(thoroughfare)
        )
    }
}

enum GeocodingError: LocalizedError {
    case noResults

    var errorDescription: String? {
        "Could not determine the address for this location."
    }
}
