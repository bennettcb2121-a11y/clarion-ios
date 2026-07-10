# Clarion iOS — Apple Health companion (Swift/SwiftUI)

The native companion to [clarionlabs.tech](https://clarionlabs.tech). One job: read the
HealthKit metrics relevant to your goals → normalize to Clarion's wearable wire format →
`POST /api/wearables/ingest`. All interpretation stays on the web. Full plan:
`bloodwise-frontend/docs/ios-app-plan.md`.

```
HealthKit (on device) ─► DailyNormalizer/WorkoutNormalizer ─► POST /api/wearables/ingest ─► Supabase ─► web dashboard
```

Because Apple Health is a hub, this one integration also carries Garmin / Whoop / Fitbit /
Apple Watch data the user already syncs into Health — no per-vendor APIs.

## Status

Scaffolded ahead of Xcode availability. Swift sources are syntax-validated but have
**never been compiled against the iOS SDK** — expect a small first-build fixup pass.

## Getting to the first build (in order)

1. **Upgrade macOS** — Settings → General → Software Update (this Mac is an M3 Pro; any
   current macOS is supported). Xcode 26 requires macOS 15.6+ and the App Store rejects
   uploads from older Xcode versions.
2. **Install Xcode 26** from the Mac App Store (large download). Launch once to install the
   iOS platform.
3. **Enroll in the Apple Developer Program** ($99/yr) at developer.apple.com — decide
   individual (fast) vs organization (needs D-U-N-S; shows "Clarion Labs" as seller).
4. **Generate the project**: `brew install xcodegen && cd clarion-ios && xcodegen`
   → open `Clarion.xcodeproj`.
5. **Fill in `Clarion/Support/Config.swift`** — Supabase URL + anon key from
   `bloodwise-frontend/.env.local`.
6. In Xcode: set your Team under Signing & Capabilities, then build to a **real iPhone**
   (HealthKit permission flows and Watch data need hardware; the simulator works for
   unit-testing normalizers with fixture data).

## Architecture (thin companion)

| Dir | What |
| --- | --- |
| `Clarion/Models.swift` | Wire format — mirrors `bloodwise-frontend/src/lib/wearables/types.ts` **exactly**. Changing either side is a breaking API change. |
| `Clarion/Auth/` | Supabase auth via GoTrue REST (URLSession, no SDK dependency). Email+password v1; Google/SIWA in Phase 2 (adding Google triggers the App Store Sign-in-with-Apple rule). Session in Keychain. |
| `Clarion/Health/` | Persona-scoped permissions, day-bucketed HealthKit queries, normalizers. Sleep is attributed to the **wake date**; wrist-temp deviation is computed against the user's own trailing baseline (needs ~5 nights). |
| `Clarion/Sync/` | 90-day backfill on first sync, 14-day incremental after; Bearer auth + `clientVersion` on every request; workout chunking to the server's 200 cap. |
| `Clarion/UI/` | Five screens total: sign-in, connect-Health primer, Home/Today card, settings, sync detail. The Today card is the guideline-4.2 defense — every requested type is visibly used. |

## Server-side contracts this app depends on

All live in bloodwise-frontend, all bearer-authed:
- `requireApiUser` accepts `Authorization: Bearer <supabase access token>` (RLS-scoped).
- `POST /api/wearables/ingest` — merges per-field with existing rows (Oura + Apple Health on
  one account don't clobber each other), validates ranges, accepts `clientVersion`.
- `GET /api/account/persona` — `{ persona, sex, menopauseStage }`; the app scopes HealthKit
  permissions to the persona (fetched at every sign-in, cached in `@AppStorage`).
- `POST /api/account/app-login-link` — one-time magic link to a `/dashboard*` path so
  "Full analysis" opens **signed in**. ⚠️ The path must be in Supabase Auth → URL
  Configuration → Redirect URLs, or Supabase rejects the redirect.
- `POST /api/account/delete` — native in-app deletion (App Store requirement); wearable rows
  cascade on `auth.users` delete.

## Compliance guardrails (do not regress)

- Read-only HealthKit: no `NSHealthUpdateUsageDescription`, no write scopes, ever.
- Health data never reaches ads/analytics/attribution SDKs — one health value in a crash
  breadcrumb is an App Store 5.1.3 violation and a brand catastrophe.
- Wellness copy only: never "diagnose/detect/screen/treat" — keeps FDA general-wellness
  safe-harbor and App Review 1.4.1 posture.
- Account deletion must stay reachable in-app (Settings), native flow in Phase 2.
