# TailTrack ✈️

**Flighty, but for *your* plane.** TailTrack is an iOS app for private pilots
that live-tracks your own aircraft by tail number using free, open ADS-B
data — no airline schedules required. Plug in `N1234C`, pick `KSQL → KSLC`,
and get wheels-up time, flight time, groundspeed, altitude, the flown track
on a map, ETE/ETA against your route, and an automatic logbook entry when
you land.

Built for flights like a C152 hop from San Carlos to Salt Lake City — or a
pattern session at your home field.

---

## Features

### Free
- **Live flight following** by tail number. US N-numbers are converted to
  their ICAO Mode S hex **offline** (the FAA's sequential allocation
  algorithm, unit-tested against the documented block anchors), so there's
  no registry lookup needed. Non-US? Enter the hex manually.
- **Open-data feeds** with automatic failover: [adsb.lol](https://adsb.lol) →
  [adsb.fi](https://adsb.fi) → [OpenSky Network](https://opensky-network.org).
- **Automatic takeoff & landing detection**, wheels-up/landing times, flown
  distance, max/avg/cruise groundspeed, max altitude.
- **Route planning**: great-circle distance, initial true course, ETE at
  your aircraft's cruise speed, live ETA while enroute.
- **Every airport, including the tiny ones** — E16, O22, NV82-style US
  strips up through KATL/KSFO/KJFK. The full worldwide
  [OurAirports](https://ourairports.com) database (public domain) downloads
  automatically on first launch and is cached on device; a curated
  ~200-airport starter list keeps the app working offline.
- **Auto airport detection**: leave the route blank and TailTrack fills in
  departure and arrival from where you actually took off and touched down
  (diversions get noted, Flighty-style).
- **Logbook** with per-flight map, stats, and notes; totals for time and
  distance.
- **Pilot profile card**: photo, name, certificate line ("STUDENT PPL"),
  home airport, primary aircraft — plus **training milestones** (first solo,
  solo XC, checkride…) and a **ratings/endorsements** list (type ratings,
  high performance, tailwheel, anything).
- **Sign in with Apple** (optional — everything works local-first).
- **Aircraft photos**: upload a shot of your plane, or tap **Find Open
  Photo** to search Openverse for CC0/public-domain images (no credit
  required) right in the app. No photo at all? Type-matched silhouette
  artwork fills in automatically.
- **Legal built in**: Terms of Service, Privacy Policy, and
  acknowledgements ship in the app (Settings → Legal). A welcome/agreement
  screen appears on first launch, and sign-up shows the standard consent
  line. Bump `LegalDocuments.version` after editing a document to
  re-prompt existing users. The texts are sensible starters tied to
  orlandonell.com / support@orlandonell.com — **have them reviewed before
  App Store release** and host matching copies on the website.

### TailTrack Pro (in-app purchase)
- Unlimited aircraft (free tier: one).
- GPX & CSV export of any flight (opens in ForeFlight, Google Earth, Excel).
- Satellite/hybrid live map with realistic terrain.

Suggested pricing (configured in `TailTrack.storekit` and App Store
Connect): **$2.99/month**, **$19.99/year** (highlighted as best value),
**$49.99 lifetime**. See "Pricing rationale" below.

---

## Getting started

### Prerequisites
- macOS with Xcode 15+ (Xcode 16 recommended)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`

### Build & run
```bash
cd TailTrack
xcodegen generate
open TailTrack.xcodeproj
```
Select the `TailTrack` scheme and run on a simulator or device. In Xcode's
Signing & Capabilities, pick your team (automatic signing).

### Trying it out
1. **Aircraft tab** → add your plane (e.g. `N1234C`, type `C152`). The
   derived Mode S hex appears instantly.
2. **Fly tab** → pick the aircraft, optionally set `KSQL → KSLC`, and hit
   **Start Tracking**. The app polls the open ADS-B networks every 8–15 s.
3. When the flight ends (or you tap End Tracking), it lands in the
   **Logbook** with the full track.

Tip for testing without flying: temporarily enter a hex override for any
aircraft currently airborne (find one on adsb.lol's map) and start tracking.

### In-app purchases (local testing)
The scheme is pre-wired to `TailTrack.storekit`, so purchases work in the
simulator out of the box (Xcode transaction manager). For TestFlight/App
Store: create the three products in App Store Connect with the same product
IDs (`com.orlandonell.tailtrack.pro.monthly` / `.yearly` / `.lifetime`).
A `DEBUG`-only "Force Pro entitlement" toggle lives in Settings for quick UI
testing.

### Sign in with Apple
Requires a **paid** Apple Developer account (the capability is in the
generated entitlements). On a free team, remove the capability and use the
app without signing in — the profile is local-first either way.
**Google Sign-In** isn't wired up: it needs the GoogleSignIn SDK plus an
OAuth client ID. Add the `GoogleSignIn` SPM package and a `GIDClientID` to
Info.plist if you want it; the profile model already stores an external
user ID.

### Aircraft & profile images
Photos are picked from your library (downscaled and stored in the app's
Application Support). **No photo? No problem** — every aircraft gets
built-in artwork automatically: an original top-down silhouette drawn in
code and matched to the type (high-wing Cessna, low-wing Piper/Cirrus,
twin, turboprop, jet). It ships with the repo, so it's license-free with
no attribution requirements. If you'd rather use real photos, note that
most "free" aircraft photos on [Wikimedia Commons](https://commons.wikimedia.org)
are CC-BY-SA — fine for personal use, but shipping them in an App Store
build requires visible attribution; truly public-domain (CC0) shots from
[Openverse](https://openverse.org) filtered to CC0 are the safe choice.
Save one to your camera roll and upload it in the aircraft editor.

---

## Pricing rationale

- Flighty charges ~$4/mo / ~$48/yr for airline tracking; ForeFlight starts
  around $130/yr. A GA companion app sits comfortably below both.
- **$19.99/year is the anchor** ("under $2/month" — an easy add-on to any
  flying budget). Monthly at $2.99 exists for low-commitment trial;
  lifetime at $49.99 (~2.5× annual) captures pilots who hate subscriptions.
- Keep the core tracker free: it grows word-of-mouth at the airfield, and
  the gated features (fleet, exports, satellite maps) are exactly what
  owners/renters with more than one plane will pay for.

## Open data sources & fair use

| Source | What | License/terms |
|---|---|---|
| [adsb.lol](https://api.adsb.lol) | Live ADS-B positions | Open API, community-run |
| [adsb.fi](https://adsb.fi) | Live ADS-B positions (failover) | Open API, community-run |
| [OpenSky Network](https://opensky-network.org) | Live positions (last resort) | Free for non-commercial; rate-limited anonymous access |
| [OurAirports](https://ourairports.com) | Worldwide airport database | Public domain |

Polling is one aircraft every 8–15 seconds — friendly to all of these. If
you fly somewhere with thin coverage, feed the networks with a ~$50
Raspberry Pi + SDR receiver at your home field; everyone's coverage
improves, and you typically get feeder perks.

`Scripts/build_airport_db.py` (optional) pre-bundles the *full* OurAirports
database into the app so worldwide airports work offline on first launch.

## Limitations (honest ones)

- **Not for navigation.** Logging/companion use only — never a substitute
  for certified avionics, traffic, or separation services.
- **Coverage varies.** Low-altitude GA flight over mountains can drop out of
  community receiver range; the track resumes when coverage returns, and a
  long signal loss at low altitude near the destination is treated as a
  probable landing.
- **Backgrounding.** iOS suspends the app in the background; tracking
  continues whenever the app is foregrounded (the data source is
  server-side, so wheels-up time is still captured retroactively from the
  first airborne sample seen).
- **Mode S hex derivation** covers US N-numbers exactly; a manual override
  field handles warbirds, non-US regs, and anything odd.

## Architecture

```
TailTrack/
├── project.yml               # XcodeGen manifest (app + tests + scheme)
├── TailTrack.storekit        # Local StoreKit config (Pro products)
├── Scripts/build_airport_db.py
├── TailTrack/
│   ├── TailTrackApp.swift    # @Observable stores injected via .environment
│   ├── Models/               # Aircraft, Airport, Flight, PilotProfile
│   ├── Services/
│   │   ├── NNumber.swift     # N-number ⇄ ICAO hex (offline, unit-tested)
│   │   ├── ADSBClient.swift  # adsb.lol → adsb.fi → OpenSky failover
│   │   ├── FlightTracker.swift # poll loop + takeoff/landing state machine
│   │   ├── AirportStore.swift  # starter JSON + OurAirports download/cache
│   │   ├── FleetStore / LogbookStore / ProfileStore / ProStore (StoreKit 2)
│   ├── Utilities/            # GreatCircle, Format, Theme, ImageStore, FlightExport
│   ├── Views/                # Fly / Logbook / Fleet / Profile / Settings
│   └── Resources/airports-starter.json
└── TailTrackTests/           # NNumber, GreatCircle, CSV parser tests
```

SwiftUI + Observation (`@Observable`), MapKit for SwiftUI, StoreKit 2,
iOS 17+. No third-party dependencies.

## Tests

Run with ⌘U (the `TailTrack` scheme includes `TailTrackTests`). The
N-number suite pins 13 known tail-number/hex pairs, both documented FAA
block anchors, invalid-input rejection, and a ~900-sample round-trip sweep
across the whole US allocation.
