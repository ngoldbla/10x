# PRD-16 — Appearance+ (themes, accents, alternate icons)

**Status:** Approved for implementation · **Thread:** `nine/` · **Scope:** one PR
**One-liner:** Three new themes — **Ember** (deep rust), **Tide** (dark teal),
**Mono** (graphite) — two new accents, and alternate app icons, all simply
*available* in prefs. Personalization as a gift, not a gate: no locks anywhere.

Prototype: `-uxdemo.themes` (`ThemePacksDemo`). Production replaces it.

## 1. Why

Themes are cheap surface area for attachment ("my Nine is the rust one"), the
prefs sheet already has the swatch grammar, and `ThemeChoice`'s tolerant
decoding (`AppModel.swift:238`) was built exactly so new cases could land
without nuking a downgrader's prefs.

## 2. The experience

- **Themes:** `ThemeChoice` gains `.ember`, `.tide`, `.mono`, each pinning its
  leaning (all three dark) with full `ThemeTones` (background / gridTone /
  digitTone) tuned for AA contrast against digits and the coral error marker.
  Prototype colors are the starting point (`ThemePacksDemo`), eyeballed on
  device before freeze. Swatch row wraps to two lines gracefully (9 swatches).
- **Accents:** `AccentChoice` gains two hues distinct from the existing eight
  and safe on light themes (deepened variants per the existing pattern,
  `AccentChoice.color(isLight:)`). Flat colors — no gradients (the prototype's
  gradient dots were paywall glamour; production stays in the suite's flat
  accent language).
- **Alternate icons (iOS only):** 3 variants (Ember / Tide / Mono grounds,
  same 9 mark) via `setAlternateIconName`; an "App icon" row of tappable
  icon-shaped swatches in prefs. Assets generated through the existing
  brand-asset pipeline (`scripts/generate_brand_assets.swift`) so they stay
  regenerable.

## 3. Non-goals

- No per-theme sounds/haptics, no custom theme builder, no tvOS/macOS
  alternate icons (unsupported), no seasonal icons.

## 4. Implementation plan

1. Engine-adjacent: `ThemeChoice`/`AccentChoice` cases + tones — decode-fixture
   tests both directions (old blob ⇄ new cases; unknown case falls back per
   field, never resets the blob).
2. Asset pass: icon variants via the script, `Assets.xcassets` alternate-icon
   entries + `project.yml`/Info wiring.
3. `PrefsSheet.swift`: swatch rows extend; App icon row (iOS section).
4. Delete `ThemePacksDemo` + flag.

## 5. Verification checklist

- [ ] Decode fixtures green both directions; downgrade keeps prefs.
- [ ] Screenshots: all 9 theme swatches, each new theme on the game screen,
      icon row + Springboard icon actually swapped (sim supports it).
- [ ] Error coral + accent legible on all three new themes (manual check
      against the colorblind-safe rule in `AppModel.swift:15`).
- [ ] tvOS picks up the new themes (shared enum) and renders sanely.
