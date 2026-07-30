# PRD-30 — Quiet Presence

**Status:** Implemented · **Thread:** `nine/` · **Wave:** 2 ("Deeper")
**One-liner:** Start today's board, walk away, and the Lock Screen keeps your
place — as a picture of the board and nothing else. No clock, no count, no
streak, ever.

> This file did not exist when the work started; `PROGRAM-2.0.md:97` was the whole
> spec, the same way it was for PRD-25, PRD-26 and PRD-31. It is the forward
> document now. What actually happened, including the things that turned out to be
> false, is in the PRD-30 section of [DEVIATIONS.md](DEVIATIONS.md).

## 1. The requirement is a negative

PROGRAM-2.0 states it twice in one line: **no timers, no countdowns, no
streak-endangered nagging ever** — "PRD-13 grace exists so we never have to".

Every other Live Activity on the platform is a clock. A delivery, a game score, a
timer, a flight. Nine's is the one shape nobody ships, which is why the whole
design is arranged so that a clock cannot appear by accident:

- **The payload has no clock in it.** `DailyPresence` carries a day ordinal, a
  band id, a 22-byte board glyph and a revision. No `Date`, no `TimeInterval`, no
  count, no streak field. A payload with nothing to render cannot render it.
- **The dynamic half is smaller still.** `NineDailyActivity.ContentState` is the
  glyph and the revision. Those are the bytes ActivityKit re-encodes on every
  update.
- **Two seal tests, because a negative erodes silently.**
  `QuietPresenceTests.testThePresencePayloadCarriesNoClockAndNoStreak` reflects
  over the encoded JSON keys; `QuietPresenceSealTests` greps every quiet surface's
  source for `timerInterval`, `style: .timer`, `countsDown`, `AlertConfiguration`,
  `pushType: .token` and the word "streak". `Text(_:style: .timer)` is the one
  that matters most: it needs no field in the payload at all, because the *system*
  animates it from a `Date`.

## 2. What it shows

The board's own portrait — the same idea as `BoardFingerprint` (PRD-22). Givens
are a constellation set back at 55% of the theme's ink; your entries come forward
at full accent. Progress is a picture that fills in, not a number that judges.

The glyph never distinguishes a right entry from a wrong one. It cannot — it
carries no digits — and it must not: this draws on a Lock Screen anyone walking
past can read, which is a stricter version of the rule `showErrors == false`
already enforces inside the app.

| Surface | Content |
|---|---|
| Lock Screen / Notification Centre | glyph at 54pt, the band's name, and how many squares are left |
| Dynamic Island, compact | the glyph at 18pt in the leading slot. **`compactTrailing` is `EmptyView()`** — that slot is where every other app puts a number, and a number here would be a clock or a score |
| Dynamic Island, minimal | the glyph at 16pt |
| Dynamic Island, expanded | glyph at 44pt, band, squares left |
| Watch Smart Stack | the same activity, free, via `supplementalActivityFamilies([.small])` |

"How many squares are left" is a count, and it is the one number allowed, because
it describes the *board*: "51 to go" is a fact about a puzzle where "30 done" is a
score and "4:12" is a deadline.

## 3. The lifecycle

`PresencePolicy.decide` is a pure function in `Sources/Shared/QuietPresence.swift`,
tested by `swift test` with no simulator — the same reason `RoseLens` and
`DraftingTable` are shaped that way.

- **Nothing starts until the board has been touched.** An untouched board is not a
  bookmark, it is an advert. This is the gate the whole feature hangs on.
- **Nothing starts while the app is on screen.** The "and leave" is half of
  "start-and-leave"; the trigger is the `scenePhase` transition to `.background`.
- Ends on solve, on day rollover, and when the pref goes off — `.immediate`
  dismissal, because a bookmark to a finished board should not linger for four
  hours being a trophy.
- Erasing back to an empty board *dims* the glyph rather than making the activity
  vanish. Disappearance is a louder event on a Lock Screen than any change of
  content.
- `staleDate` is next local midnight. It is the one `Date` ActivityKit needs and it
  is not a countdown: nothing renders it, and the view's only response is to fade.
- `pushType: nil`. No token, no APNs, no server.

A `PresenceScreen` parameter — "is the daily the board on screen" — was written
and removed. `isTouched` already proves the player started the daily, so also
requiring it to be the last board they looked at would drop the bookmark for
someone who plays the daily at breakfast and a free board at lunch. More code,
worse behaviour.

## 4. StandBy: `systemSmall` with its background taken away

