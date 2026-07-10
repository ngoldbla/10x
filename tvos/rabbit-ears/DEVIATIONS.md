# Rabbit Ears — PRD deviations

Every place the shipped v1 differs from `PRD.md` (Draft v1), and why.

## Sanctioned cuts (suite-wide direction)

1. **Top Shelf extension skipped** (PRD §6, M3). Skipped suite-wide per
   direction. The frozen-frame persistence that would feed it is implemented
   (`ChannelDirector.SavedState.frozenPhotoID` via `@CouchStored`), so the
   extension can be added later without engine changes.
2. **Style wipe seam → full-screen crossfade** (PRD §4.2, signature moment
   #1). A style swipe re-renders the *same photo* in the new style and
   `AsciiArtView` crossfades old→new frames internally with `.couchAmbient`.
   The moving vertical seam needs a progress-driven pair-render API that
   CouchKit does not expose (see COUCHKIT-ASKS #3).
3. **Multi-user profiles** (PRD §6) limited to what `@CouchStored` already
   namespaces — both stored keys use the default profile; there is no tvOS
   profile-switch hook in CouchKit yet.

## Implementation deviations

4. **Morph is a 1.5 s crossfade through a coarser grid** (PRD §4.2 hold
   gesture), per the sanctioned adjustment. The incoming photo fades in
   rendered at ~half the columns; on landing it re-renders at the fine grid
   and `AsciiArtView`'s internal ambient fade resolves the detail — glyphs
   read as re-sorting, without a true character-space morph.
5. **Style dots are passive colored dots, not 64 px live previews and not
   focusable** (PRD §5, §6). Live mini-previews were stretch; more
   importantly `.couchRemote` makes the channel itself the focusable view, so
   focusable dots would fight the swipe grammar (a focus move would eat the
   style swipe). Style changes stay on swipe ←/→; the pill shows which of the
   five styles is live plus its name. `GlassPill` itself can't host custom
   dot content (see COUCHKIT-ASKS #2), so the pill is built from
   `couchGlass(in: Capsule())` — same silhouette, same transient behavior.
6. **Lanes are All Memories / On This Day / Favorites — no per-album lanes**
   (PRD §4.2 "→ each album"), per the sanctioned scope. `CouchPhotos.album`
   exists, so album lanes are an additive change to `Lane` + one fetch case.
7. **"All Memories" uses `onThisDay` + `recentHighlights`**, not the PRD's
   `randomMemorable`-after-`onThisDay`, because CouchKit's `randomMemorable`
   actually queries *favorites* (source is truth) — it backs the Favorites
   lane instead.
8. **No-repeat window is 200 as specified**, but real pools are ≤ ~70 photos
   (query limits), so `SequencePlanner` clamps it to pool−1: exact
   full-shuffle no-repeat within a lane, which is stronger than the PRD ask
   at these pool sizes.
9. **Pre-render during dwell = source-image prefetch.** The director chooses
   `upNext` at dwell start and the app warms the decoded `CGImage` cache
   then; the styled cell render itself happens when the incoming layer
   mounts, because `AsciiEngine` has no render cache to hand a frame to (see
   COUCHKIT-ASKS #3). At 160 cols the render lands well inside the ≥ 3 s
   fade.
10. **Freeze survives relaunch** — PRD §10's open question is resolved as
    "yes": the frozen photo id persists and re-freezes when its lane pool
    loads (falls back to normal playback if the photo left the library).
    Phosphor burn-in 1 px orbit (PRD §10) not implemented: freeze stops
    drift entirely; revisit on OLED hardware.
11. **Grain/shader time during freeze** (PRD §5 "grain alive") — not
    implemented; a frozen frame is a static render. `AsciiArtView` exposes no
    time-driven noise input.
12. **Prefs long-press only fires on remotes with analog dpad data.**
    `RemoteKit` delivers `.playPauseLongPress` from its GameController-based
    8-way reader only (source), so the app runs the reader (`eightWay:
    true`). On systems without analog data the gesture never arrives —
    CouchKit suggests also exposing the sheet from a pill action, but the
    pill is non-interactive here by design (see #5 / COUCHKIT-ASKS #5).
13. **Deployment target tvOS 18.0** per the suite templates (README says
    tvOS 26; CouchKit's manifest pins `.tvOS(.v18)` and `CouchGlass`
    degrades below 26 — source is truth).
14. **`onThisDay` demo fallback**: when unauthorized, all three lanes come
    from the same 9 DemoArt recipes, so lanes look similar until photo access
    is granted. Inherent to the demo channel's size.
