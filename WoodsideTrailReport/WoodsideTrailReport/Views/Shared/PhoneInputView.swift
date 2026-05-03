import SwiftUI

// Country code entry — all ISO regions with their dial codes.
struct CountryCallingCode: Identifiable, Hashable {
    let id: String      // ISO 3166-1 alpha-2 code
    let name: String
    let dialCode: String
}

// Pre-built static list of the most common country dial codes.
// A full list of all ~250 countries is included below.
extension CountryCallingCode {
    static let all: [CountryCallingCode] = {
        let raw: [(String, String, String)] = [
            ("AF","Afghanistan","+93"), ("AL","Albania","+355"), ("DZ","Algeria","+213"),
            ("AD","Andorra","+376"), ("AO","Angola","+244"), ("AG","Antigua and Barbuda","+1"),
            ("AR","Argentina","+54"), ("AM","Armenia","+374"), ("AU","Australia","+61"),
            ("AT","Austria","+43"), ("AZ","Azerbaijan","+994"), ("BS","Bahamas","+1"),
            ("BH","Bahrain","+973"), ("BD","Bangladesh","+880"), ("BB","Barbados","+1"),
            ("BY","Belarus","+375"), ("BE","Belgium","+32"), ("BZ","Belize","+501"),
            ("BJ","Benin","+229"), ("BT","Bhutan","+975"), ("BO","Bolivia","+591"),
            ("BA","Bosnia and Herzegovina","+387"), ("BW","Botswana","+267"),
            ("BR","Brazil","+55"), ("BN","Brunei","+673"), ("BG","Bulgaria","+359"),
            ("BF","Burkina Faso","+226"), ("BI","Burundi","+257"), ("CV","Cabo Verde","+238"),
            ("KH","Cambodia","+855"), ("CM","Cameroon","+237"), ("CA","Canada","+1"),
            ("CF","Central African Republic","+236"), ("TD","Chad","+235"),
            ("CL","Chile","+56"), ("CN","China","+86"), ("CO","Colombia","+57"),
            ("KM","Comoros","+269"), ("CG","Congo","+242"), ("CR","Costa Rica","+506"),
            ("HR","Croatia","+385"), ("CU","Cuba","+53"), ("CY","Cyprus","+357"),
            ("CZ","Czech Republic","+420"), ("DK","Denmark","+45"), ("DJ","Djibouti","+253"),
            ("DM","Dominica","+1"), ("DO","Dominican Republic","+1"), ("EC","Ecuador","+593"),
            ("EG","Egypt","+20"), ("SV","El Salvador","+503"), ("GQ","Equatorial Guinea","+240"),
            ("ER","Eritrea","+291"), ("EE","Estonia","+372"), ("SZ","Eswatini","+268"),
            ("ET","Ethiopia","+251"), ("FJ","Fiji","+679"), ("FI","Finland","+358"),
            ("FR","France","+33"), ("GA","Gabon","+241"), ("GM","Gambia","+220"),
            ("GE","Georgia","+995"), ("DE","Germany","+49"), ("GH","Ghana","+233"),
            ("GR","Greece","+30"), ("GD","Grenada","+1"), ("GT","Guatemala","+502"),
            ("GN","Guinea","+224"), ("GW","Guinea-Bissau","+245"), ("GY","Guyana","+592"),
            ("HT","Haiti","+509"), ("HN","Honduras","+504"), ("HU","Hungary","+36"),
            ("IS","Iceland","+354"), ("IN","India","+91"), ("ID","Indonesia","+62"),
            ("IR","Iran","+98"), ("IQ","Iraq","+964"), ("IE","Ireland","+353"),
            ("IL","Israel","+972"), ("IT","Italy","+39"), ("JM","Jamaica","+1"),
            ("JP","Japan","+81"), ("JO","Jordan","+962"), ("KZ","Kazakhstan","+7"),
            ("KE","Kenya","+254"), ("KI","Kiribati","+686"), ("KP","North Korea","+850"),
            ("KR","South Korea","+82"), ("KW","Kuwait","+965"), ("KG","Kyrgyzstan","+996"),
            ("LA","Laos","+856"), ("LV","Latvia","+371"), ("LB","Lebanon","+961"),
            ("LS","Lesotho","+266"), ("LR","Liberia","+231"), ("LY","Libya","+218"),
            ("LI","Liechtenstein","+423"), ("LT","Lithuania","+370"), ("LU","Luxembourg","+352"),
            ("MG","Madagascar","+261"), ("MW","Malawi","+265"), ("MY","Malaysia","+60"),
            ("MV","Maldives","+960"), ("ML","Mali","+223"), ("MT","Malta","+356"),
            ("MH","Marshall Islands","+692"), ("MR","Mauritania","+222"),
            ("MU","Mauritius","+230"), ("MX","Mexico","+52"), ("FM","Micronesia","+691"),
            ("MD","Moldova","+373"), ("MC","Monaco","+377"), ("MN","Mongolia","+976"),
            ("ME","Montenegro","+382"), ("MA","Morocco","+212"), ("MZ","Mozambique","+258"),
            ("MM","Myanmar","+95"), ("NA","Namibia","+264"), ("NR","Nauru","+674"),
            ("NP","Nepal","+977"), ("NL","Netherlands","+31"), ("NZ","New Zealand","+64"),
            ("NI","Nicaragua","+505"), ("NE","Niger","+227"), ("NG","Nigeria","+234"),
            ("NO","Norway","+47"), ("OM","Oman","+968"), ("PK","Pakistan","+92"),
            ("PW","Palau","+680"), ("PA","Panama","+507"), ("PG","Papua New Guinea","+675"),
            ("PY","Paraguay","+595"), ("PE","Peru","+51"), ("PH","Philippines","+63"),
            ("PL","Poland","+48"), ("PT","Portugal","+351"), ("QA","Qatar","+974"),
            ("RO","Romania","+40"), ("RU","Russia","+7"), ("RW","Rwanda","+250"),
            ("KN","Saint Kitts and Nevis","+1"), ("LC","Saint Lucia","+1"),
            ("VC","Saint Vincent and the Grenadines","+1"), ("WS","Samoa","+685"),
            ("SM","San Marino","+378"), ("ST","Sao Tome and Principe","+239"),
            ("SA","Saudi Arabia","+966"), ("SN","Senegal","+221"), ("RS","Serbia","+381"),
            ("SC","Seychelles","+248"), ("SL","Sierra Leone","+232"), ("SG","Singapore","+65"),
            ("SK","Slovakia","+421"), ("SI","Slovenia","+386"), ("SB","Solomon Islands","+677"),
            ("SO","Somalia","+252"), ("ZA","South Africa","+27"), ("SS","South Sudan","+211"),
            ("ES","Spain","+34"), ("LK","Sri Lanka","+94"), ("SD","Sudan","+249"),
            ("SR","Suriname","+597"), ("SE","Sweden","+46"), ("CH","Switzerland","+41"),
            ("SY","Syria","+963"), ("TW","Taiwan","+886"), ("TJ","Tajikistan","+992"),
            ("TZ","Tanzania","+255"), ("TH","Thailand","+66"), ("TL","Timor-Leste","+670"),
            ("TG","Togo","+228"), ("TO","Tonga","+676"), ("TT","Trinidad and Tobago","+1"),
            ("TN","Tunisia","+216"), ("TR","Turkey","+90"), ("TM","Turkmenistan","+993"),
            ("TV","Tuvalu","+688"), ("UG","Uganda","+256"), ("UA","Ukraine","+380"),
            ("AE","United Arab Emirates","+971"), ("GB","United Kingdom","+44"),
            ("US","United States","+1"), ("UY","Uruguay","+598"), ("UZ","Uzbekistan","+998"),
            ("VU","Vanuatu","+678"), ("VE","Venezuela","+58"), ("VN","Vietnam","+84"),
            ("YE","Yemen","+967"), ("ZM","Zambia","+260"), ("ZW","Zimbabwe","+263"),
        ]
        return raw.map { CountryCallingCode(id: $0.0, name: $0.1, dialCode: $0.2) }
            .sorted { $0.name < $1.name }
    }()
}

