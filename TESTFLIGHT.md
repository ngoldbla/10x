# Shipping the Couch Suite to TestFlight

Everything binary-side is already prepared in this repo. What remains is
account-side setup in App Store Connect (one-time per app) and running one
script.

## What the repo already provides

| Requirement | Where it lives |
|---|---|
| Layered tvOS app icon (400×240 @1x/@2x) + App Store icon (1280×768) | `<app>/Assets.xcassets/App Icon & Top Shelf Image.brandassets` |
| Top Shelf image (1920×720) + wide (2320×720), @1x/@2x | same brand asset |
| Launch image (1920×1080 @1x/@2x) | `<app>/Assets.xcassets/Launch Image.launchimage` |
| Versioning (`CFBundleShortVersionString` 1.0, `CFBundleVersion` from git commit count) | `project.yml` + `scripts/testflight.sh` |
| Export-compliance answer (no non-exempt encryption) | `ITSAppUsesNonExemptEncryption: false` in each `project.yml` |
| Privacy manifest (no tracking, no data collection, no required-reason APIs) | `<app>/PrivacyInfo.xcprivacy` |
| iCloud key-value entitlement (Darkroom, Nine, Blockhead sync streaks) | generated `<App>.entitlements` via `project.yml` |
| Photos usage strings (Rabbit Ears, Darkroom, Cartridge) | `project.yml` |
| Archive → export/upload pipeline | `scripts/testflight.sh` |

Icons are deterministic pixel art rendered by `scripts/generate_brand_assets.swift`
(edit the glyph maps / palettes there and re-run to restyle; the committed
`Assets.xcassets` are its output).

## Current status (2026-07-10)

