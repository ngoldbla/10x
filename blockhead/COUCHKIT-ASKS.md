# CouchKit asks — from the Blockhead thread

None of these block v1 (workarounds noted); listed for triage.

1. **Menu mode for `.couchRemote` (focus passthrough).** `couchRemote` makes
   its host focusable and consumes `onMoveCommand`, so a screen can't both
   subscribe to gestures and let system focus walk real focusable slabs
   (PRD §7 "slabs are real focusable elements on menu screens"). Ask: a
   `mode: .capture | .observe` option (observe = report gestures without
   claiming focus/move commands), or a documented pattern for focus-driven
   menus + gesture subscriptions coexisting. *Workaround:* one remote surface
   per screen with model-driven selection + a FocusHalo-equivalent treatment.

2. **`GlassRing` animation control.** `GlassRing` animates progress changes
   with `.couchFast`, which is right for discrete progress but adds spring
   lag to a continuously-driven 8–20s countdown (we feed it from a
   `TimelineView` at 30 Hz). Ask: `GlassRing(progress:lineWidth:animation:)`
   with `nil` meaning "render the value as given". *Workaround:* 30 Hz updates
   hide the lag well enough at 3 m.

3. **`playPauseLongPress` without the 8-way reader.** The gesture is only
   emitted by the GameController-based `MicroGamepadFlickReader`
   (`eightWay: true`); a plain 4-way surface never sees it, and enabling the
   reader just for the button feels heavy (and delivers `.flick` events we
   must ignore). Ask: time the play/pause button in the base modifier so
   every surface can offer the suite prefs gesture. *Workaround:* stage
   enables `eightWay: true` and ignores `.flick`; hold also opens prefs.

4. **Freeze/hold parameter for `IdleAttract`-style TimelineViews is fine, but
   a "sweep pause" utility would help:** Blockhead pauses its stage light
   sweep during the ~600 ms verdict hold via `TimelineView(paused:)`, which
   snaps slightly on resume (the schedule keeps absolute time). Ask (nice to
   have): a phase-preserving pausable clock helper in CouchCore alongside
   `DriftPath`. *Workaround:* the 26 s sweep period makes the snap barely
   perceptible.

5. **`Question`-scale content storage is fine with `CouchStored` — no ask.**
   Confirming the `[String: EpisodeResult]` dictionary pattern works well
   with `CouchJSON` sorted-keys encoding for diff-stable files.
