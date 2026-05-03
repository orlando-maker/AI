import CoreLocation
import Foundation

// Parses the bundled woodside_boundary.geojson and answers point-in-polygon queries
// using the ray-casting algorithm.
final class BoundaryChecker {
    static let shared: BoundaryChecker = {
        BoundaryChecker(geoJSONName: "woodside_boundary") ?? BoundaryChecker()
    }()

    private let polygon: [(lat: Double, lng: Double)]

    // Fallback: empty polygon — all locations pass (advisory only, not blocking).
    private init() {
        polygon = []
    }

    init?(geoJSONName: String) {
        guard
            let url = Bundle.main.url(forResource: geoJSONName, withExtension: "geojson"),
            let data = try? Data(contentsOf: url),
            let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        polygon = Self.extractPolygon(from: json) ?? []
        if polygon.isEmpty { return nil }
    }

    private static func extractPolygon(from json: [String: Any]) -> [(lat: Double, lng: Double)]? {
        // Support both FeatureCollection and single Feature/Geometry.
        if let features = json["features"] as? [[String: Any]],
           let first = features.first {
            return extractFromFeature(first)
        }
        if let type = json["type"] as? String, type == "Feature" {
            return extractFromFeature(json)
        }
        if let type = json["type"] as? String, type == "Polygon" {
            return coordsFromGeometry(json)
        }
        return nil
    }

    private static func extractFromFeature(_ feature: [String: Any]) -> [(lat: Double, lng: Double)]? {
        guard let geometry = feature["geometry"] as? [String: Any] else { return nil }
        return coordsFromGeometry(geometry)
    }

    private static func coordsFromGeometry(_ geometry: [String: Any]) -> [(lat: Double, lng: Double)]? {
        guard
            let type = geometry["type"] as? String,
            type == "Polygon",
            let rings = geometry["coordinates"] as? [[[Double]]],
            let outer = rings.first
        else { return nil }

        return outer.compactMap { pair in
            guard pair.count >= 2 else { return nil }
            // GeoJSON stores coordinates as [longitude, latitude].
            return (lat: pair[1], lng: pair[0])
        }
    }

    // Ray-casting point-in-polygon. Returns true if inside or on boundary.
    func contains(_ coordinate: CLLocationCoordinate2D) -> Bool {
        guard polygon.count >= 3 else { return true } // open boundary = all pass
        let x = coordinate.longitude
        let y = coordinate.latitude
        var inside = false
        var j = polygon.count - 1
        for i in 0 ..< polygon.count {
            let xi = polygon[i].lng, yi = polygon[i].lat
            let xj = polygon[j].lng, yj = polygon[j].lat
            if ((yi > y) != (yj > y)) && (x < (xj - xi) * (y - yi) / (yj - yi) + xi) {
                inside.toggle()
            }
            j = i
        }
        return inside
    }
}
