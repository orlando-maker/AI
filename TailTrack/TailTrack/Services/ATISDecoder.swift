import Foundation

/// A D-ATIS broadcast decoded into plain English. Every field is optional:
/// airports word their ATIS differently, so anything not understood stays
/// in `notices` rather than being dropped.
struct DecodedATIS: Equatable {
    var information: String?          // "Bravo"
    var issuedZulu: String?           // "1856Z"
    var issuedAt: Date?
    var wind: String?
    var visibility: String?
    var weather: [String] = []        // "Light rain", "Mist"
    var sky: [String] = []            // "Few at 800 ft", "Overcast at 400 ft"
    var temperature: String?          // "17°C, dew point 12°C"
    var altimeter: String?            // "29.92 inHg"
    var approaches: [String] = []
    var landing: [String] = []
    var departing: [String] = []
    var notices: [String] = []
}

/// Turns FAA D-ATIS text ("SFO ATIS INFO B 1856Z. 28012KT 10SM FEW008 …
/// LNDG RWYS 28L, 28R. …") into readable parts. Pure and deterministic so
/// it can be unit tested; nothing here touches the network.
enum ATISDecoder {

    static func decode(_ raw: String, now: Date = Date()) -> DecodedATIS {
        var result = DecodedATIS()
        let text = raw.uppercased()
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\\(.*?\\)", with: " ", options: .regularExpression)

        // Sentences: ATIS separates items with periods ("...", ". "),
        // while frequencies like 118.1 keep their decimal point.
        let sentences = text
            .components(separatedBy: CharacterSet(charactersIn: "."))
            .reduce(into: [String]()) { parts, piece in
                // Re-join decimals the split broke apart ("118" + "1 ...").
                if let last = parts.last, last.last?.isNumber == true,
                   piece.first?.isNumber == true {
                    parts[parts.count - 1] = last + "." + piece
                } else {
                    parts.append(piece)
                }
            }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        for sentence in sentences {
            let tokens = sentence.split(separator: " ").map(String.init)
            if decodeWeather(tokens, into: &result, now: now) { continue }

            let words = Set(tokens.map { $0.trimmingCharacters(in: .punctuationCharacters) })
            if words.contains("ADVS") || words.contains("ADVISE") || sentence.hasPrefix("NOTAMS")
                && tokens.count <= 1 {
                continue   // closing "advise you have info B" / bare NOTAMs header
            }
            let plain = plainEnglish(tokens)
            guard !plain.isEmpty else { continue }

            if !words.isDisjoint(with: ["APCH", "APCHS", "APPROACH", "APPROACHES", "VISUAL"]) {
                result.approaches.append(plain)
            } else if !words.isDisjoint(with: ["LNDG", "LDG", "LANDING", "ARRIVING", "ARRIVALS"]) {
                result.landing.append(plain)
            } else if !words.isDisjoint(with: ["DEPG", "DEPTG", "DEPARTING", "DEPARTURES"]) {
                result.departing.append(plain)
            } else {
                result.notices.append(plain)
            }
        }
        return result
    }

    // MARK: - Weather group

