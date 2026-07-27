# PRD-20 "Nine in Nine Languages" — the catalog, and the grammar underneath it

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every user-facing string in Nine resolves through a String Catalog in
nine languages, with the Engine still naming nothing and still compiling on Linux.

**Architecture:** Three layers. The **Engine** loses its three display properties
and keeps its enum raw values as the stable identity (they are already frozen
inside the golden corpus hash, so this costs nothing). **Shared** stays
Linux-clean and keeps its formatting logic, resolving text through a
`Phrasebook` seam whose default is the English table the tests already assert
against. A new Darwin-only **`Sources/Strings/`** tree — listed by *both* Xcode
targets, because `Sources/Shared` compiles into the widget extension too — owns
`Localizable.xcstrings` and the `Strings.swift` that installs the real
phrasebook at launch.

**Tech Stack:** Swift 6, SwiftUI, String Catalogs (`.xcstrings`),
`xcstringstool`, XcodeGen, SwiftPM (Engine + Shared only), Python 3 harnesses on
`scripts/simrig.py`, GitHub Actions.

---

## Global Constraints

- **The Engine never localizes.** No `Foundation` localization API, no
  `LocalizedStringResource`, no catalog lookup anywhere in `Sources/Engine`. It
  emits IDs; the App layer names them. Enforced by a test, not a comment.
- **`Sources/Shared` stays Linux-clean.** It is the `NineShared` SwiftPM target
  (`Package.swift:26-33`). No `LocalizedStringResource`, no `Bundle.module`, no
  `defaultLocalization:` added to the manifest.
- **`Technique` and `Difficulty` raw values are frozen.** They are persisted
  inside every `GeneratedPuzzle` trace and therefore inside the 56 golden corpus
  hashes (`LogicSolver.swift:12-24`). Never rename a case, never reorder.
- **Nothing may throw out of a container decode** (`EXECUTING-A-PRD.md §2`).
  This PRD adds no persisted state, which is the cheapest way to obey it.
- **Launch locales, exactly nine:** `ja`, `de`, `fr`, `es`, `it`, `pt-BR`, `ko`,
  `zh-Hans`, `nl`. Source language `en`.
- **The covenant is binding** (`PRD-7`): no IAP, no gamification, no streak
  shaming. A translation that turns "Your streak held" into a scold fails
  review even if it is linguistically correct.
- **One `Phrase`-style block per file remains the seam** — this PRD converts the
  bodies, it does not scatter lookups through view code
  (`EXECUTING-A-PRD.md §4`).
- **Run `swift test --filter GoldenCorpus` after every commit**, not at the end
  (`EXECUTING-A-PRD.md §3`). Task 1 makes CI do it too, but the local habit is
  what catches it in five minutes instead of five commits.

---

## Decisions taken (from the user, 2026-07-26)

These are settled. Do not re-litigate them; implement them.

1. **Ship infra + machine-drafted translations for all nine languages**, every
   string marked `needs_review` in the catalog so nothing reads as
   human-approved, with a DEVIATIONS entry saying so plainly.
2. **Translate `Gentle` / `Steady` / `Sharp`; keep `Nocturne` in English** in
   every locale — it is a coined name, not a description. Task 9 pins this with
   a test so it is enforced rather than remembered.
3. **The rose and the board never mirror.** They are a numeric grid, not text.
   Pin them LTR; the RTL lane asserts exactly that.
4. **Add a fast Lane 1 job running the full `swift test`**, so the golden corpus
   gates every PR from now on rather than being run by hand.

---

## What the inventory found

Two exhaustive sweeps of `Sources/{App,Shared,Widgets}` (13,914 LOC). The
numbers matter because they contradict the brief's premise and set the size of
Task 5.

| | in `Phrase`-style blocks | bare literals | total distinct |
|---|---|---|---|
| `Sources/App` | ~40 | **~275** | ~315 |
| `Sources/Shared` | ~55 | ~12 | ~67 |
| `Sources/Widgets` | **0** | ~34 | ~34 |
| | ~95 | ~321 | **~415** (~397 shippable) |

- **11 `Phrase`-style blocks exist, not 8.** Three are named something else and a
  grep for `enum Phrase` misses all three: `CoachPhrase`
  (`CoachCard.swift:120`), `ShareCardPhrase` (`ShareCardView.swift:34`), and a
  `// MARK: Phrases` run of six `static let`s (`BoardAccessibility.swift:228`).
- **Most literals never reach the screen as `Text(LocalizedStringKey)`.** They
  arrive as `String` through helpers (`statusLabel`, `GlassChip`, `tile`,
  `LegendRow`, `prefRow`) and through `.accessibilityLabel(_: String)` — the
  non-localizing overload. Xcode's automatic extraction sees almost none of it.
  **The extraction must be a script plus an audit test, not a build setting.**
- **The Engine names things in three places:** `Technique.displayName`
  (`LogicSolver.swift:63`), `Difficulty.title` (`Generator.swift:44`), and
  `VariantTier.title` (`VariantConstraint.swift:282` — a duplicate of the first
  three difficulty names).
- **Duplication to collapse before translating:** the three undo toasts appear
  in **4** files (`TouchUI.swift:1571`, `MacUI.swift:759`,
  `GameScreen.swift:646`, `PadSession.swift:250`); `"Composing…"` in 8 places;
  `"Solved"` in ~10; `"\(days) day streak"` in **8 sites with 3 spellings**; the
  entire tutorial step set is duplicated between the iOS and tvOS bodies of
  `TutorialView.swift`. Translating 4 copies of one sentence is 4 chances to
  disagree.

### Two live bugs, both pre-existing

- **`ArchiveCalendar.swift:155` hard-codes `["S","M","T","W","T","F","S"]`.** The
  column *order* respects `firstWeekday`; the letters are always English. This
  is already wrong for every non-English locale and is the one unambiguous
  locale defect in the tree today.
- **`streak(1)` renders "1 day streak".** In English it merely reads badly; in
  German, French and Spanish it is ungrammatical, and one of the 8 sites is the
  share card that `DEVIATIONS.md` calls the artifact that "outlives the session
  and cannot be corrected."

### Two things `xcstringstool` will not do for you — verified on this machine

Both were probed before this plan was written, because a tool that is assumed
to check something and does not is worse than no tool.

- **`compile` catches structural errors.** A missing `value` fails with
  `exit 1` and names the JSON path. Good gate; use it.
- **`compile` does NOT catch a plural missing the CLDR `other` category** —
  `exit 0`, silent. At runtime that falls back to the key. **Task 8's plural
  completeness test is the only thing standing between the app and a German
  screen reading `streak.days`.**
- **`state: "needs_review"` is erased at compile time.** It compiles
  byte-identically to `translated`. Decision 1's "marked needs_review" is a
  source-side claim with zero runtime enforcement, so **Task 9 asserts it with a
  test** or it is a comment pretending to be a guarantee.

---

## Architecture: where each string lives, and why

```
Sources/Engine/          IDs only. Linux-clean. No text.
  Technique.rawValue  ──────┐   "nakedSingle"  (frozen in the golden hash)
  Difficulty.rawValue ──────┤   "gentle"
                            │
Sources/Shared/          Linux-clean. Structure, not vocabulary.
  Phrasebook.swift  ◄───────┘   resolve("technique.nakedSingle.name") -> String
  BoardSpeech.swift             composes sentences from WHOLE templates
  EnglishPhrases.swift          the default table; what the tests assert
                            │
Sources/Strings/         Darwin-only. NOT in Package.swift.
  Localizable.xcstrings         the catalog, 9 locales + en
  Strings.swift                 installs the real Phrasebook at launch
                            │
Sources/App, Sources/Widgets    call Strings.* directly for their own copy
```

**Why a `Phrasebook` seam instead of `LocalizedStringResource` in Shared.**
Three independent reasons, any one of which is sufficient:

1. `Sources/Shared` is a SwiftPM target that must build on Linux, where
   `LocalizedStringResource` does not exist.
2. Even on Darwin, `Sources/Shared` compiles into **two bundles** —
   `Nine.app` and `NineWidgets.appex` (`project.yml:19-22` vs `146-151`). In an
   extension `Bundle.main` *is* the extension. A file that hard-codes its bundle
   is wrong in one of the two, and `#if SWIFT_PACKAGE` to paper over a third
   case (`Bundle.module` under `swift test`) is three bundles for one source
   file.
3. `BoardSpeechTests` runs **first in CI**, before the simulator is even built
   (`nine-accessibility.yml:78-80`), and asserts exact wording. Any design that
   needs a bundle to produce a sentence takes that tripwire away.

The seam costs one indirection and buys all three back.

**Why `Sources/Strings/` is a new directory rather than a file in `Sources/App`.**
The widget needs the same catalog and the same keys. A new tree listed in both
targets' `sources:` is one line of `project.yml` per target and zero
conditionals in Swift.

---

## File Structure

**Created**

