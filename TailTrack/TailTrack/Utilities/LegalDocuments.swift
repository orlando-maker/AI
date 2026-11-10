import Foundation

/// In-app legal texts. Bump `version` when a document changes materially —
/// users are re-prompted to accept on next launch.
///
/// NOTE FOR THE DEVELOPER: these are sensible starter documents, not legal
/// advice. Have them reviewed before App Store release, and host matching
/// copies at tailtrackapp.com.
enum LegalDocuments {

    static let version = 1
    static let acceptedVersionKey = "acceptedLegalVersion"

    static let websiteURL = URL(string: "https://tailtrackapp.com")!
    /// The hosted legal pages, also entered in App Store Connect.
    static let privacyURL = URL(string: "https://tailtrackapp.com/privacy")!
    static let termsURL = URL(string: "https://tailtrackapp.com/terms")!
    static let supportEmail = "support@orlandonell.com"

    static let termsOfService = """
    TAILTRACK — TERMS OF SERVICE
    Effective date: August 22, 2026

    TailTrack ("the app") is operated by Orlando Nell (orlandonell.com) \
    ("we," "us"). By downloading or using the app you agree to these terms. \
    If you do not agree, do not use the app.

    1. NOT A NAVIGATION OR SAFETY TOOL
    TailTrack is a logging and flight-following companion for informational \
    and entertainment purposes only. It is NOT a certified navigation, \
    traffic, weather, or separation service and must never be used for \
    flight-critical decisions, collision avoidance, or as a substitute for \
    certified avionics, official briefings, or air traffic control. The \
    pilot in command is solely responsible for the safe operation of any \
    aircraft at all times, in accordance with applicable regulations \
    (including 14 CFR).

    2. DATA ACCURACY
    Positions, times, speeds, altitudes, and airport data come from \
    third-party community networks and open datasets (adsb.lol, \
    OurAirports). Coverage is incomplete and data may be \
    delayed, inaccurate, or unavailable. We make no guarantee of accuracy, \
    completeness, or availability. Third-party data is used subject to \
    each provider's own terms and licenses (see Acknowledgements).

    3. YOUR RESPONSIBILITIES
    You agree to use the app lawfully, to track only aircraft you are \
    entitled to track, and not to misuse, overload, scrape, or interfere \
    with the app or its data sources. You are responsible for the accuracy \
    of information you enter (tail numbers, hex codes, logbook entries).

    4. ACCOUNTS
    Sign in with Apple is optional. You are responsible for activity that \
    occurs under your identity on your device.

    5. PURCHASES AND SUBSCRIPTIONS
    TailTrack Pro is offered as auto-renewing subscriptions (monthly, \
    yearly) and a one-time lifetime purchase, billed through your Apple \
    account. Subscriptions renew automatically unless cancelled at least \
    24 hours before the end of the current period, and are managed or \
    cancelled in your device's App Store subscription settings. Payments, \
    renewals, and refunds are handled by Apple under Apple's Media Services \
    Terms; prices may vary by region and may change with notice.

    6. INTELLECTUAL PROPERTY
    The app, its artwork, and its content (excluding third-party data and \
    content you create) are our property and are licensed to you for \
    personal, non-commercial use on Apple-branded devices. Your logbook \
    entries, photos, and profile data are yours.

    7. DISCLAIMER OF WARRANTIES
    THE APP IS PROVIDED "AS IS" AND "AS AVAILABLE," WITHOUT WARRANTIES OF \
    ANY KIND, EXPRESS OR IMPLIED, INCLUDING MERCHANTABILITY, FITNESS FOR A \
    PARTICULAR PURPOSE, ACCURACY, AND NON-INFRINGEMENT.

    8. LIMITATION OF LIABILITY
    TO THE MAXIMUM EXTENT PERMITTED BY LAW, WE SHALL NOT BE LIABLE FOR ANY \
    INDIRECT, INCIDENTAL, SPECIAL, CONSEQUENTIAL, OR EXEMPLARY DAMAGES, OR \
    FOR ANY LOSS ARISING FROM RELIANCE ON DATA SHOWN IN THE APP. OUR TOTAL \
    LIABILITY FOR ANY CLAIM SHALL NOT EXCEED THE AMOUNT YOU PAID US IN THE \
    TWELVE MONTHS BEFORE THE CLAIM AROSE.

    9. TERMINATION
    You may stop using the app at any time; deleting the app removes its \
    on-device data. We may suspend or discontinue the app or any feature \
    at any time.

    10. CHANGES
    We may update these terms. Material changes will be presented in the \
    app for renewed acceptance. Continued use after changes take effect \
    constitutes acceptance.

    11. GOVERNING LAW
    These terms are governed by the laws of the State of California, USA, \
    without regard to conflict-of-law rules.

    12. CONTACT
    Orlando Nell — \(supportEmail) — \(websiteURL.absoluteString)
    """

