import Foundation

// Full report as returned from Supabase SELECT.
struct Report: Codable, Identifiable, Hashable {
    let id: UUID
    let createdAt: Date
    let type: String
    let description: String?
    let locationLat: Double
    let locationLng: Double
    let nearestStreet: String?
    let crossStreets: String?
    let phone: String?
    let phoneType: String?
    let contactOk: Bool?
    let email: String?
    let status: String
    let deviceId: UUID
    let routedTo: String?
    let photoUrls: [String]

    var reportType: ReportType? { ReportType(rawValue: type) }
    var statusStage: StatusStage { StatusStage(rawValue: status) ?? .created }
}

// Payload for inserting a new report — omits server-generated fields.
struct NewReport: Encodable {
    let type: String
    let description: String
    let locationLat: Double
    let locationLng: Double
    let nearestStreet: String?
    let crossStreets: String?
    let phone: String?
    let phoneType: String?
    let contactOk: Bool?
    let email: String?
    let deviceId: UUID
    let routedTo: String?
    let photoUrls: [String]
}

// One entry in the shipping-style status timeline.
struct StatusHistoryEntry: Codable, Identifiable {
    let id: UUID
    let reportId: UUID
    let stage: String
    let updatedAt: Date
    let notes: String?

    var statusStage: StatusStage { StatusStage(rawValue: stage) ?? .created }
}
