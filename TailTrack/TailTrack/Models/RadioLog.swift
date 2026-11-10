import Foundation

/// One line in a flight's radio log: something heard on, or set from, the
/// radio. Some lines write themselves (the transponder code from ADS-B,
/// the ATIS letter); the rest the pilot taps in.
struct RadioLogEntry: Codable, Identifiable, Hashable {
    enum Kind: String, Codable, CaseIterable, Identifiable {
        case atis, frequency, clearance, squawk, altimeter, note

        var id: String { rawValue }

        var label: String {
            switch self {
            case .atis: return "ATIS"
            case .frequency: return "Frequency"
            case .clearance: return "Clearance"
            case .squawk: return "Squawk"
            case .altimeter: return "Altimeter"
            case .note: return "Note"
            }
        }

        var symbol: String {
            switch self {
            case .atis: return "headphones"
            case .frequency: return "dot.radiowaves.left.and.right"
            case .clearance: return "checkmark.seal"
            case .squawk: return "number.square"
            case .altimeter: return "gauge.with.dots.needle.33percent"
            case .note: return "square.and.pencil"
            }
        }
    }

    var id = UUID()
    var time: Date
    var kind: Kind
    var text: String
    var detail: String?
    /// Written by TailTrack from ADS-B or the ATIS feed, not typed in.
    var isAutomatic = false
    var latitude: Double?
    var longitude: Double?
    var altitudeFt: Double?
}

/// Transponder codes, as a pilot reads them.
enum Squawk {
    /// Four octal digits: each is 0–7.
    static func isValid(_ code: String) -> Bool {
        code.count == 4 && code.allSatisfy { ("0"..."7").contains($0) }
    }

    static func meaning(_ code: String) -> String {
        switch code {
        case "1200": return "VFR, not talking to ATC"
        case "7500": return "Unlawful interference code"
        case "7600": return "Radio failure code"
        case "7700": return "Emergency code"
        case "1202": return "VFR glider"
        case "1255": return "Firefighting"
        case "1277": return "Search and rescue"
        default: return "Discrete code from ATC: flight following or a clearance"
        }
    }

    static func isEmergency(_ code: String) -> Bool {
        ["7500", "7600", "7700"].contains(code)
    }
}

/// A live audio feed the pilot owns or has permission to use, such as
/// their own airband receiver (RTLSDR-Airband on a Raspberry Pi, streaming
/// through Icecast).
struct RadioStream: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var url: URL
}
