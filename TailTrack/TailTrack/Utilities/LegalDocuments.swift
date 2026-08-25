import Foundation

/// In-app legal texts. Bump `version` when a document changes materially —
/// users are re-prompted to accept on next launch.
///
/// NOTE FOR THE DEVELOPER: these are sensible starter documents, not legal
/// advice. Have them reviewed before App Store release, and host matching
/// copies at orlandonell.com.
enum LegalDocuments {

    static let version = 1
    static let acceptedVersionKey = "acceptedLegalVersion"

    static let websiteURL = URL(string: "https://orlandonell.com")!
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
    third-party community networks and open datasets (adsb.lol, adsb.fi, \
    OpenSky Network, OurAirports). Coverage is incomplete and data may be \
    delayed, inaccurate, or unavailable. We make no guarantee of accuracy, \
    completeness, or availability.

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
    Effective date: August 22, 2026

    Short version: your data stays on your device. TailTrack has no \
    accounts server, no ads, no analytics, and no tracking SDKs.

    1. DATA STORED ON YOUR DEVICE
    Your pilot profile, aircraft, logbook, training progress, and photos \
    are stored only on your device (and in your own device backups, e.g. \
    iCloud device backup). We cannot see them. Deleting the app deletes \
    this data.

    2. NETWORK REQUESTS THE APP MAKES
    To function, the app contacts third-party services directly from your \
    device. Like any internet request, those services receive your IP \
    address and the query:
    • adsb.lol / adsb.fi / OpenSky Network — receive the Mode S hex code \
    or registration being tracked, to return live positions.
    • OurAirports (davidmegginson.github.io) — airport database download.
    • Openverse (api.openverse.org) — only when you use "Find Open Photo," \
    receives your search term (e.g. "Cessna 152 aircraft").
    We do not send these services your name, profile, or logbook. Each \
    service has its own privacy practices.

    3. SIGN IN WITH APPLE (OPTIONAL)
    If you choose to sign in, we receive an anonymous Apple user \
    identifier and, if you share it, your name. Both are stored only on \
    your device. Sign out at any time in the Profile tab.

    4. PURCHASES
    Subscriptions and purchases are processed entirely by Apple. We never \
    see your payment details.

    5. LOCATION
    The app does not request or use your device's location. Aircraft \
    positions come from public ADS-B broadcast data.

    6. CHILDREN
    The app is not directed to children under 13, and we do not knowingly \
    collect personal information from them.

    7. YOUR CHOICES
    Everything is on-device: edit or delete any data in the app, or delete \
    the app to remove all of it. There is no server-side account to close.

    8. CHANGES
    We may update this policy; material changes will be presented in the \
    app. The current version is always available here and at \
    \(websiteURL.absoluteString).

    9. CONTACT
    Privacy questions: \(supportEmail)
    """

    static let acknowledgements = """
    TAILTRACK — ACKNOWLEDGEMENTS & DATA SOURCES

    TailTrack is built on generous open-data communities:

    • adsb.lol — community-run ADS-B network with an open API.
    • adsb.fi — community-run ADS-B network with an open API.
    • OpenSky Network — research ADS-B network (opensky-network.org); used \
    as a fallback under its free non-commercial access terms.
    • OurAirports — worldwide airport database, dedicated to the public \
    domain by its contributors (ourairports.com).
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
