# PRD-36 — Type That Scales (Dynamic Type across the Couch Suite)

**Status:** Proposed · **Thread:** `couchkit/` + all five suite apps · **Scope:** suite-wide, not one PR

> This PRD exists because PRD-20's Task 11 ("Dynamic Type stress tests at AX5")
> could not be executed as written. The finding that retired it is the whole
> case for this one: **Nine does not respond to Dynamic Type at all**, so an AX5
> sweep passes vacuously. Making it respond is not a Nine change — it is a
> change to `CouchTypography`, which all five Couch Suite apps render through.

## 1. The measurement that produced this PRD

Run in `nine/` at `71a52d6`, quoted rather than recalled:

```
$ grep -rn "ScaledMetric"     Sources/App | wc -l      →  0
$ grep -rn "dynamicTypeSize"  Sources/App | wc -l      →  0
$ grep -rn "relativeTo:"      Sources/App | wc -l      →  0
$ grep -rEn "\.system\(size:" Sources/App | wc -l      →  64
$ grep -rn "CouchTypography"  Sources/App | wc -l      →  107
```

Every font in the app layer is either a fixed `.system(size: N)` or a
`CouchTypography.*` constant, and `CouchTypography`
(`couchkit/Sources/CouchKit/CouchUI.swift:22-31`) is fixed points on both
branches of its `#if os(tvOS)`:

```swift
public static let body    = Font.system(size: 17, weight: .medium,   design: .rounded)
public static let caption = Font.system(size: 13, weight: .semibold, design: .rounded)
```

A `Font.system(size:)` with no `relativeTo:` does not scale. So at AX5 the app
renders identically to the default size, an AX5 screenshot lane returns green,
and the green means nothing. **That is the finding: the gate PRD-20 Task 11
specified would have measured its own absence.**

The one place text *does* grow today is the widget extension, which uses
semantic styles — 22 of them:

| File | Styles | Growth risk |
|---|---|---|
| `Sources/Widgets/DailyWidgetViews.swift` | 16 (`.caption`, `.title2`, `.caption2`) | `:60-92`, `:100`, `:114` |
| `Sources/Widgets/BoardWidget.swift` | 3 (`.headline`, `.caption`, `.subheadline`) | `:129` sits in `.frame(height: 34)` with no `lineLimit` and no `minimumScaleFactor` |
| `Sources/Widgets/StreakWidget.swift` | 3 | — |

Widgets are the only surface where a larger accessibility size changes layout
today, and they grow into fixed boxes. That is a real bug, reachable now, and
it is the one piece of this PRD that does **not** wait on the suite decision.

## 2. Why this is a suite decision

`CouchTypography` is defined once in CouchKit and consumed by Rabbit Ears,
Darkroom, Nine, Blockhead and Cartridge. Giving it `relativeTo:` changes type
metrics in all five simultaneously, which re-baselines:

- every `describe-ui` accessibility baseline (PRD-19 diffs them per screen on
  every PR);
- every contrast baseline (PRD-22 measures contrast on the *composited* glass by
  screenshotting a seeded simulator and sampling pixels — different glyph
  coverage is different composited colour);
- every screenshot set, on every platform.

This is the same class of deferral as the CouchKit `HelpKit` strings recorded at
`DEVIATIONS.md:2586`: correct, cheap in isolation, and not something one app's
PRD may do to the other four without a decision.

tvOS is a further complication rather than a free win: tvOS has no Dynamic Type
control, so the `#if os(tvOS)` branch's 38/29pt constants are a fixed design and
`relativeTo:` buys nothing there. The change is real on iOS/iPadOS/macOS only,
which means the two branches stop being the same kind of object.

## 3. Scope

1. **Widget fixed-box fixes (independent, ship first).** `lineLimit` +
   `minimumScaleFactor` on the growth sites above, driven at AX5 and screenshotted.
   No CouchKit change, no suite coordination, no re-baselining.
2. **`CouchTypography` gains `relativeTo:`** on the non-tvOS branch, mapping each
   constant to the nearest `Font.TextStyle`, with the tvOS branch left fixed and
   a comment saying why.
3. **A real AX5 lane** — the one Task 11 was supposed to add, now that there is
   something for it to measure. It must be calibrated against a deliberately
   clipped layout before it is trusted; a sweep that has never been red has not
   been shown to work.
4. **Re-baseline** AX, contrast and screenshots across all five apps, in one
   coordinated pass.
5. **The 64 fixed `.system(size:)` sites in `Sources/App`** are triaged
   separately: some are numerals inside a geometrically-fixed 9×9 board and must
   stay fixed. "Everything scales" is not the goal; "nothing scales silently" is.

Localization interacts with this and is recorded here so it is not rediscovered:
`ArchiveSheet.swift:115-129` renders a weekday initial in a `44×22` frame at
`CouchTypography.caption`. It does not grow today — the font is fixed — but it
becomes a growth site the moment item 2 lands, and PRD-20's nine languages put a
CJK glyph in that box. Item 2 must not ship without re-driving the archive sheet
in `ja`, `ko` and `zh-Hans`.

## 4. What this PRD is not

Not a Nine PRD. Not a PRD-20 task. Nothing here blocks the nine languages, and
nothing here was left half-done by PRD-20 — Task 11 was retired before it was
started, on the strength of §1, and that is recorded in
`DEVIATIONS.md`.
