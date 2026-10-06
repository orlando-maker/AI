# Launching TailTrack on the App Store

A step-by-step checklist for publishing TailTrack under a parent's Apple
Developer account. Work through it in order. The waiting periods are
Apple's, not yours.

## How long it really takes

| Step | Who | Time |
|---|---|---|
| Developer Program enrollment | Mom | 15 min to apply, then usually 1–2 days for Apple to approve |
| Paid Apps agreement, tax and bank info | Mom | 15 min, then hours to a few days to turn "Active" |
| Project setup, screenshots, listing | You | One evening |
| Upload the build | You | 30 min |
| App Review | Apple | Usually within 24–48 hours |

**Tonight** you can get the enrollment in and do every step that doesn't
need it. Nothing can be uploaded until the account is active. A realistic
"live on the App Store" date is 3–5 days after Mom applies, if review goes
smoothly.

## 0. What publishing under Mom's account means

- She is the legal developer and seller. **Her full legal name appears
  under the app on the App Store** ("Seller"), not OrlandoNell.com. Only an
  organization account (a company with a D-U-N-S number) shows a business
  name, and that takes weeks.
- She accepts Apple's agreements, and the payouts, tax forms and bank
  account are in her name.
- Her Apple ID gets the two-factor prompts. Do the setup together.
- **Update the in-app Terms** (`TailTrack/Utilities/LegalDocuments.swift`)
  so they name the person who publishes. Right now they say "operated by
  Orlando Nell". Make it "operated by [Mom's full name] and Orlando Nell",
  update the website copy to match, and bump `LegalDocuments.version`.
- Later, when you have your own account, the app can move to it: App
  Store Connect → the app → App Information → Transfer App. Keep the same
  bundle ID. Sign in with Apple users need an extra migration step at
  transfer time.

## 1. Enroll (Mom)

1. On her iPhone, install the **Apple Developer** app → Account → **Enroll
   Now**. This is the fastest route, because it scans her ID. The website
   also works: developer.apple.com/programs/enroll.
2. Choose **Individual / Sole Proprietor**. Use her Apple ID, which must
   have two-factor authentication on. The cost is $99 a year.
3. Wait for the "Welcome to the Apple Developer Program" email.

## 2. Agreements, tax and banking (Mom, right after approval)

App Store Connect (appstoreconnect.apple.com) → **Business**:

1. Accept the **Paid Apps** agreement.
2. Add the bank account and fill in the tax form (W-9 for the US).
3. Wait for the status to show **Active**. Subscriptions can't be sold
   until it does, so start this first.

## 3. Point the project at her team (you, on the Mac)

1. Xcode → Settings → Accounts → **+** → sign in with her Apple ID. She
   approves the prompt on her phone.
2. Find her **Team ID**: developer.apple.com/account → Membership details.
3. In `project.yml`:
   - Set `DEVELOPMENT_TEAM: "XXXXXXXXXX"` (her Team ID) in **all three**
     targets.
   - Uncomment the `entitlements:` block (Sign in with Apple and Game
     Center) and the line `TTAppleSignInEnabled: true`.
4. Run `xcodegen generate`, open the project, and run it on your iPhone.
   With automatic signing, Xcode registers the bundle IDs
   (`com.orlandonell.tailtrack` and `.widgets`) under her team.
5. Test the whole app once on the phone:
   - Track a flight.
   - Add a past flight.
   - Open the paywall.
   - Check Customize.

## 4. Create the app in App Store Connect

Apps → **+** → New App:

- **Platform:** iOS.
- **Name:** TailTrack. Names are unique on the App Store; if it's taken,
  use something like "TailTrack: Flight Logbook".
- **Primary language:** English (U.S.).
- **Bundle ID:** com.orlandonell.tailtrack.
- **SKU:** `tailtrack-ios`.

Then fill in:

- **App Information:**
  - Category: Travel, with Utilities as secondary. Avoid "Navigation",
    because the app says it isn't a navigation tool.
  - Age rating questionnaire: answer "None" to everything, which gives 4+.
- **Pricing and Availability:** Free (Pro is sold in-app). Choose all
  countries, or start with the US, Canada and Mexico.
- **App Privacy:**
  - Privacy Policy URL: the policy page on orlandonell.com. It must say the
    same thing as the in-app policy (Settings → Legal).
  - Data collection: **"No, we do not collect data from this app."** This
    is accurate: everything stays on the device, and the lookups to
    adsb.lol, aviationweather.gov and datis.clowd.io aren't tied to the
    user. If you ever add analytics, crash reporting or a server, change
    this answer.

## 5. Subscriptions and the 7-day free trial

The product IDs must match the code exactly.

**Features → Subscriptions →** create the group **TailTrack Pro**, then:

| Product ID | Duration | Price |
|---|---|---|
| `com.orlandonell.tailtrack.pro.monthly` | 1 month | $2.99 |
| `com.orlandonell.tailtrack.pro.yearly` | 1 year | $19.99 |

For each one:

- Add a display name and description.
- Turn **Family Sharing** on.
- Add a review screenshot (a screenshot of the paywall works).
- Add an **Introductory Offer**: Free → **1 week** → all countries.
  - Apple's free-trial lengths are fixed (3 days, 1 week, 2 weeks, 1
    month, and so on). 10 days isn't one of them.
  - The app reads the trial from Apple, so if you change it here, the
    paywall text updates by itself.

