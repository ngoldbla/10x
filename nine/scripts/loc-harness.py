#!/usr/bin/env python3
"""Drive Nine in four localization modes and read the result off the AX tree.

    nine/scripts/loc-harness.py            # assert, and diff the baselines
    nine/scripts/loc-harness.py --record   # re-record them (deliberate act)

Modes are launch *arguments*, so one installed binary answers for all of them
and nothing here touches the catalog:

    de       German — the longest of the nine, and the practical worst case
    ja       Japanese — CJK, the shortest, and the only plural rule with no `one`
    double   `-NSDoubleLocalizedStrings` — every string twice, synthetic worst case
    rtl      `-AppleTextDirection` + `-NSForceRightToLeftWritingDirection`

`en` is captured too, as the reference the others are measured against.

## What this lane asserts, and why it is not what the plan proposed

The plan (Task 10 Step 4) specified truncation detection: *frame width == the
container's width AND the label ends in `…`*. That rule was measured before it
was built, and **it cannot fire in this app**. Across five modes and five
screens, zero accessibility labels contain an ellipsis — SwiftUI reports the
full logical string to accessibility, and long text here *wraps* rather than
truncating: "Light up all of its kind" is `h=16` in English and the German
"Alle gleichen Ziffern aufleuchten lassen" is `h=31` in the same 128pt column,
two lines, complete. A gate whose only rule can never match is the Dynamic Type
sweep PRD-20 already retired for measuring its own absence.

So the lane splits in two, which is also the honest description of what a
screenshot-less harness can and cannot know:

**Assertions** — hard failures, and every one of them has been watched to fail:

  1. No label or value contains `(null)`. A plural unit missing its `other`
     category compiles at exit 0 with no warning and renders exactly that
     (`DEVIATIONS.md`, PRD-20). Nothing else in the gate chain sees it, because
     everything else reads the catalog and this reads the screen.
  2. No label or value contains an unsubstituted format specifier. A format
     that failed to take its arguments reaches the user as `%1$@`. Exempt in
     `double`, where the pseudolocalizer deliberately emits the raw format
     alongside the substituted one.
  3. Nothing escapes the screen bounds.
  4. Under RTL the board does **not** mirror and the control bar **does**.

**Baselines** — reviewable diffs, not failures. Per mode and screen, the frame
of every piece of text on it. German wraps constantly and that is not a bug, so
wrapping is recorded for a human to read rather than raised as an error; a
tripwire that cries wolf is deleted six weeks later, which is the failure
`simrig.py:1-14` is a monument to. What a *reviewer* sees in these files is
height: 16 is one line, 31 is two.

The limit, stated rather than papered over: if a string is clipped by a
`lineLimit` or shrunk by a `minimumScaleFactor`, the frame does not change and
the label still reads in full, so **this lane cannot see it**. The fixed-height
boxes where that would happen are named in `PRD-36.md`; they are widget
surfaces, and `describe-ui` cannot reach a widget at all.

## Navigating a build whose labels are not English

Every anchor the AX lane uses is an English string, and none of them survive
here — under `double` the cell "Row 1, column 1" is reported as
`Row 1$lld, column 2$lld Row 1, column 1`. `describe-ui` also reports each
chrome button's SF Symbol as `uniqueId`, and **that does not localize**:
`gearshape` is `gearshape` in all five modes. Every tap in this file is by
symbol, or by a frame taken from the `en` reference pass.
"""

import argparse
import difflib
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ninestate
import simrig
from simrig import describe, run

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # nine/
BASELINES = os.path.join(REPO, "Tests", "LocBaselines")
BUNDLE_ID = "com.couchsuite.nine"

# The device type fixes the point geometry every frame here is measured in, and
# `Nine-AX` / `Nine-Contrast` belong to the other two lanes. Other agents drive
# simulators on this Mac in parallel; owning the name is what makes the erase in
# `prepare_simulator` safe.
DEVICE_TYPE = "iPhone 17 Pro"
SIM_NAME = "Nine-Loc"

MODES = {
    "en": [],
    "de": ["-AppleLanguages", "(de)", "-AppleLocale", "de_DE"],
    "ja": ["-AppleLanguages", "(ja)", "-AppleLocale", "ja_JP"],
    "double": ["-NSDoubleLocalizedStrings", "YES"],
    "rtl": ["-AppleTextDirection", "YES", "-NSForceRightToLeftWritingDirection", "YES"],
}

