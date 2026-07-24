# PRD-7 — The $4.99 buildout (program master)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** program doc — no code of its own
**One-liner:** Nine becomes a **$4.99 universal paid app** — buy once on iPhone,
iPad, Mac or Apple TV, own it everywhere, with your boards following you — and
every feature in PRD-8…18 ships to *every* user, because every user has paid.

## 1. The model (decided)

- **$4.99, paid up front, universal purchase** across iOS / macOS / tvOS (one
  App Store Connect app record, shared bundle id `com.couchsuite.nine`).
- **No IAP, no subscription, no gating.** There is no paywall, no "Pro" tier,
  no locks, no quotas anywhere in the app. Monetization UI does not exist;
  the product *is* the pitch.
- **No ads, ever** (PRD §24). The brand stays serene.
- Store pitch, in order: ① your puzzles follow you across devices (PRD-8),
  ② beautiful stats that make the habit visible (PRD-9), ③ a crafted,
  remote-first / touch-first / keyboard-first sudoku on every screen (shipped).

## 2. The collection

| PRD | Feature | Size | Primary files owned |
|---|---|---|---|
| 8 | Cloud library — all boards sync via CloudKit | L | `AppModel.swift`, new `Sources/App/CloudSync/`, entitlements, `project.yml` |
| 9 | Rich stats | M | `HistorySheet.swift`, `Scoring.swift`, new `StatsViews.swift` |
| 10 | Rose completion — erase petal + digit counts | S | `FlickRoseView.swift`, `TouchUI.swift` (rose region) |
| 11 | Coach hints + auto notes | M | `TouchUI.swift` (control bar), `BoardView.swift`, small `AppModel` API |
| 12 | Share your solve | S | new `ShareCardView.swift`, `TouchUI.swift` (completion area) |
| 13 | Streak grace | S | `Game.swift` (`StreakState`), `TouchUI.swift` (chips) |
| 14 | Daily archive | M | new `ArchiveSheet.swift`, `TouchUI.swift` (Today card) |
| 15 | Feedback — placement haptics + sound | S | `PrefsSheet.swift`, `AfterglowHaptics.swift`, `NinePrefs` |
| 16 | Appearance+ — themes, accents, alt icons | M | `AppModel.swift` (theme enums), `PrefsSheet.swift`, asset catalog |
| 17 | Nocturne difficulty | M | `Generator.swift`, `TouchUI.swift` + `HomeView.swift` (difficulty rows) |
| 18 | Welcome card + variants teaser | S | `TouchUI.swift` (home), new `WelcomeCard.swift` |

Prototype references: every feature has a flag-gated visual prototype on branch
`ngoldbla/iphone-ux-audit-sim-use` (`-uxdemo.*` launch args; screenshots in that
workspace's `.context/ux-audit/`). Prototypes are *look* references, not
implementations — production code replaces them.

## 3. Sequencing — waves, deconflicted by file ownership

`TouchUI.swift` is the contention hotspot: **at most one in-flight PRD may own
it at a time.** Within a wave, listed PRDs touch disjoint files and can run as
parallel agents; waves are ordered.

- **Wave 1 (parallel):** PRD-8 (sync — start first, longest pole) · PRD-9
  (stats) · PRD-10 (rose; sole TouchUI owner of the wave)
- **Wave 2 (after 10 merges):** PRD-11 (coach+notes; TouchUI owner) · PRD-15
  (feedback; PrefsSheet only) in parallel; then PRD-12 (share; TouchUI owner)
- **Wave 3:** PRD-13 (streak grace; TouchUI owner) → PRD-14 (archive; TouchUI
  owner) · PRD-16 (appearance; PrefsSheet/assets) in parallel with either
- **Wave 4:** PRD-17 (Nocturne) → PRD-18 (welcome + teaser)

Rules for every PRD build:
1. Branch from **latest `main`**; rebase before starting if the branch is stale.
2. The wave's TouchUI owner merges before the next TouchUI owner branches.
3. Green gates before PR: `swift test` in `nine/` (engine), `xcodebuild` for
   **iPhone simulator AND tvOS simulator** (macOS too when the PRD touches
   shared UI), and a `sim-use` screenshot of the feature actually running.
4. When a feature ships, **delete its `-uxdemo.*` scene** from
   `UXDemo.swift`/`UXDemoScenes.swift` in the same PR (the last PRD standing
   deletes the files).
5. Engine changes are TDD (`Tests/` first — the suite has 28 green tests; keep
   them green). Tolerant decoding is law: any new persisted field follows the
   `NinePrefs` pattern (`AppModel.swift:231`), because `CouchStored` discards a
   whole blob when decode throws.

## 4. Agent handoff protocol (superpowers)

Each PRD is executed by a **fresh agent session** given this kickoff prompt:

> Read `nine/PRD-<N>.md` and `nine/PRD-7.md` §3 (rules) + §5 (ASC gates). The
> PRD is the approved design — do not re-litigate product decisions. Use the
> superpowers **writing-plans** skill to turn the PRD into an implementation
> plan, then **executing-plans** (or subagent-driven-development) to build it.
> Engine work is TDD. Verify per PRD-7 §3 rule 3, then use
> **finishing-a-development-branch** to open a PR titled `Nine: <feature> (PRD-<N>)`.

Sequencing is enforced by the human: launch wave-mates together, hold the next
TouchUI owner until the current one merges.

## 5. App Store Connect gates (human-owned, not agent work)

- **Before PRD-8 merges:** create the CloudKit container
  (`iCloud.com.couchsuite.nine`) in the developer portal, add the iCloud/
  CloudKit capability to the three platform app IDs, and **re-mint match
  profiles for iOS, tvOS and macOS** — the PRD-3 app-group lesson: entitlement
  changes without re-minted profiles break `beta_all` CI on merge.
- **Before release:** set the app to paid $4.99 (universal purchase), update
  store copy to the pitch in §1, and deploy the CloudKit schema to Production
  (dev-environment schemas do not auto-promote).

## 6. Verification (program level)

- Every PRD's checklist passes; suite-wide audits stay green (no engine
  UI imports, no `.glassEffect` outside CouchKit).
- After each wave: full-suite build (`scripts/testflight.sh` dry run or CI) to
  catch cross-app breakage early.
- End state: all `-uxdemo.*` code deleted; a fresh $4.99 install on iPhone +
  Apple TV shows the same library within seconds of first launch.

## 7. Open questions

- Price-drop launch promo ($2.99 launch week)? Store-page decision, no code.
- Do prefs (theme/accent) sync too? Deferred to PRD-8 §7 — cheap via KVS if wanted.
