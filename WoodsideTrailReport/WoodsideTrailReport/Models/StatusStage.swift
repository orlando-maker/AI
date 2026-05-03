import SwiftUI

enum StatusStage: String, CaseIterable, Codable, Identifiable, Hashable {
    var id: String { rawValue }

    case created    = "created"
    case opened     = "opened"
    case forwarded  = "forwarded"
    case inProgress = "in_progress"
    case completed  = "completed"
    case closed     = "closed"

    var label: String {
        switch self {
        case .created:    return "Request Created"
        case .opened:     return "Request Opened"
        case .forwarded:  return "Forwarded to Department"
        case .inProgress: return "Work Started"
        case .completed:  return "Work Completed"
        case .closed:     return "Request Closed"
        }
    }

    var sublabel: String {
        switch self {
        case .created:    return "The correct team has been notified."
        case .opened:     return "Your request is under review."
        case .forwarded:  return "Routed to the appropriate department."
        case .inProgress: return "Work on this request has begun."
        case .completed:  return "The reported issue has been addressed."
        case .closed:     return "This request has been closed."
        }
    }

    var sfSymbol: String {
        switch self {
        case .created:    return "checkmark.circle.fill"
        case .opened:     return "folder.fill"
        case .forwarded:  return "arrow.right.circle.fill"
        case .inProgress: return "wrench.and.screwdriver.fill"
        case .completed:  return "checkmark.seal.fill"
        case .closed:     return "archivebox.fill"
        }
    }

    var color: Color {
        switch self {
        case .created:    return .blue
        case .opened:     return .orange
        case .forwarded:  return .purple
        case .inProgress: return .yellow
        case .completed:  return .green
        case .closed:     return .gray
        }
    }

    // Admin-facing display options (excludes created — that's automatic).
    static var adminOptions: [StatusStage] {
        [.opened, .forwarded, .inProgress, .completed, .closed]
    }
}