# `%1$@`, `%lld`, `%@`, `%2$#@n@`. Anchored on the percent, because `double`
# eats it — `%1$lld` arrives as `1$lld` — and that is exactly the case this must
# not flag, so the percent is what separates a real failure from the
# pseudolocalizer doing its job.
SPECIFIER = re.compile(r"%[0-9]*\$?[#@a-zA-Z]")

# Petal and cell labels are localized, but the digit inside them is not: `de`,
# `ja` and `en` all count in Western digits. Nine ships no locale that does not.
DIGIT = re.compile(r"[1-9]")


# ------------------------------------------------------------------- screens


def screens():
    """The same five the AX lane photographs, so a reviewer compares like with
    like — but reached by symbol rather than by label. Each relaunches from a
    seeded container rather than navigating back, so no screen inherits
    another's transient state."""
    return [
        dict(name="game", prefs=ninestate.PREFS_ERRORS_ON, taps=[], anchor="gearshape"),
        dict(name="game-quiet", prefs=ninestate.PREFS_ERRORS_OFF, taps=[],
             anchor="gearshape"),
        # The rose: the board leaves the tree entirely and the modal ring is all
        # that is reachable. Opened on a cell whose *frame* came from the `en`
        # pass, because "the first empty cell" is a label in five languages.
        # The ring carries no SF Symbol of its own, hence no anchor.
        dict(name="game-rose", prefs=ninestate.PREFS_ERRORS_ON, taps=["FIRST_EMPTY"],
             anchor=None),
        # Tapped by the gear, but **not anchored on it**. The sheet is a real
        # `.sheet` with `.isModal` now, which is the point — the board's 81
        # cells and its whole control bar used to stay in the VoiceOver tree
        # behind it — and the consequence is that the gear that opened it is no
        # longer reachable once it is open. Anchoring on the control you pressed
        # only works while pressing it changes nothing. `clock` is the first row
        # inside the sheet, so it says the sheet arrived rather than that the
        # button still exists.
        dict(name="prefs", prefs=ninestate.PREFS_ERRORS_ON, taps=["gearshape"],
             anchor="clock"),
        # `chevron.left` gets us there; `calendar` — the Today card — is what
        # says we have arrived. The back button does not exist on the shelf.
        dict(name="home", prefs=ninestate.PREFS_ERRORS_ON, taps=["chevron.left"],
             anchor="calendar"),
    ]


# ------------------------------------------------------------------- driving


def relaunch(udid, prefs, args):
    """One launch path, `simrig`'s, which is the only one that passes `args`."""
    simrig.relaunch(udid, BUNDLE_ID, ninestate.quiet_blobs(prefs), args)


def wait_for_symbol(udid, symbol, timeout=60.0):
    """Poll until an element carrying SF Symbol `symbol` is in the tree.

    The AX lane waits on a label; this cannot. `uniqueId` carries the symbol
    name, which is a source identifier and never localized — the one handle
    that means the same thing in every mode."""
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        data = describe(udid, tolerate=True)
        if data is not None:
            last = data
            if any(e.get("uniqueId") == symbol for e in data["entries"]):
                time.sleep(0.6)
                return describe(udid)
        time.sleep(0.5)
    seen = sorted({e.get("uniqueId", "") for e in (last or {}).get("entries", [])})
    if not seen:
        sys.exit(
            "the tree was empty on every read waiting for %r — the accessibility "
            "bridge never answered, which is the host and not the app.\n" % symbol
        )
    sys.exit("timed out waiting for symbol %r. Symbols present: %s"
             % (symbol, ", ".join(s for s in seen if s)))


def settled(udid, symbol, where, attempts=6):
    """Wait for the symbol, then for two consecutive dumps that agree.

    Lifted from the AX lane for the same reason it exists there: an element
    appears the instant its view is inserted, which on a sheet is well before
    the frames stop moving, and a frame still in motion lands in the baseline a
    fraction of a point off — so the *next* run diffs for no reason."""
    previous = comparable(wait_for_symbol(udid, symbol))
    for _ in range(attempts):
        time.sleep(0.7)
        data = describe(udid)
        current = comparable(data)
        if current == previous:
            return data
        previous = current
    sys.exit("%s never stopped moving: six reads, no two alike." % where)


def tap_frame(udid, frame):
    run(["sim-use", "tap", "--device", udid,
         "-x", str(int(frame["x"] + frame["width"] / 2)),
         "-y", str(int(frame["y"] + frame["height"] / 2))])


