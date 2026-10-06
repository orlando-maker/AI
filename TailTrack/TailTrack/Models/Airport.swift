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
        [municipality, regionDescription].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: ", ")
    }

    /// OurAirports region codes, read the way a pilot would say them:
    /// "US-CA" → "CA", "CA-BC" → "BC, Canada", "MP-U-A" → "Northern Mariana
    /// Islands", "BS-NP" → "Bahamas". Country names come from the system,
    /// so they follow the phone's language.
    var regionDescription: String? {
        guard let region, !region.isEmpty else { return nil }
        let parts = region.split(separator: "-", maxSplits: 1).map(String.init)
        let country = parts[0]
        let subdivision = parts.count > 1 ? parts[1] : ""
        if country == "US" { return subdivision.isEmpty ? "USA" : subdivision }
        let countryName = Locale.current.localizedString(forRegionCode: country) ?? country
        if country == "CA", !subdivision.isEmpty { return "\(subdivision), \(countryName)" }
        return countryName
    }
}
