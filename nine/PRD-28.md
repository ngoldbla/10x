# PRD-28 — The Parlor

**Status:** Approved for implementation · **Thread:** `nine/` · **Wave:** 3 ("Together")
**One-liner:** The same board on everyone's device, a soft dot each showing how
full their grid is, nobody's time until everybody's finished — and then the
comets, side by side.

> This file did not exist when the work started; `PROGRAM-2.0.md:95` was the whole
> spec, the same way it was for PRD-25, PRD-26, PRD-27, PRD-30 and PRD-31. It is
> the forward document now. What actually happened, including the things that
> turned out to be false, belongs in the PRD-28 section of
> [DEVIATIONS.md](DEVIATIONS.md).

## 1. The thesis, in one paragraph

PRD-27 was the cheapest member of the "Together, Quietly" pillar: two people
already in the room, no network at all. This is the second cheapest, and the
reason is the same asset both lean on from opposite sides. **The board never
crosses the wire.** `(seed, difficulty) → puzzle` is a pure function the golden
corpus has frozen since Phase 0, so a parlor is N devices independently
composing byte-identical grids from eight bytes and a tier. There is no shared
document, no operational transform, no conflict resolution, no authority, and no
state to reconcile — the hardest problem in multiplayer is deleted rather than
solved. What is left to send is a small number that says how far along someone is.

The strategic point is the one PRD-24 made about variants and PRD-27 made about
modes, one turn further: **the input covenant is transport-agnostic.** A parlor
board is played with exactly the same rose, on exactly the same board view,
through exactly the same four buttons, and it is *your* board — your hands, your
device, your solve. If that stops being true, the feature is wrong.

## 2. The one idea: the seed is the message

```swift
public struct ParlorInvite: Equatable, Sendable {   // Sources/Shared/Parlor.swift
    public let seed: UInt64
    public let difficulty: Difficulty
    public let day: Int?        // non-nil when it is a daily
}
```

That is the entire protocol on the way in. It has two envelopes and one meaning:

| transport | envelope |
|---|---|
| SharePlay | `Codable`, over `GroupSessionMessenger` |
| Game Center | `[String: String]`, in `GKGameActivity.properties` |

**The `[String: String]` codec is the load-bearing half**, because it is what
makes "Game Center challenges wrap the same primitive" true in code rather than
in a sentence. `GKGameActivity.properties` is a flat string dictionary — the only
payload GameKit will carry — so the invite must survive a round trip through one.
That codec is pure, total, and Linux-testable, and a malformed dictionary yields
*no invite* rather than a wrong board.

Three consequences worth stating because they are the whole cost model:

- **The corpus is now load-bearing in a second direction.** It has always meant
  "a quiet change re-rolls every future daily". It now also means "a quiet change
  hands two friends different boards under the same invite" — silently, with both
  of them believing they are racing. EXECUTING-A-PRD §3 says run it after every
  engine commit; this PRD is the reason that stops being a formality.
- **Nothing new is persisted, anywhere.** There is no `nine.parlor`. A parlor is a
  live session and its boards are ordinary library boards; when the call ends,
  what survives is the boards, exactly as if you had played them alone.
- **`GameKind` gains no case,** for PRD-27 §3's reason exactly: a parlor board
  carries no rules an old build cannot enforce. It is an ordinary sudoku that
  several people happened to solve at once.

## 3. An invite opens a free board unless it is today's daily

The provenance guard, and it is a rule rather than an implementation detail:

> An arriving `ParlorInvite` opens **today's daily** when `day == todayOrdinal`.
> In every other case — a past daily, a future one, a free board — it opens a
> `.free(difficulty)` board composed from the invite's seed.

Without it, a friend can hand you Thursday on Saturday and you take streak credit
for a day you did not play. It is the same shape as the archive's
`day < todayOrdinal` guard (`AppModel.swift:882`) and `ChannelLedger`'s `openedOn`
provenance, and it is enforced in the pure layer so no surface can forget it.

**A parlor solve otherwise counts for everything** — streak, history, archive,
leaderboards, achievements, replay, debrief. This is the deliberate inverse of
PRD-27 §7, and the two rules have the same one-line justification read in
opposite directions:

> A duel solve is refused because two people filled that board and it is not
> your solve. A parlor solve is granted because you filled your own board with
> your own hands, and the only thing that was shared was which board it was.

## 4. Presence carries no time, structurally

```swift
public struct ParlorPresence: Codable, Equatable, Sendable {
    public let fill: Int        // cells you have filled, 0…fillable
    public let done: Bool
}
```

There is no time field, no elapsed, no score, no cell, no digit and no name.
"No times until everyone finishes" is therefore not a rule the UI obeys; it is a
fact about the bytes, and it is sealed the way PRD-30 sealed the Live Activity's
missing clock — by reflecting over the **encoded keys** rather than by trusting a
comment. `Text(_:style: .timer)` needed no field in PRD-30's payload either; the
lesson is that the seal has to be on the wire and on the surface both.

