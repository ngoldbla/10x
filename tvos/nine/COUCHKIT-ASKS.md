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

4. **`ChromeVisibility` + `GlassSheet` focus hand-off (documentation ask).**
   With `.couchRemote` attached at a screen's root, the root stays focusable
   and consumes move commands, so a `GlassSheet`'s buttons can never gain
   focus. Nine works around it by detaching `.couchRemote` while its sheet is
   presented. If that is the intended pattern, a note in API.md (or a
   `couchRemote(enabled:)` parameter) would save the other threads the same
   discovery.
