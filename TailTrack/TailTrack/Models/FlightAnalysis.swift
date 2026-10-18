import Foundation

/// Post-flight analysis: landing detection, pattern-work recognition, and
/// the auto-generated flight story. All of it is recorded data presented
/// back to the pilot — never instruction, and landing counts always go
/// through pilot confirmation before they're stored.
extension Flight {

    /// Conservative landing count from track transitions (airborne → on
    /// ground). ADS-B gets patchy at pattern altitude, so this is a
    /// suggestion for the pilot to confirm, not a silent logbook entry.
    var detectedLandings: Int {
        var count = 0
        var airborne = false
        for point in track {
            if !point.onGround {
                airborne = true
            } else if airborne {
                count += 1
                airborne = false
            }
        }
        if airborne && landingTime != nil { count += 1 }
        if count == 0 && landingTime != nil { count = 1 }
        return count
    }

    /// Same field out and back with multiple landings → pattern work.
    var isLikelyPatternWork: Bool {
        guard let dep = departure?.ident, let dest = destination?.ident else { return false }
        return dep == dest && (landingsCount ?? detectedLandings) >= 2
    }

    /// "Departed San Carlos at 9:12 AM, climbed to 4,500 ft, flew 62 nm,
    /// hit 126 kt over the ground, landed at Monterey at 10:01 AM."
    var story: String {
        var parts: [String] = []

        if let takeoffTime {
            let name = departure?.municipality ?? departure?.ident ?? "the field"
            parts.append("departed \(name) at \(Format.localTime(takeoffTime))")
        }
        if let maxAlt = maxAltitudeFt, maxAlt > 100 {
            parts.append("climbed to \(Format.feet(maxAlt))")
        }
        let distance = track.isEmpty ? (routeDistanceNM ?? 0) : distanceFlownNM
        if distance > 1 {
            parts.append("flew \(Format.nm(distance))")
        }
        if let maxGS = maxGroundSpeedKt, maxGS > 20 {
            parts.append("hit \(Format.knots(maxGS)) over the ground")
        }
        if isLikelyPatternWork, let field = destination?.ident {
            parts.append("logged \((landingsCount ?? detectedLandings)) landings in the pattern at \(field)")
        }
        if let landingTime {
            let name = destination?.municipality ?? destination?.ident ?? "the destination"
            parts.append("landed at \(name) at \(Format.localTime(landingTime))")
        }

        guard !parts.isEmpty else { return "A flight in \(tailNumber)." }
        var text = "\(tailNumber) " + parts.joined(separator: ", ") + "."
        if let planned = plannedDestinationIdent {
            text += " Planned for \(planned) — diverted."
        }
        return text
    }
}