**There is no StandBy API.** StandBy is a `WidgetLocation`, and the only function
that takes one is `disfavoredLocations(_:for:)` — an opt-out. There is no
`\.widgetLocation` to read.

So the detection is an inference, and it is named in the source rather than hidden:
`family == .systemSmall && showsWidgetContainerBackground == false` **is** StandBy
today. Lock Screen widgets are the `accessory*` families; iOS 18's tinted Home
Screen keeps its container background and only moves `widgetRenderingMode` to
`.accented`. If the inference ever stops holding, the failure is benign — the
ambient face appears somewhere else that also removed the background.

The face itself is the glyph at 86% of the tile and **nothing else**. Every
candidate caption was tried against the 11pm-in-bed test and lost: a percentage is
a number to read at midnight, a streak is a reason to feel something, and "Today's
board" is a label on the only thing on screen. Zero animation — the idle-pixel
test's most literal case is a widget on screen for eight hours beside someone
asleep. Night Mode hands us `.vibrant`, so the glyph draws in `.primary` /
`.secondary` and the red tint reads as chosen rather than survived.

## 5. The widget finally wears your theme

`WidgetPalette` was three hardcoded constants under a comment saying "the in-app
tinted themes don't reach the extension (it can't read nine's prefs)". True, and
not a law: `SharedAppearance` has carried theme and accent across a process
boundary since PRD-6 — just not *this* one, because it travels by KVS and the
widget extension reads KVS no more than it reads Application Support.

`WidgetSnapshot` gains `themeRaw` / `accentRaw` (additive optionals, `schemaVersion`
stays 1, exactly as `lastGraceDay`'s doc comment prescribes) and
`Sources/Shared/SharedPalette.swift` turns them into numbers. All four widgets
follow the player now, not just the new one. The palette is a second copy by
necessity — SwiftUI `Color` → RGB round-tripping is unreliable, which is why
`AccentChoice.lightBarRGB` is already a hand-written second copy in the App layer
— so `SharedPaletteTests` reads `Theme.swift` as text and fails in both directions.

The API's shape encodes PRD-22's finding: the accent's light/dark variant follows
the **theme's** leaning, not the system's. Camel is a light theme on a phone in
dark mode, and a vivid accent on Camel is 3.36:1.

## 6. One pref, on by default

`NinePrefs.livePresence`, in Feel. **On**, and that is a covenant judgement taken
deliberately.

The anti-bloat constitution's rule is about *notifications* — "a single opt-in
silent daily reminder at most, off by default". Three properties keep this on the
other side of that line, and the third is enforced by a test:

1. It exists only because the player started a board and walked away.
2. It ends itself, on solve and at midnight.
3. It is never given an `AlertConfiguration`, so it cannot buzz, ring or bannerise
   — `QuietPresenceSealTests.testTheLiveActivityIsNeverAlerting`.

iOS also already owns a global off switch and a swipe-to-dismiss, which is the real
opt-in gate. Off by default would have shipped a feature that effectively does not
exist, behind a settings row the covenant makes expensive.

## 7. No entitlement, no `match` re-mint

Checked rather than assumed: the only build settings Xcode 26.6 defines for this
are `INFOPLIST_KEY_NSSupportsLiveActivities` and `…FrequentUpdates`
(`CoreBuildSystem.xcspec`). There is no entitlement and no App ID capability behind
Live Activities.

So unlike app groups (PRD-3), Game Center and CloudKit (PRD-8), **the trap
EXECUTING-A-PRD §6 says has fired three times does not fire here.** One
Info.plist key on the app — not the extension, which only renders — and nothing to
POST to the portal.

`NSSupportsLiveActivitiesFrequentUpdates` is deliberately absent: it buys a bigger
update budget, and an activity with no clock updates only when the picture changes.

## 8. What was deliberately not done

Recorded with reasons in DEVIATIONS; the headline three:

- **No Live Activity has ever appeared on a Lock Screen.** ActivityKit needs the
  app backgrounded on a device or a booted simulator, and a Live Activity is not in
  the accessibility tree `ax-snapshot.py` reads even when it is on screen. What is
  verified is the artifact: the Release archive carries `NSSupportsLiveActivities`
  and links ActivityKit into the appex. The rendering is unphotographed — the same
  class of standing deferral as PRD-31's "no Apple Pencil has ever written a digit".
- **No Dynamic Island hardware.** Compact and minimal are device surfaces.
- **The nine languages are machine-drafted**, consistent with PRD-20's standing
  headline deferral.