def tap_symbol(udid, data, symbol):
    entry = next((e for e in data["entries"] if e.get("uniqueId") == symbol), None)
    if entry is None:
        sys.exit("cannot tap %r — no element carries that symbol" % symbol)
    tap_frame(udid, entry["frame"])


def capture(udid, screen, mode, args, first_empty):
    """One screen in one mode, settled and dumped."""
    relaunch(udid, screen["prefs"], args)
    # The board is the one thing on the game screen that is reliably present in
    # every mode, and the control bar rides with it.
    data = settled(udid, "gearshape", "%s/%s" % (mode, screen["name"]))
    where = "%s/%s" % (mode, screen["name"])
    for step in screen["taps"]:
        if step == "FIRST_EMPTY":
            tap_frame(udid, first_empty)
        else:
            tap_symbol(udid, data, step)
        time.sleep(1.2)
        # The symbol that says we have *arrived* is not the one we tapped: the
        # back chevron takes us to the shelf, which has no back chevron.
        data = (settled(udid, screen["anchor"], where) if screen["anchor"]
                else settled_plain(udid, where))
    return data


def settled_plain(udid, where, attempts=8):
    """Settle with no anchor at all — for the rose, which carries no symbol."""
    previous = None
    for _ in range(attempts):
        time.sleep(0.7)
        data = describe(udid)
        current = comparable(data)
        if current == previous:
            return data
        previous = current
    sys.exit("%s never stopped moving: %d reads, no two alike." % (where, attempts))


# -------------------------------------------------------------- the readings


def is_status_bar(entry):
    return entry.get("region", {}).get("kind") == "Top"


# The board's cell size, measured per tree rather than assumed. Populated by
# `calibrate_board_cell` before any screen is normalized.
_CELL_SIZE = [40.0]


def calibrate_board_cell(data):
    """Learn this build's board cell size from the tree itself.

    **This was `width == 40 and height == 40`, and a layout change silently
    blinded the whole lane.** The board used to be width-bound at 362pt on an
    iPhone 17 Pro, which is a 40.2pt cell; when it grew to full width the cell
    became ~44pt, `is_board_cell` matched nothing, and `first_empty_frame` exited
    with "the frozen board has no empty cell to open the rose on" — a message
    about the *fixture*, pointing at a file that had not changed. A hard-coded
    geometry in a harness is a claim about the app that nothing keeps true.

    Counting is what makes this safe. A tolerant rule ("a square button of
    plausible size") would also match the five 44pt tool circles, which is
    presumably why the constant was pinned in the first place. There is exactly
    one square-button size that occurs 81 times, and that is the board.
    """
    import collections
    squares = collections.Counter(
        round(e["frame"]["width"], 1)
        for e in data.get("entries", [])
        if e.get("role") == "Button"
        and abs(e["frame"]["width"] - e["frame"]["height"]) < 0.6
    )
    for size, count in squares.items():
        if count == 81:
            _CELL_SIZE[0] = size
            return size
    return None


def is_board_cell(entry):
    """One of the 81 synthetic cells. Their geometry is the AX lane's baseline,
    not this one's — here they are asserted on directly under `rtl` and would
    otherwise be 81 lines of noise per file."""
    if entry.get("role") != "Button":
        return False
    frame = entry["frame"]
    return abs(frame["width"] - _CELL_SIZE[0]) < 0.6 \
        and abs(frame["height"] - _CELL_SIZE[0]) < 0.6


def comparable(data):
    return [element_line(e) for e in data["entries"] if not is_status_bar(e)]


# Today's date is as non-deterministic as the clock, and the home shelf's daily
# card is labelled with it — "Today, Jul 27, 2026, One a day". `ax-snapshot.py`
# has masked this since PRD-19; this lane did not, so its five baselines rotted
# every midnight and nobody saw it, because the contrast step ahead of it
# crashed before this one ever ran in CI.
#
# One pattern per rendering the launch locales actually produce, because the
# AX label is comma-joined and the English date contains a comma of its own —
# splitting on commas would cut "Jul 27" from "2026". Verified against the
# captures this lane writes:
#     en / double   Jul 27, 2026
#     de            27. Juli 2026
#     ja            2026年7月27日
TODAY = re.compile(
    r"\b[A-Z][a-z]{2} \d{1,2}, \d{4}\b"          # Jul 27, 2026
    r"|\b\d{1,2}\. [^\s,]+ \d{4}\b"                # 27. Juli 2026
    r"|\d{4}\u5e74\d{1,2}\u6708\d{1,2}\u65e5"                # 2026年7月27日
)


