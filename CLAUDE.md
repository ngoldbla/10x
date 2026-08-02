# Working in this repo

This repo is **Nine and CouchKit**. It was the five-app Couch Suite until the
four feature-complete siblings moved to repositories of their own; if you find a
PRD, a `DEVIATIONS.md` entry or a source comment that talks about Rabbit Ears,
Darkroom, Blockhead or Cartridge, it is a record of a decision made when the
suite was one repository. **Leave those as written** — rewriting them to match
the present would falsify them.

`nine/docs/EXECUTING-A-PRD.md` is the playbook for changing Nine. Read it before
starting a PRD; it carries the determinism contract, the persistence rules and
the traps below in more detail than this file does.

## The two folders

- `nine/` — the app. Universal target (tvOS + iOS + macOS) plus `NineWidgets`
  (iOS extension) and `NineWatch` (watchOS, embedded in the iOS app).
- `couchkit/` — the shared Swift package, consumed as a local path dependency
  (`../couchkit`). It is developed **here**, in the same commits as the app.
  That is not a compromise; it is what actually happened for the whole life of
  the suite, and the reason it stayed when the other apps left.

`couchkit/API.md` is the interface contract. `couchkit/ASKS-PLAN.md` and the
`COUCHKIT-ASKS.md` files describe an ask-and-triage protocol between separate
app threads — historical, not live.

## Verify before you claim

```bash
cd nine     && swift test
cd couchkit && swift test
cd nine     && python3 scripts/strings.py --selftest-catalog && python3 scripts/strings.py --audit
```

Those four are the PR gate (`.github/workflows/nine-engine.yml`). The expensive
lane (`nine-accessibility.yml`) runs the AX-tree, contrast and localization
harnesses — see BUILD.md. A green build is not evidence; the harnesses exist
because green builds shipped defects that only showed up on a real screen.

## Traps that have already fired

- **Entitlements.** `.gitignore` ignores `*/*.entitlements` because XcodeGen
  generates them, with four explicit `!nine/*.entitlements` exceptions for the
  files that cannot be generated. That rule has swallowed a needed entitlements
  file before and broken the CI mac archive. If you add one, add the negation.
- **Build numbers.** `CFBundleVersion` is `git rev-list --count HEAD × 10` plus
  a per-platform offset (tvOS +0, iOS +1, mac +2). ASC enforces uniqueness per
  *app record*, not per platform, so the disjoint trains are load-bearing.
  Anything that lowers the commit count lowers the build number, which ASC
  rejects — which is why the four sibling apps were removed with `git rm` rather
  than `git filter-repo`. Do not rewrite this repo's history.
- **`LibraryCloudStore` builds a `CKContainer(identifier:)`,** which traps on a
  binary holding the iCloud account but not the CloudKit entitlement. Keep
  `AppModel` off any target that does not carry it — this is why `Theme.swift`
  exists separately from `AppModel.swift`, so `BoardView` can compile into the
  watch target without dragging the model in.
- **Tests that read source files as text.** `SharedPaletteTests` walks `#filePath`
  out of `nine/` and parses `couchkit/Sources/CouchKit/CouchUI.swift` to assert a
  palette literal; others assert that named enums live in named files. A verbatim
  move is not a free move — if you move a type, repoint the test at the file that
  now owns the fact rather than relaxing the assertion.
- **CouchKit's SwiftUI layer is gated `#if os(tvOS)`**, not
  `#if canImport(SwiftUI)`. macOS can import SwiftUI but lacks
  `onPlayPauseCommand`, `glassEffect` and the absolute microGamepad dpad, so a
  Mac `swift test` of the umbrella target fails unless the UI files compile to
  nothing off-tvOS.
- **`#available` needs every platform named.** A bare `*` means "available at the
  deployment target on anything not listed", so adding a platform to
  `Package.swift` silently claims Liquid Glass on it and makes the material
  fallback unreachable.
- **The `.xcodeproj` is generated.** Edit `nine/project.yml`, never the project
  file. Same for `Info.plist`.

## Art direction

The five rules are in the README and they still govern every surface. The one
worth repeating here because it is the easiest to violate by accident: the
default state of every screen is **zero visible UI**. Chrome is transient glass
that appears on input and recedes; the pixel aesthetic belongs to the content
layer only, never to buttons.
