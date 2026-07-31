# CouchKit asks — from the Nine thread

1. **Deliver ambiguous flicks to the app.** `MicroGamepadFlickReader`
   (RemoteKit.swift) drops `.ambiguous` classifications on the floor. That
   honors the never-misfire rule, but Nine's PRD (§4.3) wants the two
   candidate petals to *shimmer* on an ambiguous flick so the player knows to
   flick again, cleaner. Ask: a new gesture such as
   `case flickAmbiguous(Direction8OrCenter, Direction8OrCenter)` (the two
   sectors adjacent to the stroke angle), emitted instead of silence.
   `FlickClassifier` already knows the angle; only the reader's `finishStroke`
   needs to forward it. Nine's `RoseState.shimmerDigits` and its shimmer
   animation are already wired and waiting — no misfire risk either way.

2. **Distinguish the click-tap from a rose tap (nice-to-have).** A clickpad
   press is also a touch; when the finger lifts quickly the 8-way reader
   classifies it as a `.flick(.center)`. Nine currently swallows center
   flicks arriving < 0.4 s after the rose opens so opening the rose can never
   itself place a 5. If the reader could suppress the stroke that contained a
   digital click (GCMicroGamepad `buttonA` pressed during the touch), apps
   would not need this heuristic.

3. **Play/pause long-press double-fire.** `.onPlayPauseCommand` is attached
   unconditionally, and the 8-way reader separately times `buttonX` for
   `.playPauseLongPress`. A long press therefore likely delivers *both* a
   `.playPause` and, ~0.6 s later, a `.playPauseLongPress`. For Nine,
   play/pause-tap is undo, so opening prefs silently costs the player a move.
   Nine works around it by re-applying the last undo when a long-press lands
   within 1.2 s. Ask: suppress the `.playPause` emission when the reader is
   active and the press exceeds the long-press threshold (emit on release,
   not on press).

5. **macOS enablement (heads-up, not an ask — done in-repo).** PRD-4 adds a
   native macOS destination to Nine, so CouchKit gains `.macOS(.v15)` and the
   portable SwiftUI layer widens its gates to `os(macOS)`: `CouchStore`
   (Application Support resolves inside the App Sandbox container; KVS mirrors
   unchanged), `CouchUI` (`CouchScale.chrome` mac branch = **0.70**, typography
   reuses the iOS ramp), `GlassComponents` (the `GlassSheet` scrim-dismiss and
   the `FocusHalo` no-op already cover non-tvOS), `CouchGlass` (glass
   availability gains `macOS 26.0`; the material fallback carries macOS 15),
   and `HelpKit` (keyboard legend). `RemoteKit` / `AsciiEngine` /
   `PhotoKitPlus` stay platform-gated. The four sibling apps declare no macOS
   destination, so this is compile-surface only for them. No API change
   requested — flagged here so the next thread editing these files knows macOS
   is now a live target.

6. **PadKit added to CouchKit (heads-up, not an ask — done in-repo).** PRD-5
   adds `couchkit/Sources/CouchKit/PadKit.swift` (`#if os(tvOS)`), a sibling to
   RemoteKit for extended gamepads: it observes `GCController` connect/disconnect,
   filters STRICTLY to `extendedGamepad` (the Siri Remote's `microGamepad` stays
   RemoteKit's — the two readers must never both claim a device), and publishes
   `PadGesture` (move w/ analog momentum via the pure `PadMomentum`, right-stick
   `flick`/`flickAmbiguous` reusing `CouchCore.FlickClassifier`, buttons,
   connect/disconnect). `PadHaptics` vends per-locality `GCDeviceHaptics` engines
   with the `AfterglowHaptics` create-at-need lifecycle; `motionTilt(at:)` exposes
   GCMotion for the gyro trophy. No CouchKit API change is requested — flagged
   here so the next thread (Blockhead/Cartridge will want controller input)
   knows the reader already exists and where the filter/never-misfire rules live.
   PadKit fulfils COUCHKIT-ASKS #1 for the pad (it owns its own reader, so it
   forwards ambiguous strokes as `flickAmbiguous`); the Siri-Remote ask #1 still
   stands for RemoteKit.

4. **`ChromeVisibility` + `GlassSheet` focus hand-off (documentation ask).**
   With `.couchRemote` attached at a screen's root, the root stays focusable
   and consumes move commands, so a `GlassSheet`'s buttons can never gain
   focus. Nine works around it by detaching `.couchRemote` while its sheet is
   presented. If that is the intended pattern, a note in API.md (or a
   `couchRemote(enabled:)` parameter) would save the other threads the same
   discovery.

