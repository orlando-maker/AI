import Foundation
import CoreLocation

/// One airport row, sourced from the OurAirports public-domain dataset
/// (or the bundled starter list).
struct Airport: Codable, Identifiable, Hashable {
    let ident: String        // ICAO/GPS code, e.g. KSQL
    let name: String
    let latitude: Double
    let longitude: Double
    let elevationFt: Int?
    let iata: String?
    let municipality: String?
    let region: String?      // ISO region, e.g. US-CA
    let kind: String?        // small_airport / medium_airport / large_airport / seaplane_base

    var id: String { ident }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    /// "San Carlos, US-CA" style secondary line.
    var locationDescription: String {
        [municipality, region].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }
}
