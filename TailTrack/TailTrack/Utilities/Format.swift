import Foundation

/// Aviation-flavored display formatting.
enum Format {

    /// 5430 s → "1h 30m"; 95 s → "1m 35s" under an hour.
    static func duration(_ interval: TimeInterval) -> String {
        let total = Int(interval.rounded())
        let h = total / 3600
        let m = (total % 3600) / 60
        let s = total % 60
        if h > 0 { return "\(h)h \(m)m" }
        if m > 0 { return "\(m)m \(s)s" }
        return "\(s)s"
    }

    /// Hours as a logbook decimal, e.g. "1.5 h".
    static func logbookHours(_ interval: TimeInterval) -> String {
        String(format: "%.1f h", interval / 3600)
    }

    /// Always the phone's local time: for things people outside the
    /// cockpit read, like a shared flight story.
    static func localTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }

    /// The pilot's chosen clock (Settings → Customize): local "2:30 PM" or
    /// Zulu "14:30Z".
    static func clockTime(_ date: Date) -> String {
        switch Customization.shared.clock {
        case .local: return localTime(date)
        case .zulu: return zuluFormatter.string(from: date) + "Z"
        }
    }

    private static let zuluFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    static func dayAndTime(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .shortened)
    }

    static func nm(_ value: Double) -> String {
        value >= 100 ? String(format: "%.0f nm", value) : String(format: "%.1f nm", value)
    }

    static func knots(_ value: Double) -> String {
        String(format: "%.0f kt", value)
    }

    static func feet(_ value: Double) -> String {
        let rounded = (value / 25).rounded() * 25
        return "\(Int(rounded).formatted()) ft"
    }

    static func fpm(_ value: Double) -> String {
        let rounded = Int((value / 25).rounded() * 25)
        return rounded > 0 ? "+\(rounded) fpm" : "\(rounded) fpm"
    }

    static func degrees(_ value: Double) -> String {
        String(format: "%03.0f°", value)
    }

    /// "4s ago" / "2m 05s ago" style staleness label.
    static func age(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total)s ago" }
        return String(format: "%dm %02ds ago", total / 60, total % 60)
    }
}