    /// Pulls the header and METAR-style weather out of a sentence. Returns
    /// true when the sentence was the header/weather block.
    private static func decodeWeather(_ tokens: [String], into result: inout DecodedATIS,
                                      now: Date) -> Bool {
        // Only the header/weather sentence carries a wind group, altimeter,
        // Zulu time or "INFO B" — gating on those keeps a notice such as
        // "RWY 10/28 CLSD" from being misread as a temperature.
        // Only the first Zulu time is the broadcast time; later ones live in
        // notices ("RWY 10/28 CLSD 0600Z TO 1300Z").
        let cleaned = tokens.map { $0.trimmingCharacters(in: CharacterSet(charactersIn: ",;")) }
        let awaitingTime = result.issuedZulu == nil
        let isWeather = cleaned.enumerated().contains { i, token in
            decodeWind(token) != nil
                || match(token, #"^[AQ]\d{4}$"#) != nil
                || (awaitingTime && match(token, #"^\d{4}Z$"#) != nil)
                || ((token == "INFO" || token == "INFORMATION") && i + 1 < cleaned.count
                    && phonetic[cleaned[i + 1]] != nil)
        }
        guard isWeather else { return false }

        var matched = false
        var inRemarks = false
        var index = 0
        while index < tokens.count {
            let token = tokens[index].trimmingCharacters(in: CharacterSet(charactersIn: ",;"))
            defer { index += 1 }
            if inRemarks { continue }

            if token == "RMK" {
                inRemarks = true
                matched = true
            } else if token == "INFO" || token == "INFORMATION", index + 1 < tokens.count,
                      result.information == nil {
                let letter = tokens[index + 1].trimmingCharacters(in: .punctuationCharacters)
                if letter.count == 1, let word = phonetic[letter] {
                    result.information = word
                    index += 1
                    matched = true
                }
            } else if let time = match(token, #"^(\d{2})(\d{2})Z$"#), result.issuedZulu == nil {
                result.issuedZulu = token
                result.issuedAt = zuluDate(hour: Int(time[1])!, minute: Int(time[2])!, now: now)
                matched = true
            } else if let wind = decodeWind(token) {
                result.wind = wind
                matched = true
            } else if let range = match(token, #"^(\d{3})V(\d{3})$"#), let wind = result.wind {
                result.wind = wind + ", varying \(range[1])°–\(range[2])°"
                matched = true
            } else if token.range(of: #"^\d$"#, options: .regularExpression) != nil,
                      index + 1 < tokens.count,
                      let fraction = match(tokens[index + 1], #"^(\d/\d)SM$"#) {
                result.visibility = "\(token) \(fraction[1]) statute miles"
                index += 1
                matched = true
            } else if let vis = match(token, #"^([PM])?(\d{1,2}|\d/\d)SM$"#) {
                let amount = vis[2]
                switch vis[1] {
                case "P": result.visibility = "Better than \(amount) statute miles"
                case "M": result.visibility = "Less than \(amount) statute mile"
                default: result.visibility = "\(amount) statute mile\(amount == "1" ? "" : "s")"
                }
                matched = true
            } else if let sky = decodeSky(token) {
                result.sky.append(sky)
                matched = true
            } else if result.temperature == nil,
                      let temp = match(token, #"^(M?\d{2})/(M?\d{2})?$"#),
                      temp[2].isEmpty || celsiusValue(temp[2]) <= celsiusValue(temp[1]) {
                // Dew point can't exceed temperature — a runway pair like
                // 10/28 fails that test.
                var text = "\(celsius(temp[1]))°C"
                if !temp[2].isEmpty { text += ", dew point \(celsius(temp[2]))°C" }
                result.temperature = text
                matched = true
            } else if let alt = match(token, #"^A(\d{2})(\d{2})$"#) {
                result.altimeter = "\(alt[1]).\(alt[2]) inHg"
                matched = true
            } else if let qnh = match(token, #"^Q(\d{4})$"#), let hPa = Int(qnh[1]) {
                result.altimeter = "\(hPa) hPa"
                matched = true
            } else if let wx = decodePhenomena(token) {
                result.weather.append(wx)
                matched = true
            }
        }
        return matched
    }

    private static func decodeWind(_ token: String) -> String? {
        guard let w = match(token, #"^(VRB|\d{3})(\d{2,3})(?:G(\d{2,3}))?KT$"#) else { return nil }
        let speed = Int(w[2]) ?? 0
        if speed == 0 { return "Calm" }
        var text = w[1] == "VRB" ? "Variable at \(speed) kt" : "\(w[1])° at \(speed) kt"
        if !w[3].isEmpty, let gust = Int(w[3]) { text += ", gusting \(gust) kt" }
        return text
    }

    private static func decodeSky(_ token: String) -> String? {
        if token == "CLR" || token == "SKC" { return "Clear" }
        guard let s = match(token, #"^(FEW|SCT|BKN|OVC|VV)(\d{3})(CB|TCU)?$"#),
              let hundreds = Int(s[2]) else { return nil }
        let names = ["FEW": "Few", "SCT": "Scattered", "BKN": "Broken",
                     "OVC": "Overcast", "VV": "Sky obscured, vertical visibility"]
        let height = (hundreds * 100).formatted(.number.grouping(.automatic))
        var text = "\(names[s[1]] ?? s[1]) at \(height) ft"
        if s[3] == "CB" { text += " (cumulonimbus)" }
        if s[3] == "TCU" { text += " (towering cumulus)" }
        if s[1] == "BKN" || s[1] == "OVC" || s[1] == "VV" { text += " · ceiling" }
        return text
    }

    private static func decodePhenomena(_ token: String) -> String? {
        guard let p = match(token, #"^([-+]|VC)?(MI|PR|BC|DR|BL|SH|TS|FZ)?((?:DZ|RA|SN|SG|IC|PL|GR|GS|UP|BR|FG|FU|VA|DU|SA|HZ|PY|PO|SQ|FC|SS|DS)+)$"#) else {
            return nil
        }
        let intensity = ["-": "Light", "+": "Heavy", "VC": "In the vicinity:"][p[1]]
        let descriptor = ["MI": "shallow", "PR": "partial", "BC": "patches of", "DR": "drifting",
                          "BL": "blowing", "SH": "showers of", "TS": "thunderstorm with",
                          "FZ": "freezing"][p[2]]
        let names = ["DZ": "drizzle", "RA": "rain", "SN": "snow", "SG": "snow grains",
                     "IC": "ice crystals", "PL": "ice pellets", "GR": "hail", "GS": "small hail",
                     "UP": "unknown precipitation", "BR": "mist", "FG": "fog", "FU": "smoke",
                     "VA": "volcanic ash", "DU": "dust", "SA": "sand", "HZ": "haze",
                     "PY": "spray", "PO": "dust whirls", "SQ": "squalls", "FC": "funnel cloud",
                     "SS": "sandstorm", "DS": "duststorm"]
        var codes: [String] = []
        var rest = Substring(p[3])
        while rest.count >= 2 {
            codes.append(String(rest.prefix(2)))
            rest = rest.dropFirst(2)
        }
        let what = codes.compactMap { names[$0] }.joined(separator: " and ")
        let phrase = [intensity, descriptor, what].compactMap { $0 }.joined(separator: " ")
        guard let first = phrase.first else { return nil }
        return first.uppercased() + phrase.dropFirst()
    }

    // MARK: - Plain English for the rest

    private static func plainEnglish(_ tokens: [String]) -> String {
        let words: [String] = tokens.compactMap { token in
            let core = token.trimmingCharacters(in: CharacterSet(charactersIn: ",;:"))
            let trailing = String(token.dropFirst(core.count))
            guard !core.isEmpty else { return nil }
            let word: String
            if let expansion = abbreviations[core] {
                word = expansion
            } else if keepAsIs.contains(core) || core.contains(where: \.isNumber)
                        || core.count == 1 || (core.count == 2 && !shortWords.contains(core)) {
                word = core   // acronyms, runway/taxiway names like 28L, A3, F, AA
            } else {
                word = core.lowercased()
            }
            return word + trailing
        }
        let sentence = words.joined(separator: " ")
        guard let first = sentence.first else { return "" }
        return first.uppercased() + sentence.dropFirst() + "."
    }

    static let phonetic: [String: String] = [
        "A": "Alpha", "B": "Bravo", "C": "Charlie", "D": "Delta", "E": "Echo", "F": "Foxtrot",
        "G": "Golf", "H": "Hotel", "I": "India", "J": "Juliett", "K": "Kilo", "L": "Lima",
        "M": "Mike", "N": "November", "O": "Oscar", "P": "Papa", "Q": "Quebec", "R": "Romeo",
        "S": "Sierra", "T": "Tango", "U": "Uniform", "V": "Victor", "W": "Whiskey",
        "X": "X-ray", "Y": "Yankee", "Z": "Zulu",
    ]

    /// Two-letter words that are English, not taxiway names.
    private static let shortWords: Set<String> = [
        "IN", "ON", "TO", "OF", "AT", "BE", "IS", "OR", "NO", "UP", "AN", "AS", "BY", "IT",
        "IF", "DO", "GO", "WE", "US", "ME", "MY", "SO", "AM",
    ]

    private static let keepAsIs: Set<String> = [
        "ILS", "RNAV", "GPS", "VOR", "LOC", "DME", "LDA", "NDB", "RNP", "PAPI", "VASI", "ALS",
        "ASR", "RVR", "ATC", "ATIS", "VFR", "IFR", "SID", "STAR", "CTAF", "UNICOM", "AGL", "MSL",
        "NM", "FICON", "TFR", "LAHSO", "UAS", "NOTAM", "PCL", "MALSR", "REIL", "HIRL", "TDZ",
    ]

    private static let abbreviations: [String: String] = [
        "APCH": "approach", "APCHS": "approaches", "APP": "approach", "ARR": "arrival",
        "ARRS": "arrivals", "DEP": "departure", "DEPS": "departures", "DEPG": "departing",
        "DEPTG": "departing", "LNDG": "landing", "LDG": "landing", "RWY": "runway",
        "RWYS": "runways", "TWY": "taxiway", "TWYS": "taxiways", "CLSD": "closed",
        "BTN": "between", "BTWN": "between", "VCNTY": "vicinity", "ARPT": "airport",
        "ACFT": "aircraft", "CTC": "contact", "FREQ": "frequency", "OPS": "operations",
        "OPN": "open", "SIMUL": "simultaneous", "SIMULT": "simultaneous", "PARL": "parallel",
        "LCL": "local", "OTS": "out of service", "U/S": "unserviceable", "AVBL": "available",
        "UNAVBL": "unavailable", "ACTV": "active", "INOP": "inoperative", "ACT": "activity",
        "WI": "within", "FT": "feet", "FLT": "flight", "HDG": "heading", "CLNC": "clearance",
        "DEL": "delivery", "GND": "ground", "TWR": "tower", "CONST": "construction",
        "CONSTR": "construction", "EQUIP": "equipment", "TFC": "traffic", "PRKG": "parking",
        "RMP": "ramp", "LGT": "light", "LGTS": "lights", "LGTD": "lighted", "OBST": "obstruction",
        "SFC": "surface", "WND": "wind", "INFO": "information", "INSTRS": "instructions",
        "INSTR": "instruction", "REQ": "request", "REQD": "required", "HAZ": "hazard",
        "MAINT": "maintenance", "PTRN": "pattern", "ALT": "altitude", "ALTM": "altimeter",
        "EXPT": "expect", "EXP": "expect", "VIS": "visibility", "VSBY": "visibility",
        "BRKG": "braking", "ACTN": "action", "CNTRLN": "centerline", "THR": "threshold",
        "DSPLCD": "displaced", "NOTAMS": "NOTAMs", "ASSOC": "associated", "AUTH": "authorized",
        "BCN": "beacon", "CAUTN": "caution", "CHG": "change", "DLA": "delay", "DLY": "daily",
        "FLD": "field", "HEL": "helicopter", "HELI": "helicopter", "INTL": "international",
        "OBSC": "obscured", "PERM": "permanent", "PSN": "position", "PROC": "procedure",
        "PROCS": "procedures", "RDR": "radar", "SVC": "service", "TEMP": "temporary",
        "TKOF": "takeoff", "TRML": "terminal", "UFN": "until further notice", "VEH": "vehicle",
        "WIP": "work in progress", "XNG": "crossing", "DEPARTURE": "departure",
    ]

    // MARK: - Helpers

    /// Capture groups of a whole-token regex match, with unmatched groups
    /// as empty strings; nil when the token doesn't match.
    private static func match(_ token: String, _ pattern: String) -> [String]? {
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let m = regex.firstMatch(in: token, range: NSRange(token.startIndex..., in: token))
        else { return nil }
        return (0..<m.numberOfRanges).map { i in
            Range(m.range(at: i), in: token).map { String(token[$0]) } ?? ""
        }
    }

    private static func celsiusValue(_ value: String) -> Int {
        value.hasPrefix("M") ? -(Int(value.dropFirst()) ?? 0) : (Int(value) ?? 0)
    }

    private static func celsius(_ value: String) -> String {
        String(celsiusValue(value))
    }

    /// The broadcast's issue time is only hours and minutes; place it on the
    /// most recent matching UTC moment (so a 2350Z ATIS read at 0010Z is
    /// yesterday's).
    private static func zuluDate(hour: Int, minute: Int, now: Date) -> Date? {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .current
        guard let today = utc.date(bySettingHour: hour, minute: minute, second: 0, of: now) else {
            return nil
        }
        return today > now.addingTimeInterval(10 * 60)
            ? utc.date(byAdding: .day, value: -1, to: today)
            : today
    }
}

extension DecodedATIS {
    /// One line for the radio log, the way a pilot jots ATIS on a
    /// kneeboard: wind, altimeter, and the runway in use.
    var kneeboardSummary: String {
        var parts: [String] = []
        if let wind { parts.append("Wind \(wind)") }
        if let altimeter { parts.append("Altimeter \(altimeter)") }
        if let runways = landing.first ?? departing.first ?? approaches.first {
            parts.append(String(runways.dropLast(runways.hasSuffix(".") ? 1 : 0)))
        }
        return parts.joined(separator: " · ")
    }
}