**The denominator is free.** Everyone composed the same puzzle, so
`fillable = 81 − givens` is identical on every device and never needs sending.
The wire carries a count; the percentage is computed locally. That is
determinism paying for a second thing after it has already paid for the board.

### 4.1 Times arrive in a second message that cannot be sent early

```swift
public struct ParlorFinish: Codable, Equatable, Sendable {
    public let seconds: Int
    public let packed: Data     // SolveReplay.packed — 1288 bytes at 300 moves
}
```

A device may send its `ParlorFinish` only once `room.isComplete`, which is a pure
predicate on the roster: **non-empty, and every member `done`.** So the moment
the last person finishes, every device independently reaches the same conclusion
in the same instant and everyone's number arrives at once. Nobody is waiting on a
host, because there isn't one.

Someone who leaves is removed from the roster, and a departure can therefore
*complete* a room. That is the correct behaviour and not a leniency: a parlor of
people who have all finished, plus one who hung up, is a parlor that is finished.

## 5. The dots

One soft glow-dot per participant, in a thin row that is not on the grid.
Radius and luminance track fill; nothing else moves.

**The dots have no names, and that is the framework's decision rather than
ours.** A SharePlay `Participant` exposes an `id: UUID` and nothing else — no
display name, no handle, no avatar — because the system will not tell an app who
is on the call. Ambient presence is what GroupActivities can actually support,
which is a happy collision with what the covenant wanted anyway. Dots are ordered
by participant id so the row is stable across every device and every redraw, and
your own dot is always first.

Three properties, each a test the covenant already runs:

- **The idle-pixel test.** A dot changes when a message arrives and at no other
  time. There is no pulse, no breathing, no shimmer. A board that reaches 0fps
  while you think keeps reaching it in a parlor.
- **The 11pm-in-bed test.** No sound, no haptic, no banner when someone finishes.
  The dot fills. That is the whole announcement.
- **The roommate test.** Nothing on the screen says who is ahead, because nothing
  on the screen can: a dot is a fill, and the ordering is by opaque id, not rank.

### 5.1 What VoiceOver hears

The row is one container with a child per dot, each labelled by ordinal rather
than by identity, because there is no identity to speak: *"Someone else. 24 of 51
filled."* Your own dot names itself. A finished dot says *finished*, and says
nothing about how long it took, because the local device does not know yet.

PRD-24's finding applies here in its exact original form — a structurally perfect
tree that is semantically silent — and the dots are the highest-risk surface in
this PRD for it, being a `Canvas` of circles with no text anywhere near them.

## 6. Side-by-side comets

When the room completes, the debrief gains one section: your comet and each
other comet, on small boards, side by side, all running the same 5 s loop from
`CometTimeline`. It is the payoff PROGRAM-2.0 promised and it costs almost
nothing, because three surfaces already draw that timeline and this is the
fourth — the loop is fitted to a fixed 5 s for every solve *specifically so that
a comet's duration never advertises a time*, which is the property this PRD needs
and PRD-26 already paid for.

The seconds print under each comet, once, as a fact. **No ranking, no winner, no
podium, no ordering by time** — the dots' id ordering is kept, so the fastest
solve is wherever it happened to be all along. PRD-27 §7's "no winner is ever
declared" is inherited verbatim, and for a stronger reason: this is the surface
where a leaderboard would be easiest to add and most tempting.

## 7. The Game Center half is the same invite, sent asynchronously

"Beat my Thursday daily" is a `ParlorInvite` with a `day`, delivered by GameKit
instead of by a FaceTime call.

- **Issuing:** from the completion chip of a solved board — `GKGameActivity`
  started from a `GKGameActivityDefinition`, with the invite in `properties`,
  shared through the ordinary share sheet.
- **Receiving:** `GKGameActivityListener.player(_:wantsToPlayGameActivity:)`
  hands the activity back on launch; the properties decode to an invite and §3's
  provenance guard opens the board.

Two facts about this that were discovered rather than assumed, and both belong in
the spec because they constrain it:

1. **Every classic Game Center challenge API is deprecated as of iOS 26.**
   `GKChallenge`, `GKScoreChallenge`, `GKAchievementChallenge` and every
   `challengeComposeController` overload are `API_DEPRECATED_WITH_REPLACEMENT`
   in the 26.x SDKs, replaced by App-Store-Connect-defined `GKChallengeDefinition`
   — which is leaderboard-backed and carries **no payload at all**. A seed
   cannot ride a Game Center challenge in the sense the program plan meant.
2. **`GKGameActivity.properties` is the payload that replaces it**, and it is a
   flat `[String: String]`. That is why §2's second envelope exists and why the
   codec is a first-class tested type rather than an implementation detail.

**This half is gated on an App Store Connect record** — a `GKGameActivityDefinition`
— exactly as PRD-24's per-channel leaderboards are gated on leaderboard records
and PRD-26's replays on a schema deploy. **No entitlement is involved**, so it
implies no `match` re-mint. Until the record exists, `loadGameActivityDefinitions`
returns nothing, the challenge action does not appear, and the app is otherwise
untouched — the same fire-and-forget failure mode that let PRD-24 ship ahead of
its portal work.

