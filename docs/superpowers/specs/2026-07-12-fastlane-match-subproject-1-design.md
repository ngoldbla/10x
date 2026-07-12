# Fastlane adoption — Sub-project 1: foundation + `match` + `beta` lane (rabbit-ears)

**Status:** Approved design, ready for implementation planning
**Date:** 2026-07-12
**Owner:** ngoldbla

## Goal

Adopt Fastlane for the Couch Suite, starting with a single vertical slice: a
Fastlane foundation, `match`-managed code signing stored in a private Git repo,
and a `beta` lane that builds and uploads **rabbit-ears only** to TestFlight —
replacing, for that one app, the hand-rolled `scripts/testflight.sh` path.

This is the first of four sub-projects toward full Fastlane adoption (motivation:
"full adoption," option C). Each sub-project is scoped, spec'd, planned, and
implemented separately. See the roadmap at the end.

## Why rabbit-ears first

rabbit-ears has **no `.entitlements`** (no iCloud key-value storage), so it
isolates the `match` + lane mechanics from the ad-hoc re-sign complication that
Darkroom/Nine/Blockhead need. If signing breaks, we know it's the match/lane
half, not the entitlements half. Clean experiment; small blast radius.

## Chosen approach: Approach 2 — full match, manual distribution signing

`match` manages the Apple Distribution certificate **and** an App Store
provisioning profile for `com.couchsuite.rabbitears`. The archive is signed
manually with that distribution profile.

**Key realization:** the existing `testflight.sh` archives *unsigned* because
*automatic **development** signing* at archive time requires a registered Apple
TV device on the team (none exists). **App Store *distribution* profiles need no
registered devices.** Signing the archive manually with a match-managed
distribution profile therefore sidesteps the exact problem the unsigned-archive
workaround was built for. Both the unsigned archive **and** the ad-hoc re-sign
hack disappear; entitlements bake in naturally at archive time (moot for
rabbit-ears, but this proves the pattern for the KVS apps in Sub-project 2).

**Fallback — Approach 3 (documented, not implemented):** if archive-time tvOS
distribution signing misbehaves, revert to the proven unsigned-archive +
ad-hoc re-sign flow, but pin the **match**-managed profile explicitly at export
(dropping `-allowProvisioningUpdates`). No redesign required; only the lane's
build/sign step changes.

## Scope

### In scope
- `fastlane/Fastfile`, `fastlane/Appfile`, `fastlane/Matchfile`, `Gemfile` +
  `Gemfile.lock`.
- `match` mints a **fresh** Apple Distribution cert + App Store profile for
  `com.couchsuite.rabbitears`, encrypted into the private repo
  `git@github.com:ngoldbla/couch-suite-certificates.git` (already created,
  private, empty).
- A `beta` lane that builds and uploads rabbit-ears to TestFlight, with a
  dry-run mode (`upload:false`) that exports a signed `.ipa` without uploading.
- `rabbit-ears/project.yml` switched to manual App Store distribution signing.
- Reuse the existing App Store Connect API key (`ASC_KEY_ID` / `ASC_ISSUER_ID` /
  `ASC_KEY_P8` or `ASC_KEY_PATH`) for both `match` and `pilot`.

### Explicitly out of scope (deferred)
- The other four apps and the iCloud-KVS re-sign story → **Sub-project 2**.
- **`.github/workflows/testflight-tvos.yml` is not touched.** The green CI
  pipeline keeps running `testflight.sh`. The `beta` lane is validated
  **locally** in this sub-project. CI migration → **Sub-project 2**.
