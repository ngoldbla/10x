# Executing a Nine PRD

Working notes for whoever picks up the next PRD — human or agent. Everything
here is a rule that has already cost someone a broken build, a lost afternoon,
or a suite-wide TestFlight outage. It is not general advice; it is this repo's
scar tissue.

Read first: [PROGRAM-2.0.md](../PROGRAM-2.0.md) for where the PRD sits in the
program, `nine/PRD-<n>.md` for the spec itself, the last two sections of
[DEVIATIONS.md](../DEVIATIONS.md) for what was deliberately left undone and
why, and [PRD-7.md](../PRD-7.md) for the covenant.

---

## 1. The covenant is binding, not aspirational

Nine is a $4.99 paid app with **no IAP, no subscription, no tips, no ads, no
gamification** (XP, levels, badges, avatars), **no notifications** beyond a
single opt-in silent daily reminder that is off by default, and **no streak
shaming**. The coach never places a digit. There is no fifth control button.

Before shipping any user-visible change, run the taste ritual from the program
plan: the 11pm-in-bed test, the roommate test, the first-flick test, the
delete-it-for-a-week test, the idle-pixel test.

**One new input concept per release, maximum.** Spend it deliberately or not at
all.

---

## 2. Persistence: the rules that will bite you

### New per-board state goes in a sibling key, not on `LibraryEntry`

`nine.library` persists as **one** `CouchStored` blob. `BoardLibrary`'s
hand-written decode quarantines whole *elements* it cannot read, so a future
`Difficulty` case or `GameKind` discriminator can no longer destroy a player's
library. It does **not** protect unknown *fields inside an element it can still
read* — `LibraryEntry`'s synthesized decode ignores keys it has no property
for, so an older build decodes the entry "successfully" and erases the new field
on its next autosave, 0.6 s later, repeatedly, for any mixed-version
two-device player.

Field-level preservation was implemented and reverted: **1515 ms** to decode a
full 60-entry library against a **49 ms** baseline, on a launch path budgeted at
800 ms for the whole app. So:

> **Put new per-board persisted state in a sibling top-level key of the blob
> (which `carriedTopLevel` preserves for free), or in its own `CouchStored`
> blob. Do not add fields to `LibraryEntry`.**

This applies directly to PRD-11 (hints used), PRD-25 (`CoachProgress`) and
PRD-26 (`SolveReplay`).

### Never throw out of a container decode

Any `Codable` type persisted through `CouchStored` must decode tolerantly —
`CouchStored` discards the **whole blob** when decode throws. See the
hand-written `init(from:)` on `NineGame`, `NinePrefs` and `BoardLibrary` for the
pattern. Adding a field means adding a `decodeIfPresent … ?? default`, and
adding an enum case means checking every persisted enum's decode is `try?`-guarded.

### Data placement

Streak, prefs, history and coach progress stay in KVS (small, LWW-safe — do not
grow `SolveHistory`). Library and immutable replay records go to CloudKit zone
`NineLibrary`. Pantry/catalog data is local-only.

---

## 3. Determinism: the golden corpus is a contract

`Tests/EngineTests/GoldenCorpusTests.swift` freezes SHA-256 hashes of 50
`(seed, difficulty)` pairs. Classic generation is a pure function that the whole
app leans on — every daily is `(day → seed) → puzzle`, every shared board is a
seed — so a quiet change silently re-rolls **every future daily** and breaks
**every shared seed**.

- Run it after every engine commit, not at the end of the branch.
- A mismatch is a bug until proven otherwise. The hasher is pinned to the FIPS
  180-4 vectors, so a failure always means generation moved.
- Re-freezing is a deliberate act with a paper trail:
  `NINE_FREEZE_GOLDEN=1 swift test --filter GoldenCorpus`.

For PRD-23's variant refactor specifically: `SudokuGrid` stays untouched, classic
paths delegate to a shared static empty `ConstraintContext` rather than being
rewritten, and `BacktrackSolver`'s originals stay frozen — they define classic
dailies forever.

---

## 4. Accessibility is a regression surface now

The board is one `Canvas` with 81 synthetic accessibility children in 9 box
containers (`Sources/App/BoardAccessibility.swift`), labelled by the pure
formatter in `Sources/Shared/BoardSpeech.swift`. Any change to `BoardView` or the
game screens can silently flatten that tree, and nothing on screen changes when
it does.

CI now diffs it for you, per screen, on every PR touching `nine/`:

```bash
python3 nine/scripts/ax-snapshot.py             # diff against Tests/AXBaselines/
python3 nine/scripts/ax-snapshot.py --record    # re-record, deliberately
```

A drift is a bug until proven otherwise. When it *is* intended, re-record and
say so in the PR — the baselines are the paper trail. Two coupled re-freezes:
changing the seeded board means
`NINE_FREEZE_AX_FIXTURE=1 swift test --filter AXFixture` **and** `--record`,
together, or the baselines are photographs of a board that no longer exists.

Reading a tree by hand is still the fastest way to answer "what does this one
cell say":

