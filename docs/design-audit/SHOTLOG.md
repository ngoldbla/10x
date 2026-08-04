# SHOTLOG — how each shot was made

Every shot ID in `INDEX.md` has an entry here, so any frame can be re-made. A
critique cites shot IDs; this file is the only place paths and commands live.

## Preconditions, common to every lane

```bash
cd nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
```

**State.** Every simulator lane seeds the same container via
`nine/scripts/ninestate.py` → `quiet_blobs(PREFS_ERRORS_ON)`: the frozen board
from `nine/Tests/AXBaselines/fixture.nine.library.json`, first-run and help
marked seen, session count 9, drawer found, all three lifetime tips spent,
`errorHighlight` and `resumeOnLaunch` on. Without it every shot would be of
*today's* board with a scatter of transient chrome, and two runs an hour apart
would not be comparable.

**The clock is pinned to 9:41** by `simrig.pin_status_bar` — Apple's demo time,
which also makes the frames look like the marketing shots they are judged
against.

**⚠️ Lanes that send AppleScript input are mutually exclusive.** `System Events`
key focus is a single global resource: the tvOS lane, the macOS lane and
`shotlist.py`'s rotation step all type, and running any two at once sends the
keys to the wrong window. Measured during this audit — see the note at the foot
of this file. Builds and asset copying may run in parallel; input may not.

---

## Builds

| Product | Command | Output |
|---|---|---|
| tvOS | `xcodebuild -project Nine.xcodeproj -scheme Nine -destination 'id=CE3BB020-7FC5-40F8-9F60-C304A294B0A6' -configuration Debug -derivedDataPath build/tvos build CODE_SIGNING_ALLOWED=NO` | `nine/build/tvos/Build/Products/Debug-appletvsimulator/Nine.app` |
| watchOS | `xcodebuild -project Nine.xcodeproj -scheme NineWatch -destination 'id=066E84D7-2EDD-42CB-9C99-1DF8DF90D03F' -configuration Debug -derivedDataPath build/watch build CODE_SIGNING_ALLOWED=NO` | `nine/build/watch/Build/Products/Debug-watchsimulator/NineWatch.app` |
| macOS | see **The macOS signing detour** below | `nine/build/mac/Build/Products/Debug/Nine.app` |
| iOS/iPadOS | built by `shotlist.py` itself into `nine/.build/shots` | `…/Debug-iphonesimulator/Nine.app` (contains `NineWidgets.appex`) |

### The macOS signing detour

The committed `nine/Nine-macOS.entitlements` declares CloudKit, KVS, Game Center
and `aps-environment`. `xcodebuild` refuses to ad-hoc-sign a binary carrying
them — *"has entitlements that require signing with a development certificate"* —
and `project.yml` additionally pins `CODE_SIGN_STYLE: Manual` with a
`PROVISIONING_PROFILE_SPECIFIER`, so `CODE_SIGN_IDENTITY=-` alone is not enough.

The audit builds against a reduced, **gitignored** entitlements file at
`.context/design-audit/tools/Nine-macOS-audit.entitlements` (sandbox +
network.client only). This is safe rather than a hack: `AppModel`'s
`mayBuildCloudContainer` asks the binary through `SecTask` whether its own
signature carries CloudKit, precisely so an unentitled local build skips
`LibraryCloudStore` instead of trapping in `CKContainer(identifier:)` — the
PRD-33 fix. The audit build is exactly the configuration that guard exists for.

```bash
cd nine && xcodebuild -project Nine.xcodeproj -scheme Nine \
  -destination 'platform=macOS,arch=arm64' -configuration Debug \
  -derivedDataPath build/mac build \
  CODE_SIGN_STYLE=Automatic CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=YES PROVISIONING_PROFILE_SPECIFIER= DEVELOPMENT_TEAM= \
  ENABLE_HARDENED_RUNTIME=NO \
  "CODE_SIGN_ENTITLEMENTS=../.context/design-audit/tools/Nine-macOS-audit.entitlements"
```

---

## Simulators

| Role | Name | UDID |
|---|---|---|
| tvOS | `CouchTV` | `CE3BB020-7FC5-40F8-9F60-C304A294B0A6` |
| iPhone | `Nine-Shotlist-iPhone` | `5598400A-BD06-459E-86E1-5AA30CE1FCB2` |
| iPad | `Nine-Shotlist-iPad` | `AA9C41B9-2192-499F-9265-04C720F9BB36` |
| watchOS | `Apple Watch Series 11 (46mm)` | `066E84D7-2EDD-42CB-9C99-1DF8DF90D03F` |

**`Nine-Loc` (`ECF01102-…`) was booted before this audit began and is another
agent's. It was never touched.**

---

## Per-shot log

Format: shot ID · how it was reached · notes. Bundles appear in ID order.
`shotlist.py` = the stock iOS/iPadOS lane (`--device both --appearance both`);
`drive.py` = the audit-owned iOS driver (`.context/design-audit/tools/`).

### B01 — identity · P8 asset lane, no simulator

