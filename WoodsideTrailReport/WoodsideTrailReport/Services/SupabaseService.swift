import Foundation
import Supabase

// Central service for all Supabase operations. Use SupabaseService.shared throughout the app.
@Observable
final class SupabaseService {
    static let shared = SupabaseService()

    private let client: SupabaseClient
    private(set) var isAdminLoggedIn = false

    private init() {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .iso8601

        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601

        client = SupabaseClient(
            supabaseURL: Config.supabaseURL,
            supabaseKey: Config.supabaseAnonKey,
            options: SupabaseClientOptions(
                db: .init(encoder: encoder, decoder: decoder)
            )
        )
    }

    // MARK: - Public (anonymous) Operations

    func submitReport(_ report: NewReport) async throws -> UUID {
        let response: [Report] = try await client
            .from("reports")
            .insert(report)
            .select()
            .execute()
            .value
        guard let id = response.first?.id else {
            throw SupabaseAppError.noIDReturned
        }
        return id
    }

    func fetchMyReports(deviceID: UUID) async throws -> [Report] {
        let reports: [Report] = try await client
            .rpc("get_my_reports", params: ["p_device_id": deviceID.uuidString])
            .execute()
            .value
        return reports
    }

    func fetchTimeline(reportID: UUID) async throws -> [StatusHistoryEntry] {
        let entries: [StatusHistoryEntry] = try await client
            .rpc("get_report_timeline", params: ["p_report_id": reportID.uuidString])
            .execute()
            .value
        return entries
    }

    // MARK: - Photo Upload

    func uploadPhoto(_ jpegData: Data, reportID: UUID) async throws -> String {
        let path = "\(reportID.uuidString)/\(UUID().uuidString).jpg"
        _ = try await client.storage
            .from(Config.photosBucket)
            .upload(
                path,
                data: jpegData,
                options: FileOptions(contentType: "image/jpeg")
            )
        let publicURL = try client.storage
            .from(Config.photosBucket)
            .getPublicURL(path: path)
        return publicURL.absoluteString
    }

    // MARK: - Admin Authentication

    func adminSignIn(password: String) async throws {
        try await client.auth.signIn(
            email: Config.adminEmail,
            password: password
        )
        isAdminLoggedIn = true
    }

    func adminSignOut() async throws {
        try await client.auth.signOut()
        isAdminLoggedIn = false
    }

    // MARK: - Admin Operations (require authenticated session)

    func fetchAllReports() async throws -> [Report] {
        let reports: [Report] = try await client
            .from("reports")
            .select()
            .order("created_at", ascending: false)
            .execute()
            .value
        return reports
    }

    func addStatusEntry(reportID: UUID, stage: StatusStage, notes: String?) async throws {
        struct Payload: Encodable {
            let reportId: UUID
            let stage: String
            let notes: String?
        }
        let payload = Payload(reportId: reportID, stage: stage.rawValue, notes: notes)
        try await client
            .from("report_status_history")
            .insert(payload)
            .execute()

        // Also update the shorthand status column on the report for quick display.
        try await client
            .from("reports")
            .update(["status": stage.rawValue])
            .eq("id", value: reportID.uuidString)
            .execute()
    }

    func deleteReport(_ reportID: UUID) async throws {
        try await client
            .from("reports")
            .delete()
            .eq("id", value: reportID.uuidString)
            .execute()
    }
}

enum SupabaseAppError: LocalizedError {
    case noIDReturned

    var errorDescription: String? {
        "Submission succeeded but no confirmation ID was returned. Please try again."
    }
}
