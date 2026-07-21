# PRD-5 — Pad Nine (controller-driven play on Apple TV)

**Status:** Draft v1 for review · **Thread:** `nine/` · **Scope:** two PRs (5a pad grammar + gate + haptics, 5b iOS-era parity ports)
**One-liner:** Sudoku becomes a twin-stick game. With a DualSense (or any
extended gamepad) paired to the Apple TV, the left stick walks the grid, the
right stick *is* the flick rose — one deflection per digit, no round-trip —
and the Afterglow haptic crescendo that today only iPhones feel detonates in
your palms. In a pad session the Siri Remote cannot play: the board listens
to the controller alone.

## 1. Why

The remote grammar tops out around 1.5s per digit because every digit
round-trips through the rose: click, bloom, flick, collapse. A gamepad has two
analog sticks and ten buttons; the rose's 3×3 direction-to-digit isomorphism
(`RoseGeometry`) maps onto the right stick with **zero new concepts** — the
grammar players learned on the remote and on iPhone transfers thumb-for-thumb.
PS5 controllers are already in the living rooms Apple TV lives in, and tvOS
pairs them natively.

This PRD also pays down two standing IOUs from `DEVIATIONS.md`: cursor
momentum ("fast flick crosses a box") — deferred on the remote because move
commands carry no velocity — falls out of an analog stick for free; and the
play/pause double-fire workaround disappears in pad sessions because prefs get
a dedicated button.

### Product shape: a mode, not a second SKU

- **Separate controller-required tvOS app** — rejected. Splits streaks, saves,
  history, and review surface; punishes the remote players we already shipped;
  doubles signing/CI for one input method.
- **Pad play as a session mode inside Nine tvOS** — chosen. When an extended
  gamepad connects, the shelf grows a **Pad Play** card; entering it starts a
  controller-locked session. Remote players lose nothing; the household
  chooses per sitting. One app record, one streak.

The requirement is honored *inside the session*: while a pad session is
active, RemoteKit gestures are not delivered to the board — the remote can
exit (Menu = save + home, an App Review necessity and a courtesy), but it
cannot move the cursor or place a digit. No controller connected → the card
shows "Connect a controller" and the session cannot start. Controller
disconnects mid-game → the board freezes under a glass "Reconnect your
controller" veil (timer paused); reconnect resumes in place, or Menu exits.

## 2. The experience

### 2.1 Pad grammar (complete)

| Control | Effect |
|---|---|
| Left stick | Move cursor; analog momentum — full deflection glides across a box, feathered deflection steps one cell |
| D-pad | Single-step cursor (precision fallback) |
| **Right stick flick** | **Place digit 1–9 by rose direction** (up-left=1 … down-right=9); the cursor cell is always armed — no bloom step |
| R3 (stick click) | Place 5 (center petal) |
| Cross (✕) | Open the visual rose on the cursor cell (learning mode: petals + shimmer, flick or d-pad+✕ to place) |
| Circle (○) | Erase user entry / cancel rose |
| Square (□) | Sticky pencil toggle — right-stick flicks now place corner marks (mode chip glows, as iOS) |
| Triangle (△) | Toggle same-number highlight of the digit under the cursor |
| L1 / R1 | Jump cursor to previous / next empty cell |
| L2 (hold) | Peek: dim all cells except the highlighted digit's kind (release to restore) |
| Options | Prefs sheet |
| Menu / PS | System behavior; Menu on board = save + home |