7. **The material ladder, a scaling type ramp and a real sheet (heads-up, not
   an ask — done in-repo, additive only).** Nine's visual-foundation wave adds
   to three CouchKit files. Every change is additive or tvOS-identical, and the
   four sibling apps are tvOS-only, so all of them compile untouched and render
   byte-identically.

   * `CouchGlass.swift` — the shim exposed two rungs (`.regular`,
     `.regular.interactive()`), so a board, a sheet, a chip and a stat tile
     *inside* that sheet all got the same material; Nine had twelve sites
     nesting `.regular` glass in `.regular` glass and cards measuring 1.03:1
     against their page. Four new modifiers, none of which touch
     `couchGlass`/`couchGlassInteractive`: `couchGlassOverContent(in:)`
     (`.clear`, for chrome over live content), `couchGlassTinted(_:in:)`
     (`.regular.tint(_)`, for primacy), **`couchInset(in:tint:)`**
     (`.identity` + a tint — shape and colour, *no second material*; this is
     the fix for glass-on-glass and the one Blockhead's stat rows will want),
     and `couchElevated(in:isLight:)` / `couchGlassElevated(in:isLight:)`
     (a `.topLeading → .bottomTrailing` gradient rim plus a silhouette shadow,
     drawn as a blurred fill of the caller's own shape rather than as
     `.shadow` — `FocusHalo`'s recorded reason). All four honour
     **Reduce Transparency**, which had zero hits suite-wide before this.
   * `CouchUI.swift` — the ramp gained `heading`, `label`, `numeral` and a
     `couchText(_:_:)` overload that takes a foreground (the existing
     `couchText(_:)` hard-sets `.primary`, so chaining `.secondary` after it is
     a silent no-op — five Nine sites were doing exactly that). **`caption`
     changed meaning on iOS/macOS only**: it is now the 11pt tier and the old
     13pt tier is `label`. On tvOS and watchOS `caption` and `label` are the
     same font and every shipped tvOS constant is unchanged. The non-tvOS rungs
     are now `Font.system(_ style:design:weight:)`, so Dynamic Type finally
     does something on handheld; tvOS/watchOS stay fixed.
   * `GlassComponents.swift` — `GlassChip` gained `emphasis:` (defaulted to the
     shipped `.secondary`) and now sets `.monospacedDigit()`,
     `.contentTransition(.numericText())` and `.contentTransition(.symbolEffect(.replace))`;
     the chip is the suite's only ticking surface and it visibly re-measured
     itself every second. `GlassSheet` gained `scrim:` and `isLight:`
     (both defaulted to the shipped values) and, **on iOS compact width only**,
     now presents through the system `.sheet` with detents, a drag indicator and
     a 38pt corner radius; the trailing-panel path is unchanged in kind for
     regular width and identical on tvOS. Note `import Symbols` at the top —
     SwiftUI imports that module without re-exporting it, so `.replace` does not
     resolve on a bare `import SwiftUI`.

   Nothing here changes an existing signature or what an existing call site
   renders. If a sibling app wants the ladder, `couchInset` is the one to reach
   for first.

8. **`ControlLegend` can lay itself out on a `Grid` (heads-up, not an ask —
   done in-repo).** `HelpKit.swift` gained one defaulted initializer parameter,
   `arrangement:`, and one new nested type, `ControlLegend.Arrangement`. The
   default is `.fixedColumns`, which is the shipped body verbatim — Rabbit
   Ears, Darkroom, Blockhead and Cartridge compile untouched and render
   byte-identically, and `HelpOverlay` still asks for the default.

   `.grid` exists because the shipped layout pins the gesture column to
   `210 * CouchScale.chrome`. On a phone that is 115.5pt against an action
   column measured at 201.4pt, so the gutter between the two ran from 20pt to
   71pt across three rows depending on how long each gesture's name happened to
   be — and German, measured, clips. A `Grid` + `GridRow` +
   `.gridColumnAlignment(.leading)` makes the gesture column exactly as wide as
   the widest gesture in the current locale and starts the action column on one
   vertical in every language.

   `.grid` also lifts the action column off `.secondary`. On a light ground
   that resolved to (98,98,97) — **4.35:1**, under AA for text this size — and
   it was the same pixel as the prefs sheet's section headers and its setting
   values, so three semantic roles shared one voice. It is `.primary` at 78%
   there now. Only Nine's prefs sheet opts in today; any app whose legend sits
   on a light surface should.

9. **The specular layer, and a bar rung (heads-up, not an ask — done in-repo).**
   Round 2's blind panel returned one finding in ten of fourteen scenes, worded
   almost identically every time: *"no Liquid Glass anywhere — the glass
   refracts nothing"*, written about surfaces that call `.glassEffect` correctly.
   The diagnosis is not the call sites. It is that a lens **displaces** the field
   behind it, and a displaced monotonic ramp is the same ramp — so glass over a
   near-black ground with one key light has nothing to show. Two additions
   follow from that, both in `CouchGlass.swift`:

   * `public enum CouchSpecular` — every rim, sheen, glint-falloff and shadow
     number in the suite, published both as `Gradient` stop sets (so a `Canvas`
     caller such as Nine's board and its rose get the same edge without a second
     copy of the numbers) and as ready-made `LinearGradient`s. The shipped rim
     was `white 0.20 → 0.04` on dark, which is 5/255 at its brightest over a
     #0C0C0F ground — genuinely absent after compositing. Non-tvOS now draws an
     outer bevel whose bottom lip is *dark* rather than merely unlit, plus a
     second 1pt highlight inset one point and confined to the top arc, because
     glass has thickness and thickness on screen is two bright lines a hair
     apart.
   * `couchRim(in:isLight:)` — the rim **without** the shadow, for the many
     surfaces that are flush rather than floating (keys, chips, tiles, stat
     blocks). `couchElevated` was giving all of them a drop shadow they should
     not have.
   * `couchGlassBar(in:isLight:)` — clear-leaning glass with an interior sheen
     and a specular top rim **masked to zero at both ends**. That mask is the
     point: a full-bleed 1pt hairline is exactly what the critics kept calling
     "a hard seam", and a glint that runs out of light instead of terminating is
     the difference between a seam and an edge.

   `GlassPill`, `GlassChip` and `GlassRing` now take the rim, resolving
   `isLight` from `\.colorScheme` rather than growing an argument four shipped
   apps would have to pass. **Every raise is fenced `#if !os(tvOS)`** and the
   shipped rim and single-blur shadow survive verbatim as `CouchRim.tvRim`, so
   Rabbit Ears, Darkroom, Blockhead and Cartridge render byte-identically. A
   sibling app that wants the new edge on tvOS should say so rather than
   removing the fence — the couch is a different viewing distance and the
   numbers were tuned in the hand.
