# Localization baselines — every screen in four other languages (PRD-20)

Twenty-five `sim-use describe-ui` dumps: five screens × `en`, `de`, `ja`,
`double`, `rtl`. Diffed on every pull request by
`.github/workflows/nine-accessibility.yml`.

```bash
python3 nine/scripts/loc-harness.py --selftest   # calibrate the assertions, no simulator
python3 nine/scripts/loc-harness.py              # assert, and diff these files
python3 nine/scripts/loc-harness.py --record     # re-record, deliberately
```

Modes are **launch arguments**, not build settings, so one installed binary
answers for all five and nothing here touches the catalog.

| Mode | Flags | Why |
|---|---|---|
| `en` | — | the reference the others are read against |
| `de` | `-AppleLanguages (de)` | the longest of the nine; the practical worst case |
| `ja` | `-AppleLanguages (ja)` | CJK, the shortest, and the only plural rule with no `one` |
| `double` | `-NSDoubleLocalizedStrings YES` | every string twice — synthetic worst case |
| `rtl` | `-AppleTextDirection YES -NSForceRightToLeftWritingDirection YES` | layout, and the two things that must not follow it |

## What is a failure, and what is a diff

**Failures** live in `loc-harness.py` and are asserted, not eyeballed: nothing
renders `(null)`; no unsubstituted format specifier reaches the screen; nothing
runs off the *side* of the window; and under RTL the board and the rose hold
still while the control bar mirrors. Each is proven able to fail by
`--selftest`, which needs no simulator — three of the four cannot be calibrated
against the real app, because nothing in Nine renders `(null)`, leaves a
specifier unsubstituted or overruns the window today.

**These files are the diff.** They carry the frame of every piece of text on
every screen, and the column to read is **height**: `16` is one line, `31` is
two. German wraps constantly and that is not a bug, so wrapping is recorded for
a human rather than raised as an error — a tripwire that cries wolf is deleted
six weeks later.

## Two things this cannot see, stated so nobody assumes otherwise

- **A string clipped by `lineLimit` or shrunk by `minimumScaleFactor`.** The
  frame does not change and the accessibility label still reports the string in
  full. Measured: across all twenty-five dumps, **zero** labels contain an
  ellipsis. The fixed-height boxes where this would happen are named in
  `PRD-36.md`; they are widget surfaces, and `describe-ui` cannot reach a widget.
- **tvOS and macOS.** `describe-ui` is iOS-only — the same wall PRD-19 and
  PRD-22 hit.

## Why the harness navigates by SF Symbol

Every anchor the AX lane uses is an English label, and none of them survive
here: under `double` the cell `Row 1, column 1` is reported as
`Row 1$lld, column 2$lld Row 1, column 1`. `describe-ui` reports each chrome
button's symbol as `uniqueId` and **that does not localize** — `gearshape` is
`gearshape` in all five modes. Every tap is by symbol, or by a frame taken from
the `en` pass.

## The bugs these files were written after

Both were in the RTL mode, both had been checked with a screenshot, and both
had been recorded as working.

- **The board's 81 accessibility frames mirrored while the pixels did not.**
  `Row 1, column 1` reported the digit `4` at x=342 while the 4 was drawn at
  x=20. A `Canvas` draws in raw coordinates; `.position(x:y:)` is
  direction-aware. Every cell but column 5 was somewhere other than it looked,
  for VoiceOver, Switch Control and Voice Control alike — and a screenshot diff
  showed a perfect board.
- **The rose mirrored visibly**, to `3 2 1 / 6 5 4 / 9 8 7`. That is the exact
  harm PRD-20 decision 3 forbids: it moves the 7 under the thumb that expects
  the 3.

Which is the whole argument for asserting on frames rather than on pixels, and
for opening the rose rather than trusting the sentence in the plan — the plan
and its follow-up both said petal 1 sits bottom-left. It sits top-left; the ring
is telephone-keypad order.
