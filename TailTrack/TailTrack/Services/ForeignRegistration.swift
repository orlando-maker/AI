import Foundation

/// Registrations from TailTrack's neighbors: Canada, Mexico, Central
/// America, the Caribbean and Bermuda. (Guam, the Northern Marianas, Puerto
/// Rico and the US Virgin Islands are on the US register, so they're plain
/// N-numbers.)
enum ForeignRegistration {

    /// Prefix rules: the nationality mark, then the letters that follow
    /// its hyphen.
    private static let rules: [(pattern: String, prefixLength: Int)] = [
        ("^C[FGI][A-Z]{3}$", 1),          // Canada: C-FABC, C-GABC, C-IABC
        ("^X[ABC][A-Z]{3}$", 2),          // Mexico: XA-, XB-, XC-
        ("^V[PQ][A-Z]{3}$", 2),           // British territories: VP-C Cayman, VP-B/VQ-B Bermuda, VQ-T Turks & Caicos
        // Bahamas, Jamaica, Trinidad, Barbados, Guyana, Antigua, Belize, St Kitts,
        // Grenada, St Lucia, Dominica, St Vincent, Haiti, Aruba, Curaçao/St Maarten,
        // Suriname, Panama, Costa Rica, Nicaragua, Guatemala, El Salvador, Honduras
        ("^(C6|6Y|9Y|8P|8R|V2|V3|V4|J3|J6|J7|J8|HH|P4|PJ|PZ|HP|TI|YN|TG|YS|HR)[A-Z]{3}$", 2),
    ]

    /// Adds the hyphen people often skip when typing: "CFABC" → "C-FABC",
    /// "XAABC" → "XA-ABC", "C6ABC" → "C6-ABC". Anything else, including
    /// registrations already hyphenated, passes through unchanged.
    static func hyphenated(_ registration: String) -> String {
        for rule in rules where registration.range(of: rule.pattern, options: .regularExpression) != nil {
            let split = registration.index(registration.startIndex, offsetBy: rule.prefixLength)
            return String(registration[..<split]) + "-" + String(registration[split...])
        }
        return registration
    }

    /// Canada's C-F and C-G blocks follow a regular pattern: C-FAAA is
    /// C00001 and each later registration is the next code, 26 letters per
    /// place, with C-G picking up right after C-FZZZ. The pattern was worked
    /// out by the open-source tar1090 project from observed aircraft, so
    /// it's only used where nothing better exists (looking up past flights),
    /// never to steer live tracking.
    static func canadianHex(for registration: String) -> String? {
        let reg = registration.uppercased()
        let start: Int
        if reg.hasPrefix("C-F") {
            start = 0xC00001
        } else if reg.hasPrefix("C-G") {
            start = 0xC044A9
        } else {
            return nil
        }
        let letters = Array(reg.dropFirst(3))
        let values = letters.compactMap { $0.asciiValue.map { Int($0) - 65 } }
        guard letters.count == 3, values.count == 3,
              values.allSatisfy({ (0..<26).contains($0) }) else { return nil }
        return String(format: "%06x", start + values[0] * 676 + values[1] * 26 + values[2])
    }
}
