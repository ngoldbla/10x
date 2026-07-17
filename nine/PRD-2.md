# PRD-2 — Side-by-Side Nine (board anchor + ambient slot)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one small PR (days-scale, iOS-only)
**One-liner:** Don't embed the internet in a sudoku app — make Nine the best app
to multitask *over*. A board-position setting parks the grid low (or high) so a
system Picture-in-Picture video sits in the freed band, plus one optional,
nearly-invisible ambient chip.

## 1. Why

On tall iPhones the board is a centered square between two flexible spacers
(`TouchUI.swift` ~266-301), leaving two dead vertical bands. Users want to watch
video or glance at something while solving. iOS sandboxing forbids embedding
other apps' content (the "widgetize YouTube/news around the board" idea is
platform-impossible), but the OS already composites PiP video over any app —
our job is simply to leave elegant, contiguous room for it.

Adversarial framing that shaped this: "it's just a padding change" — exactly,
that's the pitch. Smallest possible feature that delivers real dual-use.

## 2. The experience

- **Board position** pref: Top / Center / Bottom (default Center). Anchor =
  Bottom means all free space collects *above* the board — a PiP window from
  Safari/YouTube parks there without covering the grid or controls.
- **Ambient display** pref: Off (default) / Clock / Streak. One dim,
  non-interactive `GlassChip` centered in the band *opposite* the board — a
  clock, or "128 pts · 4 day streak". No animation while playing. Suppressed
  when the band is under ~100pt or while the composing chip is up.
- Both live under a new **"Layout"** section in the prefs sheet.
- Short screens (iPhone SE, landscape) degrade automatically: no free space →
  every anchor looks like Center, ambient chip absent. iPad Split View already
  width-caps the board, so the anchor is *most* useful there.

## 3. Non-goals

- No embedded web views, news feeds, video players, or third-party now-playing
  info (no public API for arbitrary now-playing; EventKit calendar permission is
  too heavy an ask for a game).
- No onboarding hint — settings-only discoverability (it's a preference, not an
  invisible input grammar; the tvOS `hintFlashed` chip pattern exists at
  `GameScreen.swift:132` if this decision is ever revisited).
- tvOS untouched.

## 4. Implementation plan

Modified files only: `Sources/App/AppModel.swift`, `Sources/App/TouchUI.swift`,
`Sources/App/PrefsSheet.swift`.

### Step 1 — Prefs (AppModel.swift)

Two enums next to `AppearanceChoice` (~line 40), same shape (String raw values,
`Codable, Sendable, CaseIterable`, `title`):

```swift
enum BoardAnchor: String, Codable, Sendable, CaseIterable {
    case top, center, bottom            // titles "Top" / "Center" / "Bottom"
}
enum AmbientSlot: String, Codable, Sendable, CaseIterable {
    case none, clock, streak            // titles "Off" / "Clock" / "Streak"
}
```

`NinePrefs`: `var boardAnchor: BoardAnchor = .center`,
`var ambientSlot: AmbientSlot = .none`; in `init(from:)` follow the existing
tolerant pattern exactly: `decodeIfPresent(...) ?? .center` / `?? .none`.
Persistence is free via the `didSet` mirror (AppModel.swift:124-126).

### Step 2 — Layout restructure (TouchUI.swift, `TouchGameScreen.body`)

**Control-bar rule:** the bar keeps its screen edge — `controlsAtBottom` is
about thumb reach and must not move with the board. `boardAnchor` only
redistributes the free space between the bar and the opposite edge. So
`controlsAtBottom + anchor=.bottom` → board hugs the bar, one contiguous free
band on top (the PiP case); the bar never detaches from its edge.

Replace the two symmetric `Spacer(minLength: 0)`s with edge-aware bands:

```swift
VStack(spacing: 12) {
    if controlsAtBottom {
        band(.top, ...); boardArea(...); band(.bottom, ...); controlBar
    } else {
        controlBar; band(.top, ...); boardArea(...); band(.bottom, ...)
    }
}
```

`band(edge:)`: the anchored edge collapses (`Spacer().frame(height: 0)` to keep
VStack spacing symmetric); the free edge is
`Color.clear.frame(maxWidth:.infinity, maxHeight:.infinity)` (acts as Spacer)
with the ambient chip in an `.overlay`, centered.