| Path | Responsibility |
|---|---|
| `nine/Sources/Shared/Phrasebook.swift` | The seam: a resolver + install-once global. Linux-clean. |
| `nine/Sources/Shared/EnglishPhrases.swift` | The English source of truth, as data. What tests assert and what the catalog is generated *from*. |
| `nine/Sources/Strings/Localizable.xcstrings` | The catalog. `en` + 9 locales. |
| `nine/Sources/Strings/Strings.swift` | Key constants, `LocalizedStringResource` lookup, `Strings.install()`. |
| `nine/scripts/strings.py` | Extract / audit / pseudo-localize. The instrument. |
| `nine/scripts/loc-harness.py` | Pseudo-loc + RTL + Dynamic Type screenshots, on `simrig.py`. |
| `nine/Tests/SharedTests/PhrasebookTests.swift` | The seam's own tests. |
| `nine/Tests/EngineTests/StringSealTests.swift` | Source-grep: no bare literals, no Engine text. |
| `nine/Tests/EngineTests/CatalogTests.swift` | Key coverage, plural completeness, `needs_review`, Nocturne pinning. |
| `nine/Tests/LocBaselines/` | Per-screen pseudo-loc + Dynamic Type baselines. |
| `.github/workflows/nine-engine.yml` | The fast Lane 1: full `swift test` + catalog audit, no simulator. |

**Modified**

| Path | Change |
|---|---|
| `nine/Sources/Engine/LogicSolver.swift:63-76` | Delete `Technique.displayName`. |
| `nine/Sources/Engine/Generator.swift:44-51` | Delete `Difficulty.title`. |
| `nine/Sources/Engine/VariantConstraint.swift:282-288` | Delete `VariantTier.title`. |
| `nine/Sources/Shared/BoardSpeech.swift` | Phrase book → `Phrasebook`; de-compose the coach sentences. |
| `nine/Sources/Shared/ArchiveCalendar.swift:155,217` | `weekdayInitials` bug; `ListFormatter`. |
| `nine/Sources/Shared/SolveCardFacts.swift`, `TipCoach.swift` | Phrase blocks → catalog keys. |
| `nine/Sources/App/*` (26 files) | Extraction. `TouchUI`, `MacUI`, `HomeView`, `PrefsSheet` are the big four. |
| `nine/Sources/Widgets/*` (4 files) | Extraction; the gallery strings are the user-visible ones. |
| `nine/project.yml` | `Sources/Strings` in both targets; `developmentRegion`; `CFBundleLocalizations`. |
| `.github/workflows/nine-accessibility.yml` | Pseudo-loc, RTL and Dynamic Type steps on the already-built app. |
| `nine/DEVIATIONS.md` | The PRD-20 section. |
| `nine/PROGRAM-2.0.md` | Status row. |

---

## Task ordering, and why it is this order

Task 1 first because **it is the measuring instrument**, and PRD-22's whole
lesson was that the harness found five failures on its first run against
unmodified code. An extraction that cannot be audited is an extraction you have
to trust. Task 2 next because it is the smallest change with the largest blast
radius (the golden corpus). Tasks 5–6 are the bulk and are mechanical *because*
1–4 made them so.

---

### Task 1: The instrument — audit tripwire and the fast Lane 1

**Why first:** Everything after this is measured by it. It must fire against
today's unmodified tree, and it does — the prototype found **101 bare literals**
by the narrow detector alone.

**Files:**
- Create: `nine/scripts/strings.py`
- Create: `nine/Tests/EngineTests/StringSealTests.swift`
- Create: `.github/workflows/nine-engine.yml`

**Interfaces:**
- Produces: `python3 scripts/strings.py --audit` (exit 0/1, prints
  `tree/file:line literal` per offence); `StringSealTests` running the same rule
  in-process so `swift test` alone is sufficient locally.

- [ ] **Step 1: Write the failing test**

`nine/Tests/EngineTests/StringSealTests.swift`. Modelled on
`VariantChannelSealTests` — a **source** check, deliberately, so it fires on the
line that introduces the coupling, in the PR that introduces it.

```swift
// StringSealTests — the mechanical half of "every string goes through the catalog".
//
// The inventory that opened PRD-20 found ~397 shippable user-facing strings, of
// which ~321 were bare literals passed to a view constructor or an
// `.accessibilityLabel(_: String)`. Xcode's automatic extraction sees almost
// none of those, because they never take the `LocalizedStringKey` overload. So
// "we localized the app" is a claim that needs an instrument, and this is it.
//
// Deliberately a *source* check, like VariantChannelSealTests: it names the file
// and line, in the PR that adds it, when it is cheap to talk about.
import XCTest
import Foundation

final class StringSealTests: XCTestCase {

    /// View constructors and modifiers whose String argument reaches a human.
    private static let sinks = [
        "Text", "Label", "Button", "Toggle", "Picker", "Section", "TextField",
        "Link", "Menu", "NavigationLink", "Window", "CommandMenu", "GlassChip",
        "GlassIconButton",
    ]
    private static let modifiers = [
        "navigationTitle", "accessibilityLabel", "accessibilityHint",
        "accessibilityValue", "accessibilityAction", "help",
        "configurationDisplayName", "description",
    ]

    private static let trees = ["Sources/App", "Sources/Widgets", "Sources/Shared"]

    /// Debug-only surfaces the player never sees. Each one is named, never
    /// pattern-matched: an exemption that can grow by accident is not an
    /// exemption, it is a hole.
    private static let exempt = [
        "Sources/App/PadProbeHUD.swift",     // --pad-probe launch arg only
    ]

    func testNoBareUserFacingLiteral() throws { /* implemented in Step 3 */ }
}
```

- [ ] **Step 2: Run it and watch it fail against unmodified code**

```bash
cd nine && swift test --filter StringSeal
```

Expected: **FAIL, ~101+ offences.** If it passes, the detector is broken — the
prototype run that opened this PRD found 21 in `MacUI.swift` and 17 in
`TouchUI.swift` alone. A green first run means fix the test, not celebrate.

- [ ] **Step 3: Implement the detector**

Walk `trees`, skip `exempt` and comment lines, and flag a double-quoted literal
of ≥2 characters passed as the first argument to a `sinks` constructor or a
`modifiers` modifier. Allow `Strings.` references and `#""#`-marked
never-localize constants (`ShareCardMetrics.wordmark`, per
`ShareCardView.swift:57`). Report `tree/file:line "literal"`, assert the list is
empty with a message naming `scripts/strings.py --extract` as the fix.

- [ ] **Step 4: Port the same rule to `scripts/strings.py --audit`**

One rule, two runners: the test for `swift test`, the script for the lane and for
`--extract` to consume. Add `--audit` checks that need the catalog and so cannot
live in a pure source grep:

```
key used in Swift but absent from the catalog     -> fail
key in the catalog referenced by no Swift file    -> fail (dead string)
catalog fails `xcstringstool compile`             -> fail, echo its stderr
```

`xcstringstool print` lists keys with no build and no simulator, which is why
this belongs in the cheap job.

- [ ] **Step 5: Add the fast Lane 1 workflow**

`.github/workflows/nine-engine.yml` — decision 4. This is the job that makes the
golden corpus a gate instead of a habit.

```yaml
# The cheap gate. No simulator, no signing, no Xcode project generation.
#
# It exists because until PRD-20 the ONLY test invocation in CI was
# `swift test --filter 'BoardSpeechTests|AXFixtureTests'` — the 56-hash golden
# corpus that EXECUTING-A-PRD §3 calls a contract was run by hand and by nothing
# else. PRD-20 touches the enums those hashes are made of, which made it the
# wrong PRD to keep relying on remembering.
name: Engine + catalog (Nine)

on:
  pull_request:
    paths: ['nine/**', 'couchkit/**', '.github/workflows/nine-engine.yml']
  workflow_dispatch:

concurrency:
  group: nine-engine-${{ github.ref }}
  cancel-in-progress: true

permissions:
  contents: read

jobs:
  engine:
    runs-on: macos-latest
    timeout-minutes: 30
    steps:
      - uses: actions/checkout@v4
      - name: Select Xcode 26+
        run: |
          set -euo pipefail
          XC=""
          for d in /Applications/Xcode_26*.app; do [ -e "$d" ] && XC="$d"; done
          if [ -n "$XC" ]; then sudo xcode-select -s "$XC"; fi
          xcodebuild -version
      # The whole suite, including GoldenCorpus. ~120 s per EXECUTING-A-PRD §5.
      - name: swift test
        working-directory: nine
        run: swift test
      - name: Audit the catalog
        working-directory: nine
        run: python3 scripts/strings.py --audit
```

- [ ] **Step 6: Prove the new lane catches what it exists to catch**

Locally, temporarily reorder two lines inside `Generator.dig` (or any generation
path), run `swift test --filter GoldenCorpus`, confirm it fails, then revert. A
gate nobody has seen fire is a gate nobody should believe.

- [ ] **Step 7: Commit**

```bash
git add nine/scripts/strings.py nine/Tests/EngineTests/StringSealTests.swift \
        .github/workflows/nine-engine.yml
git commit -m "PRD-20: the string audit, and a lane that runs the golden corpus"
```

---

### Task 2: The Engine stops naming things

**Files:**
- Modify: `nine/Sources/Engine/LogicSolver.swift:63-76`
- Modify: `nine/Sources/Engine/Generator.swift:44-51`
- Modify: `nine/Sources/Engine/VariantConstraint.swift:282-288`
- Modify: `nine/Tests/EngineTests/StringSealTests.swift`