```bash
sim-use describe-ui --device $UDID | grep -c "Row "        # must be 81
sim-use describe-ui --device $UDID --point X,Y --json \
  | python3 -c "import sys,json; d=json.load(sys.stdin)['data']['raw']; print(d['AXValue'], d['custom_actions'])"
```

The plain listing shows labels and frames only — **values and custom actions are
visible only with `--json`**, so a regression there is invisible without it.

Two things no dump can see, so they live in `Tests/SharedTests/BoardSpeechTests.swift`
instead: Voice Control input labels (`accessibilityUserInputLabels` is absent
from the AX API `describe-ui` reads) and the wording of any announcement.

Four gotchas worth knowing before you fight them:

- UIKit surfaces `.accessibilityActions` in **reverse** declaration order — so
  the whole `cellActions` block reads bottom-up, and putting `Erase` last in the
  rotor means declaring it first.
- Switch Control's group scan has **no API**: it is derived from the
  accessibility *container* tree. Nesting is the only lever, and a child belongs
  to one parent, so a grouping choice is also a VoiceOver traversal-order choice.
- SwiftUI derives an image-only `Button`'s accessibility frame from the SF
  Symbol's tight glyph bounds, not its `.frame(44, 44)`. Fix with
  `.contentShape(.accessibility, Circle())`.
- Never leak state the sighted player is not shown. `showErrors == false` must
  suppress the "wrong" word in the spoken value, the wrong-digits rotor, **and**
  the error haptic.

User-facing strings belong in one `Phrase` block per file — that is the single
seam PRD-20 converts to `LocalizedStringResource`. Don't scatter literals through
view code.

---

## 5. Build, test, verify

```bash
cd nine
COUCH_TEAM_ID=XC6FN96MA8 xcodegen generate      # project files are generated, never committed

swift test                                       # Engine + Shared; must stay under ~120 s

for dest in 'generic/platform=iOS Simulator' 'generic/platform=tvOS Simulator' 'platform=macOS'; do
  xcodebuild -project Nine.xcodeproj -scheme Nine -destination "$dest" -derivedDataPath build build
done
```

Release configuration breaks in ways Debug does not, and CI archives in Release.
Prove it locally without needing signing:

```bash
xcodebuild archive -project Nine.xcodeproj -scheme Nine \
  -destination 'generic/platform=iOS' -configuration Release \
  -archivePath /tmp/NineRelease.xcarchive \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO
```

**Then actually drive the app.** A green test suite is not evidence that a
reshaped surface works. Install on a simulator, walk every screen you touched,
and keep the screenshots. See the `run-couch-suite` skill for tvOS and prefer
`sim-use` over `axe` on iOS 26.x simulators.

---

## 6. Shipping

### Entitlements: the trap that has fired three times

App groups (PRD-3), Game Center, and CloudKit (PRD-8) each broke the whole
suite's TestFlight run the same way.

> **Any entitlement change must POST the capability to the bundle ID **and**
> `match --force` re-mint all three profiles (tvos / ios / macos) BEFORE the PR
> merges.** CI runs `match(readonly: true)` and cannot mint anything.

CloudKit additionally needs `aps-environment` and the Push capability, because
`CKSyncEngine` relies on CloudKit push for background sync.

### Build numbers collide across branch and merge

`CFBundleVersion` = `git rev-list --count HEAD × 10 + platform offset`
(tvOS +0, iOS +1, macOS +2). The repo **squash-merges**, so a feature branch
already computes the count main will have *after* the merge.

- Merging to `main` triggers `beta_all` for the whole suite. That is the normal
  way to ship.
- A branch `workflow_dispatch` with `validate_only: true` is safe.
- A branch dispatch that **uploads** consumes the post-merge build number. If you
  do that (the only option when `MATCH_PASSWORD` is unavailable locally), merge
  with **`[skip ci]` in the squash title** — otherwise ASC rejects the duplicates
  and the failure can abort the run before the four sibling apps upload.

```bash
gh workflow run "TestFlight (Couch Suite)" --ref <branch> \
  -f app=nine -f platform=all -f validate_only=false
```

Note the workflow has a concurrency group: back-to-back dispatches cancel the
queued one.

### One PR, and say what you didn't do

Record every deferral in `DEVIATIONS.md` with its reason, and prefer a measured
number over an adjective. "Reverted, 1515 ms against a 49 ms baseline" tells the
next person where to start; "too slow" does not.

---

## 7. Running several PRDs at once

Wave 0 splits cleanly, but only along file boundaries. `Sources/App/TouchUI.swift`
is the contention point — it owns the iOS home shelf **and** the game screen, so
**do not run two UI-heavy PRDs in parallel.** Safe splits:

- engine-only work (`Sources/Engine`) against anything;
- one UI PRD at a time;
- new-file work (a new sheet, a new view) against an existing-file PRD.

Give each agent explicit file ownership in its prompt, and say plainly which
files it may not touch. Agents that share a file will silently clobber each
other's edits and leave the tree mid-build.
