# Shipping Nine to TestFlight

Everything binary-side is already prepared in this repo. What remains is
account-side setup in App Store Connect (one-time) and running one lane.

Nine is **universal**: one target, one bundle ID (`com.couchsuite.nine`), with a
remote UI on tvOS, a touch UI on iPhone/iPad and a keyboard UI on the Mac. It
embeds two more bundles — `NineWidgets` (iOS) and `NineWatch` (watchOS). Its ASC
app record carries all three platforms, and each uploads to its own TestFlight
build train under the same app.

## What the repo already provides

| Requirement | Where it lives |
|---|---|
| Layered tvOS app icon (400×240 @1x/@2x) + App Store icon (1280×768) | `nine/Assets.xcassets/App Icon & Top Shelf Image.brandassets` |
| Top Shelf image (1920×720) + wide (2320×720), @1x/@2x | same brand asset |
| Launch image (1920×1080 @1x/@2x) | `nine/Assets.xcassets/Launch Image.launchimage` |
| Flat iOS / macOS / watchOS app icons + alternate iOS icons (PRD-16) | `nine/Assets.xcassets/AppIcon*.appiconset` |
| Versioning (`CFBundleShortVersionString` 1.0, `CFBundleVersion` from git commit count) | `nine/project.yml` + `fastlane/Fastfile` |
| Export-compliance answer (no non-exempt encryption) | `ITSAppUsesNonExemptEncryption: false` in `nine/project.yml` |
| Privacy manifest (no tracking, no data collection, no required-reason APIs) | `nine/PrivacyInfo.xcprivacy` |
| iCloud KVS, CloudKit and Game Center entitlements | the four checked-in `nine/*.entitlements` files |
| Archive → sign → upload pipeline | `fastlane/Fastfile` (`scripts/testflight.sh` is the manual tvOS-only fallback) |

Icons are deterministic pixel art rendered by `scripts/generate_brand_assets.swift`
(edit the glyph map / palette there and re-run to restyle; the committed
`Assets.xcassets` is its output).

## Build numbers

`CFBundleVersion` is `git rev-list --count HEAD × 10`, plus a per-platform offset
— tvOS +0, iOS +1, macOS +2. App Store Connect enforces uniqueness per app
record, **not** per platform, so a universal app's three builds must never share
a number; the disjoint trains are what keep them apart (commit 23 → tvOS 230,
iOS 231, mac 232).

It is computed in CI and never committed back, so there is no self-trigger loop.
The workflow checks out at `fetch-depth: 0` for this reason — a shallow clone
would make the count 1 every run.

**This is why this repo's history was reduced by plain deletion rather than
`git filter-repo` when the four sibling apps were split out.** Rewriting history
can drop commits, and a lower commit count means a lower build number, which ASC
rejects. If you ever do rewrite this repo's history, check the resulting count
against the last build in ASC before shipping.

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

