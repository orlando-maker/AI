import Foundation

struct StateRouteDetector {
    // Known state route names and identifiers in and around Woodside, CA.
    // Apple Maps may return different representations, so we check multiple forms.
    private static let stateRouteKeywords: [String] = [
        // CA-84
        "Woodside Road", "La Honda Road", "Kings Mountain Road",
        "CA-84", "Route 84", "SR-84", "Hwy 84", "Highway 84",
        // CA-35
        "Skyline Boulevard", "Skyline Blvd",
        "CA-35", "Route 35", "SR-35", "Hwy 35", "Highway 35",
        // I-280
        "Interstate 280", "I-280", "I280", "US-280",
    ]

    /// Returns true if `thoroughfare` matches any known state route or interstate.
    static func isStateRoute(_ thoroughfare: String?) -> Bool {
        guard let t = thoroughfare, !t.isEmpty else { return false }
        return stateRouteKeywords.contains {
            t.localizedCaseInsensitiveContains($0)
        }
    }

    static let caltransAlertMessage = """
        We cannot process requests for state roads or state highways, \
        as they are maintained by Caltrans.

        Please report this issue to Caltrans District 4 via their Customer \
        Service Request system at dot.ca.gov, or by sending a written request \
        to their district office by US mail.
        """
}