| ID | How it was made |
|---|---|
| `B01-S01`…`S06` | Copied from `Assets.xcassets`: `AppIcon.appiconset/AppIcon-1024.png` (Original), Ember/Tide/Mono variants, macOS and watchOS icon sets |
| `B01-S07` | `TopShelfWide.imageset` source at 4640×1440 |
| `B01-S08` | `TopShelf.imageset` source at 3840×1440 |
| `B01-S09` | launch image source at 3840×2160 |
| `B01-S10`…`S12` | tvOS `Icon.iconset` parallax layers, back/middle/front, opened individually to verify the mark is on the front layer |

### B03 — tvOS game · P5 exclusive lane

| ID | How it was made |
|---|---|
| `B03-S01` | Boot `CouchTV` (`CE3BB020-…`), seed container via `simrig` + `ninestate.py quiet_blobs(PREFS_ERRORS_ON)`, launch with the frozen fixture; click the CouchTV window title bar first, then `key code 124/123/126/125/36/53`; capture `xcrun simctl io CouchTV screenshot`. **Discarded two earlier frames that blind input sent astray** — see the tvOS trap at the foot of this file. |

### B04 — iOS shelf · P3 stock lane

| ID | How it was made |
|---|---|
| `B04-S01` | `shotlist.py --device iphone --appearance dark` → `home` scene |
| `B04-S02` | same, `--appearance light` |
| `B04-S03` | dark, `home-bottom` scene (scrolled to bottom) |
| `B04-S04` | light, `home-bottom` |
| `B04-S05` | light, `channel` scene (Thermo page) |
| `B04-S06` | dark, `channel` |

### B05 — iOS game · P3 stock lane + P4 recede

| ID | How it was made |
|---|---|
| `B05-S01` | `shotlist.py --device iphone --appearance light` → `game` scene |
| `B05-S02` | same, `--appearance dark` |
| `B05-S03` | light, `rose` scene (flick rose open) |
| `B05-S04` | dark, `rose` |
| `B05-S05`…`S08` | `probe_recede.py`: relaunch, photograph the same screen at t = 1/4/8/15 s with **no input**, dark appearance |

### B07 — macOS · P7 exclusive lane

| ID | How it was made |
|---|---|
| `B07-S01` | snapshot aside `~/Library/Containers/com.couchsuite.nine`; seed quiet blobs; `open` the audit build (signed against the gitignored `Nine-macOS-audit.entitlements`); capture the game window via `screencapture -l <windowid>` |
| `B07-S02` | ⌘, to open Settings, then capture the window |

### B12 — theme gallery · P4 iOS driver

| ID | How it was made |
|---|---|
| `B12-S01`…`S04` | `drive.py` seeds the **stored** key `appearance` (`auto`/`camel`/`dark`/`light` — not `theme`; see the prefs-blob trap below), reads the blob back after launch, and fingerprints the board fill so an identical-frame gallery reports itself |

### Critiques cite but no image was committed

The iPad frames used by the measurements (`.context/design-audit/shots/_stock/ipad-*`,
`_recede/ipad-*`) have **no committed critique** and therefore no committed
downscale — see `INDEX.md` → What was not captured.

---

## Trap: the prefs blob key is `appearance`, not `theme`

Seeding a theme requires the **stored** key, which is not the Swift property
name. `NinePrefs` declares `var theme: ThemeChoice` and maps it with
`case theme = "appearance"` so that 1.x blobs (auto/dark/light) decode unchanged
(`nine/Sources/App/AppModel.swift`).

Writing `{"theme": "camel"}` therefore seeds **nothing**: `decodeIfPresent` never
finds the key and falls back to `.auto`. The whole nine-theme gallery came back as
nine identical dark frames — no error, no empty file, every screenshot a correct
picture of the wrong state.

It was caught by asking a question the pictures had to answer:
`ThemeChoice.colorScheme` returns `.light` for `.camel` and `.light`, so those two
frames **must** render light. Both were dark, which is impossible if the pref had
landed. Without that check the gallery would have supported a confident and
entirely fabricated finding that Nine's nine themes are visually identical.

`accent` is *not* remapped, so a run can have the accent land while the theme
silently does not — which reads as "the themes are subtle" rather than as a bug.

`.context/design-audit/tools/drive.py` now (a) writes `appearance` via a named
constant, (b) reads the blob back off the device after every launch and exits if
the value is not there, and (c) fingerprints each board's own fill so a gallery of
identical frames reports itself instead of being filed.

## Note: the failure this log exists to prevent

Two tvOS shots were captured, looked correct, and were wrong. The tvOS
accessibility tree reports only the host `PineBoard` shell, so there is nothing
to assert against and input is blind. With another lane holding key focus, every
keystroke went elsewhere — and the resulting frames were correctly exposed
pictures of a real board that were nearly filed as "the rose open" and "the rose
previewing a 7". The only tell was the pinned clock advancing (0:27 → 1:20 →
1:29) while the board did not change.

They were discarded. `.context/design-audit/tools/tvdrive.py` now carries
`press_verified`, which fingerprints the screen as a 24×24 tile-luminance grid
before and after each keystroke and raises if nothing moved. Coarse on purpose:
an exact pixel diff always reports "changed" (the clock ticks, the glass
shimmers) and therefore proves nothing.