**Interfaces:**
- Consumes: `StringSealTests` from Task 1.
- Produces: `Technique.rawValue` and `Difficulty.rawValue` as the documented l10n
  key stems. Call sites move to `Strings.technique(_:)` / `Strings.difficulty(_:)`
  in Task 4; between Task 2 and Task 4 the tree does not build, so **these two
  tasks land as one commit** if the gap is inconvenient.

- [ ] **Step 1: Write the failing test — the Engine names nothing**

Append to `StringSealTests`:

```swift
    /// The Engine is Linux-clean and never localizes (PROGRAM-2.0 §PRD-20). The
    /// structural enforcement is that SwiftPM does not compile `Sources/App` —
    /// but that only catches an `import SwiftUI`, not a `displayName` returning
    /// English. This catches the second one.
    func testEngineNamesNothing() throws {
        let banned = ["displayName", "var title", "blurb", "explainer", "caption"]
        // ... walk Sources/Engine, flag any of `banned`, assert empty ...
    }
```

- [ ] **Step 2: Run it; expect three offences**

```bash
cd nine && swift test --filter StringSeal
```

Expected: FAIL naming `LogicSolver.swift:63`, `Generator.swift:44`,
`VariantConstraint.swift:282`.

- [ ] **Step 3: Delete the three properties, and say what replaced them**

In `LogicSolver.swift`, replace the `displayName` body with a doc comment on the
enum — the identity claim is the valuable part:

```swift
/// …existing frozen-raw-value doc comment…
///
/// **The raw value is also the localization identity.** `Technique.nakedSingle`
/// is `technique.nakedSingle.name` in the catalog, derived mechanically rather
/// than mapped by hand, because a hand-written map is a second list that can
/// disagree with this one. There is deliberately no `displayName` here: the
/// Engine compiles on Linux and must never reach a bundle. See
/// `Sources/Strings/Strings.swift`.
```

Same treatment for `Difficulty` and `VariantTier`.

- [ ] **Step 4: Run the golden corpus — the claim that this is free**

```bash
cd nine && swift test --filter GoldenCorpus
```

Expected: **56/56 pass.** `displayName` and `title` are *computed* properties,
never encoded, so no hash can move. That is the reasoning; this is the evidence.
Record the run in the eventual DEVIATIONS entry — EXECUTING-A-PRD §3 says a
mismatch is a bug until proven otherwise, and the converse deserves a number
too.

- [ ] **Step 5: Commit** (with Task 4 if the tree does not build alone)

```bash
git add nine/Sources/Engine nine/Tests/EngineTests/StringSealTests.swift
git commit -m "PRD-20: the Engine emits IDs and names nothing"
```

---

### Task 3: The `Phrasebook` seam in Shared

**Files:**
- Create: `nine/Sources/Shared/Phrasebook.swift`
- Create: `nine/Sources/Shared/EnglishPhrases.swift`
- Create: `nine/Tests/SharedTests/PhrasebookTests.swift`

**Interfaces:**
- Produces:
  ```swift
  public struct Phrasebook: Sendable {
      public typealias Resolve = @Sendable (String, [PhraseArg]) -> String
      public init(resolve: @escaping Resolve)
      public func string(_ key: String, _ args: PhraseArg...) -> String
      public static var current: Phrasebook { get }
      public static func install(_ book: Phrasebook)
      public static let english: Phrasebook
  }
  public enum PhraseArg: Sendable { case int(Int), text(String) }
  public enum EnglishPhrases { public static let table: [String: String] }
  ```
  `EnglishPhrases.table` maps key → an English format string using positional
  specifiers (`%1$lld`). Task 9 generates the catalog's `en` locale **from this
  table**, so there is one English source of truth, not two.

- [ ] **Step 1: Write the failing tests**

`nine/Tests/SharedTests/PhrasebookTests.swift`:

```swift
func testDefaultsToEnglishWithNothingInstalled() {
    XCTAssertEqual(Phrasebook.english.string("board.cell.label", .int(3), .int(5)),
                   "Row 3, column 5")
}

func testUnknownKeyReturnsTheKeyRatherThanCrashing() {
    // A missing key must be loud in a screenshot and silent at runtime: the
    // player sees "board.nope" and files a bug; nobody gets a crash on a
    // Tuesday because a translator deleted a row.
    XCTAssertEqual(Phrasebook.english.string("board.nope"), "board.nope")
}

func testPositionalArgumentsSurviveReordering() {
    // German fronts the column in some phrasings. If the resolver is
    // positional, a translation can reorder; if it is not, this test is the
    // only place anyone finds out.
    let book = Phrasebook { _, args in Phrasebook.format("%2$lld/%1$lld", args) }
    XCTAssertEqual(book.string("k", .int(3), .int(5)), "5/3")
}

func testInstallIsHonouredAndIdempotentReadsAreCheap() { /* … */ }
```

- [ ] **Step 2: Run; expect a compile failure**

```bash
cd nine && swift test --filter Phrasebook
```

Expected: FAIL, `cannot find 'Phrasebook' in scope`.

- [ ] **Step 3: Implement `Phrasebook.swift`**

```swift
// Phrasebook.swift — the one seam between Nine's formatting logic and its words.
//
// `Sources/Shared` is the `NineShared` SwiftPM target and must build on Linux,
// where `LocalizedStringResource` does not exist. It also compiles into TWO
// bundles — Nine.app and NineWidgets.appex — where `Bundle.main` means two
// different things, and into `swift test`, where it means a third. Rather than
// three conditionals in every formatter, there is one indirection here: the App
// installs a resolver at launch, and everything in Shared asks this.
//
// The default is English, held as data in `EnglishPhrases`, which is what
// `BoardSpeechTests` asserts against and what Task 9 generates the catalog's
// `en` locale from. One English, two consumers.
import Foundation

public enum PhraseArg: Sendable {
    case int(Int)
    case text(String)
}

public struct Phrasebook: Sendable {
    public typealias Resolve = @Sendable (_ key: String, _ args: [PhraseArg]) -> String
    private let resolve: Resolve
    public init(resolve: @escaping Resolve) { self.resolve = resolve }

    public func string(_ key: String, _ args: PhraseArg...) -> String {
        resolve(key, args)
    }

    public static let english = Phrasebook { key, args in
        guard let format = EnglishPhrases.table[key] else { return key }
        return Phrasebook.format(format, args)
    }

    // Written exactly once per PROCESS, before the first read. NOT "from
    // `NineApp.init`" — see the amendment below; that call site does not
    // exist on iOS, on tvOS, or in the widget extension. A lock on the READ path would cost 81 acquisitions per AX dump
    // (`BoardAccessibility` labels every cell) and 42 per archive body
    // evaluation (`ArchiveCalendar`'s own comment at :229 explains why that
    // path is measured, not assumed) — for a value that never changes after
    // launch. The assert is what keeps "written once" true.
    nonisolated(unsafe) private static var installed: Phrasebook?
    public static var current: Phrasebook { installed ?? .english }

    public static func install(_ book: Phrasebook) {
        assert(installed == nil, "Phrasebook.install is launch-time and once")
        installed = book
    }

    /// Positional `String(format:)` over `PhraseArg`. Positional so a
    /// translation may reorder — `%1$lld` / `%2$lld`, never bare `%lld` in a
    /// multi-argument string.
    public static func format(_ format: String, _ args: [PhraseArg]) -> String {
        String(format: format, arguments: args.map { arg -> CVarArg in
            switch arg {
            case .int(let n): return n
            case .text(let s): return s
            }
        })
    }
}
```

- [ ] **Step 4: Implement `EnglishPhrases.swift` with the Shared keys only**

Start with exactly the keys `BoardSpeech`, `TipCoach`, `SolveCardFacts` and
`ArchiveCalendar` need. Task 5 adds the App keys. Every multi-argument entry uses
positional specifiers.

- [ ] **Step 5: Run the tests; expect pass**

```bash
cd nine && swift test --filter 'Phrasebook|BoardSpeech'
```

Expected: PASS, and `BoardSpeechTests` still green — it has not been touched yet.

- [ ] **Step 6: Commit**

```bash
git add nine/Sources/Shared/Phrasebook.swift nine/Sources/Shared/EnglishPhrases.swift \
        nine/Tests/SharedTests/PhrasebookTests.swift
git commit -m "PRD-20: the Phrasebook seam, Linux-clean and bundle-free"
```

---

### Task 4: The catalog, `Strings.swift`, and the two-bundle wiring


