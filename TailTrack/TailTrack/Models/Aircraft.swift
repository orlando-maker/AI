import Foundation

/// A saved aircraft in the user's fleet.
struct Aircraft: Codable, Identifiable, Hashable {
    var id = UUID()
    var tailNumber: String = ""       // e.g. N1234C
    var typeCode: String = ""         // ICAO type designator, e.g. C152
    var nickname: String = ""
    var cruiseSpeedKt: Double = 110   // planning true airspeed
    var icaoHexOverride: String = ""  // manual Mode S hex for non-US or edge cases
    var photoFileName: String?        // user-uploaded photo of the aircraft
    var homeAirportIdent: String?     // where this plane lives (great for rentals)

    /// The Mode S hex used for ADS-B lookups: manual override if set,
    /// otherwise computed from the US N-number.
    var resolvedHex: String? {
        let override = icaoHexOverride.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if !override.isEmpty { return override }
        return NNumber.icaoHex(for: tailNumber)
    }

    var displayName: String {
        nickname.isEmpty ? NNumber.normalize(tailNumber) : nickname
    }

    var subtitle: String {
        let type = typeCode.isEmpty ? "Unknown type" : typeCode
        return nickname.isEmpty ? type : "\(NNumber.normalize(tailNumber)) · \(type)"
    }
}

/// Built-in performance presets for common GA types, used to pre-fill
/// cruise speed when adding an aircraft. Values are typical cruise TAS.
enum AircraftLibrary {
    struct Preset: Identifiable, Hashable {
        let typeCode: String
        let name: String
        let cruiseKt: Double
        var id: String { typeCode }
    }

    static let presets: [Preset] = [
        Preset(typeCode: "C152", name: "Cessna 152", cruiseKt: 107),
        Preset(typeCode: "C172", name: "Cessna 172 Skyhawk", cruiseKt: 122),
        Preset(typeCode: "C182", name: "Cessna 182 Skylane", cruiseKt: 145),
        Preset(typeCode: "C206", name: "Cessna 206 Stationair", cruiseKt: 150),
        Preset(typeCode: "C210", name: "Cessna 210 Centurion", cruiseKt: 170),
        Preset(typeCode: "P28A", name: "Piper Cherokee / Archer", cruiseKt: 124),
        Preset(typeCode: "P28R", name: "Piper Arrow", cruiseKt: 137),
        Preset(typeCode: "PA32", name: "Piper Saratoga / Six", cruiseKt: 150),
        Preset(typeCode: "PA46", name: "Piper Malibu / Mirage", cruiseKt: 200),
        Preset(typeCode: "M20P", name: "Mooney M20", cruiseKt: 155),
        Preset(typeCode: "SR20", name: "Cirrus SR20", cruiseKt: 155),
        Preset(typeCode: "SR22", name: "Cirrus SR22", cruiseKt: 180),
        Preset(typeCode: "BE33", name: "Beechcraft Debonair", cruiseKt: 165),
        Preset(typeCode: "BE36", name: "Beechcraft Bonanza 36", cruiseKt: 176),
        Preset(typeCode: "BE58", name: "Beechcraft Baron 58", cruiseKt: 195),
        Preset(typeCode: "DA20", name: "Diamond DA20", cruiseKt: 138),
        Preset(typeCode: "DA40", name: "Diamond DA40", cruiseKt: 150),
        Preset(typeCode: "DA62", name: "Diamond DA62", cruiseKt: 190),
        Preset(typeCode: "RV7", name: "Van's RV-7", cruiseKt: 165),
        Preset(typeCode: "RV10", name: "Van's RV-10", cruiseKt: 175),
        Preset(typeCode: "J3", name: "Piper J-3 Cub", cruiseKt: 70),
        Preset(typeCode: "CH7A", name: "Citabria", cruiseKt: 105),
        Preset(typeCode: "PC12", name: "Pilatus PC-12", cruiseKt: 270),
        Preset(typeCode: "TBM9", name: "TBM 900 series", cruiseKt: 320),
        Preset(typeCode: "SF50", name: "Cirrus Vision Jet", cruiseKt: 300),
    ]

    static func preset(for typeCode: String) -> Preset? {
        presets.first { $0.typeCode.caseInsensitiveCompare(typeCode) == .orderedSame }
    }
}