Already **done** for the Aquilops LLC team (`XC6FN96MA8`): `signing.env` is
configured, the bundle IDs are registered, the ASC app record exists ("Nine:
Couch Sudoku"), and builds have shipped on all three platforms. The section
below documents the setup for a fresh team or account.

In [App Store Connect](https://appstoreconnect.apple.com) → Apps → **+ New App**:

| App | Platforms | Bundle ID | Name suggestion |
|---|---|---|---|
| Nine | tvOS + iOS + macOS | `com.couchsuite.nine` | Nine — Couch Sudoku |

Notes:

- The bundle IDs register automatically the first time you archive with
  `-allowProvisioningUpdates` (or add them under Certificates, Identifiers &
  Profiles → Identifiers). The identifier needs **iCloud** (key-value storage
  *and* CloudKit), **Game Center**, and **App Groups** — see the widget and
  watch sections below for the exact order.
- App name on ASC must be globally unique; the "Name suggestion" column adds a
  descriptor for that reason. `CFBundleDisplayName` (what shows under the icon)
  stays "Nine".

## Ship a build

```bash
set -a && source signing.env && set +a
bundle install
bundle exec fastlane ios beta app:nine platform:tvos upload:false  # dry run
bundle exec fastlane ios beta_app app:nine                         # tvOS + iOS + macOS
```

The lane runs `match(readonly: true)` → `xcodegen generate` → `gym` (manual App
Store distribution signing, so entitlements bake in at archive time — no ad-hoc
re-sign) → `pilot`. Processing on Apple's side takes 5–15 minutes.

`platform:` accepts `tvos` (default), `ios` or `mac`. `upload:false` exports a
signed artifact into `nine/dist/` instead of uploading. On the mac leg gym
produces a `.pkg` rather than an `.ipa`, and the lane points pilot at it
explicitly — pilot defaults to "ipa preferred" and would otherwise re-upload the
leftover `Nine-iOS.ipa` from the iOS leg, colliding on a build number that had
just shipped.

**CI:** `.github/workflows/testflight-tvos.yml` runs `bundle exec fastlane ios
beta_all` on merge to `main` (or one platform via `workflow_dispatch`;
`validate_only: true` = dry run, no upload). It installs a **read-only SSH deploy
key** (`MATCH_DEPLOY_KEY` secret) to clone the certs repo, then `match(readonly)`
+ `gym` + `pilot`. `setup_ci` manages a temp keychain — no manual cert import.

Required GitHub secrets on `ngoldbla/10x`: `COUCH_TEAM_ID`, `ASC_API_KEY_ID`,
`ASC_API_ISSUER_ID`, `ASC_API_KEY_P8` (base64 .p8), `MATCH_PASSWORD`,
`MATCH_DEPLOY_KEY` (private half of a read-only deploy key added to
`couch-suite-certificates`).

## Signing assets

Signing assets live encrypted in the private repo `couch-suite-certificates`,
which is **still shared with the four spun-out Couch Suite apps** —
`ngoldbla/{rabbit-ears,darkroom,blockhead,cartridge}` each hold a read-only
deploy key to the same store. `fastlane/Matchfile` here is scoped to Nine's
three bundle ids so a bare `fastlane match` cannot reach a sibling's profiles,
and theirs are scoped the same way in the other direction.

Per-platform profiles are match-named `match AppStore <bundle> tvos` (tvOS),
`match AppStore <bundle>` (iOS) and `match AppStore <bundle> macos` (macOS). The
team distribution certificate was **imported** into match rather than minted —
the account was at Apple's certificate limit. The `beta` lane always runs
`match(readonly: true)`; only a one-time bootstrap mints or imports.

Local-run gotcha: a Mac holding stale copies of the distribution cert in other
keychains triggers password prompts. Put fastlane's temp keychain first —
`CI=true` plus `security list-keychains -d user -s fastlane_tmp_keychain
login.keychain` — so codesign resolves the match-managed key. Certs-repo commits
must use a GitHub **noreply** email (private-email push protection).

## First-build review notes

- **Internal testing** (your team, up to 100 testers) needs no review — the
  build is testable the moment processing finishes.
- **External testing** requires a brief Beta App Review. Nine runs fully
  featured with zero permissions and no account, so no demo account or reviewer
  notes are needed. Testers who want Game Center leaderboards must be signed
  into Game Center in Settings.

## Verify before shipping

```bash
cd nine && swift test && python3 scripts/strings.py --audit
cd nine && xcodegen generate
xcodebuild -scheme Nine -destination 'platform=tvOS Simulator,name=CouchTV' build
```

See [BUILD.md](BUILD.md) for the full simulator loop and the measured gates, and
`.claude/skills/run-nine` for the agent-driven variant.

## Known deferrals (fine for TestFlight)

- **Top Shelf extensions** (the dynamic content row when the app sits in the top
  row of the home screen) are a v1.1 item; the static Top Shelf images shipped
  here are the correct fallback and satisfy App Store validation.
- App Store **screenshots and metadata** are only needed for external TestFlight
  groups and App Store release, not for internal TestFlight builds.

## Game Center (Nine, one-time — done 2026-07-16)

Nine 1.1 reports to two leaderboards (`com.couchsuite.nine.points`,
`com.couchsuite.nine.streak`) and seven achievements (`GameCenter.ID` in
`nine/Sources/App/GameCenter.swift`). The ASC records were created via the App
Store Connect API by `scripts/setup_gamecenter_nine.rb` (idempotent — safe to
re-run; reads `~/.appstoreconnect/asc_api_key.json`, runs with Homebrew ruby +
fastlane's jwt gem: `GEM_PATH=/opt/homebrew/Cellar/fastlane/<v>/libexec
/opt/homebrew/opt/ruby/bin/ruby scripts/setup_gamecenter_nine.rb`).

Not-yet-released Game Center items work immediately in development and
TestFlight builds (testers must be signed into Game Center in Settings).
Before the public App Store release: upload achievement/leaderboard artwork in
ASC and include Game Center with the version submission — until then the
dashboard shows placeholder art, which is fine for beta.

## Widgets (Nine iOS, one-time — REQUIRED BEFORE MERGING PRD-3)

Nine iOS embeds the `NineWidgets` extension (`com.couchsuite.nine.widgets`,
app group `group.com.couchsuite.nine`). match does not manage capabilities,
and adding App Groups **invalidates the existing iOS `com.couchsuite.nine`
profile** — sequence portal → re-mint → merge, or the next nine/iOS CI run
fails signing (PRD-3 §3a):

1. **Portal (manual):** create app group `group.com.couchsuite.nine`;
   register App ID `com.couchsuite.nine.widgets` with the App Groups
   capability and assign the group; enable App Groups on the **iOS**
   `com.couchsuite.nine` App ID and assign the same group. (tvOS App ID
   untouched.)
2. **Re-mint writable match (local, one-time):** `source signing.env &&
   fastlane match appstore` (Matchfile already lists the widget bundle id) —
   plus `fastlane match development` if you debug on device. CI stays
   `readonly: true`.
3. Merge. The Fastfile fetches both profiles on the nine/iOS leg
   (`APPS["nine"][:extensions]`) and exports with both provisioning-profile
   entries; the tvOS leg is unchanged.

Verify with `fastlane beta app:nine platform:ios upload:false`.

## The watch app (Nine iOS, one-time — REQUIRED BEFORE MERGING PRD-6)

Nine iOS now embeds `NineWatch` (`com.couchsuite.nine.watchkitapp`), whose only
entitlement is iCloud key-value storage pinned to the *app's* identifier. Same
hazard as the widget, and the same order — **embedding a new bundle changes the
iOS archive's profile set, so the existing `com.couchsuite.nine` profile must be
re-minted before the next CI run or the nine/iOS leg fails signing, which takes
`beta_all` with it.**

1. **Portal (manual):** register App ID `com.couchsuite.nine.watchkitapp` and
   enable **iCloud** on it (key-value store). No app group, no CloudKit, no
   push — the watch declares none of them.
2. **Re-mint writable match (local, one-time):** `source signing.env &&
   fastlane match appstore`. The Matchfile already lists the watch bundle id.
   CI stays `readonly: true` and can mint nothing.
3. Verify: `fastlane beta app:nine platform:ios upload:false` must resolve
   three profiles — app, widget, watch — and export.
4. Merge.

No new lane and no new platform value: a watch app ships *inside* the iOS ipa,
so `beta app:nine platform:ios` already carries it, and `CURRENT_PROJECT_VERSION`
rides the same project-wide xcargs, which is what keeps the embedded watch app's
version in lockstep with its host (ASC rejects them otherwise).
