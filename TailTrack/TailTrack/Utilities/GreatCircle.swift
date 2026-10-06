import Foundation
import CoreLocation

/// Great-circle math on a spherical Earth. Plenty accurate for GA planning
/// (errors are well under 0.5%).
enum GreatCircle {

    static let earthRadiusNM = 3440.065

    static func distanceNM(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let φ1 = a.latitude.radians, φ2 = b.latitude.radians
        let dφ = (b.latitude - a.latitude).radians
        let dλ = (b.longitude - a.longitude).radians
        let h = sin(dφ / 2) * sin(dφ / 2) + cos(φ1) * cos(φ2) * sin(dλ / 2) * sin(dλ / 2)
        return 2 * earthRadiusNM * asin(min(1, sqrt(h)))
    }

    /// Initial true course from a to b, degrees 0–360.
    static func initialBearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let φ1 = a.latitude.radians, φ2 = b.latitude.radians
        let dλ = (b.longitude - a.longitude).radians
        let y = sin(dλ) * cos(φ2)
        let x = cos(φ1) * sin(φ2) - sin(φ1) * cos(φ2) * cos(dλ)
        let θ = atan2(y, x).degrees
        return (θ + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Points along the great circle from a to b (inclusive), for drawing
    /// the planned route on the map.
    static func routePoints(from a: CLLocationCoordinate2D,
                            to b: CLLocationCoordinate2D,
                            count: Int = 48) -> [CLLocationCoordinate2D] {
        guard count >= 2 else { return [a, b] }
        let φ1 = a.latitude.radians, λ1 = a.longitude.radians
        let φ2 = b.latitude.radians, λ2 = b.longitude.radians

        let d = 2 * asin(min(1, sqrt(
            sin((φ2 - φ1) / 2) * sin((φ2 - φ1) / 2) +
            cos(φ1) * cos(φ2) * sin((λ2 - λ1) / 2) * sin((λ2 - λ1) / 2)
        )))
        guard d > 1e-9 else { return [a, b] }

        var pts: [CLLocationCoordinate2D] = []
        pts.reserveCapacity(count)
        for i in 0..<count {
            let f = Double(i) / Double(count - 1)
            let A = sin((1 - f) * d) / sin(d)
            let B = sin(f * d) / sin(d)
            let x = A * cos(φ1) * cos(λ1) + B * cos(φ2) * cos(λ2)
            let y = A * cos(φ1) * sin(λ1) + B * cos(φ2) * sin(λ2)
            let z = A * sin(φ1) + B * sin(φ2)
            let φ = atan2(z, sqrt(x * x + y * y))
            let λ = atan2(y, x)
            pts.append(CLLocationCoordinate2D(latitude: φ.degrees, longitude: λ.degrees))
        }
        return pts
    }
}

private extension Double {
    var radians: Double { self * .pi / 180 }
    var degrees: Double { self * 180 / .pi }
}