> **Amendment (2026-07-26, from Task 3's review).** The install site this plan
> names does not exist on three of the four processes `Sources/Shared` compiles
> into, and the illustrative code above said so in a comment three times.
>
> * `NineApp.init` is inside `#if os(macOS)` (`Sources/App/NineApp.swift`). On
>   **iOS and tvOS `NineApp` has no `init` at all** — there is nowhere for the
>   call to be until one is added.
> * **`NineWidgets.appex` never runs `NineApp`.** `NineWidgetBundle` is its own
>   `@main`. Left as is, `installed` stays nil there forever and
>   `Phrasebook.current` is permanently English — in the one bundle whose
>   existence is half the argument for the seam existing at all. Harmless while
>   the widget consumes no Shared phrase (verified: it consumes none today), and
>   a silent English island the moment one lands.
> * Even on macOS, `@State private var model = AppModel()` (`NineApp.swift:13`)
>   is a stored-property default, **constructed before the `init` body runs**. An
>   install placed in `init` is one `AppModel` change away from being too late.
>   `AppModel` builds no phrases today.
>
> So the invariant Task 4 must satisfy is **once per process, before the first
> read** — not "from `NineApp.init`". Three ways to satisfy it, and Task 4 picks
> one: add the missing `init` on iOS/tvOS *and* a second install in
> `NineWidgetBundle`; or have `Phrasebook.current` self-install on first read;
> or install lazily from `Strings.string` itself. Whichever it is, note that
> `Phrasebook.install` is a `precondition`, not an `assert` — it survives `-O`,
> so a double install is a trap in the shipping app rather than a silent
> overwrite.
>
> Nothing here is a bug on the branch today. It is the comment Tasks 4 and 5
> would have trusted.

**Files:**
- Create: `nine/Sources/Strings/Localizable.xcstrings`
- Create: `nine/Sources/Strings/Strings.swift`
- Modify: `nine/project.yml` (both targets)
- Modify: `nine/Sources/App/NineApp.swift` (install at launch — **and add an
  `init` on iOS/tvOS, which has none today; see the amendment)
- Modify: `nine/Sources/Widgets/NineWidgetBundle.swift` (its own install —
  the appex never runs `NineApp`)
- Create: `nine/Tests/EngineTests/CatalogTests.swift`

**Interfaces:**
- Consumes: `Phrasebook`, `EnglishPhrases.table` (Task 3);
  `Technique.rawValue`, `Difficulty.rawValue` (Task 2).
- Produces:
  ```swift
  public enum Strings {
      public static func install()                       // once per process; see amendment
      public static func string(_ key: String, _ args: PhraseArg...) -> String
      public static func technique(_ t: Technique) -> String   // technique.<raw>.name
      public static func difficulty(_ d: Difficulty) -> String // difficulty.<raw>.title
      public static func resource(_ key: String) -> LocalizedStringResource
  }
  ```

- [ ] **Step 1: Write the failing test — the catalog reaches both bundles**

`nine/Tests/EngineTests/CatalogTests.swift`. This test cannot link `Strings`
(SwiftPM does not compile `Sources/Strings`), so it follows the established
`AppearancePaletteTests` / `VariantChannelSealTests` pattern: **read the source
and the catalog as files.**

```swift
// CatalogTests — the catalog is a build input for two bundles, and the ways it
// can be wrong are all silent.
//
// `Sources/Shared` and `Sources/Engine` compile into Nine.app AND into
// NineWidgets.appex (project.yml:19-22 vs :146-151). In an app extension
// `Bundle.main` is the extension, so a catalog listed by only one target gives
// the widget an English-only Home Screen on a Japanese phone — and every
// platform build stays green while it does. That is PRD-16's
// ALTERNATE_APP_ICON_NAMES lesson in a different file.
import XCTest
import Foundation

final class CatalogTests: XCTestCase {

    func testBothTargetsListTheStringsTree() throws {
        let yml = try String(contentsOf: nineRoot.appendingPathComponent("project.yml"),
                            encoding: .utf8)
        // Nine and NineWidgets must EACH list Sources/Strings.
        XCTAssertEqual(yml.components(separatedBy: "- Sources/Strings").count - 1, 2, """
            Sources/Strings must be listed by BOTH the Nine and NineWidgets \
            targets. A widget without the catalog renders English on a \
            localized phone, and every platform build stays green.
            """)
    }

    func testDeclaredLocalizationsAreExactlyTheNineLaunchLocales() throws { /* … */ }

    func testEveryEnglishPhraseHasACatalogEntry() throws {
        // EnglishPhrases.table is the source of truth; the catalog's `en` is
        // generated from it. Drift means someone hand-edited one of them.
    }
}
```

- [ ] **Step 2: Run; expect failure on all three**

```bash
cd nine && swift test --filter Catalog
```

Expected: FAIL — `project.yml` lists `Sources/Strings` zero times, and the
catalog does not exist.

- [ ] **Step 3: Create the catalog and generate `en` from `EnglishPhrases`**

```bash
cd nine && python3 scripts/strings.py --extract
```

`--extract` writes `Sources/Strings/Localizable.xcstrings` with
`"sourceLanguage": "en"`, one entry per `EnglishPhrases.table` key, each
carrying the English value and the `comment` that becomes the translator's only
context. Comments are not optional here: `"Sharp"` is unguessable without one,
and `Phrase.solved = "Solved."` versus `statusLabel("Solved")` are different
parts of speech that a translator will get wrong exactly once per language.

- [ ] **Step 4: Implement `Strings.swift`**

```swift
// Strings.swift — the App layer's single mapping from stable ID to human words.
//
// The Engine emits `Technique.nakedSingle` and `Difficulty.gentle`; nothing in
// `Sources/Engine` or `Sources/Shared` knows what those are called. This file
// is where they get names, and it is the only file in Nine that imports the
// localization machinery.
//
// It lives in `Sources/Strings` rather than `Sources/App` because the widget
// extension compiles `Sources/Shared` too and needs the same keys against its
// own bundle. `Bundle.main` is correct in both: in an appex, main IS the appex.
import Foundation

public enum Strings {

    /// Called once per process, before the first read. Where from is NOT
    /// `NineApp.init` alone — see the amendment on this task.
    public static func install() {
        Phrasebook.install(Phrasebook { key, args in
            let format = String(localized: String.LocalizationValue(key),
                                bundle: .main,
                                comment: "")
            // A key that resolves to itself is a missing entry; fall back to
            // English rather than showing the player a dotted identifier.
            if format == key, let english = EnglishPhrases.table[key] {
                return Phrasebook.format(english, args)
            }
            return Phrasebook.format(format, args)
        })
    }

    public static func technique(_ t: Technique) -> String {
        Phrasebook.current.string("technique.\(t.rawValue).name")
    }

    public static func difficulty(_ d: Difficulty) -> String {
        Phrasebook.current.string("difficulty.\(d.rawValue).title")
    }
}
```

The `format == key` fallback is deliberate and is the reason
`PhrasebookTests.testUnknownKeyReturnsTheKeyRatherThanCrashing` exists: a
translator deleting a row must degrade to English, not to a dotted identifier on
the share card.

- [ ] **Step 5: Wire both targets in `project.yml`**

Under `targets.Nine.sources`, after `- Sources/Shared`:

```yaml
      # The String Catalog and its accessor. Listed by BOTH targets on purpose:
      # NineWidgets compiles Sources/Shared and Sources/Engine in, so it needs
      # the same keys resolved against its OWN bundle. A catalog in only the app
      # gives the widget an English Home Screen on a localized phone, and three
      # green platform builds do not catch it.
      - Sources/Strings
```

The identical two lines under `targets.NineWidgets.sources`. Then, under
`targets.Nine.info.properties`:

```yaml
        CFBundleDevelopmentRegion: en
        CFBundleLocalizations: [en, ja, de, fr, es, it, pt-BR, ko, zh-Hans, nl]
```

- [ ] **Step 6: Install at launch — on all four processes**

Once per process, before the first read. `NineApp.init` alone reaches exactly
one of the four (see the amendment at the head of this task): it is
`#if os(macOS)`-only, the widget extension never runs `NineApp`, and even on
macOS the `@State` model default is constructed before the `init` body. So:

```swift
Strings.install()
```

…from an `init` on `NineApp` that is **not** wrapped in `#if os(macOS)`, plus a
second call in `NineWidgetBundle` — or from a self-installing
`Phrasebook.current`, if that is the shape chosen. Verify per bundle rather than
per platform: the check is that `Phrasebook.current` is not `.english` in a
running widget, which no unit test can answer.

- [ ] **Step 7: Verify the catalog compiles, and that its failure mode is loud**

```bash
cd nine
XT=/Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool
$XT compile Sources/Strings/Localizable.xcstrings --output-directory /tmp/nine-loc
find /tmp/nine-loc -type f
```

Expected: `en.lproj/Localizable.strings` (plus `.stringsdict` once Task 8 adds
plurals). Then break it on purpose — delete a `"value"` key — and confirm
`exit 1` with the JSON path named. Restore.

- [ ] **Step 8: Build all three platforms and prove the widget got the catalog**

```bash
cd nine && COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" \
    -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
done
# The claim, and the artifact that settles it:
find build/Build/Products/Debug-iphonesimulator/Nine.app -name '*.lproj' -o -name '*.strings' | sort
find build/Build/Products/Debug-iphonesimulator/Nine.app/PlugIns/*.appex -name '*.lproj' | sort
```

Expected: **both** bundles list `.lproj` directories. A green build proves
nothing here — PRD-16's alternate icons compiled green with no
`CFBundleAlternateIcons` at all, and `plutil -p` on the artifact was the only
thing that disagreed. This is the same check on a different key.

- [ ] **Step 9: Commit**

```bash
git add nine/Sources/Strings nine/project.yml nine/Sources/App/NineApp.swift \
        nine/Tests/EngineTests/CatalogTests.swift
git commit -m "PRD-20: the catalog, and the two bundles that need it"
```

---

### Task 5: Mechanical extraction — `Sources/App`

> **Amendment (2026-07-26, from Task 1's review).** `StringSealTests` measures
> **call sites only** — a literal passed to `Text(…)` or `.accessibilityLabel(…)`.
> It is blind to the ~300+ prose literals sitting in `Phrase` enum bodies and
> computed properties, which is where most of Nine's copy actually lives:
> `AppModel.swift`'s 25 enum titles, `HomeView.swift`'s `blurb`/`detail`/
> `NineLegend` sets, `TutorialGrammar.swift`'s 28 fields, and every
> `static let` inside the 11 phrase blocks.
>
> **An empty `offences.txt` does NOT mean the extraction is finished**, and Task
> 1's baseline going to zero is a necessary condition, never a sufficient one.
> The sufficient condition is `scripts/strings.py --audit`'s *catalog* half:
> every key used in Swift present in the catalog, and no dead keys. Track both
> numbers in each commit message, and do not close this task on the call-site
> count alone.

**Why this is now mechanical:** Tasks 1–4 built the instrument, the identity and
the sink. This task is ~275 literals across 26 files and is the bulk of the PRD,
but every one of them is the same edit, and `StringSealTests` says when you are
done.

**Files:** all of `nine/Sources/App` except `PadProbeHUD.swift`. The four that
hold half the strings: `TouchUI.swift` (~48), `MacUI.swift` (~35),
`HomeView.swift` (~50), `PrefsSheet.swift` (~30).

**Interfaces:**
- Consumes: `Strings.string(_:_:)`, `Strings.difficulty(_:)` (Task 4).
- Produces: one `Phrase` block per file, bodies calling `Strings.string`.

- [ ] **Step 1: Collapse the duplicates first — before any translation**

Translating four copies of one sentence is four chances to disagree, and the
translator cannot see that they are the same string. Move to
`Sources/Shared/EnglishPhrases` + one key each:

| Strings | Copies | Sites |
|---|---|---|
| `"Undid \(digit)"` / `"Restored \(digit)"` / `"Undid note \(digit)"` | **4 each** | `TouchUI.swift:1571`, `MacUI.swift:759`, `GameScreen.swift:646`, `PadSession.swift:250` |
| `"Composing…"` | 8 | `TouchUI:240,407,802,1148`, `HomeView:105,212`, `MacUI:178`, `GameScreen:366,438`, `TutorialView:231,697` |
| `"Solved"` | ~10 | across shelf, game, widgets |
| `"\(days) day streak"` | 8, **3 spellings** | `BoardSpeech:386`, `SolveCardFacts:84`, `StreakChip:36`, `TouchUI:909`, `MacUI:448`, `GameScreen:509`, `DailyWidgetViews:118`, `StreakWidget:62` |
| `"Press Back to return"` / `"Tap outside to return"` | 3 sheets | `PrefsSheet:181,188`, `HistorySheet:88,92`, `BoardsSheet:50,54` |
| tutorial step titles + bodies | 2 (iOS + tvOS) | `TutorialView:122-147` and `:634-659` |

Run `swift test` after the collapse and before the extraction: a de-duplication
that changed a string is a behaviour change hiding inside a refactor.

- [ ] **Step 2: Give each file a `Phrase` block, and rename the three odd ones**

`CoachPhrase` → `Phrase` (`CoachCard.swift:120`), `ShareCardPhrase` → `Phrase`
(`ShareCardView.swift:34`), and the `// MARK: Phrases` run
(`BoardAccessibility.swift:228`) becomes a real block. One convention, so a grep
for `enum Phrase` is complete — today it silently misses three files.

- [ ] **Step 3: Convert the bodies**

```swift
private enum Phrase {
    static let graceTitle = Strings.string("streak.grace.title")
    static func undidPlacement(_ digit: Int) -> String {
        Strings.string("game.undo.placement", .int(digit))
    }
}
```

Key naming, domain-first and mechanical: `shelf.*`, `game.*`, `prefs.*`,
`tutorial.*`, `archive.*`, `board.*`, `coach.*`, `streak.*`, `widget.*`,
`difficulty.*`, `technique.*`.

- [ ] **Step 4: Route `.accessibilityLabel` through the catalog too**

`.accessibilityLabel(_ : String)` is the non-localizing overload and is ~40 of
the offences. `EXECUTING-A-PRD.md §4` is explicit that the AX tree is a
regression surface; an un-localized VoiceOver label is a regression that no
screenshot shows.

- [ ] **Step 5: Fix the three composed strings that hard-code a name**

- `TutorialView.swift:392` hard-codes **"Steady"** inside prose ("One shared
  Steady board a day…"). It must take `Strings.difficulty(.steady)` as an
  argument, or the tutorial says "Steady" in Japanese.
- `HomeView.swift:294` — `"\(title) takes a moment to compose"` interpolates a
  localized noun into a sentence. Whole-sentence key, difficulty name as `%@`.
- `TutorialGrammar.swift:35` hand-rolls `%@` with
  `replacingOccurrences(of: "%@", with: digit)`. Delete the hand-rolling; it is
  a format specifier the catalog already understands.

- [ ] **Step 6: Run the audit until it is empty**

```bash
cd nine && swift test --filter StringSeal && python3 scripts/strings.py --audit
```

Expected: PASS, 0 offences. Re-run `--extract` to fold the new keys in.

- [ ] **Step 7: Re-record the AX baselines — deliberately**

Five baselines are anchored on English literals
(`"Row 9, column 9"`, `"Resume on launch, On"`, `"How to play"`, `"Place 1"`,
plus taps on `"Settings"` and `"Home"`). If the collapse in Step 1 changed any
wording, the trees drift.

```bash
cd nine && python3 scripts/ax-snapshot.py             # read the diff FIRST
python3 scripts/ax-snapshot.py --record               # only if the diff is intended
```

A drift is a bug until proven otherwise. If the diff shows anything other than
wording you deliberately changed, stop — that is the PRD-19 collapse, not a
string edit.

- [ ] **Step 8: Commit** (in file-group batches, not one 26-file commit)

```bash
git commit -m "PRD-20: extract Sources/App — shelf and game surfaces"
git commit -m "PRD-20: extract Sources/App — prefs, sheets, tutorial"
```

---

### Task 6: Mechanical extraction — `Sources/Widgets`

**Why it is its own task:** the widget's strings are the only ones a player sees
**before** launching the app, in the widget gallery, and they resolve against a
different bundle. A reviewer could reasonably approve Task 5 and reject this.

**Files:** `DailyWidgetViews.swift` (~19), `BoardWidget.swift` (6),
`StreakWidget.swift` (5), `DailyProvider.swift`.

- [ ] **Step 1: The gallery strings first**

`.configurationDisplayName` and `.description` are the App Store-adjacent copy:
`"Daily"` / `"Today's puzzle, your streak and points at a glance."`
(`DailyWidgetViews.swift:25-26`), `"Playable Daily"` / `"Play today's puzzle
right on your Home Screen."` (`BoardWidget.swift:17-18`), `"Streak"` / `"Your
daily streak on the Lock Screen."` (`StreakWidget.swift:15-16`).

These take `LocalizedStringResource`, so they are the one place
`Strings.resource(_:)` is used rather than `Strings.string(_:)`.

- [ ] **Step 2: `BoardIntents.swift` already does it right — leave it**

`:14` and `:40` already declare `static let title: LocalizedStringResource`.
Both intents are `isDiscoverable = false`, so they never surface in Shortcuts.
No `AppShortcutsProvider` exists in the repo; PRD-33 is where that lands. Note
it as not-done rather than inventing scope.

- [ ] **Step 3: Verify on a device-sized simulator, in German**

Building is not evidence. Install, add all three widgets, switch the simulator
to German, and read the gallery:

```bash
xcrun simctl launch $UDID com.couchsuite.nine -AppleLanguages '(de)' -AppleLocale de_DE
```

Expected: gallery entries in German. If they are English, the catalog did not
reach the appex, and Task 4 Step 8's `find` was read too generously.

- [ ] **Step 4: Commit**

```bash
git add nine/Sources/Widgets && git commit -m "PRD-20: extract the widgets, gallery copy first"
```

---

### Task 7: The grammar the phrase book was hiding

**Why this is not part of Task 5:** every other file needed its literals moved.
`BoardSpeech` needs its *sentences rebuilt*, because its phrase book composes
them from fragments — which is the one localization mistake that produces nine
languages of confident, grammatical-looking nonsense.

**Files:**
- Modify: `nine/Sources/Shared/BoardSpeech.swift:377-472` and `:143-230`
- Modify: `nine/Tests/SharedTests/BoardSpeechTests.swift`

**The defect, in the code's own words:**

```swift
static func remaining(_ countWord: String, _ digitNoun: String) -> String {
    "\(countWord) \(digitNoun) remaining."          // "two fours remaining."
}
static func coachXWing(_ plural: String, base: String, cover: String, _ digit: String) -> String {
    "\(sentenceCased(plural)) in these two \(base) can only sit in two \(cover), …"
}
private static func sentenceCased(_ word: String) -> String { /* uppercase first letter */ }
```

Four things here are English-only, and a one-for-one key conversion preserves
all four:

1. **`sentenceCased`** capitalizes a sentence-initial word. German capitalizes
   every noun regardless of position; Japanese has no case at all. The operation
   is meaningless outside a handful of languages.
2. **`digitWords` / `digitPlurals`** spell numerals as English words. Japanese,
   Korean and Chinese use counters that depend on what is being counted;
   "fours" has no equivalent form.
3. **Fragment order** — "two fours remaining" fixes subject-object-adverb order
   in the *code*, so no translator can move it.
4. **`rowsWord` / `columnsWord` interpolated into a sentence** forces the unit
   noun into whatever case English happens to need.

- [ ] **Step 1: Write the failing tests — the properties, not the strings**

```swift
func testCoachSentencesAreWholeTemplatesNotFragments() throws {
    // The seal: no key in the coach family may take a pre-formatted English
    // noun. Arguments are Ints and IDs; the sentence is one catalog entry.
    for key in EnglishPhrases.table.keys where key.hasPrefix("coach.") {
        XCTAssertFalse(EnglishPhrases.table[key]!.contains("%@ %@"), """
            \(key) splices two words together. Whatever grammar that assumes is \
            English's, and a translator cannot fix it from the catalog.
            """)
    }
}

func testRemainingClauseHasOneKeyPerPluralCategory() { /* … */ }

func testNoSentenceCasingHelperSurvives() throws {
    let source = try String(contentsOf: boardSpeechURL, encoding: .utf8)
    XCTAssertFalse(source.contains("sentenceCased"), """
        Sentence-casing a translated noun is an English-only operation. German \
        capitalizes nouns everywhere; Japanese has no case. The catalog entry \
        carries its own capitalization.
        """)
}
```

- [ ] **Step 2: Run; expect failure**

```bash
cd nine && swift test --filter BoardSpeech
```

- [ ] **Step 3: Rebuild the coach sentences as whole templates**

One key per technique per unit-kind, with the unit baked into the sentence
rather than spliced:

```
coach.xWing.sentence.rowBase   = "%1$lld's in these two rows can only sit in two columns, so no other square in those columns can be a %1$lld."
coach.xWing.sentence.colBase   = "%1$lld's in these two columns can only sit in two rows, so no other square in those rows can be a %1$lld."
coach.nakedSingle.sentence     = "%1$@ has one candidate left: %2$lld."
coach.hiddenSingle.sentence.row = "Only one square in row %1$lld can take a %2$lld."
coach.hiddenSingle.sentence.col = "Only one square in column %1$lld can take a %2$lld."
coach.hiddenSingle.sentence.box = "Only one square in box %1$lld can take a %2$lld."
```

Two rows where there was one function, six where there were two — the
duplication is the point. A translator can now render each one naturally, and
`%1$lld` appearing twice in the X-Wing sentence is exactly why arguments are
positional.

- [ ] **Step 4: Move the digit words into the catalog, per digit**

**Decision taken (user, 2026-07-26) — this supersedes the "no fragments" rule
for the digit noun specifically, and only for it.**

The digit words exist for VoiceOver: speech synthesis reads "two fours
remaining" naturally and "2 4's remaining" badly, and that is the surface PRD-19
exists to protect. So the Swift arrays go, but the words survive as catalog
entries — 19 keys, one per digit plus zero:

```
board.digitWord.1 … .9     "one" … "nine"
board.digitPlural.1 … .9   "ones" … "nines"
board.countWord.0          "zero"
```

`remainingClause` still splices one noun into a sentence, but the splice is now
**a translator's choice rather than an English assumption**: a Japanese, Korean
or Chinese template simply uses the numeral and never references the word keys,
while English, German and French use them and inflect as their grammar needs.

```
board.remaining = { one: "%1$@ %2$@ remaining.", other: "%1$@ %2$@ remaining." }
board.allDone   = "All %1$@ done."
```

Everything else in this task's no-fragments rule stands. The coach sentences in
Step 3 take **no** pre-formatted nouns — the unit kind is baked into the key,
not spliced.

- [ ] **Step 4a: Add the test that pins the exception's boundary**

An exception that is not bounded is not an exception. This is what stops the
next person widening it:

```swift
func testTheOnlySplicedNounIsTheDigit() throws {
    // Decision of 2026-07-26: `board.digitWord.*` / `board.digitPlural.*` may be
    // spliced into a sentence, because VoiceOver reads "two fours remaining"
    // and "2 4's remaining" is a copy regression on the surface PRD-19 protects.
    // Nothing else may. A `%@` in a coach sentence is a fragment splice and the
    // grammar it assumes is English's.
    for (key, format) in EnglishPhrases.table where key.hasPrefix("coach.") {
        XCTAssertFalse(format.contains("%@"), """
            \(key) splices a pre-formatted word. Only the digit noun is allowed \
            to be spliced (board.digitWord.*), and only outside coach.*.
            """)
    }
}
```

- [ ] **Step 5: Update `BoardSpeechTests` to assert the new wording**

The test file is a *specification* of what the board says, and CI runs it before
it will build a simulator. Rewriting the assertions is expected; deleting them
is not.

- [ ] **Step 6: Run, then re-record the AX baselines**

```bash
cd nine && swift test --filter 'BoardSpeech|AXFixture'
python3 scripts/ax-snapshot.py          # read the diff
python3 scripts/ax-snapshot.py --record
```

Every spoken cell value changes shape here, so expect a large, *explicable*
diff. If a diff line is not explained by a sentence you rewrote, it is a
collapse.

- [ ] **Step 7: Commit**

```bash
git commit -m "PRD-20: the coach speaks in whole sentences, not English fragments"
```

---

### Task 8: Plurals, numbers, dates, lists — and the weekday bug

**Files:**
- Modify: `nine/Sources/Shared/ArchiveCalendar.swift:155,217`
- Modify: the 8 `String(format: "%d:%02d", …)` sites
- Modify: `nine/Sources/Strings/Localizable.xcstrings` (plural variations)
- Modify: `nine/Tests/EngineTests/CatalogTests.swift`

- [ ] **Step 1: Write the failing plural-completeness test**

This is the test that Apple's tooling does not give you. Verified on this
machine: a plural entry missing the CLDR `other` category **compiles clean,
exit 0**, and falls back to the key at runtime.

```swift
/// `xcstringstool compile` accepts a plural with no `other` category — measured,
/// exit 0, no warning — and at runtime that renders the key. So a German player
/// would read `streak.days` on the share card and nothing in the build would
/// have said so. This is the gate.
func testEveryPluralHasTheCategoriesItsLanguageRequires() throws {
    // CLDR cardinal categories actually used by the nine launch locales.
    // ja/ko/zh-Hans: {other}. de/nl/it/es/fr: {one, other}. pt-BR: {one, many, other}.
    let required: [String: Set<String>] = [
        "en": ["one", "other"], "de": ["one", "other"], "nl": ["one", "other"],
        "it": ["one", "other"], "es": ["one", "other"], "fr": ["one", "other"],
        "pt-BR": ["one", "many", "other"],
        "ja": ["other"], "ko": ["other"], "zh-Hans": ["other"],
    ]
    // ... for every entry with `variations.plural`, assert each locale's
    // categories are a superset of `required[locale]`, naming key + locale ...
}
```

- [ ] **Step 2: Run; expect failure**

```bash
cd nine && swift test --filter Catalog
```

- [ ] **Step 3: Convert the count-bearing strings to plural variations**

Every site the inventory flagged, with the source-language bug fixed on the way
past — `streak(1)` renders **"1 day streak"** today in all 8 sites:

```
streak.days      one: "%lld day streak"      other: "%lld day streak"
streak.days.held one: "%lld day streak, held" other: "%lld day streak, held"
board.empty      one: "%lld empty"           other: "%lld empty"
board.wrong      one: "%lld wrong."          other: "%lld wrong."
stats.left       one: "%lld left"            other: "%lld left"
game.autoNotes   one: "Auto notes · filled %lld candidate"  other: "… %lld candidates"
shelf.inProgress one: "%lld in progress"     other: "%lld in progress"
```

English `one` and `other` being identical for `streak.days` is not redundancy —
it is the entry existing so German, French and Spanish can differ.

- [ ] **Step 4: Fix `weekdayInitials` — the one unambiguous live locale bug**

`ArchiveCalendar.swift:155` returns `["S","M","T","W","T","F","S"]`. The column
order already respects `firstWeekday`; only the letters are wrong.

```swift
/// Ask the locale, do not spell them. The order here has always respected
/// `firstWeekday`; the letters were English on every locale, which is a bug
/// that predates PRD-20 and that no test could see because no test ran in a
/// non-English locale.
private static var weekdayInitials: [String] {
    let symbols = displayFormatter("").veryShortWeekdaySymbols ?? []
    // ... rotate by firstWeekday exactly as the existing code does ...
}
```

Add a test asserting the German initials are `["M","D","M","D","F","S","S"]`
starting Monday — it fails against today's code, which is the point.

- [ ] **Step 5: `ListFormatter` for the joined accessibility label**

`ArchiveCalendar.swift:217` joins with a literal `", "`. Japanese uses `、` and
Chinese `，`. `ListFormatter` knows this; a catalog entry would only move the
hard-coding.

- [ ] **Step 6: The clock — consolidate 8 copies, keep the deliberate shape**

`String(format: "%d:%02d", …)` appears in `HistorySheet:281`, `MacUI:777`,
`StatsDrawer:172`, `TouchUI:1482`, `BoardsSheet:245`, `GameScreen:665`,
`SolveCardFacts:76`, `DailyProvider:90`. One copy, in Shared, next to
`SolveCardFacts.elapsedText` — which already documents *why* minutes run past 60
rather than growing an hours field (`:71-75`). Keep that decision; it is a
card-layout choice, not an oversight. Localize the numerals via
`.formatted(.number)` on each component so Eastern Arabic and Devanagari render,
and leave the `:` separator alone.

- [ ] **Step 7: Percentages and signed numbers**

`"\(Int(fraction * 100))%"` in 4 places (`BoardFingerprint:86`, `HomeView:137`,
`MacUI:202`, `DailyProvider:94`) → `fraction.formatted(.percent)`.
`"+\(record.points)"` (`HistorySheet:271`) →
`.formatted(.number.sign(strategy: .always()))`. `"\(Int(seconds))s"`
(`StatsDrawer:167`) becomes a catalog entry — `s` is an English abbreviation.

- [ ] **Step 8: Run everything**

```bash
cd nine && swift test && python3 scripts/strings.py --audit
```

- [ ] **Step 9: Commit**

```bash
git commit -m "PRD-20: plurals, and the weekday initials that were always English"
```

---

### Task 9: The nine languages

**Files:**
- Modify: `nine/Sources/Strings/Localizable.xcstrings`
- Modify: `nine/Tests/EngineTests/CatalogTests.swift`

**Decision 1 governs this task:** machine-drafted, every string
`state: "needs_review"`, and a DEVIATIONS entry saying so plainly.

- [ ] **Step 1: Write the tests that make the decision enforceable**

`state: "needs_review"` is erased by `xcstringstool compile` — verified; it
compiles byte-identically to `translated`. So the claim needs its own test or it
is a comment pretending to be a guarantee.

```swift
func testEveryMachineDraftIsMarkedNeedsReview() throws {
    // Nine languages nobody on this project reads. The state is the only
    // honest record of that, and the compiler throws it away, so this is where
    // it is kept true. When a human reviews a language, they flip its states
    // and this test's expected count moves with them — deliberately, in a diff.
}

func testNocturneIsIdenticalInEveryLocale() throws {
    // Decision 2: Gentle/Steady/Sharp are descriptions and translate; Nocturne
    // is a coined name and does not. A pinned test rather than a comment,
    // because the next translation pass will not have read this plan.
    for locale in Self.launchLocales {
        XCTAssertEqual(value(of: "difficulty.nocturne.title", in: locale), "Nocturne")
    }
}

func testNoLocaleIsMissingAKeyThePlayerCanReach() throws { /* … */ }
```

- [ ] **Step 2: Draft the nine locales**

Per key, per locale, with `"state": "needs_review"`. Two rules the drafting must
respect, both from the covenant rather than from grammar:

- **Nothing may become a scold.** "Your streak held" / "You took yesterday off;
  one rest day won't cost you." (`TouchUI.swift` Phrase block) exists precisely
  so PRD-13 never shames. A translation that lands as "You missed a day!" fails
  review even if it is correct.
- **Nothing may imply a purchase.** "No ads, no subscription, nothing else to
  buy" (`FirstRun.swift:383`) is a covenant statement.

- [ ] **Step 3: Pin `Nocturne`, translate the other three**

```
difficulty.gentle.title   ja "やさしい"   de "Sanft"      …
difficulty.steady.title   ja "おだやか"   de "Stetig"     …
difficulty.sharp.title    ja "するどい"   de "Scharf"     …
difficulty.nocturne.title ja "Nocturne"  de "Nocturne"   …  ← every locale
```

With a catalog `comment` on the Nocturne entry saying it is deliberate, so the
first human translator does not "fix" it.

- [ ] **Step 4: Compile and count**

```bash
cd nine
XT=/Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool
$XT compile Sources/Strings/Localizable.xcstrings --output-directory /tmp/nine-loc
ls /tmp/nine-loc            # expect 10 .lproj directories
$XT print Sources/Strings/Localizable.xcstrings | wc -l   # the key count for DEVIATIONS
```

- [ ] **Step 5: Commit**

```bash
git commit -m "PRD-20: nine languages, every string marked needs_review"
```

---

### Task 10: The pseudo-loc + RTL lane

**Files:**
- Create: `nine/scripts/loc-harness.py`
- Create: `nine/Tests/LocBaselines/`
- Modify: `.github/workflows/nine-accessibility.yml`

**Interfaces:**
- Consumes: `scripts/simrig.py` — `prepare_simulator`, `build_and_install`,
  `seed`, `describe`, `wait_for`, `relaunch`, `wait_until_dead`.
- Produces: `python3 scripts/loc-harness.py [--record] [--app PATH] [--out-dir]`.

- [ ] **Step 1: Prove the mechanism before building a lane on it**

Apple's pseudolanguages are launch arguments, not build settings, so they need
no catalog changes. **This is an assumption until it is a screenshot.** Install
the built app and try all three, reading the screen each time:

```bash
UDID=...   # a booted iPhone 17 Pro
xcrun simctl launch $UDID com.couchsuite.nine -NSDoubleLocalizedStrings YES
xcrun simctl launch $UDID com.couchsuite.nine -AppleTextDirection YES \
                                              -NSForceRightToLeftWritingDirection YES
xcrun simctl launch $UDID com.couchsuite.nine -AppleLanguages '(de)' -AppleLocale de_DE
```

Expected: doubled strings; a mirrored chrome layout; German. **If double-length
does not fire**, fall back to generating a `qps-Ploc` locale into a *copy* of the
catalog in a temp tree and building there — deterministic, testable, and it does
not pollute the shipped catalog. Record which path was taken and why; an
assumption that survived because nobody checked is how the AX tree shipped
empty in 1.1.

- [ ] **Step 2: Write the failing test — the rose never mirrors**

Decision 3. The rose is a spatial 3×3 ring whose petal positions mirror the
board's digit layout; mirroring it would move the 7 under the thumb that expects
the 3.

```python
# In loc-harness.py, asserted from the AX tree rather than from pixels: the
# frames are the claim, and `describe-ui` reports them in points.
def assert_rose_unmirrored(ltr_tree, rtl_tree):
    """Petal 1 sits bottom-left and petal 9 top-right in BOTH directions.

    The rose is a numeric grid, not text (PRD-20 decision 3). Chrome may
    mirror; this may not. Asserted on the ring's own frames because a
    screenshot diff cannot tell a mirrored rose from a moved one.
    """
```

- [ ] **Step 3: Implement the harness on `simrig.py`**

Reuse the rig wholesale — the dedicated simulator, the erase, the bridge
warm-up, the seeded container, the settle-before-you-read discipline. Every one
of those exists because of a specific way the naive version was flaky
(`simrig.py:1-14`). Extend `relaunch` to pass launch arguments, which is the one
thing it cannot do today:

```python
def relaunch(udid, bundle_id, blobs, args=()):
    run(["xcrun", "simctl", "terminate", udid, bundle_id], check=False)
    wait_until_dead(udid, bundle_id)
    seed(udid, bundle_id, blobs)
    run(["xcrun", "simctl", "launch", udid, bundle_id, *args])
```

Screens: the same five the AX lane uses, so a reviewer compares like with like.
Modes: `double` (truncation), `rtl` (layout + the rose assertion), `de` (the
longest real launch language — German is the practical worst case of the nine,
and a real language finding nothing while a synthetic one fails is useful
information about the synthetic one).

- [ ] **Step 4: Detect truncation from the tree, not by eye**

Truncation is the failure this lane exists for and it is invisible to a
screenshot diff, because a truncated label still looks like a label. Assert on
frames: any element whose frame width is at its container's width **and** whose
label ends in `…` is a clipped string. Report `screen/element: "label"`.

- [ ] **Step 5: Wire it into the existing lane**

The `ax-tree` job already has a built app and a warm simulator, and it already
budgets 180 minutes. A second job would rebuild from scratch to learn the same
thing. Add after the contrast step:

```yaml
      # Pseudo-localization, RTL and the German build, on the app that is
      # already built. Truncation is the failure this catches, and it is
      # invisible to a screenshot diff — a clipped label still looks like a
      # label. The assertions are on `describe-ui` frames.
      - name: Pseudo-loc, RTL and Dynamic Type
        working-directory: nine
        run: |
          set -euo pipefail
          python3 scripts/loc-harness.py \
            --app build/Build/Products/Debug-iphonesimulator/Nine.app \
            --out-dir "$RUNNER_TEMP/loc"
```

and add `${{ runner.temp }}/loc` to the `if: failure()` artifact paths — on
failure those screenshots are the whole review.

- [ ] **Step 6: Record baselines and commit**

```bash
cd nine && python3 scripts/loc-harness.py --record
git add nine/scripts/loc-harness.py nine/Tests/LocBaselines \
        .github/workflows/nine-accessibility.yml
git commit -m "PRD-20: pseudo-loc and RTL, with the rose pinned LTR"
```

---

### Task 11: Dynamic Type stress

**Files:**
- Modify: `nine/scripts/loc-harness.py`
- Modify: `nine/Tests/LocBaselines/`

The mechanism is confirmed on this machine — note the **underscore**:

```bash
xcrun simctl ui $UDID content_size accessibility-extra-extra-extra-large
```

- [ ] **Step 1: Write the failing assertion — 44pt at AX5**

The craft charter requires "no truncation at top non-AX Dynamic Type" and
"≥44pt AX frames" (`PROGRAM-2.0.md §Craft charter`). At AX5 those two fight each
other, which is exactly why it is worth measuring.

```python
AX_FRAME_FLOOR = 44.0   # points, PRD-19's rule
SIZES = ["large", "extra-extra-extra-large", "accessibility-extra-extra-extra-large"]
```

- [ ] **Step 2: Assert on frames across the three sizes**

For each of the five screens × three content sizes: no interactive element's
frame drops below 44×44, and no label is clipped. `EXECUTING-A-PRD.md §4` warns
that SwiftUI derives an image-only `Button`'s AX frame from the SF Symbol's
tight glyph bounds rather than its `.frame(44,44)` — so expect the six
`GlassIconButton`s in the control bar (`TouchUI.swift:694-734`) to be where this
first fires, and `.contentShape(.accessibility, Circle())` to be the fix.

- [ ] **Step 3: Run it and expect real failures**

Run against the current tree **before** fixing anything, and write the failures
down. A stress test whose first run is green has not been calibrated — PRD-22's
harness found five failures on its first run against unmodified code, and PRD-16's
palette test found a four-release-old sub-AA pair.

- [ ] **Step 4: Fix what it finds, or record what is deferred with its number**

"Reverted, 1515 ms against a 49 ms baseline" tells the next person where to
start; "too slow" does not (`EXECUTING-A-PRD.md §6`).

- [ ] **Step 5: Commit**

```bash
git commit -m "PRD-20: Dynamic Type stress at AX5, measured on frames"
```

---

### Task 12: Verify, drive, record, ship

- [ ] **Step 1: The full gate**

```bash
cd nine
COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate
swift test                                     # must stay under ~120 s
swift test --filter GoldenCorpus               # 56/56, said out loud
python3 scripts/strings.py --audit
python3 scripts/ax-snapshot.py
python3 scripts/contrast-harness.py --quick
python3 scripts/loc-harness.py
for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" \
    -derivedDataPath build CODE_SIGNING_ALLOWED=NO build
done
```

- [ ] **Step 2: The Release archive**

Release breaks in ways Debug does not, and CI archives in Release. String
Catalogs are compiled by a build phase, which is precisely the kind of thing
that can be configured only for Debug and discovered on TestFlight:

```bash
xcodebuild archive -project Nine.xcodeproj -scheme Nine \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath /tmp/NineRelease.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
find /tmp/NineRelease.xcarchive -name '*.lproj' | sort   # 10 per bundle, both bundles
```

- [ ] **Step 3: Actually drive it, in Japanese and German**

A green test suite is not evidence that a reshaped surface works
(`EXECUTING-A-PRD.md §5`). Install on a simulator and walk **every screen this
PRD touched** in `ja` and in `de`, keeping the screenshots:

- home shelf, Today card, difficulty cards (the blurbs are long in German)
- game screen, control bar, rose open, coach card
- prefs (every section), boards sheet, history sheet, archive sheet
- first run, tutorial, share card, completion chip
- all three widgets in the gallery, and on the Home Screen
- **VoiceOver on**, reading cells and the coach — the AX labels are ~40 of the
  strings and no screenshot shows them

tvOS and macOS too: `MacUI.swift` holds 21 bare literals today, has no `Phrase`
block, and has not been touched by the last five PRDs, which makes it the least
exercised surface in this PR. Use the `run-couch-suite` skill for tvOS and
prefer `sim-use` over `axe` on iOS 26.x.

- [ ] **Step 4: The taste ritual**

Per `EXECUTING-A-PRD.md §1`, on the German and Japanese builds specifically:
the 11pm-in-bed test, the roommate test, the first-flick test, the
delete-it-for-a-week test, the idle-pixel test. A doubled-length German string
that pushes the board off-centre fails the idle-pixel test even though nothing
truncated.

- [ ] **Step 5: Confirm no entitlement changed**

`EXECUTING-A-PRD.md §6` — the trap that has fired three times. Localization
needs no capability and no `match` re-mint, and that is a claim with an artifact:

```bash
git diff origin/main -- nine/Nine-iOS.entitlements nine/Nine-tvOS.entitlements \
                        nine/Nine-macOS.entitlements nine/Nine.entitlements
```

Expected: **empty.** If it is not empty, stop and re-mint all three profiles
before the PR merges — CI runs `match(readonly: true)` and cannot mint anything.

- [ ] **Step 6: Write the DEVIATIONS entry**

A new `## PRD-20` section, in the house voice, leading with what measurement
found rather than what was built. It must contain at least:

- **The two facts `xcstringstool` does not check** — plural `other` missing
  compiles clean at exit 0, and `needs_review` is erased at compile time — with
  the note that both are gated by our own tests instead, because a tool assumed
  to check something and not checking it is worse than no tool.
- **The two pre-existing bugs the inventory found**: `weekdayInitials` English
  on every locale, and `streak(1)` reading "1 day streak" across 8 sites in 3
  spellings.
- **The numbers**: keys in the catalog, strings extracted, `swift test` count and
  wall time *with the load average* (a number without one is not a number),
  golden corpus 56/56 after every commit.
- **Not done**, each with its reason: no human review of any of the nine
  languages (decision 1, stated plainly — this is the headline deferral); no
  tvOS/macOS pseudo-loc lane (`describe-ui` is iOS-only, same wall PRD-19 and
  PRD-22 hit); CouchKit's own strings (`HelpKit.swift:117-134` — "Click to
  start" / "Tap to start" reach Nine's tvOS home via `HomeOverlay`, and
  localizing them means a catalog in a package shared by five apps, which is a
  suite decision, not Nine's); no `AppShortcutsProvider` to localize (PRD-33);
  no store-page localization (PRD-35); and whatever Task 7 Step 4 decided about
  English losing "two fours remaining".

- [ ] **Step 7: Update the status table**

`PROGRAM-2.0.md:25` — `PRD-20 localization | not started | needs translators,
not infrastructure`. That line was written before anyone counted; the honest
replacement records that infrastructure was ~397 strings and two live locale
bugs, and that translators are still the open item.

- [ ] **Step 8: One PR**

```bash
gh pr create --base main --title "Nine: nine languages, and the grammar underneath (PRD-20)"
```

---

## Self-review notes

**Spec coverage.** Every clause of `PROGRAM-2.0.md:71` maps to a task: String
Catalogs first → Tasks 1, 4; mechanical extraction of every literal → Tasks 5, 6;
Engine never localizes / Linux CI → Task 2 plus Task 1's new Lane 1; stable IDs →
Task 2 (the raw values already were the IDs, which is why `techniqueID` is not a
new symbol); single App-layer `Strings.swift` → Task 4; the nine launch locales →
Task 9; pseudo-loc + RTL audit CI lane → Task 10; plural variants → Task 8;
Dynamic Type stress tests → Task 11.

**Three places this plan deviates from the brief, and why.**

1. *"Each file already has a `Phrase` block; that is the seam."* — 11 files do,
   out of ~48, and three of those blocks are named something else. The seam is
   partly built. Tasks 5 and 6 create it where it is missing, which is most of
   the work and was not in the brief's estimate.
2. *"Mechanical extraction"* — cannot be Xcode's automatic extraction, because
   ~321 of ~397 strings arrive as `String` through helper functions and the
   non-localizing `.accessibilityLabel` overload. The mechanism is a script plus
   a source-grep test (Task 1), which is why that task is first.
3. *"Engine … emits stable IDs (`techniqueID`, difficulty raw values)"* — no new
   symbol is needed. `Technique.rawValue` **is** the stable ID and is already
   frozen inside the golden corpus hash. Adding a `techniqueID` field would be a
   second identity that can disagree with the first, and would risk the very
   hashes it was meant to protect. Task 2 deletes rather than adds.

**Ordering risk.** Tasks 2 and 4 are a build-breaking pair: deleting
`Difficulty.title` orphans ~10 call sites until `Strings.difficulty(_:)` exists.
Land them as one commit if the intermediate tree will not build. Every other task
leaves the tree green.

**File contention** (`EXECUTING-A-PRD.md §7`). Task 5 touches
`Sources/App/TouchUI.swift`, the repo's contention hotspot, which owns both the
iOS home shelf and the game screen. **Do not run another UI-heavy PRD in
parallel with Task 5.** Tasks 1–4 and 7–9 are safe against anything.

**What could still go wrong.** Two things this plan does not fully de-risk:

- The pseudolanguage launch arguments (Task 10 Step 1) are the lane's
  foundation and are unverified against *this app*. The fallback is specified,
  but if `-NSDoubleLocalizedStrings` turns out not to fire, Task 10 costs
  meaningfully more than budgeted.
- The nine machine-drafted languages are, by decision, unreviewed. The tests pin
  their *shape* — keys present, plurals complete, states honest, Nocturne
  unmoved — and pin nothing about whether the German for "Your streak held"
  reads as comfort or as an accusation. That is the deferral the DEVIATIONS
  entry has to state without softening, because it is the one thing in this PRD
  that a green CI run says nothing about.