The right stick honors the never-misfire covenant: deflection must cross 0.75
magnitude and return to rest to register (reusing `CouchCore.FlickClassifier`
with its forgiveness cone); ambiguous angles shimmer the two candidate petals
in a ghost rose at the cursor — the ask CouchKit never delivered for the Siri
Remote (COUCHKIT-ASKS #1) works here because we own the reader.

### 2.2 Haptics — the Afterglow score, in hand (Signature)

tvOS controllers expose CoreHaptics engines (`GCController.haptics`,
`GCDeviceHaptics`). The exact pattern iPhones play — nine transient ticks
crescendo 0.25s→2.15s, warm 0.35s thump at 2.40s (`AfterglowHaptics`) — plays
through the DualSense on solve. During play: a whisper tick on digit placement,
a soft double-knock on an error placement (only when error highlight is on),
one detent tick per box crossed while gliding. Quiet by design; a "Controller
haptics" pref row turns it all off.

**Trophy tilt returns to the TV.** PRD-1 declined the Siri Remote's IMU;
DualSense/DualShock expose real gyro via `GCMotion`. After the sweep settles,
tilting the *controller* steers the specular highlight on the solved board —
the iPhone trophy pane, at ten feet.

### 2.3 iOS-era parity ledger (PR 5b)

"All of the iOS updates," mapped honestly:

| iOS 1.1 / PRD feature | Pad Nine disposition |
|---|---|
| Tap-to-highlight | Ported as △ toggle + L2 peek (cursor-park highlight already shipped) |
| History + points | Ported: `HistorySheet` gate widens to tvOS, opens from a shelf History card (remote-navigable too — all remote users gain it) |
| Game Center | Ported: `GameCenter.swift` gate widens to tvOS (GameKit is native); same IDs; dashboard from the History sheet |
| Interactive tutorial | Ported, re-gestured: five beats on pad verbs (move → flick a digit → pencil → highlight → difficulty); plays on first pad session |
| Afterglow | Already shared; 5a adds pad haptics + gyro trophy |
| Resume on launch | Ported (same pref; opens Continue directly) |
| New game from prefs sheet | Ported |
| Light mode | **Not ported** — the TV void stays always-dark; brand call, noted in DEVIATIONS |
| Bottom controls / board anchor / ambient slot | Not applicable (no thumbs, no PiP posture; TV composition is already the calm ideal) |
| Widgets | Not applicable on tvOS |

Everything in the ledger that widens a gate (History, Game Center, resume,
new-game) lands for **remote players as well** — the pad session is the
occasion, not a wall.

## 3. Non-goals

- No controller support on the home shelf beyond focus navigation (the shelf
  stays the focus-engine surface it is; the pad grammar begins at the board).
- No app-level "requires controller" declaration — the app still serves remote
  players; enforcement is session-scoped.
- No DualSense adaptive-trigger effects in v1 (delight candidate, not load-bearing; see Open questions).
- No second-player / duel mode (still the v2 line from PRD §3).
- No remote+pad hybrid input within one session — one master at a time, by design.

## 4. Implementation plan

### Step 1 — PadKit reader (CouchKit, 5a)

New `couchkit/Sources/CouchKit/PadKit.swift` (`#if os(tvOS)`, sibling to
RemoteKit — controllers are a suite asset; Blockhead and Cartridge will want
this): observes `GCController` connect/disconnect notifications, filters to
`extendedGamepad` profiles (**explicitly excluding the Siri Remote's
microGamepad**, which RemoteKit owns — the two readers must never both claim a
device), publishes `PadGesture` (move(analog:), flick(Direction8OrCenter),
button(PadButton), connect/disconnect). Right-stick classification reuses
`FlickClassifier`; left-stick momentum = deflection magnitude → repeat-rate
curve. `padHaptics` vends a CoreHaptics engine per locality with the
create-at-need lifecycle `AfterglowHaptics` proved.

### Step 2 — Session mode (Nine, 5a)

- `AppModel`: `padSession: Bool` + `padConnected` (observation of PadKit);
  entering Pad Play requires a connected pad.
- `GameScreen.swift`: when `padSession`, the `.couchRemote` closure ignores
  board gestures (Menu/back still exits — the existing detach pattern from the
  prefs sheet shows the way) and a `PadGesture` handler drives the same
  mutation paths. The ghost-rose (right-stick shimmer/preview) renders via the
  existing `RoseState.shimmerDigits` wiring that has been waiting since v1.
- Shelf: Pad Play card appears when `padConnected` (focus-navigable by remote;
  entering it hands the board to the pad). Disconnect veil + reconnect resume.
- Info.plist: `GCSupportsControllerUserInteraction: true` +
  `GCSupportedGameControllers` (ExtendedGamepad). (Do **not** set the
  requires-controller key — the app as a whole still supports the remote;
  verify exact key names against current tvOS docs during implementation.)

### Step 3 — Haptics + gyro (5a)

`AfterglowHaptics` refactors into a pattern factory (pure `CHHapticPattern`
builders, shared) + engine providers (iPhone `CHHapticEngine` /
`GCDeviceHaptics` engine). Placement/error/box ticks are new tiny patterns.
Gyro trophy: PadKit exposes `motionTilt()` polled through the existing
`BoardView.afterglowTilt` closure — the exact seam PRD-1 built (`AfterglowMotion`
stays iOS-only).

### Step 4 — Parity ports (5b)

Gate-widening PRs per the §2.3 ledger: `GameCenter.swift` → `os(iOS) ||
os(tvOS)` (dashboard via `GKGameCenterViewController` on tvOS),
`HistorySheet.swift` likewise (chrome at `CouchScale` TV sizes), tutorial
gains the `TutorialGrammar` abstraction (shared need with PRD-4 — whichever
lands first builds it), resume-on-launch and new-game rows appear in the tvOS
prefs sheet.

## 5. Risks

- **Two readers, one bus**: RemoteKit's microGamepad reader and PadKit's
  extended reader both hang off GameController notifications. The Siri Remote
  *is* a GCController; misclassification would double-deliver gestures. Filter
  by profile class, test with both connected, and kill `GCController.current`
  assumptions (two-controller households).
- **Right-stick misfire** is the app-killer, same as v1 flicks. The 0.75
  threshold + return-to-rest + forgiveness cone must survive a QA soak (10
  consecutive error-free speed runs, the M1 gate resurrected — this time on a
  DualSense).
- **Controller haptics variance**: Xbox pads lack DualSense fidelity; patterns
  must degrade to rumble gracefully (CoreHaptics maps automatically; verify
  the crescendo doesn't turn to mud).
- **Simulator can't test any of this** — GCController pairing, haptics, and
  gyro are device-only. Budget real-device QA time with a physical DualSense
  from day one.
- **App Review**: a session that refuses remote input is fine *because* the
  app remains fully remote-playable; keep it that way in every future PRD.

## 6. Verification checklist

1. Pair a DualSense to a real Apple TV: Pad Play card appears within 1s of
   connect; disappears on disconnect.
2. Full solve using only the controller: every §2.1 row behaves; left-stick
   glide crosses boxes; d-pad steps singles.
3. Right stick: 50-digit speed run, zero misfires; deliberate sloppy diagonals
   shimmer the ghost rose and place nothing.
4. In a pad session, mash the Siri Remote: cursor never moves, nothing places;
   Menu still saves + exits. Outside a pad session, remote grammar unchanged.
5. Disconnect mid-game → veil + paused timer; reconnect → resume in place;
   Menu during veil → home, board saved.
6. Haptics: placement tick, error knock, box detents, full Afterglow crescendo
   on solve; "Controller haptics" pref silences all; Xbox pad degrades sanely.
7. Gyro: tilt steers the trophy sheen after the sweep; remote-mode solves
   still settle to static sheen (PRD-1 behavior preserved).
8. Parity (5b): History + Game Center reachable by remote and pad; tutorial
   pad beats advance on the real gestures; resume-on-launch honors the pref.
9. Both-connected chaos test: Siri Remote + DualSense + a second pad; input
   ownership never flaps; no gesture double-delivery.
10. tvOS + iOS builds unaffected in size/behavior when no controller ever
    connects (PadKit is inert without a device).

## 7. Open questions

- DualSense adaptive triggers: R2 resistance as a "pencil pressure" gimmick or
  full abstinence? (Leaning abstinence; the suite's restraint is the brand.)
- Should L2 peek become a remote feature too (hold-click variant)? Decide
  after pad ergonomics prove it.
- Does Pad Play deserve its own Top Shelf image state? (Top Shelf remains
  suite-skipped per DEVIATIONS; note only.)
