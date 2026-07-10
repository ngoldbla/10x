# CouchKit asks — from the Cartridge thread

Recorded per suite rules; Cartridge works around all of these today.

1. **Subject-aware crops in PhotoKitPlus** (PRD §5.3). An async
   `CuratedPhoto.subjectRect(maxDimension:) -> CGRect?` using
   Vision saliency / pet / face detection on-device. Cartridge currently
   center-crops squares for actor sprites; a subject rect would make the
   "that's MY cat" moment land far more often.
2. **Landscape/orientation hint on `CuratedPhoto`** (e.g. `pixelAspect` or
   `isLandscape`). We currently have to load full pixels to learn the aspect
   before deciding actor vs backdrop lanes.
3. **`playPauseLongPress` without the 8-way reader.** RemoteKit only times
   the play/pause button inside `MicroGamepadFlickReader`; apps that don't
   need `.flick` still must enable `eightWay: true` to get the suite-wide
   prefs gesture. A lightweight button-timing path (or delivering it from
   the 4-way layer) would let Cartridge run with the reader off.
4. **Simultaneous short/long play-pause disambiguation.** When the 8-way
   reader emits `.playPauseLongPress`, the system `onPlayPauseCommand` may
   have already fired `.playPause` for the same physical press. A
   RemoteKit-level debounce (suppress `.playPause` for presses that become
   long) would remove per-app workarounds.
5. **Sprite-scale `AsciiEngine.render` canvas parameter.** `render(image:)`
   always draws at `maxCanvas`; for 24×24 sprites we call `renderGrid` +
   `draw(grid:style:canvas:)` ourselves. A `canvas:` passthrough on
   `render(image:)` would be sugar only — low priority.
6. **Alpha-preserving `AsciiEngine.cgImage(from:)`** uses `noneSkipLast`
   (opaque). A variant honoring alpha would let DemoArt-based sprites carry
   knockout transparency without an extra CGContext pass.
