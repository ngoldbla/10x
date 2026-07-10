# CouchKit asks — from the Rabbit Ears thread

Recorded per suite rules; built against the current interface in the
meantime (workarounds noted).

1. **Make the transient-chrome treatment public.** `TransientChrome`
   (opacity + blur + offset driven by `ChromeVisibility`) is internal to
   `GlassComponents.swift`, so any custom chrome (our caption chip + style
   pill stack) must re-implement the fade/blur/slide to match `GlassPill`.
   Ask: `extension View { func transientChrome(_ chrome: ChromeVisibility) -> some View }`.
   *Workaround:* duplicated the three modifiers in `ChannelView.bottomChrome`.

2. **`GlassPill` with custom content.** `GlassPill` only hosts
   `GlassAction` (SF-symbol buttons); the PRD's style pill wants five colored
   dots / 64 px live previews. Ask: a `GlassPill { AnyView }` variant or a
   public capsule-chrome container. *Workaround:* rebuilt the pill with
   `couchGlass(in: Capsule())`.

3. **Progress-driven pair rendering for the style wipe + true pre-render.**
   PRD §7 mentions `AsciiEngine.renderStream` for crossfade pairs; it does
   not exist. Two asks: (a) an API that renders one photo in two styles and
   composites at a seam position `x∈[0,1]` (the wipe signature moment), and
   (b) a render cache / `prewarm(image:style:grid:)` so "pre-render next
   frame during dwell" can be literal. *Workaround:* full-screen crossfade
   between styles; prefetch decodes the source image only.

4. **`GlassSheet` focus capture.** When the sheet appears, focus can remain
   on the app root (which `.couchRemote` keeps focusable), so the sheet's
   `.onExitCommand` may never see Back — Menu would then exit the app from
   an open sheet. Ask: GlassSheet should move default focus into itself
   (e.g. `.defaultFocus`/`FocusState` plumbing) and optionally swallow
   root-level gestures while presented. *Workaround:* root handler ignores
   gestures while the sheet is up; dismissal relies on focus having moved to
   the sheet's buttons.

5. **4-way fallback for `.playPauseLongPress`.** RemoteKit only emits it
   from the GameController 8-way reader; on `.fourWay` systems the suite's
   one prefs affordance is unreachable (docs suggest a pill action, but
   ambient apps may have no interactive pill). Ask: time `onPlayPauseCommand`
   presses in the base path too, or expose a documented fallback.

6. **`CouchPhotos.demoPhotos` can return duplicate ids in one call** — it
   draws from 9 recipes through a `SequencePlanner` with window 4, so a
   `limit: 9` result may repeat a recipe. Callers sequencing by id must
   dedupe. Ask: dedupe inside the query (or draw with window = count − 1).
   *Workaround:* the view model dedupes pool ids.

7. **Per-photo time/noise input on `AsciiArtView`** for "grain alive" during
   freeze (PRD §5): a frozen frame should keep its film grain breathing while
   drift is stopped. Needs a shader-time or animated-seed parameter.
