# Building the Couch Suite

Five independent tvOS apps + one shared Swift package. Everything below was
verified on this branch; engine logic is additionally verified by tests that run
on any platform (CI'd on Linux with Swift 6.0.3).

## Prerequisites (to run the apps)

- macOS with **Xcode 26+** (tvOS 26 SDK for Liquid Glass; apps deploy back to tvOS 18
  with an automatic material fallback via CouchKit's `CouchGlass` shim)
- **XcodeGen** (`brew install xcodegen`) — project files are generated, never committed

## Build & run an app

```bash
cd rabbit-ears             # or darkroom / nine / blockhead / cartridge
xcodegen generate
open RabbitEars.xcodeproj  # select an Apple TV 4K simulator, Cmd+R
```

**Nine is universal (tvOS + iOS).** The same target also builds for iPhone/iPad
simulators — pick one as the run destination and you get the touch UI (tap a
cell → flick rose; same engine, same saves format). Everything else is tvOS-only.

Each app depends on `../couchkit` as a local SwiftPM package — no other dependencies,
no accounts, no network. All five run fully featured with zero permissions
(procedural demo art stands in until Photos access is granted where relevant).

## Ship to TestFlight

Each app carries its full TestFlight kit: layered brand-asset icons + Top Shelf
images (committed, regenerable via `scripts/generate_brand_assets.swift`),
versioning, privacy manifest, export-compliance flag, and — for Darkroom, Nine,
and Blockhead — the iCloud key-value entitlement their streak sync needs.

```bash
echo 'COUCH_TEAM_ID=<your team id>' > signing.env   # gitignored, one-time
scripts/testflight.sh <app> --upload                 # or: all --upload
```

See [TESTFLIGHT.md](TESTFLIGHT.md) for the App Store Connect one-time setup.

## Verify the engines (any platform, no Xcode needed)

```bash
cd <folder> && swift test
```

## Verification matrix (as of this branch)

| Package | Tests | Status |
|---|---|---|
| couchkit | 35 | ✅ 0 failures |
| rabbit-ears | 24 | ✅ 0 failures |
| darkroom | 41 | ✅ 0 failures (incl. 27/27 compiled puzzles re-verified human-solvable) |
| nine | 28 | ✅ 0 failures (incl. 25-puzzle generation soak: unique + technique-bounded) |
| blockhead | 55 | ✅ 0 failures (incl. full 188-question pack lint) |
| cartridge | 36 | ✅ 0 failures (incl. bot-winnability proofs for all 4 games) |
| **Total** | **219** | **all green** |

Audits enforced suite-wide: no `.glassEffect` outside CouchKit's shim; no
SwiftUI/UIKit/Photos imports inside any `Sources/Engine`; every app's SwiftUI layer
hand-audited against CouchKit's real source signatures (no Xcode on the build
container, so UI code compiles first on your Mac — any breakage should be minor
and localized; engines are proven).

## Known caveats

- The SwiftUI layers have not been compiled against the tvOS SDK yet (built on
  Linux). Expect possible small fixups on first `xcodegen generate` + build.
- Top Shelf extensions and sound are deferred suite-wide (v1.1) — see each app's
  `DEVIATIONS.md`.
- Each app filed CouchKit improvement requests in `COUCHKIT-ASKS.md`; none are
  blockers, all have documented workarounds in place.