Everything below is **done** for the Aquilops LLC team (`XC6FN96MA8`):
`signing.env` is configured, all five bundle IDs are registered, all five
ASC app records exist (named "Rabbit Ears: Ambient Pixel TV", "Darkroom: Photo
Picross", "Nine: Couch Sudoku", "Blockhead: Nightly Quiz", "Cartridge: Photo
Micro-Games"), and first builds were uploaded. The sections below document the
setup for a fresh team/account.

Note on signing mechanics: the archive is built unsigned (no registered Apple TV
device exists on the team, which automatic development signing would require),
then re-signed ad-hoc with resolved entitlements so the export step — which does
the real App Store distribution signing via `-allowProvisioningUpdates` —
preserves iCloud KVS for Darkroom/Nine/Blockhead. This is all inside
`scripts/testflight.sh`; no manual steps.

## One-time setup (per Apple Developer account)

1. Join the [Apple Developer Program](https://developer.apple.com/programs/) ($99/yr).
2. Put your Team ID in `signing.env` (gitignored):

   ```bash
   COUCH_TEAM_ID=ABCDE12345
   ```

3. Sign into Xcode with the same Apple ID (Xcode → Settings → Accounts), **or**
   create an App Store Connect API key (Users and Access → Integrations) and add
   to `signing.env`:

   ```bash
   ASC_KEY_ID=XXXXXXXXXX
   ASC_ISSUER_ID=xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx
   ASC_KEY_PATH=$HOME/.appstoreconnect/AuthKey_XXXXXXXXXX.p8
   ```

## One-time setup (per app)

In [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+ New App**:

| App | Platform | Bundle ID | Name suggestion |
|---|---|---|---|
| Rabbit Ears | tvOS | `com.couchsuite.rabbitears` | Rabbit Ears — Ambient Pixel TV |
| Darkroom | tvOS | `com.couchsuite.darkroom` | Darkroom — Photo Picross |
| Nine | tvOS | `com.couchsuite.nine` | Nine — Couch Sudoku |
| Blockhead | tvOS | `com.couchsuite.blockhead` | Blockhead — Nightly Quiz |
| Cartridge | tvOS | `com.couchsuite.cartridge` | Cartridge — Photo Micro-Games |

Notes:

- The bundle IDs register automatically the first time you archive with
  `-allowProvisioningUpdates` (or add them under Certificates, Identifiers &
  Profiles → Identifiers). For **Darkroom, Nine, and Blockhead**, make sure the
  identifier has the **iCloud** capability (key-value storage) checked — the
  entitlement is already in the binary; automatic signing will request it.
- App name on ASC must be globally unique; the "Name suggestion" column adds a
  descriptor for that reason. `CFBundleDisplayName` (what shows under the icon)
  stays the short name.

## Ship a build

```bash
scripts/testflight.sh rabbit-ears --upload   # one app
scripts/testflight.sh all --upload           # the whole suite
```

The script regenerates the Xcode project, archives for `generic/platform=tvOS`
with `CFBundleVersion = git commit count` (monotonic, no manual bumping),
exports with `method: app-store-connect`, and uploads. Processing on Apple's
side takes 5–15 minutes; the build then appears under TestFlight in ASC.

Without `--upload` the script exports a signed `.ipa` into `<app>/dist/` that
you can hand to Transporter.

First-build review notes:

- **Internal testing** (your team, up to 100 testers) needs no review — the
  build is testable the moment processing finishes.
- **External testing** requires a brief Beta App Review. All five apps run fully
  featured with zero permissions (procedural demo art until Photos is granted),
  so no demo account or reviewer notes are needed. A one-liner like "All content
  is generated on-device; grant Photos to see personal art" is plenty.

## Verify before shipping

```bash
cd <app> && xcodegen generate
xcodebuild -scheme <Scheme> -destination 'platform=tvOS Simulator,name=CouchTV' build
```

See `BUILD.md` for the full simulator run/screenshot loop, and
`.claude/skills/run-couch-suite` for the agent-driven variant.

## Known deferrals (fine for TestFlight)

- **Top Shelf extensions** (the dynamic content row when an app sits in the top
  row of the home screen) are a v1.1 item suite-wide; the static Top Shelf
  images shipped here are the correct fallback and satisfy App Store validation.
- App Store **screenshots/metadata** are only needed for external TestFlight
  groups and App Store release, not for internal TestFlight builds.

## Fastlane (all five apps)

Every Couch Suite app now ships via Fastlane with `match`-managed signing:

```bash
set -a && source signing.env && set +a
fastlane ios beta app:darkroom upload:false   # dry run: signed .ipa in darkroom/dist/
fastlane ios beta app:darkroom                # build, sign, upload one app to TestFlight
fastlane ios beta_all                         # build + upload all five apps
```

`app:` accepts `rabbit-ears` (default), `darkroom`, `nine`, `blockhead`, or
`cartridge` (see the `APPS` map in `fastlane/Fastfile`).

Signing assets live encrypted in the private repo `couch-suite-certificates`.
The **team distribution certificate was imported** into `match` (the account was
at Apple's cert limit, so no new cert was minted); `match` created a **tvOS** App
Store profile per app, named `match AppStore <bundle-id> tvos`. Each app signs its
archive directly with that distribution profile — tvOS App Store profiles need no
registered devices, so the unsigned-archive + ad-hoc re-sign dance in
`scripts/testflight.sh` is **not** needed on this path. The iCloud key-value
entitlement for Darkroom/Nine/Blockhead is baked in at archive time and verified
present in the signed binaries.

The `beta` lane always runs `match(readonly: true)` — only the one-time bootstrap
mints/imports. Local runs use the Homebrew `fastlane` (no `bundle exec`); the
committed `Gemfile` pins the version for the future CI migration. Notes for that
migration: `MATCH_PASSWORD` is already a GitHub secret on the repo; certs-repo
commits must use a GitHub **noreply** email (private-email push protection); and
`match` needs the tvOS platform (`platform: "tvos"`) and the `…tvos` profile name.

**CI:** `.github/workflows/testflight-tvos.yml` runs `bundle exec fastlane ios
beta_all` on merge to `main` (or one app via `workflow_dispatch` with `app:`;
`validate_only: true` = dry run, no upload). It installs a **read-only SSH deploy
key** (`MATCH_DEPLOY_KEY` secret) to clone the certs repo, then `match(readonly)`
+ `gym` + `pilot`. `setup_ci` manages a temp keychain — no manual cert import.

Required GitHub secrets on `ngoldbla/10x`: `COUCH_TEAM_ID`, `ASC_API_KEY_ID`,
`ASC_API_ISSUER_ID`, `ASC_API_KEY_P8` (base64 .p8), `MATCH_PASSWORD`,
`MATCH_DEPLOY_KEY` (private half of a read-only deploy key added to
`couch-suite-certificates`). The legacy `APPLE_DISTRIBUTION_CERT_P12` /
`APPLE_CERT_PASSWORD` / `KEYCHAIN_PASSWORD` secrets are no longer used and can be
removed. `scripts/testflight.sh` is retained as a manual fallback but CI no
longer calls it.

