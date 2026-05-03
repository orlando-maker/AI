# Woodside Trail Report

A free iOS/iPadOS/watchOS/visionOS app for residents and visitors of Woodside, CA to report trail damage, street sign issues, roadway problems, and more.

**Not affiliated with the Town of Woodside.** For errors or support contact support@orlandonell.com.

---

## Setup

### Prerequisites

- macOS with Xcode 15+
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) — `brew install xcodegen`
- A free [Supabase](https://supabase.com) account
- A free [Resend](https://resend.com) account (for admin email notifications)

### 1. Supabase Setup

1. Create a new Supabase project (free tier, region `us-west-1`).
2. In **SQL Editor**, run the full migration from `supabase/migration.sql`.
3. In **Authentication → Users**, create the admin user by running:
   ```sql
   select auth.create_user('{"email":"admin@orlandonell.com","password":"adminisadmyn123","email_confirm":true}');
   ```
4. In **Storage**, create a bucket named `report-photos` (private).
5. Copy your **Project URL** and **anon public key** from Settings → API.

### 2. Admin Email Notifications

1. Sign up at [resend.com](https://resend.com) and get your API key.
2. In **Supabase → Edge Functions**, create a function named `notify-admin` using the code in `supabase/notify-admin.ts`.
3. Add `RESEND_API_KEY` to Supabase → Settings → Edge Function Secrets.
4. In **Database → Webhooks**, create a webhook: table `reports`, event `INSERT`, URL = your Edge Function URL.

### 3. Configure the App

Open `WoodsideTrailReport/Config.swift` and fill in:

```swift
static let supabaseURL = URL(string: "https://YOUR_PROJECT.supabase.co")!
static let supabaseAnonKey = "YOUR_ANON_KEY"
```

### 4. Generate Xcode Project

```bash
cd WoodsideTrailReport
xcodegen generate
open WoodsideTrailReport.xcodeproj
```

### 5. App Groups (required for iPhone ↔ Watch shared device ID)

In Xcode, add the **App Groups** capability to both targets and set the group ID to:
`group.com.orlandonell.woodside`

### 6. Replace Boundary GeoJSON

`WoodsideTrailReport/Resources/woodside_boundary.geojson` contains a simplified placeholder polygon.

To get the accurate boundary:
1. Download California Places TIGER/Line 2023 from:
   `https://www2.census.gov/geo/tiger/TIGER2023/PLACE/tl_2023_06_place.zip`
2. Extract and filter for PLACEFP = `85922` (Woodside).
3. Convert the shapefile to GeoJSON using [mapshaper.org](https://mapshaper.org) or:
   ```bash
   ogr2ogr -f GeoJSON woodside_boundary.geojson tl_2023_06_place.shp -where "PLACEFP='85922'"
   ```
4. Replace the file in `WoodsideTrailReport/Resources/`.

---

## Architecture

| Layer | Technology |
|---|---|
| UI | SwiftUI (iOS 17+, iPadOS, watchOS 10+, visionOS) |
| Maps | MapKit (native) |
| Geocoding | CLGeocoder (native Apple) |
| Backend | Supabase free tier (PostgreSQL + Storage + Auth) |
| Admin notifications | Supabase Edge Function + Resend.com free tier |
| Local storage | UserDefaults (device UUID, terms acceptance) |
| Anti-bot | Hardcoded Q&A challenge (no reCAPTCHA) |

## Admin Access

In the app sidebar, tap **About**. Tap the version number **5 times** to reveal a hidden code field. Enter `511`. You will be prompted for the admin password.

---

## License

This app is owned and licensed by [orlandonell.com](https://orlandonell.com). It is free of charge and may not be redistributed or resold. For licensing inquiries visit orlandonell.com.