def mask(text):
    """Replace today's date, in whichever locale rendered it, with `<today>`."""
    return TODAY.sub("<today>", text or "")


def element_line(entry):
    frame = entry["frame"]
    return "%-11s %3d,%-3d %3dx%-3d %s" % (
        entry.get("role", "?"), frame["x"], frame["y"],
        frame["width"], frame["height"], json.dumps(mask(entry.get("label") or "")),
    )


def baseline_text(data, mode, runtime):
    """The reviewable artifact: every piece of text on the screen, with the
    frame it occupies. Height is the column to read — 16 is one line, 31 two."""
    head = [
        "# mode: %s   runtime: %s   device: %s   sim-use: %s" % (
            mode, runtime, DEVICE_TYPE, simrig.sim_use_version()),
        "# role        x,y     w x h   label",
    ]
    body = [
        element_line(e) for e in data["entries"]
        if not is_status_bar(e) and not is_board_cell(e)
    ]
    return "\n".join(head + sorted(body)) + "\n"


# --------------------------------------------------------------- assertions


def texts(data):
    """Every human-readable string in the tree, with the entry it came from."""
    for entry in data["entries"]:
        if is_status_bar(entry):
            continue
        for field in ("label", "value"):
            text = entry.get(field)
            if text:
                yield entry, field, text


def assert_no_null_render(data, where):
    """A plural unit with no `other` category compiles at exit 0, emits no
    warning, and renders the four characters `(null)` on screen — measured in
    PRD-20 and recorded in DEVIATIONS. Every catalog-side gate reads the
    catalog; this reads what the user sees, which is the only place the two can
    be caught disagreeing."""
    return ["%s: %s %s renders (null) — a plural is missing its `other`: %r"
            % (where, e.get("role"), f, t)
            for e, f, t in texts(data) if "(null)" in t]


def assert_no_raw_specifier(data, where, mode):
    """A format that never took its arguments reaches the user as `%1$@`.

    Exempt under `double`: the pseudolocalizer prints the raw format beside the
    substituted one *with the percent eaten* (`Row 1$lld, column 2$lld Row 1,
    column 1`), so the percent is precisely what separates a real failure from
    the mode working as designed."""
    if mode == "double":
        return []
    return ["%s: %s %s carries an unsubstituted specifier: %r"
            % (where, e.get("role"), f, t)
            for e, f, t in texts(data) if SPECIFIER.search(t)]


def assert_on_screen(data, where):
    """Nothing may run off the side of the screen.

    **Horizontally only, and that is the whole design of this check.** The first
    version measured all four edges and its first run reported ten failures, all
    of them wrong: two Japanese preference rows and eight theme swatches sitting
    below the fold of a sheet that scrolls. Content continuing past the bottom
    edge is what a scroll view is; flagging it is how a lane earns the
    reputation that gets it deleted.

    Nothing in Nine scrolls sideways, so horizontal overflow has no innocent
    reading — it is a row that a longer word has pushed out of the window. That
    is exactly the German failure this lane exists for.

    Vertical growth is not ignored, it is *recorded*: the baselines carry every
    y and every height, so a reviewer sees the Japanese sheet grow by 40pt as a
    diff to read rather than an error to dismiss."""
    screen = data.get("screen") or {}
    width = screen.get("width")
    if not width:
        return ["%s: the dump carries no screen bounds to measure against" % where]
    problems = []
    for entry in data["entries"]:
        if is_status_bar(entry):
            continue
        f = entry["frame"]
        over = []
        if f["x"] < 0:
            over.append("%dpt off the leading edge" % -f["x"])
        if f["x"] + f["width"] > width:
            over.append("%dpt past the trailing edge" % (f["x"] + f["width"] - width))
        if over:
            problems.append("%s: %r runs %s (frame %d,%d %dx%d)" % (
                where, entry.get("label"), " and ".join(over),
                f["x"], f["y"], f["width"], f["height"]))
    return problems


