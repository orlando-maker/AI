import Foundation

/// Deterministic mapping between US registration numbers (N-numbers) and
/// ICAO 24-bit Mode S addresses. The FAA assigns the US block A00001–ADF7C7
/// sequentially over the ordered space of valid N-numbers, so the transponder
/// hex code of a US aircraft can be computed offline from its tail number.
///
/// Letters I and O are never used in N-numbers. Letters may only appear as the
/// final one or two characters, and a 5-character body allows any single
/// trailing character.
enum NNumber {

    private static let charset: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ") // 24 letters, no I/O
    private static let allChars: [Character] = Array("ABCDEFGHJKLMNPQRSTUVWXYZ0123456789")

    // Sizes of the allocation buckets. suffixSize = 1 + 24*25; each bucketN
    // covers everything that can follow the Nth digit.
    private static let suffixSize = 601
    private static let bucket4Size = 35      // 1 + 24 + 10
    private static let bucket3Size = 951     // 10*35 + 601
    private static let bucket2Size = 10111   // 10*951 + 601
    private static let bucket1Size = 101711  // 10*10111 + 601

    private static let usBlockLast = 0xDF7C7 // offset of ADF7C7 (N99999)

    private static let validPattern = try! NSRegularExpression(
        pattern: "^N[1-9]([0-9]{0,4}|[0-9]{0,3}[A-HJ-NP-Z]|[0-9]{0,2}[A-HJ-NP-Z]{2})$"
    )

    /// Normalizes user input like "n1234c " or "1234C" to "N1234C".
    /// The N prefix is only added when the result is a valid US N-number,
    /// so non-US registrations (G-ABCD, D-EABC, VH-XYZ…) pass through
    /// untouched.
    static func normalize(_ raw: String) -> String {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !s.isEmpty, !s.hasPrefix("N") else { return s }
        let candidate = "N" + s
        return matchesPattern(candidate) ? candidate : s
    }

    static func isValid(_ tailNumber: String) -> Bool {
        matchesPattern(normalize(tailNumber))
    }

    private static func matchesPattern(_ s: String) -> Bool {
        let range = NSRange(s.startIndex..., in: s)
        return validPattern.firstMatch(in: s, range: range) != nil
    }

    /// N-number → ICAO hex (lowercase, e.g. "a061be" for N1234C).
    /// Returns nil for anything that is not a valid US registration.
    static func icaoHex(for tailNumber: String) -> String? {
        let tail = normalize(tailNumber)
        guard isValid(tail) else { return nil }
        let body = Array(tail.dropFirst())
        var count = 1
        loop: for (i, c) in body.enumerated() {
            if i == 4 {
                guard let idx = allChars.firstIndex(of: c) else { return nil }
                count += idx + 1
            } else if charset.contains(c) {
                guard let off = suffixOffset(Array(body[i...])) else { return nil }
                count += off
                break loop
            } else {
                guard let d = c.wholeNumberValue else { return nil }
                switch i {
                case 0: count += (d - 1) * bucket1Size
                case 1: count += d * bucket2Size + suffixSize
                case 2: count += d * bucket3Size + suffixSize
                case 3: count += d * bucket4Size + suffixSize
                default: return nil
                }
            }
        }
        return String(format: "a%05x", count)
    }

    /// ICAO hex → N-number for addresses inside the US block, else nil.
    static func tailNumber(forICAOHex hexString: String) -> String? {
        let h = hexString.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard h.count == 6, h.hasPrefix("a"), let value = Int(h.dropFirst(), radix: 16),
              value >= 1, value <= usBlockLast else { return nil }
        var i = value - 1
        var out = "N"

        let d1 = i / bucket1Size + 1
        guard d1 <= 9 else { return nil }
        out += String(d1)
        i %= bucket1Size
        if i < suffixSize { return out + suffix(at: i) }

        i -= suffixSize
        out += String(i / bucket2Size)
        i %= bucket2Size
        if i < suffixSize { return out + suffix(at: i) }

        i -= suffixSize
        out += String(i / bucket3Size)
        i %= bucket3Size
        if i < suffixSize { return out + suffix(at: i) }

        i -= suffixSize
        out += String(i / bucket4Size)
        i %= bucket4Size
        if i == 0 { return out }
        return out + String(allChars[i - 1])
    }

    // MARK: - Suffix helpers (0–2 trailing letters)

    private static func suffix(at offset: Int) -> String {
        guard offset > 0 else { return "" }
        let i0 = (offset - 1) / (charset.count + 1)
        let rem = (offset - 1) % (charset.count + 1)
        let c0 = String(charset[i0])
        return rem == 0 ? c0 : c0 + String(charset[rem - 1])
    }

    private static func suffixOffset(_ s: [Character]) -> Int? {
        if s.isEmpty { return 0 }
        guard s.count <= 2, let i0 = charset.firstIndex(of: s[0]) else { return nil }
        var count = (charset.count + 1) * i0 + 1
        if s.count == 2 {
            guard let i1 = charset.firstIndex(of: s[1]) else { return nil }
            count += i1 + 1
        }
        return count
    }
}
