# Couch Suite UX feedback round — design

Date: 2026-07-12. Source: owner feedback after first TestFlight builds.

## The feedback, diagnosed

| Feedback | Root cause found |
|---|---|
| "Too much double clicking (or more)" everywhere; Blockhead handoff takes ~10 clicks | `couchRemote` makes each screen `.focusable()` but never *claims* focus. tvOS routes `onTapGesture`/`onMoveCommand` only to the focused view, so every screen swap (Blockhead swaps constantly: handoff → question → handoff) leaves clicks landing nowhere until the focus engine recovers. There is exactly one focusable per screen, so recovery is luck. |
| Nine: two clicks to place; no preview of the digit while swiping | By design: click opens the digit rose, swipe walks petals, click places. The focused petal is only shown out in the ring — never in the cell — so you can't see what you're about to commit. First-click loss (above) makes it feel worse. |
| Secret config menus hard to find and hard to navigate | All five apps open prefs only via play/pause long-press (which requires the 8-way reader) with no visible affordance. Worse: in Rabbit Ears and Darkroom the remote surface stays attached (and focused) while the sheet shows native focus Buttons — focus often never reaches the sheet (Darkroom's own comment: "even when focus never moved into it"). |
| Rabbit Ears grabs only 1–2 photos; no way to manage | `randomMemorable` fetches **favorites only**; `onThisDay` requires exact month/day matches. Thin pools loop 1–2 photos. No status or refresh anywhere. |
| Darkroom never grabs photos | Darkroom feeds solely from `onThisDay(limit: 12)`; no photo taken on today's month/day in any year → silent DemoArt fallback, forever. |
| Cartridge games never show photos | Sprite lane defaults to photos but sources `randomMemorable` → favorites-only → DemoArt when the library has no favorites. |
| No instructions or guidance text | No help infrastructure exists; a handful of transient one-line captions only. |

## Design

### 1. RemoteKit claims focus (couchkit) — fixes dropped clicks suite-wide
`CouchRemoteModifier` gains a `@FocusState`, `.focused($focused)`, and asserts
focus on appear (immediate + one delayed re-assert ~350 ms for transition
races). Assert on appear only — never continuously — so sheets that rely on
the native focus engine can take focus while a surface stays attached.

### 2. Blockhead: one persistent remote surface at the root
Move `.couchRemote` from the seven screens onto `RootView`, dispatching to
`model.handle(gesture)` which switches on `route` (all per-route handlers
already live in AppModel). The focusable is never torn down during the party
loop → the handoff click always lands, first time. `interceptsBack` stays
false only at `.stage` (suite rule: system handles exit at the root); the one
identity change at the stage boundary is covered by the focus assert.

### 3. Nine: see the digit before you commit
While the rose is open on a 4-way remote, the focused petal's digit renders as
a large ghost glyph (accent color, ~35% opacity) in the selected cell —
swiping the petals live-previews exactly what a click will place. 8-way flick
placement stays instant (already single-gesture). `BoardView` gets an optional
`previewDigit: Int?`.

### 4. Photo curation that degrades gracefully (couchkit)
Principle: **demo art only when the library has zero usable photos** — never
because a *lane* came up empty.
- `randomMemorable`: favorites first; top up to `limit` with recent photos
  (deduped) when favorites run short.
- `onThisDay`: exact month/day matches first (all years); top up with recents.
- New `CouchPhotos.census()` → `(photos: Int, favorites: Int)` for status UI.
- Consumers unchanged in shape: Rabbit Ears lanes, Darkroom plates, and
  Cartridge sprites all inherit real photos through these two queries.

### 5. Settings: reachable and discoverable
- Rabbit Ears + Darkroom adopt Nine's proven pattern: **detach the remote
  surface while the sheet is up** so sheet Buttons get real focus (reattach +
  focus assert on close). Blockhead's model-driven panel already navigates
  reliably; it stays.
- Every prefs sheet gains a **Photos status line** where relevant
  ("132 photos · 4 favorites", or "No photos found — sign into iCloud Photos
  in Settings" when the census is zero) and Rabbit Ears gains **Refresh
  photos**.
- Discoverability: each app flashes a one-time-per-session chip on launch —
  "Hold ▶︎ for settings" — using the existing chrome chip pattern.

### 6. Guidance: a shared control legend (couchkit HelpKit)
- `LegendRow` (symbol, gesture, action) + `ControlLegend` list view.
- `HelpOverlay(title:rows:)` — full-screen glass card; dismisses on click/back.
- Each app auto-shows its overlay **once on first launch**
  (`@CouchStored("help.seen")`), and embeds the same legend at the top of its
  prefs sheet, so the sheet doubles as the manual thereafter.
- Persistent bottom captions (existing pattern) added where missing (Nine
  board, Blockhead stage).

## Out of scope (deliberate)
- No per-photo picking/exclusion UI (tvOS has no limited-library picker); an
  album-based source picker can be v1.2 if status + broadened pools don't
  satisfy.
- No Top Shelf extensions (already deferred suite-wide).
- Blockhead prefs panel not converted to native focus buttons.

## Testing
- New CouchCore-level logic stays pure where possible; curation top-up order
  gets unit coverage via a seam (asset lists in, ordering out) if extractable
  cheaply; otherwise verified on-simulator (photo library seeded via
  `simctl addmedia`).
- Full suite driven on the CouchTV simulator per app: handoff click-once,
  Nine preview ghost, prefs reachability, photos appearing in Rabbit
  Ears/Darkroom/Cartridge, first-run help overlay.