**Features → In-App Purchases →** add a Non-Consumable:

- Product ID: `com.orlandonell.tailtrack.pro.lifetime`
- Price: $49.99
- Family Sharing on

How the trial works for a user:

- They tap "7 days free, then $19.99 a year". Apple's sheet confirms the
  trial, and nothing is charged for 7 days.
- After that, Apple charges automatically unless they cancel at least 24
  hours before the trial ends.
- Each Apple ID gets one trial. The paywall shows the trial only to people
  who can still use it.

## 6. Screenshots and listing

- **Screenshots:** take them in the Simulator with ⌘S. You need the largest
  iPhone and, because the app runs on iPad, the largest iPad. Show real
  screens:
  - the live map
  - a flight's replay
  - the logbook
  - the ATIS card
  - the paywall's feature list
- **Subtitle** (30 characters max): `Your plane, tracked & logged`
- **Keywords** (100 characters max):
  `flight tracker,ADS-B,logbook,pilot,aviation,tail number,student pilot,METAR,ATIS,Cessna,airplane`
- **Description:** adapt the website's "The idea" paragraph and the six
  entries. Keep the "not for navigation" line.
- **Support URL:** orlandonell.com, or a contact page.

## 7. Upload the build

1. Xcode: set the run destination to **Any iOS Device (arm64)** → Product
   → **Archive**.
2. Organizer → **Distribute App** → App Store Connect → Upload.
3. Wait 15–30 minutes. The build appears under TestFlight once Apple has
   processed it.
4. Every new upload needs a higher `CURRENT_PROJECT_VERSION` in
   `project.yml` (1, 2, 3…).

Optional: TestFlight internal testing lets you try the real App Store build
and sandbox purchases before review.

## 8. Submit for review

On the **1.0** version page:

1. Select the build.
2. Under **In-App Purchases and Subscriptions**, add all three products.
   First-time products must be submitted together with an app version.
3. Fill in **App Review Information**:
   - Mom's name, phone and email.
   - "Sign-in required": **No**.
   - Notes: paste the text below.
4. Choose **Manually release this version**, so you pick launch day.
5. Click **Submit for Review**.

### Review notes to paste

> TailTrack is a flight tracker and logbook for general-aviation pilots. It
> uses public ADS-B data (adsb.lol), aviation weather (aviationweather.gov)
> and digital ATIS (datis.clowd.io).
>
> - No login is needed. The "account" on first launch is a local pilot
>   profile stored only on the device. Sign in with Apple is optional, and
>   nothing is sent to any server of ours (there isn't one). Profile → Sign
>   Out removes it.
> - Live tracking: Fly tab → enter the tail number of an aircraft that is
>   currently flying. Small private aircraft are often on the ground, so
>   the easiest test is TailTrack Pro's Crew Mode, which follows any
>   airline flight that's in the air by its flight number.
> - Past flights: Logbook → + → Add Past Flight, then open the flight and
>   tap "Find the flight path" (Pro). TailTrack retrieves the real ADS-B
>   track from the public archives.
> - Background audio: Settings → My receivers plays live airband audio
>   from a radio receiver the pilot runs themselves (an Icecast/HTTP
>   stream). It keeps playing with the screen locked, like a radio app.
> - TailTrack is for logging and information only. It is not a navigation
>   or traffic tool, and says so in the app.

If review pushes back on background audio because they can't test it,
delete `audio` from `UIBackgroundModes` in `project.yml` and resubmit. It's
a one-line change. Receivers will then only play while the app is open.

## 9. After approval

- Press **Release**. The app appears in every country within a few hours.
- Put the App Store badge and link on orlandonell.com, and change "Coming
  October 2026" to "Available now".
- Answer support emails quickly. Early reviews matter most.