def board_columns(data):
    """Cell label → frame, keyed by the column digit the label carries.

    The label is localized and its word order is not fixed — German renders
    `Spalte 2, Zeile 1` (column first) and Japanese `2列 1行` — so the row and
    column cannot be read positionally. Row 1 is instead the cells sharing the
    smallest `y`, and their order left to right is what this returns."""
    cells = [e for e in data["entries"] if is_board_cell(e)]
    if not cells:
        return []
    top = min(e["frame"]["y"] for e in cells)
    row1 = [e for e in cells if e["frame"]["y"] == top]
    return sorted(row1, key=lambda e: e["frame"]["x"])


def assert_board_unmirrored(ltr, rtl):
    """The board is a spatial numeric grid, not text (PRD-20 decision 3):
    column 1 stays on the left in every language, because mirroring it would
    move the 7 under the thumb that expects the 3.

    Asserted on the *frames*, and this is the whole reason the plan says frames
    rather than pixels. The board is drawn by a `Canvas`, which draws in raw
    coordinates and does not mirror; the 81 accessibility children are placed
    with `.position(x:y:)`, which does. So the pixels obeyed decision 3 while
    the accessibility tree quietly did the opposite, and a screenshot diff — the
    instrument this was first checked with — showed a perfect board.

    Measured before the fix: `Row 1, column 1` reported `4` at x=342 while the
    digit 4 was drawn at x=20. Every cell but column 5 was somewhere else than
    it looked, for VoiceOver, Switch Control and Voice Control alike.
    """
    problems = []
    left, right = board_columns(ltr), board_columns(rtl)
    if len(left) != 9 or len(right) != 9:
        return ["the board's top row is not nine cells (LTR %d, RTL %d) — "
                "nothing can be compared" % (len(left), len(right))]
    for i, (a, b) in enumerate(zip(left, right), start=1):
        if a["frame"]["x"] != b["frame"]["x"] or a.get("value") != b.get("value"):
            problems.append(
                "the board mirrored under RTL: position %d of the top row holds "
                "%r at x=%d in LTR but %r at x=%d in RTL. The Canvas does not "
                "mirror, so the accessibility frames have left the drawn cells."
                % (i, a.get("value"), a["frame"]["x"],
                   b.get("value"), b["frame"]["x"]))
    return problems


def assert_chrome_mirrored(ltr, rtl):
    """The counterpart, and the reason the one above is not just
    `.environment(\\.layoutDirection, .leftToRight)` on the whole app: the
    control bar *must* still mirror, or Nine is not localized at all, it is
    merely translated. Measured LTR `chevron.left … gearshape` → RTL
    `gearshape … chevron.left`."""
    def bar(data):
        return [e["uniqueId"] for e in sorted(
            (e for e in data["entries"]
             if e.get("uniqueId") and e.get("role") == "Button"),
            key=lambda e: e["frame"]["x"])]
    a, b = bar(ltr), bar(rtl)
    if len(a) < 2:
        return ["the control bar is not in the LTR tree (%d buttons) — "
                "this assertion cannot run" % len(a)]
    if b != list(reversed(a)):
        return ["the control bar did not mirror under RTL: LTR %s, RTL %s. "
                "Chrome is text-directional and must follow the layout; only "
                "the board and the rose are pinned." % (a, b)]
    return []


def rose_petals(data):
    """Petal digit → frame. The rose is nine buttons carrying one digit each;
    the surrounding words are localized and the digit is not."""
    petals = {}
    for entry in data["entries"]:
        if entry.get("role") != "Button" or is_board_cell(entry):
            continue
        found = DIGIT.search(entry.get("label") or "")
        if found:
            petals.setdefault(int(found.group()), entry["frame"])
    return petals


def rose_layout(data):
    """Petal digit → its (column, row) rank in the 3×3 ring, 0-based.

    Ranks rather than points, so the claim survives the ring being moved,
    resized or re-centred — only its *arrangement* is being asserted."""
    petals = rose_petals(data)
    if len(petals) != 9:
        return None
    columns = sorted({f["x"] for f in petals.values()})
    rows = sorted({f["y"] for f in petals.values()})
    if len(columns) != 3 or len(rows) != 3:
        # Petal frames land a point apart on the same visual row (measured: 320
        # and 321), so snap to the nearest of three bands rather than trusting
        # equality — which would otherwise report nine columns and no rows.
        columns = _bands({f["x"] for f in petals.values()})
        rows = _bands({f["y"] for f in petals.values()})
    if len(columns) != 3 or len(rows) != 3:
        return None
    return {d: (_band_of(f["x"], columns), _band_of(f["y"], rows))
            for d, f in petals.items()}


