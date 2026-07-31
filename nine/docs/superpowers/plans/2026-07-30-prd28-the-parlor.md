# PRD-28 — The Parlor: implementation plan

Spec: [`nine/PRD-28.md`](../../../PRD-28.md). Ten tasks, pure layers first, each
one ending green. Engine is untouched throughout — the corpus is run after every
task anyway, because §2 makes it load-bearing in a second direction.

**Precondition (done first, out of scope but blocking):** `DuelHandoff.decide`
on `main` returns `.continue` unconditionally and `DuelHandoffTests` is 7-red on
a clean checkout. PRD-28 cannot claim a green gate on top of a red suite, so the
rule is restored per PRD-27 §4.1/§4.2 before anything here starts.

---

## Task 1 — `ParlorInvite` and its two envelopes

`Sources/Shared/Parlor.swift`, `Tests/SharedTests/ParlorTests.swift`.

The seed, the tier, the optional day. `Codable` for SharePlay; a
`[String: String]` codec for `GKGameActivity.properties`. Round-trip both.
Malformed dictionaries — missing key, non-numeric seed, unknown difficulty,
extra keys — yield `nil`, never a wrong board.

**Done when** a hand-written dictionary from a future build decodes to nothing
rather than to a board nobody asked for.

## Task 2 — the provenance guard

`ParlorInvite.opens(today:) -> GameKind`. `.daily(day)` only when
`day == todayOrdinal`; `.free(difficulty)` in every other case, including a
future day. Pure, total, tested against yesterday / today / tomorrow / nil.

## Task 3 — `ParlorPresence`, `ParlorFinish`, and the room

`ParlorRoom` is a reducer over `[ParticipantID: ParlorPresence]`:
merge, remove-on-leave, stable ordering by id with self first, `fraction(of:)`
against a locally known `fillable`, and `isComplete` = non-empty ∧ all `done`.

The one rule with teeth: `mayReveal` is `isComplete`, and a departure can flip
it true.

## Task 4 — the two seals

- `ParlorSealTests` reflects over `ParlorPresence`'s **encoded JSON keys** and
  fails on anything matching time/second/elapsed/score/name — PRD-30's method,
  because a comment saying "no clock" is not a seal.
- The same test greps the parlor surfaces for `style: .timer`, `timerInterval`
  and the debrief's seconds formatter outside the revealed branch.

## Task 5 — strings

Every new phrase into `EnglishPhrases`, the catalog and nine machine drafts,
each `needs_review`, each with a translator comment. `scripts/strings.py --audit`
at zero new offences.

## Task 6 — the transport seam and the loopback

`Sources/App/ParlorSession.swift`: a `ParlorTransport` protocol (send presence,
send finish, a stream of inbound envelopes, a roster), a `GroupActivities`
implementation behind `#if canImport(GroupActivities)`, and a loopback
implementation with synthetic participants that the simulator can actually run.
The seam exists because no FaceTime call can be placed between two simulators
and this machine's are slimmed with `messaging` disabled.

## Task 7 — the dot row

A `Canvas` of circles, radius and luminance by fill, ordered by id, self first,
static between messages. Accessibility children per dot, labelled by ordinal —
there are no names to use, because `Participant` exposes only a `UUID`.

## Task 8 — side-by-side comets in the debrief

One section, `CometTimeline` at the same 5 s loop on small boards, seconds under
each as a fact, ordering inherited from the dots so it can never read as a
ranking.

## Task 9 — the Game Center half

`GameCenter.challenge(_:)` issues a `GKGameActivity` carrying the invite;
`GKGameActivityListener` receives one and routes it through Task 2's guard.
Gated on an App Store Connect `GKGameActivityDefinition` that does not exist —
fire-and-forget, so the action is absent rather than broken until it does.

## Task 10 — the gate

Entitlement into `Nine-iOS.entitlements` (and the merge-blocking re-mint written
down where it cannot be missed), three platform builds, a Release archive, the
corpora, `ax-snapshot.py` with no re-record, the strings audit, and then the app
is driven on an iPhone and an iPad simulator through the loopback.

---

## What would make this plan wrong

- If `GKGameActivity.properties` turns out not to survive the round trip the way
  the header reads, Task 9's transport is wrong and the honest fallback is a
  share-sheet URL — which needs a URL type and is a different PR.
- If the Group Activities entitlement turns out **not** to be required (PRD-30
  got that answer once), Task 10 loses its merge blocker and the PR gets simpler.
  Checked against `DVTPortalCachedPortalCapabilities.json`, not assumed.
- If `GroupSessionMessenger` refuses a 1288-byte packed replay, Task 8 sends a
  seconds-only finish and the comets stay solitary.
