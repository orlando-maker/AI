import CoreLocation
import Foundation

enum Config {
    // MARK: - Supabase (fill in after creating your Supabase project)
    static let supabaseURL = URL(string: "https://YOUR_PROJECT.supabase.co")!
    static let supabaseAnonKey = "YOUR_ANON_KEY"

    // MARK: - Admin (credentials validated by Supabase Auth over HTTPS)
    static let adminEmail = "admin@orlandonell.com"
    static let adminPassword = "adminisadmyn123"
    static let adminGateCode = "511"
    static let adminGateTapCount = 5

    // MARK: - Map
    // Downtown Woodside, CA — centered near Woodside Center / Town Hall area
    static let mapCenter = CLLocationCoordinate2D(latitude: 37.4291, longitude: -122.2538)
    static let mapDefaultSpan = 0.05 // degrees (~3 miles)

    // MARK: - Emergency contacts
    // San Mateo County Sheriff non-emergency — press 1 for dispatcher
    static let sheriffNonEmergencyPhone = "6503634911"
    static let sheriffNonEmergencyFormatted = "(650) 363-4911"

    // MARK: - Support
    static let supportEmail = "support@orlandonell.com"
    static let websiteURL = URL(string: "https://orlandonell.com")!

    // MARK: - Storage
    static let photosBucket = "report-photos"

    // MARK: - App Group (shared between iOS and watchOS targets)
    static let appGroupID = "group.com.orlandonell.woodside"
}
