import Foundation

enum ReportType: String, CaseIterable, Identifiable, Codable {
    case trailDamage      = "trail_damage"
    case streetSignDamage = "street_sign_damage"
    case laneMarking      = "lane_marking"
    case roadwayDamage    = "roadway_damage"
    case horseTrailGate   = "horse_trail_gate"
    case illegallyParked  = "illegally_parked"
    case vehicleCollision = "vehicle_collision"
    case generalFeedback  = "general_feedback"

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .trailDamage:      return "Trail Damage"
        case .streetSignDamage: return "Street Sign Damage"
        case .laneMarking:      return "Lane Marking Issue"
        case .roadwayDamage:    return "Roadway Damage"
        case .horseTrailGate:   return "Horse Trail Gate"
        case .illegallyParked:  return "Illegally Parked Vehicle"
        case .vehicleCollision: return "Vehicle Collision / Emergency"
        case .generalFeedback:  return "General Feedback"
        }
    }

    var icon: String {
        switch self {
        case .trailDamage:      return "figure.hiking"
        case .streetSignDamage: return "signpost.right"
        case .laneMarking:      return "road.lanes"
        case .roadwayDamage:    return "exclamationmark.triangle"
        case .horseTrailGate:   return "fence.fill"
        case .illegallyParked:  return "car.fill"
        case .vehicleCollision: return "phone.fill"
        case .generalFeedback:  return "bubble.left"
        }
    }

    // Vehicle collision routes to 911; does not open the report form.
    var isEmergencyRoute: Bool { self == .vehicleCollision }

    // These types are blocked when the location is on a state route.
    var isStateRouteBlocked: Bool {
        switch self {
        case .trailDamage, .streetSignDamage, .laneMarking, .roadwayDamage:
            return true
        default:
            return false
        }
    }

    var horseTrailNote: String? {
        guard self == .horseTrailGate else { return nil }
        return "Horse trail gate issues are managed by the Woodside Horse Trail Club."
    }
}
