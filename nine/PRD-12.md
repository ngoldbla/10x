# PRD-12 — Share your solve

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one small PR
**One-liner:** A finished board becomes a gift: a glass card — solved grid,
time, difficulty, streak, the NINE wordmark — one tap from the completion chip.
In a paid app with no free tier, word-of-mouth artifacts are the entire
acquisition channel.

Prototype: `-uxdemo.share` (`ShareCardDemo`). Production replaces it.

## 1. Why

Today a solve ends with a small "Solved" chip and nowhere to go
(`before/13-solved-chip.png`). Every solved board is a proud moment already
rendered in Nine's distinctive glass language — letting it leave the app is
free marketing that matches the brand (quiet, beautiful, no growth-hack copy).

## 2. The experience

- Beside the existing completion chip, a `square.and.arrow.up` glass button:
  **Share your solve**. Tap → system share sheet with a rendered PNG.
- The card (portrait, ~1080×1350 for feeds): mini solved grid (givens in
  digit tone, player digits in accent), "Solved in 3:40", "Steady · 12-day
  streak" (streak line only when > 0, daily only), NINE wordmark in accent.
  Rendered by `ImageRenderer` from a dedicated `ShareCardView` — a lightweight
  grid draw (Canvas), *not* the live `BoardView` (no afterglow machinery).
- Card honors the player's current theme + accent — shares look like *your* Nine.
- Daily shares append a discreet second line: "Nine · daily puzzle" — no URL
  spam; the wordmark is the hook.

## 3. Non-goals

- No social SDKs, no referral tracking, no share prompts/nags (the button
  waits, never asks). No tvOS share (no share sheet there); macOS uses the
  standard `NSSharingServicePicker` via ShareLink if free, else skipped this PR.

## 4. Implementation plan

1. `ShareCardView.swift` (+ `SolvedGridThumb` Canvas) — pure SwiftUI, themed
   via `ThemeTones`/accent.
2. `TouchUI.swift` completion overlay: button + `ImageRenderer` → `ShareLink`.
3. Delete `ShareCardDemo` + flag.

## 5. Verification checklist

- [ ] iPhone sim: solve via `--debug-fill`, share button appears with the chip,
      share sheet presents, saved PNG matches the card (screenshot the preview).
- [ ] Card renders correctly in Void and Paper themes (two saved PNGs).
- [ ] tvOS build green (feature fenced to iOS).