    static let privacyPolicy = """
    TAILTRACK — PRIVACY POLICY
    Effective date: October 18, 2026

    Short version: your data stays on your device. TailTrack does not operate any servers that store user accounts or data, and has no ads, no analytics, and no tracking SDKs.

    TABLE OF CONTENTS
    1. Personal Information We Collect
    2. How We Use Your Personal Information
    3. How We Share Your Personal Information
    4. Your Choices Regarding Your Personal Information
    5. Security Of Your Personal Information
    6. Retention of Personal Information
    7. International Users
    8. Notice to European Users
    9. Notice to Canadian Users
    10. Notice to Australian and New Zealand Users
    11. Children and People with Difficulty Accessing
    12. Do Not Track
    13. Updates To This Privacy Policy
    14. Contact Us

    1. PERSONAL INFORMATION WE COLLECT
    TailTrack is operated by Orlando Nell (orlandonell.com) ("we," "us"). We do not collect your personal information on any server of ours. The information below is created and kept only on your device:
    • Your pilot profile: your name, optional photo, certificate line, and home airports.
    • Your aircraft: tail numbers, types, nicknames, and any photos you add.
    • Your logbook: flights, flight tracks, notes, landings, radio log entries, weather, and any photos you attach to a flight.
    • Your training progress and achievements.
    If you choose Sign in with Apple, we receive an anonymous Apple user identifier and, if you share it, your name. Both are stored only on your device.
    Logbook page scanning reads your photo on your device using Apple's text recognition. The photo is not uploaded anywhere.
    The app does not request or use your device's location, contacts, camera roll in bulk, or microphone. Aircraft positions come from public ADS-B broadcast data, not from your phone.

    2. HOW WE USE YOUR PERSONAL INFORMATION
    Your information is used on your device only, to run the features you choose: tracking an aircraft, building your logbook, showing statistics, and sharing cards and exports that you create. We do not use it for advertising, profiling, or analytics, and we do not sell it.

    3. HOW WE SHARE YOUR PERSONAL INFORMATION
    We do not receive your personal information, so we have nothing to sell or share. To work, the app contacts third-party services directly from your device. Like any internet request, those services receive your IP address and the query itself:
    • adsb.lol — receives the Mode S hex code or registration being tracked, to return live positions and flight history.
    • OurAirports (davidmegginson.github.io, or its GitHub mirror) — airport database and radio frequency downloads.
    • Aviation Weather Center (aviationweather.gov) — receives the airport codes you look up, to return METAR and TAF weather.
    • datis.clowd.io — receives an airport code, to return that airport's digital ATIS.
    • Radio receivers you add yourself — only when you press play, the app connects to the stream address you entered. LiveATC.net links open in its own app or your browser; TailTrack sends it nothing.
    • Openverse (api.openverse.org) — only when you use "Find Open Photo," receives your search term (for example "Cessna 152 aircraft").
    We do not send these services your name, profile, or logbook. Each service has its own privacy practices.
    Purchases and subscriptions are processed entirely by Apple. We never see your payment details. If you share a flight card, export, or photo, it goes to the app or person you choose.

    4. YOUR CHOICES REGARDING YOUR PERSONAL INFORMATION
    Everything is on your device, so you control it. You can edit or delete any aircraft, flight, photo, or profile information in the app, sign out of Sign in with Apple or delete your account in the Profile tab, and remove everything by deleting the app. Your logbook is also visible in the Files app, so you always have your own copy. You decide whether to add a radio receiver, use Find Open Photo, or sign in at all. There is no server-side account to close.

    5. SECURITY OF YOUR PERSONAL INFORMATION
    Your data is stored in the app's private storage on your device, protected by iOS and your device passcode. If you use iCloud device backup, your backups are protected by Apple. Because we hold no copy of your data, a lost or unprotected device is the main risk, so keep your device locked. No method of storage or transmission is completely secure, and we cannot guarantee absolute security.

    6. RETENTION OF PERSONAL INFORMATION
    Your information stays on your device until you delete it or delete the app. We keep no copy. Third-party services listed above may keep ordinary server logs under their own policies.

    7. INTERNATIONAL USERS
    TailTrack is operated from the United States and is available in many countries. Your personal information is stored on your own device and is not transferred to us. The third-party services listed above may be located in, or process requests from, other countries, and your requests to them travel over the internet to wherever they operate.

    8. NOTICE TO EUROPEAN USERS
    Because your personal information stays on your device and we do not receive it, we do not operate a database of personal data about you. For the limited network requests the app makes (section 3), the services involved receive your IP address and the query needed to respond; we rely on performing the service you asked for. You can access, correct, or erase your data directly in the app, and you can ask us questions at the address below. You may also lodge a complaint with your local data protection authority.

    9. NOTICE TO CANADIAN USERS
    We do not collect your personal information on our servers. Your information is stored on your device, and you can access, correct, or delete it in the app. The third-party services in section 3 may process requests outside Canada. For questions about our practices, contact us at the address below. You may also contact the Office of the Privacy Commissioner of Canada.

    10. NOTICE TO AUSTRALIAN AND NEW ZEALAND USERS
    We do not collect your personal information on our servers; it stays on your device and you can access, correct, or delete it in the app. The third-party services in section 3 may process requests outside Australia and New Zealand. For questions or a privacy concern, contact us at the address below. If you are not satisfied, you may contact the Office of the Australian Information Commissioner or the New Zealand Privacy Commissioner.

    11. CHILDREN AND PEOPLE WITH DIFFICULTY ACCESSING
    The app is not directed to children under 13, and we do not knowingly collect personal information from them. If you have difficulty accessing this policy or the app, contact us at the address below and we will provide it in another format and help where we can.

    12. DO NOT TRACK
    TailTrack does not track you across apps or websites, and contains no advertising or analytics trackers, so there is nothing to opt out of. We therefore treat every user the same regardless of any Do Not Track setting.

    13. UPDATES TO THIS PRIVACY POLICY
    We may update this policy. The effective date at the top shows when it last changed, and material changes will be presented in the app. The current version is always available in Settings → Legal and at \(websiteURL.absoluteString).

    14. CONTACT US
    Privacy questions: \(supportEmail)
    Orlando Nell — \(websiteURL.absoluteString)
    """