- `deliver` / App Store release + metadata → **Sub-project 3**.
- `snapshot` screenshots (needs a UI test target that doesn't exist) →
  **Sub-project 4**.

`scripts/testflight.sh` remains **untouched** throughout and continues to ship
all five apps. It is the safety net for this sub-project.

## Files created / changed

| File | Change |
|---|---|
| `fastlane/Fastfile` | New. Lane `beta` (build + upload rabbit-ears); private helper `api_key` (ASC key shim, supports base64 `ASC_KEY_P8` and file-path `ASC_KEY_PATH`); `setup_ci` + `readonly` match scaffolding readied for CI but not yet wired to a workflow. |
| `fastlane/Appfile` | New. `team_id` from `COUCH_TEAM_ID`; `app_identifier` supplied per-lane (single-app scope for now). |
| `fastlane/Matchfile` | New. `git_url` = certs repo, `storage_mode "git"`, `type "appstore"`, `app_identifier(["com.couchsuite.rabbitears"])`. |
| `Gemfile` / `Gemfile.lock` | New. Pin `fastlane` (currently 2.237.0) for reproducible tooling. CI adopts `bundle install` in Sub-project 2. |
| `rabbit-ears/project.yml` | `CODE_SIGN_STYLE: Automatic` → `Manual`; add `CODE_SIGN_IDENTITY: "Apple Distribution"` and `PROVISIONING_PROFILE_SPECIFIER` referencing the match-managed profile; keep `DEVELOPMENT_TEAM` / `COUCH_TEAM_ID`. |
| `signing.env` (gitignored) | Add `MATCH_PASSWORD` and `MATCH_GIT_URL`. Reuses existing `COUCH_TEAM_ID` + `ASC_*`. |
| `.gitignore` | Add Fastlane noise (`fastlane/report.xml`, `fastlane/README.md` regeneration, `*.mobileprovision`, etc.). |

## The `beta` lane — data flow

```
xcodegen generate (rabbit-ears)
   ↓
app_store_connect_api_key   ← ASC_KEY_ID / ASC_ISSUER_ID / ASC_KEY_P8 (base64) or ASC_KEY_PATH
   ↓
setup_ci                    ← temp keychain on CI; no-op locally (built in now, exercised in SP2)
   ↓
match(type: "appstore", readonly: true)   ← installs cert + profile; NEVER mints in the beta lane
   ↓
gym(scheme: "RabbitEars", export_method: "app-store",
    xcargs: "CURRENT_PROJECT_VERSION=$(git rev-list --count HEAD)")    ← signed archive; entitlements bake in
   ↓
pilot(skip_waiting_for_build_processing: true)     ← skipped when invoked with upload:false (dry run → signed .ipa only)
```

**Build number stays git-derived** (`git rev-list --count HEAD`): monotonic,
never committed back, identical to today's behavior. **No `increment_build_number`**
— that would commit to the repo and risk self-triggering CI.

## Signing model

`match` mints the Apple Distribution cert + an App Store provisioning profile
for the one bundle ID and encrypts them into `couch-suite-certificates`.
`project.yml` switches rabbit-ears to manual signing pointing at that profile.
Because it is an App Store distribution profile, `gym` signs the archive with no
registered-device requirement.

**Bootstrap (one-time, requires explicit go-ahead at implementation time):**
`fastlane match appstore` is run **once, non-readonly**, to create and push the
cert + profile. This is the only account-mutating, hard-to-reverse step — it
mints a real distribution certificate in the Apple Developer account. It will
**not** be run without explicit confirmation at that moment. The maintainer
chooses/stores a strong `MATCH_PASSWORD` (password manager); it becomes a GitHub
secret in Sub-project 2.

The existing distribution cert (in the `APPLE_DISTRIBUTION_CERT_P12` GitHub
secret) is left valid and untouched, so `testflight.sh` keeps shipping the other
four apps during and after this sub-project. If Apple's distribution-cert limit
is hit, the old cert is revoked at the Sub-project 2 cutover, not now.

## Error handling

- **Approach 3 fallback** documented above for archive-time signing failure —
  only the lane's build/sign step changes.
- The `beta` lane **always** runs `match(readonly: true)` — locally and on CI.
  The only read-write `match` invocation is the dedicated one-time bootstrap
  (a separate command / lane), so a normal build can never mint or regenerate
  certs.
- Fastlane exits non-zero on failure (loud, no silent failures).
- The ASC key shim supports **both** base64 `ASC_KEY_P8` and file-path
  `ASC_KEY_PATH`, matching `testflight.sh` so local and CI auth stay consistent.
- `testflight.sh` remains a complete working fallback for rabbit-ears.

## Verification (definition of done)

1. **Dry run:** `bundle exec fastlane ios beta upload:false` produces a signed
   `.ipa`; `codesign -dv --verbose=4` confirms Apple Distribution identity and
   the match-managed provisioning profile.
2. **End-to-end:** `bundle exec fastlane ios beta` results in the rabbit-ears
   build appearing under TestFlight in App Store Connect (processing 5–15 min).
3. The certs repo `couch-suite-certificates` now contains encrypted `certs/`
   and `profiles/` entries.

## Roadmap (later sub-projects — each separately scoped)

| # | Sub-project | Delivers |
|---|---|---|
| 2 | Roll `beta` out to all 5 apps + migrate CI | Darkroom/Nine/Blockhead (iCloud-KVS), retire `scripts/testflight.sh`, rework `testflight-tvos.yml` to `bundle exec fastlane ios beta` + `match --readonly`, rotate GitHub secrets (add `MATCH_PASSWORD`/`MATCH_GIT_URL`, retire `APPLE_DISTRIBUTION_CERT_P12` once the match cert is authoritative). Validate the entitlements-bake-in claim on the KVS apps. |
| 3 | `release` lane (`deliver`) | App Store submission + metadata management. |
| 4 | `snapshot` screenshots | tvOS UI-test-driven store screenshots (requires adding a UI test target). |

## Open decisions deferred to their sub-projects
- Whether SP2 keeps a single shared App Store profile per app or a wildcard.
- Whether SP2 revokes the legacy distribution cert or keeps both during a grace
  period.
- SP4 UI-test target design.
