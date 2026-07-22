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