- `freeSpace = geo.size.height - (side + 2*boardInset + 16) - 76`, computed once
  in the GeometryReader next to `side`.
- `showAmbient` requires: slot != .none, band is opposite the anchor,
  `freeSpace >= ~100`, and `model.composing == nil` (the composing chip overlays
  at `.top` and would collide). For anchor == .center the chip goes in the band
  opposite the control bar, so "turn on clock" is never a silent no-op.

### Step 3 — AmbientSlotView (TouchUI.swift, ~30 lines under "Chrome atoms")

```swift
private struct AmbientSlotView: View {
    let model: AppModel
    var body: some View {
        switch model.prefs.ambientSlot {
        case .none: EmptyView()
        case .clock:
            TimelineView(.everyMinute) { t in
                GlassChip(t.date.formatted(date: .omitted, time: .shortened), systemImage: "clock")
            }
        case .streak:
            GlassChip(streakText, systemImage: "flame")
        }
    }
}
```

Reuses `GlassChip` (same idiom as the TouchHomeView header chips,
TouchUI.swift:66-70). Muting: `.opacity(0.5)` + `.allowsHitTesting(false)`, no
transitions/`withAnimation` — the minute tick is a plain text swap; streak text
only changes on solve, so nothing moves during play. `streakText` composed from
existing `model.totalPoints` / `model.displayedStreak` (AppModel.swift:190-192),
mirroring the home header's conditionals.

### Step 4 — PrefsSheet rows

Inside the existing `#if os(iOS)` block after "Resume on launch" (~line 90): a
"Layout" caption header (same style as `newGameSection`: `CouchTypography.caption`,
`.secondary`, `28 * CouchScale.chrome` padding) + two cycling `prefRow`s copying
the Appearance row's cycle idiom (lines 74-82):

- **Board position** — detail `boardAnchor.title`, cycles `allCases`. Symbols
  `inset.filled.tophalf.square` / `square.inset.filled` /
  `inset.filled.bottomhalf.square` (verify on iOS 18; fallback
  `arrow.up.square` / `square` / `arrow.down.square`).
- **Ambient display** — detail `ambientSlot.title`, cycles `allCases`; symbols
  `circle.slash` / `clock` / `flame`.

Optionally move the existing "Controls" row under the same Layout header (same
category, zero risk).

### Edge cases (verified in design, mostly no code)

- **Rose clamping needs no change:** the rose lives in `boardArea`'s overlay, so
  `rosePosition` clamping (TouchUI.swift:437-445) is board-local and moves with
  the board. Confirm visually on the top row with anchor = .top.
- **Completion chip / undo toast: leave as-is.** With anchor = .top the chip
  lands in the free band (nicer than today); with anchor = .bottom it can sit
  over the board's lowest rows — but the game is already solved.
- **iPad Split View already correct:** `side = max(200, min(...))` caps by the
  min dimension. (The pre-existing `max(200, …)` floor could overflow a
  sub-230pt width; predates this feature — note, don't fix.)
- tvOS: only the two enums + pref fields are platform-neutral; all UI changes
  sit in `#if os(iOS)` code.

## 5. Verification checklist

1. Build both destinations (proves tvOS untouched).
2. iPhone 16 sim, drive with AXe: free game → gear → cycle "Board position";
   screenshot top/center/bottom × Controls top/bottom (6 shots). Bar stays at
   its edge; free band contiguous.
3. Ambient: Clock (dim, band opposite anchor, taps pass through), Streak, Off.
   Anchor = center → chip appears opposite the control bar.
4. Rose: anchor = bottom, tap a bottom-row + corner cell — petals stay
   on-board; anchor = top, tap a top-row cell.
5. Completion: DEBUG fill rig, place last digit, check chip at each anchor.
6. iPhone SE sim: all three anchors identical (centered), no ambient chip.
7. iPad sim: 1/3 Split View, cycle anchors; full screen too.
8. Device (or iPad sim): Safari PiP video + anchor = bottom + controls bottom →
   PiP parks in the top band covering nothing.
9. Persistence: set bottom + clock, kill & relaunch → both stick; first launch
   after upgrade (keys absent) → defaults, no reset of other prefs.
