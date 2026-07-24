# PRD-15 — Feedback (placement haptics + sound)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one small PR
**One-liner:** Placing a digit gets a fingertip tick, solving keeps its haptic
crescendo, and a new **Feedback** group in prefs owns it all — the tactile
polish that makes glass feel like glass.

Prototype: `-uxdemo.feedback` (`FeedbackDemo`) — shows the settings group.

## 1. Why

Nine already has a world-class *solve* haptic (Afterglow's score,
`AfterglowHaptics.swift`) but placement — the thing you do 50 times a board —
is silent. Perceived quality of a paid app lives in exactly this gap.

## 2. The experience

- **Placement tick:** a light `UIImpactFeedbackGenerator` tap on successful
  `place`/pencil toggle; a softer variant on erase. Errors get nothing extra
  (the coral highlight speaks; no punishment buzz by default).
- **Solve chime:** an optional, very short glass-brush sound on solve
  (system-bundled AudioServices asset or a tiny bundled sample — the suite
  ships no sound today; keep it a single file, honor the silent switch).
- **Prefs → Feedback group** (`PrefsSheet`, iOS section): Placement haptics
  (default on) · Solve chime (default off — off is the statement) · Error buzz
  (default off). New `NinePrefs` fields with tolerant decoding
  (`AppModel.swift:231` pattern) — a downgrade must not reset prefs.
- tvOS's existing "Controller haptics" row is untouched.

## 3. Non-goals

- No sound design pass (one chime max), no per-theme sounds, no haptic
  patterns beyond impact styles, no macOS haptics.

## 4. Implementation plan

1. `NinePrefs`: three fields + tolerant decode + tests-by-decode-fixture.
2. Small `PlacementFeedback` helper in the app layer (view-side, like
   `AfterglowHaptics`); wire into `TouchGameScreen`'s commit paths.
3. `PrefsSheet.swift`: Feedback section. Delete `FeedbackDemo` + flag.

## 5. Verification checklist

- [ ] Prefs blob from a build without the new fields decodes with defaults
      (fixture test) — and vice-versa (forward blob on old decode logic).
- [ ] iPhone sim screenshot of the Feedback group; toggles persist relaunch.
- [ ] Haptics verified on a physical iPhone (sim has no Taptic) — note in PR.
- [ ] tvOS + macOS builds green.