def _bands(values, tolerance=6):
    """Collapse near-equal coordinates into their three resting bands."""
    bands = []
    for value in sorted(values):
        if not bands or value - bands[-1] > tolerance:
            bands.append(value)
    return bands


def _band_of(value, bands):
    return min(range(len(bands)), key=lambda i: abs(value - bands[i]))


def assert_rose_unmirrored(ltr, rtl):
    """The ring's arrangement is identical in both writing directions.

    Decision 3: the rose is a spatial 3×3 numeric ring, not text. Mirroring it
    would move the 7 under the thumb that expects the 3. Asserted on the ring's
    own frames because a screenshot diff cannot tell a mirrored rose from a
    moved one.

    The plan and the follow-up prompt both describe the invariant as "petal 1
    bottom-left and petal 9 top-right". **That is not this app.** Measured: the
    ring is telephone-keypad order — 1 2 3 across the top at y=220, 4 5 6 at
    270, 7 8 9 at 320 — so petal 1 is top-*left* and petal 9 bottom-*right*.
    Written down here because that sentence has now been carried through two
    documents without anyone opening the rose.

    Which corner holds the 1 is not the claim, though, and pinning it would
    make this test fail the day the ring is redesigned for a reason that has
    nothing to do with language. The claim is that **the direction does not
    change the arrangement**, so the two layouts are compared to each other."""
    left, right = rose_layout(ltr), rose_layout(rtl)
    for name, layout in (("LTR", left), ("RTL", right)):
        if layout is None:
            return ["%s: the rose is not nine petals in a 3×3 ring — nothing "
                    "can be compared" % name]
    displaced = [d for d in range(1, 10) if left[d] != right[d]]
    if displaced:
        return ["the rose mirrored under RTL: petal %d sits at column %d row %d "
                "in LTR and column %d row %d in RTL. The ring is spatial and "
                "must not follow the writing direction."
                % (d, left[d][0], left[d][1], right[d][0], right[d][1])
                for d in displaced]
    return []


# ---------------------------------------------------------------- selftest


def tree(entries, width=402, height=874):
    """A `describe-ui` dump, minus everything the assertions do not read."""
    return {"screen": {"x": 0, "y": 0, "width": width, "height": height},
            "entries": [dict({"role": "StaticText", "region": {"kind": "Main"}}, **e)
                        for e in entries]}


def cell(x, y=238, value="Empty", label="Row 1, column 1"):
    return dict(role="Button", label=label, value=value,
                frame={"x": x, "y": y, "width": 40, "height": 40})


def petal(digit, x, y):
    return dict(role="Button", label="Place %d" % digit,
                frame={"x": x, "y": y, "width": 44, "height": 44})


def button(symbol, x):
    return dict(role="Button", label=symbol, uniqueId=symbol,
                frame={"x": x, "y": 788, "width": 44, "height": 44})


def text(label, x=20, y=100, width=100, height=16):
    return dict(label=label, frame={"x": x, "y": y, "width": width, "height": height})


