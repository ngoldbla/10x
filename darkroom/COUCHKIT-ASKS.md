# Darkroom → CouchKit asks

Non-blocking; Darkroom works around each of these today.

1. **Suppress `.playPause` when `.playPauseLongPress` fires.** The 4-way
   path emits `.playPause` via `onPlayPauseCommand` on press, and the 8-way
   reader emits `.playPauseLongPress` on a ≥ 0.6 s release — so a long press
   delivers *both*. Any app that binds play/pause to a game action (Darkroom:
   ✕-mark) must undo it when the long-press arrives. Ideal: RemoteKit debounces
   the pair and emits exactly one gesture.
2. **Deliver `.playPauseLongPress` without the 8-way reader.** It currently
   requires `eightWay: true` (the GameController path), so 4-way apps enable
   the analog reader solely for the prefs gesture. A UIKit long-press
   recognizer on the play/pause button (or a timer on `onPlayPauseCommand`)
   would decouple them.
3. **Continuous drag stream for hold+swipe.** `CellStepAccumulator` exists in
   CouchCore, but RemoteKit never surfaces per-frame dpad deltas while a hold
   is active, so Darkroom's drag-fill quantizes to discrete `.swipe` events
   during the hold. Ask: a `dragStep(x:, y:)` gesture (fed by the analog dpad
   through `CellStepAccumulator`) between `holdBegan`/`holdEnded`.
4. **`CuratedPhoto` location for real assets.** `locationLabel` is `nil` for
   library assets in v1 (no geocoding), so the develop chip reads "October
   2016" without the "· Portland" the PRD shows. Reverse-geocode (or coarse
   `PHAsset.location` → locality cache) would complete the moment.
5. **Move-command velocity/repeat metadata.** For true momentum cursors
   (fast flick = multiple cells), RemoteKit would need to expose either flick
   velocity or key-repeat state; today apps can only approximate with
   repeated-swipe timing.