// MARK: - Phone Input View

struct PhoneInputView: View {
    @Binding var dialCode: String
    @Binding var number: String

    @State private var showCountryPicker = false
    @State private var searchText = ""

    private var selectedCountry: CountryCallingCode? {
        CountryCallingCode.all.first { $0.dialCode == dialCode && $0.id == "US" }
            ?? CountryCallingCode.all.first { $0.dialCode == dialCode }
    }

    private var isUS: Bool { dialCode == "+1" }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                showCountryPicker = true
            } label: {
                Text(dialCode)
                    .font(.body.monospaced())
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .foregroundStyle(.primary)

            TextField(isUS ? "(555) 555-0100" : "Phone number", text: $number)
                .keyboardType(.numberPad)
                .onChange(of: number) { _, new in
                    if isUS {
                        number = formatUS(new)
                    } else {
                        number = new.filter { $0.isNumber }
                    }
                }
        }
        .sheet(isPresented: $showCountryPicker) {
            CountryPickerSheet(selectedDialCode: $dialCode, isPresented: $showCountryPicker)
        }
    }

    private func formatUS(_ input: String) -> String {
        let digits = input.filter { $0.isNumber }
        let limited = String(digits.prefix(10))
        switch limited.count {
        case 0:        return ""
        case 1...3:    return "(\(limited)"
        case 4...6:    return "(\(limited.prefix(3))) \(limited.dropFirst(3))"
        default:
            let area = limited.prefix(3)
            let mid  = limited.dropFirst(3).prefix(3)
            let last = limited.dropFirst(6)
            return "(\(area)) \(mid)-\(last)"
        }
    }
}

// MARK: - Country Picker Sheet

struct CountryPickerSheet: View {
    @Binding var selectedDialCode: String
    @Binding var isPresented: Bool
    @State private var searchText = ""

    private var filtered: [CountryCallingCode] {
        if searchText.isEmpty { return CountryCallingCode.all }
        return CountryCallingCode.all.filter {
            $0.name.localizedCaseInsensitiveContains(searchText) ||
            $0.dialCode.contains(searchText)
        }
    }

    var body: some View {
        NavigationStack {
            List(filtered) { country in
                Button {
                    selectedDialCode = country.dialCode
                    isPresented = false
                } label: {
                    HStack {
                        Text(country.name)
                        Spacer()
                        Text(country.dialCode)
                            .font(.body.monospaced())
                            .foregroundStyle(.secondary)
                        if country.dialCode == selectedDialCode {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .foregroundStyle(.primary)
            }
            .searchable(text: $searchText, prompt: "Search countries")
            .navigationTitle("Country Code")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                }
            }
        }
    }
}