def command_selftest(_args):
    """Drive every assertion both ways, without a simulator.

    Each of the four assertions below is a tripwire, and a tripwire nobody has
    watched trip is a decoration. Three of them cannot be calibrated against the
    real app at all — today's build renders no `(null)`, leaves no specifier
    unsubstituted and overruns nothing — so the *only* evidence they work is
    here. (The fourth was calibrated against the app: it fired on the RTL board
    before `BoardAccessibility.swift` pinned the layout direction.)

    Every case asserts an exact failure count as well as the wording, because a
    check that returns two problems where one was expected has still found
    something nobody predicted.
    """
    ltr_board = [cell(20 + 40 * i, value=str(i + 1)) for i in range(9)]
    ltr_bar = [button("chevron.left", 14), button("gearshape", 344)]
    # Telephone-keypad order, as the app actually lays it out, with the one-point
    # jitter the real ring shows between petals on the same visual row.
    ltr_rose = [petal(d, 168 + 50 * ((d - 1) % 3) + (d % 2),
                      220 + 50 * ((d - 1) // 3)) for d in range(1, 10)]

    cases = [
        ("a clean screen renders no (null)",
         lambda: assert_no_null_render(tree([text("Fehler hervorheben")]), "x"), []),
        ("a plural with no `other` reaches the screen as (null)",
         lambda: assert_no_null_render(tree([text("(null) verbleibend")]), "x"),
         ["renders (null)"]),
        ("an unsubstituted specifier is a failure in a real language",
         lambda: assert_no_raw_specifier(tree([text("That leaves %1$@.")]), "x", "de"),
         ["unsubstituted specifier"]),
        ("the same string is not a failure under `double`, which eats the %",
         lambda: assert_no_raw_specifier(tree([text("That leaves %1$@.")]), "x", "double"),
         []),
        ("`double`'s own mangling is not a specifier and must not be flagged",
         lambda: assert_no_raw_specifier(
             tree([text("Row 1$lld, column 2$lld Row 1, column 1")]), "x", "de"), []),
        ("text inside the screen is fine",
         lambda: assert_on_screen(tree([text("Timer", x=20, width=100)]), "x"), []),
        ("text past the trailing edge is not",
         lambda: assert_on_screen(tree([text("Ausgeblendet", x=350, width=100)]), "x"),
         ["past the trailing edge"]),
        ("text below the fold of a scrolling sheet is content, not a failure",
         lambda: assert_on_screen(tree([text("アクセントカラー", y=865, height=16)]), "x"), []),
        ("a board that holds still under RTL passes",
         lambda: assert_board_unmirrored(tree(ltr_board), tree(ltr_board)), []),
        ("a board whose cells mirror is caught, once per displaced cell",
         lambda: assert_board_unmirrored(
             tree(ltr_board),
             tree([cell(20 + 40 * i, value=str(9 - i)) for i in range(9)])),
         ["the board mirrored under RTL"] * 8),
        ("chrome that mirrors passes",
         lambda: assert_chrome_mirrored(
             tree(ltr_bar),
             tree([button("gearshape", 14), button("chevron.left", 344)])), []),
        ("chrome pinned left-to-right with the rest of the app is caught",
         lambda: assert_chrome_mirrored(tree(ltr_bar), tree(ltr_bar)),
         ["did not mirror"]),
        ("a rose that holds still passes in both directions",
         lambda: assert_rose_unmirrored(tree(ltr_rose), tree(ltr_rose)), []),
        ("a rose that mirrors is caught, and the middle column is not displaced",
         lambda: assert_rose_unmirrored(
             tree(ltr_rose),
             tree([petal(d, 268 - 50 * ((d - 1) % 3) + (d % 2),
                         220 + 50 * ((d - 1) // 3)) for d in range(1, 10)])),
         ["the rose mirrored under RTL"] * 6),
        ("a rose missing a petal is caught rather than silently skipped",
         lambda: assert_rose_unmirrored(tree(ltr_rose), tree(ltr_rose[:8])),
         ["not nine petals"]),
    ]

    failed = False
    for name, run_case, expected in cases:
        problems = run_case()
        # Count *and* wording, and each expected fragment must be matched by its
        # own problem — a substring test against the joined output passes when
        # one line happens to contain every fragment, which is how a
        # wrong-but-same-shaped result gets waved through.
        ok = len(problems) == len(expected)
        if ok:
            remaining = list(problems)
            for fragment in expected:
                match = next((p for p in remaining if fragment in p), None)
                if match is None:
                    ok = False
                    break
                remaining.remove(match)
        print("%s %s" % ("ok  " if ok else "FAIL", name))
        if not ok:
            print("       expected %d problem(s) matching %s" % (len(expected), expected))
            for problem in problems:
                print("       got: %s" % problem)
            failed = True
    if failed:
        sys.exit("the localization assertions do not do what they claim")
    print("\n%d cases, every assertion watched to fire and to stay quiet." % len(cases))


# ------------------------------------------------------------------- entry


def unified_diff(expected, actual, name):
    return "".join(difflib.unified_diff(
        expected.splitlines(keepends=True), actual.splitlines(keepends=True),
        fromfile="%s (baseline)" % name, tofile="%s (this run)" % name))


def first_empty_frame(reference):
    """The cell the rose opens on, taken from the English pass.

    `describe-ui` reports the cell's value, and in English "Empty" is a string
    this file is allowed to know. In the other four modes it is not — which is
    why the *frame* travels rather than the label."""
    empties = [e for e in reference["entries"]
               if is_board_cell(e) and e.get("value") == "Empty"]
    if not empties:
        sys.exit("the frozen board has no empty cell to open the rose on")
    return min(empties, key=lambda e: (e["frame"]["y"], e["frame"]["x"]))["frame"]


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--record", action="store_true",
                        help="overwrite the baselines instead of diffing them")
    parser.add_argument("--app", help="prebuilt Nine.app (skips xcodebuild)")
    parser.add_argument("--only-mode", choices=sorted(MODES),
                        help="one mode, for local iteration")
    parser.add_argument("--out-dir", default=None,
                        help="where to write what was captured, with a "
                             "screenshot per screen. CI uploads this, so a "
                             "failed run is reviewable without a Mac.")
    parser.add_argument("--no-erase", action="store_true",
                        help="reuse the simulator as-is. Local iteration only.")
    parser.add_argument("--selftest", action="store_true",
                        help="calibrate the assertions against hand-built "
                             "trees. No simulator, no build, ~0 s — and the "
                             "only proof three of them can fail at all.")
    args = parser.parse_args()

    if args.selftest:
        return command_selftest(args)

    runtime = simrig.newest_ios_runtime()
    print("runtime: %s  device: %s" % (runtime["name"], DEVICE_TYPE))
    udid = simrig.prepare_simulator(
        runtime, SIM_NAME, DEVICE_TYPE, erase=not args.no_erase)
    simrig.build_and_install(udid, args.app, REPO)

    os.makedirs(BASELINES, exist_ok=True)
    captured_dir = args.out_dir or os.path.join(BASELINES, ".captured")
    os.makedirs(captured_dir, exist_ok=True)

    modes = [args.only_mode] if args.only_mode else list(MODES)
    if "en" not in modes:
        # `en` is not optional even when it is not being recorded: it carries
        # the frame the rose is opened on and both sides of every RTL claim.
        modes.insert(0, "en")

    failures = []
    trees = {}
    first_empty = None
    for mode in modes:
        for screen in screens():
            where = "%s/%s" % (mode, screen["name"])
            print("capturing %s…" % where)
            if mode == "en" and screen["name"] == "game-rose" and first_empty is None:
                # Calibrate before the first tree is read for cells. The English
                # `game` pass is the first screen captured, so its board is the
                # measurement, and every later mode inherits it — the board does
                # not change size between locales.
                if calibrate_board_cell(trees[("en", "game")]) is None:
                    sys.exit(
                        "could not find 81 equally sized square buttons in the "
                        "English game tree, so the board is not where this lane "
                        "thinks it is. That is a real finding about the app or "
                        "about `describe-ui`'s probe budget — not a fixture "
                        "problem — and it must be read before it is recorded.")
                first_empty = first_empty_frame(trees[("en", "game")])
            data = capture(udid, screen, mode, MODES[mode], first_empty)
            trees[(mode, screen["name"])] = data

            failures += assert_no_null_render(data, where)
            failures += assert_no_raw_specifier(data, where, mode)
            failures += assert_on_screen(data, where)

            text = baseline_text(data, mode, runtime["version"])
            path = os.path.join(BASELINES, "%s-%s.txt" % (mode, screen["name"]))
            if args.record:
                with open(path, "w") as handle:
                    handle.write(text)
                print("  recorded %s" % os.path.relpath(path, REPO))
            else:
                # Kept pass or fail: a diff in a log is a diff you have to
                # reconstruct; the file is the thing you copy over the baseline
                # once you have decided the change was intended.
                with open(os.path.join(captured_dir, "%s-%s.txt"
                                       % (mode, screen["name"])), "w") as handle:
                    handle.write(text)
                if not os.path.exists(path):
                    failures.append("%s: no baseline; run with --record" % where)
                else:
                    with open(path) as handle:
                        expected = handle.read()
                    if expected != text:
                        failures.append(unified_diff(expected, text, where))
            run(["xcrun", "simctl", "io", udid, "screenshot",
                 os.path.join(captured_dir, "%s-%s.png" % (mode, screen["name"]))],
                check=False)

    if ("rtl", "game") in trees:
        failures += assert_board_unmirrored(trees[("en", "game")],
                                            trees[("rtl", "game")])
        failures += assert_chrome_mirrored(trees[("en", "game")],
                                           trees[("rtl", "game")])
        failures += assert_rose_unmirrored(trees[("en", "game-rose")],
                                           trees[("rtl", "game-rose")])

    if not args.no_erase:
        run(["xcrun", "simctl", "shutdown", udid], check=False)

    if failures:
        for detail in failures:
            print("\n" + detail)
        sys.exit("\n%d localization problem(s). Captures and screenshots: %s"
                 % (len(failures), captured_dir))
    print("every mode matches its baseline, and the board holds still under RTL.")


if __name__ == "__main__":
    main()