    static let acknowledgements = """
    TAILTRACK — ACKNOWLEDGEMENTS & DATA SOURCES

    TailTrack is built on generous open-data communities:

    • adsb.lol — community-run ADS-B network. Live positions and flight \
    history are © adsb.lol contributors, available under the Open \
    Database License (opendatacommons.org/licenses/odbl). TailTrack does \
    not use OpenSky Network or adsb.fi data.
    • OurAirports — worldwide airport database and radio frequencies, \
    dedicated to the public domain by its contributors (ourairports.com).
    • Aviation Weather Center — METAR and TAF weather from the FAA and \
    National Weather Service (aviationweather.gov).
    • D-ATIS — the FAA's digital ATIS, served free by the community \
    mirror at datis.clowd.io. The decoded view is TailTrack's own reading \
    of the broadcast; the original text is always shown alongside it.
    • Openverse — CC0/public-domain image search by the WordPress \
    community (openverse.org). Photos surfaced in "Find Open Photo" are \
    filtered to licenses that require no attribution; the photographers \
    still deserve thanks.

    The built-in aircraft silhouette artwork is original to TailTrack.

    If you fly often, consider hosting an ADS-B feeder (a Raspberry Pi and \
    an SDR dongle) for these networks — coverage where YOU fly improves, \
    and the data stays free for everyone.

    Fly safe. — \(websiteURL.absoluteString)
    """
}
