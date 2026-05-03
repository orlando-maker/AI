import Foundation

struct EmailValidator {
    // RFC 5322 simplified pattern — covers all real-world email formats.
    private static let pattern =
        #"^[A-Z0-9a-z._%+\-]+@[A-Za-z0-9.\-]+\.[A-Za-z]{2,}$"#

    // Well-known disposable / throwaway email domains.
    private static let blocklist: Set<String> = [
        "mailinator.com", "guerrillamail.com", "guerrillamailblock.com",
        "throwaway.email", "tempmail.com", "10minutemail.com", "yopmail.com",
        "sharklasers.com", "grr.la", "trashmail.com", "dispostable.com",
        "fakeinbox.com", "maildrop.cc", "spamgourmet.com", "trashmail.at",
        "discard.email", "getairmail.com", "mailnull.com", "spamcorpse.com",
        "deadaddress.com", "trashmail.io", "getnada.com", "spamex.com",
    ]

    static func isValid(_ email: String) -> Bool {
        guard email.range(of: pattern, options: .regularExpression) != nil else {
            return false
        }
        let domain = email.components(separatedBy: "@").last?.lowercased() ?? ""
        return !blocklist.contains(domain)
    }

    static func errorMessage(for email: String) -> String? {
        if email.isEmpty { return "Email address is required." }
        if email.range(of: pattern, options: .regularExpression) == nil {
            return "Please enter a valid email address."
        }
        let domain = email.components(separatedBy: "@").last?.lowercased() ?? ""
        if blocklist.contains(domain) {
            return "Please use a permanent email address."
        }
        return nil
    }
}
