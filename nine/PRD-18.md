# PRD-18 — Welcome card + variants teaser

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one small PR
**One-liner:** Two small home-surface touches for a paid app: a one-time
welcome that shows a buyer everything they just got ("One purchase — iPhone,
iPad, Mac & Apple TV; your puzzles follow you"), and a quiet Killer · Thermo
card that says the app keeps growing.

Prototypes: `-uxdemo.variants` (home-inline) and the retired paywall layout
(`ProSheetDemo`) whose ledger styling the welcome card inherits.

## 1. Why

A $4.99 buyer's first 30 seconds should confirm the purchase was smart. The
welcome is the one moment Nine may talk about itself — a feature ledger shown
once, never again. The teaser keeps the "one price, growing app" story visible
without a single dark pattern.

## 2. The experience

- **Welcome (first run after purchase/update):** a HelpOverlay-style glass
  card *before* the existing touch legend on first launch: the ledger rows
  (daily & streak · coach · archive · stats · every theme · cross-device sync
  — final list reflects what's actually shipped when this merges), the line
  "One purchase · iPhone, iPad, Mac & Apple TV", one button: **Begin**.
  Dismissal persists via `CouchStored` flag (`welcome.seen`, tolerant default
  false); the touch legend still follows on true first run (two cards max,
  then never again). tvOS/macOS: skipped this PR — iOS is where buyers land
  first; parity is a follow-up line item.
- **Variants teaser:** the prototype card as built (`square.on.square`,
  "Killer · Thermo — new variants, coming soon", sparkles) at the bottom of
  the home scroll, below the learn row. Tap: a gentle chip "In the works —
  they'll simply appear here." No email capture, no notify-me, no external links.
- Remove-by-date discipline: the teaser ships with a comment-dated review
  horizon (three months) — if variants haven't landed by then, the card comes
  out rather than rotting into a broken promise.

## 3. Non-goals

- No changelog screen, no "what's new" recurring cards, no marketing pushes,
  no rating prompts (ever — suite stance).

## 4. Implementation plan

1. `WelcomeCard.swift` (ledger card, HelpOverlay presentation pattern) +
   `welcome.seen` flag; ordering with `helpSeen` on true first run.
2. Variants teaser card in `TouchUI.swift` (production version of the
   prototype hunk) + tap chip.
3. Delete `-uxdemo.variants` flag, the home-inline prototype hunks, and —
   as the last PRD in the program — the entire `UXDemo.swift` /
   `UXDemoScenes.swift` files once every other PRD has shipped its deletion.

## 5. Verification checklist

- [ ] Fresh install: welcome → Begin → legend → home; second launch: neither.
- [ ] Update-install simulation (flag absent, `helpSeen` true): welcome shows
      once, legend does not repeat.
- [ ] Teaser tap chip appears and fades; screenshots of both cards.
- [ ] tvOS + macOS builds green; `-uxdemo` inventory empty at program end.
