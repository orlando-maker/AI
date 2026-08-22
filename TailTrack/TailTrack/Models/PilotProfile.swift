import Foundation

/// A certificate, rating, or endorsement the pilot holds —
/// e.g. "Private Pilot ASEL", "Instrument Airplane", "Type: CE-525",
/// "High Performance Endorsement".
struct RatingEntry: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String = ""
    var dateEarned: Date?
}

/// One step in the training checklist.
struct TrainingMilestone: Codable, Identifiable, Hashable {
    var id = UUID()
    var title: String
    var completed: Bool = false
    var date: Date?

    /// Standard private-pilot journey, used to seed the checklist.
    static func defaultSyllabus() -> [TrainingMilestone] {
        [
            "First lesson",
            "First landing",
            "Pre-solo written",
            "First solo",
            "First solo cross-country",
            "Long solo cross-country",
            "Night training complete",
            "FAA written passed",
            "Checkride passed",
        ].map { TrainingMilestone(title: $0) }
    }
}

/// The pilot's local profile card. Sign in with Apple attaches a stable
/// user identifier; everything else lives on-device.
struct PilotProfile: Codable {
    var name: String = ""
    /// Free-form certificate/ratings headline, e.g. "Student Pilot" or "PPL · IR".
    var certificateLine: String = ""
    var homeAirportIdent: String = ""
    var avatarFileName: String?
    var appleUserID: String?
    var ratings: [RatingEntry] = []
    var milestones: [TrainingMilestone] = TrainingMilestone.defaultSyllabus()

    var isSignedInWithApple: Bool { !(appleUserID ?? "").isEmpty }

    static let certificatePresets = [
        "Student Pilot",
        "Sport Pilot",
        "Private Pilot",
        "Private Pilot · Instrument",
        "Commercial Pilot",
        "Commercial · Instrument",
        "ATP",
        "CFI",
        "CFII",
    ]

    // Custom decoding so profiles saved by older builds (without ratings or
    // milestones) still load.
    enum CodingKeys: String, CodingKey {
        case name, certificateLine, homeAirportIdent, avatarFileName, appleUserID, ratings, milestones
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name = try c.decodeIfPresent(String.self, forKey: .name) ?? ""
        certificateLine = try c.decodeIfPresent(String.self, forKey: .certificateLine) ?? ""
        homeAirportIdent = try c.decodeIfPresent(String.self, forKey: .homeAirportIdent) ?? ""
        avatarFileName = try c.decodeIfPresent(String.self, forKey: .avatarFileName)
        appleUserID = try c.decodeIfPresent(String.self, forKey: .appleUserID)
        ratings = try c.decodeIfPresent([RatingEntry].self, forKey: .ratings) ?? []
        milestones = try c.decodeIfPresent([TrainingMilestone].self, forKey: .milestones)
            ?? TrainingMilestone.defaultSyllabus()
    }
}