## 8. The entitlement, which is a merge blocker

SharePlay needs the **Group Activities** capability
(`com.apple.developer.group-session`). This was checked against Xcode's own
portal capability table rather than assumed — `DVTPortalCachedPortalCapabilities.json`
carries it as `GROUP_ACTIVITIES` with that exact profile key — because PRD-30
established that "does this need the portal" is a question with a checkable
answer, and got a *no* that time.

> Per EXECUTING-A-PRD §6, the capability must be POSTed to the bundle ID and
> `match --force` must re-mint the profile **before this PR merges**. CI runs
> `match(readonly: true)` and cannot mint anything. This is the fourth time an
> entitlement has been able to break the whole suite's TestFlight run, and the
> first three all broke it.

The entitlement is added to `Nine-iOS.entitlements` only, because §9 ships this
on iOS only, which scopes the re-mint to the iOS profile.

## 9. Surfaces

**iPhone and iPad. Not tvOS, not macOS, not the watch.**

SharePlay is offered from the game screen while a call is active, and from a
shelf card that starts one. The board composition is untouched: the dot row sits
in the chrome the drafting-table rail and the phone's control column already own,
so `BoardCompositionRules` gains nothing and PRD-31's "the composition is a pure
function of the window" is not disturbed.

tvOS can *join* a group session but cannot start a FaceTime call, and the Mac's
parlor is a different design rather than a translation — the same shape of
deferral as PRD-24's tvOS channel page, PRD-26's Mac debrief and PRD-27's
iPhone duel.

## 10. The input-concept budget: this release spends zero

The rose is untouched. There is no fifth control button. No gesture is added.

- The shelf card is a card.
- The invite arrives through the system's own SharePlay affordance, which is
  Apple's chrome and not ours.
- The dot row is a read-only `Canvas` with no gesture on it at all.
- The debrief section is a section in a card that already scrolls.

A "nudge your friend" action was considered and **refused**: it is a notification
by another name, and the anti-bloat constitution rules those out. A parlor where
nobody can be prodded is the entire point of calling it quiet.

## 11. What this PRD explicitly does not do

- **No shared board.** Nobody sees anybody's digits, ever. Two people in a parlor
  cannot help each other, cannot spoil a cell, and cannot see a mistake. That is
  a design decision and not a phase-one limitation: a shared grid is a different
  product, and it is the one that would need conflict resolution.
- **No chat, no reactions, no emoji, no voice.** FaceTime is already carrying the
  voice; adding a second channel inside the app would be a worse version of the
  one the player is already on.
- **No notifications, no nudges, no invitations that arrive unbidden.** The
  covenant, unchanged.
- **No ranking, no winner, no head-to-head record, no rematch streak, no parlor
  leaderboard.** §6.
- **No persistence.** No `nine.parlor`, no roster history, no "your last parlor".
- **No tvOS, macOS or watch surface.** §9.
- **No variant channels in a parlor.** The invite carries a classic
  `(seed, difficulty)`; a killer or thermo board additionally needs its rules,
  which is the same CloudKit-shaped gap that stops a variant board syncing today
  (PRD-24's standing deferral). A parlor of classic boards is honest; a parlor
  where one person's cages did not arrive is not.

## 12. Verification

Green gates, per PRD-7 §3 rule 3 and EXECUTING-A-PRD §5:

- `swift test` — the whole of §2, §3, §4 and §4.1 is pure and lives in
  `Sources/Shared`, tested with no simulator and no session, the same shape as
  `RoseLens`, `DraftingTable`, `QuietPresence` and `Duel`.
- Two seals: the encoded keys of `ParlorPresence` (no time can be sent early)
  and a grep of the parlor surfaces (no time can be *drawn* early). One without
  the other is PRD-30's `style: .timer` lesson repeated.
- Golden corpus **56/56** and variant corpus **9/9** after every commit. Nothing
  they hash is in the diff, and §2 is why that matters more here than usual.
- iOS + tvOS + macOS builds, plus a Release archive.
- `python3 scripts/ax-snapshot.py` — the four existing baselines match with **no
  re-record**. A drift means the parlor leaked onto a solitary board.
- `python3 scripts/strings.py --audit` — new keys with translator comments, zero
  new bare-literal offences.

And then it is **driven**, with the honest caveat this PRD is stuck with: a
FaceTime call cannot be placed between two simulators, and this machine's
simulators are slimmed with `messaging` disabled, so no real group session can
exist here. The presence row, the reveal, the comets and the accessibility tree
are therefore driven through a **loopback transport** — the same seam the live
session plugs into, fed by synthetic participants — which is exactly PRD-31's
position on the Pencil recognizer: the rendering half is driven, seeded and
photographed; the half that needs hardware is measured against constructed
input and **said so**.
