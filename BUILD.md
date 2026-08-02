# Building Nine

One universal app plus the CouchKit Swift package it is built on. Engine and
catalog logic is verified by tests that run on any platform, with no Xcode.

## Prerequisites

- macOS with **Xcode 26+** (tvOS 26 / iOS 26 SDKs for Liquid Glass; the app
  deploys back to tvOS 18 / iOS 18 with an automatic material fallback via
  CouchKit's `CouchGlass` shim)
- **XcodeGen** (`brew install xcodegen`) — project files are generated, never
  committed
- Python 3 for the harnesses in `nine/scripts/`

## Build & run

```bash
cd nine
xcodegen generate
open Nine.xcodeproj      # pick a destination, Cmd+R
```

`xcodegen generate` produces three targets:

| Target | Destinations |
|---|---|
| `Nine` | tvOS, iOS (iPhone + iPad), macOS — one universal target |
| `NineWidgets` | iOS app extension (WidgetKit); filtered out of the tvOS and macOS graphs |
| `NineWatch` | watchOS, embedded in the iOS app |

Nine depends on `../couchkit` as a local SwiftPM package. There are no other
dependencies and no remote packages anywhere in the repo.

## Verify without Xcode (any platform)

```bash
cd nine     && swift test    # engine + shared, including the golden corpus
cd couchkit && swift test    # CouchCore + the pure half of PadKit

cd nine && python3 scripts/strings.py --selftest-catalog
cd nine && python3 scripts/strings.py --audit
```

These four commands are exactly what `.github/workflows/nine-engine.yml` runs on
every pull request, so a green run locally is a green run in CI.

## The measured gates

`.github/workflows/nine-accessibility.yml` runs the expensive lane on every PR.
It is deliberately separate from the TestFlight workflow: that one ships and must
never be blocked by a slow simulator; this one gates review and is free to be
slow.

| Harness | What it measures |
|---|---|
| `nine/scripts/ax-snapshot.py` | the accessibility tree per screen, diffed against committed baselines |
| `nine/scripts/contrast-harness.py` | contrast sampled from screenshots of the composited glass, not computed from theme constants |
| `nine/scripts/loc-harness.py` | pseudo-localization and RTL, five screens × five locale modes |
| `nine/scripts/shotlist.py` | photographs every surface across iPhone/iPad × light/dark × portrait/landscape. No baselines and no gate by design — a pixel diff of a live-blur material is noise — so it produces evidence and leaves judgement to the reader. |

All four sit on `nine/scripts/simrig.py`: the dedicated simulator, the erase, the
bridge warm-up, the seeded container, the settle-before-you-read discipline.
Every one of those exists because of a specific way the naive version was flaky.

Baselines live beside the harnesses in `nine/Tests/{AXBaselines,ContrastBaselines,LocBaselines}`.
The committed files are the contract; the `.captured/` directories next to them
are what a comparison run actually saw and are gitignored.

## Ship to TestFlight

```bash
echo 'COUCH_TEAM_ID=<your team id>' > signing.env   # gitignored, one-time
bundle install
bundle exec fastlane ios beta_app app:nine upload:false   # dry run, all platforms
```

See [TESTFLIGHT.md](TESTFLIGHT.md) for App Store Connect setup and the required
GitHub secrets.

## Known caveats

- Top Shelf extensions and sound are deferred (v1.1) — see `nine/DEVIATIONS.md`.
- The localization lane is knowingly stale: its symbol anchors no longer match
  the redesigned sheets, and its baselines are uniformly old rather than partly
  re-recorded.
- `ja-home` AX baselines still rot when the rendered date changes *width* (a
  single-to-double-digit day, or a longer month name). Daily rot is masked;
  monthly rot is not. Fixing it means pinning the clock in the seeded state,
  which is simrig's territory and a change all three lanes would inherit.
