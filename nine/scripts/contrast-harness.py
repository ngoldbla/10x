#!/usr/bin/env python3
"""Measure Nine's board contrast on the *composited* glass (PRD-22).

`Tests/EngineTests/AppearancePaletteTests.swift` measures the raw theme
constants, and says so in its own doc comment. The board never draws those: it
draws them through a `couchGlass` plane that lifts the void, under an
alternating box wash, at whatever opacity `.glassEffect` resolves to on this
OS. The gap between the two numbers is the entire reason PRD-22 exists — a
green palette test means "no worse than what shipped", never "the board meets
contrast".

So this harness measures pixels. For every (theme, accent) pair it seeds the
frozen AX-fixture board into a dedicated simulator, launches, screenshots and
samples the composited surface:

  * **ground**, per 3x3 box, as the median of that box's nine per-cell median
    colours. Per box because the board's box borders *are* luminance steps
    (`BoardView.draw` step 1) — the bright boxes and the dim boxes are two
    different grounds, and a floor has to hold on the worse one. Per-cell
    medians first, so the one cell carrying the resume cursor's accent wash
    cannot move its box.
  * **ink**, per class, as the median of the decile of pixels furthest in
    luminance from their own cell's ground, pooled over every cell of the
    class. The furthest *pixel* is antialiasing noise; the furthest decile is
    the glyph's core.

Then the reported ratio for a class is its ink against the **worst of the nine
grounds**, because a player reading a given in box 5 has no idea box 5 happens
to be the dim one.

Four columns, four floors. Three are PRD-22's: given digits >= 7:1, your
entries >= 4.5:1, the coral error marker >= 3:1. The fourth is the rose's petal
glyph at AA, and it exists because PRD-22 takes the opaque disc *off* the
petals so the board can be seen bending underneath — a petal you cannot read is
not an improvement.

    nine/scripts/contrast-harness.py                    # measure and gate
    nine/scripts/contrast-harness.py --record           # rewrite the matrix
    nine/scripts/contrast-harness.py --themes dark,ember --accents gold
    nine/scripts/contrast-harness.py --contrast         # Increase Contrast pass
    nine/scripts/contrast-harness.py --quick            # the PR-lane subset

Determinism comes from the same four things `ax-snapshot.py` relies on and
shares through `simrig.py` — a frozen board, a fixed device, fixed chrome
state, a dedicated erased simulator — plus two more of its own:

  5. **The cursor cell is never a sample.** `TouchUI` resumes with the cursor
     on cell 40, which fills that cell with `accent.opacity(0.16)` and rings it
     at 0.9. Measuring a given through it would report the accent's contrast
     and call it the digit's.
  6. **Screenshots are BMP, not PNG.** `simctl io screenshot --type=bmp`
     writes an uncompressed top-down 32-bit buffer, so a cell's pixels are an
     index rather than a full-frame inflate-and-unfilter in pure Python. At
     eighty cells that is the difference between a lane and an afternoon.
"""

import argparse
import json
import os
import struct
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import simrig

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # nine/
BASELINES = os.path.join(REPO, "Tests", "ContrastBaselines")
MATRIX = os.path.join(BASELINES, "matrix.txt")
FIXTURE = os.path.join(REPO, "Tests", "AXBaselines", "fixture.nine.library.json")
BUNDLE_ID = "com.couchsuite.nine"

# Same device as the AX lane, for the same reason: frames are in points, so the
# device type fixes the geometry every sample rectangle is derived from.
DEVICE_TYPE = "iPhone 17 Pro"
SIM_NAME = "Nine-Contrast"

# Every theme that has tones of its own. `auto` is excluded on purpose:
# `ThemeChoice.tones(for:)` delegates it to Void or Paper by construction, so
# measuring it would photograph one of those two a second time and report the
# matrix as larger than it is.
THEMES = ["dark", "light", "camel", "blueprint", "forest", "ember", "tide", "mono"]
ACCENTS = ["glacier", "ember", "meadow", "lilac", "crimson", "gold",
           "teal", "magenta", "moss", "orchid"]

# The subset the PR lane runs: every theme against one accent, plus every accent
# against the two grounds that have historically failed. Named rather than
# sampled, so what it does not cover is legible.
QUICK_THEMES = THEMES
QUICK_ACCENTS = ["glacier"]
QUICK_EXTRA_THEMES = ["blueprint", "camel"]

# PRD-22's floors, on the composited surface.
FLOORS = {"givens": 7.0, "entries": 4.5, "coral": 3.0, "petal": 4.5}

# A recorded value may improve freely and may drift down by this much before it
# reads as a regression. Rendering is not bit-exact across runtime point
# releases, and a matrix that fails on 0.02 is a matrix nobody re-runs.
#
# The petal column gets a *relative* budget, and it has to. Its reported value
# is the worst of nine petals, and which petal is worst flips frame to frame as
# the board bends underneath — two readings of a resting rose came out 14.40 and
# 15.21. An absolute 0.25 on a column that swings 5% of 15 fails a build that
# changed nothing, which is how a lane gets deleted.
DRIFT = 0.25
RELATIVE_DRIFT = {"petal": 0.08}

# The resume cursor (`TouchUI.swift`: `@State private var cursor = 40`).
CURSOR_CELL = 40

# iPhone 17 Pro, in points. The screenshot is in pixels; every AX frame is in
# points; this is the bridge between them, and `Frame.__init__` checks it
# against the real image rather than trusting it.
SCREEN_POINT_WIDTH = 402.0


# ------------------------------------------------------------------- pixels


class Frame:
    """One decoded screenshot: a flat BGRA buffer plus the stride to index it.

    Deliberately not a general BMP reader. `simctl` writes exactly one shape —
    BITMAPV5HEADER, 32 bits per pixel, BI_BITFIELDS with the masks below, top-
    down (negative height) — and anything else is rejected loudly. A reader that
    silently coped with a different byte order would produce numbers that look
    entirely plausible and are wrong, which is the worst thing a measuring
    instrument can do."""

    def __init__(self, path):
        with open(path, "rb") as handle:
            data = handle.read()
        if data[:2] != b"BM":
            sys.exit("%s is not a BMP — did simctl ignore --type=bmp?" % path)
        offset = struct.unpack("<I", data[10:14])[0]
        header, width, height, planes, bpp, compression = struct.unpack(
            "<IiiHHI", data[14:34])
        if bpp != 32 or compression != 3 or planes != 1:
            sys.exit("unexpected BMP shape in %s (bpp %d, compression %d) — this "
                     "harness reads simctl's 32-bit BI_BITFIELDS output only"
                     % (path, bpp, compression))
        red, green, blue, alpha = struct.unpack("<IIII", data[54:70])
        if (red, green, blue) != (0x00FF0000, 0x0000FF00, 0x000000FF):
            sys.exit("unexpected channel masks in %s (R %08x G %08x B %08x) — the "
                     "byte order this harness assumes (B,G,R,A) no longer holds"
                     % (path, red, green, blue))
        if height >= 0:
            sys.exit("%s is bottom-up; simctl has always written top-down and "
                     "every row index here assumes it" % path)
        self.width = width
        self.height = -height
        self.stride = width * 4
        self.offset = offset
        self.data = data
        # Points to pixels. Asserted rather than assumed: every sample rectangle
        # in this file comes from an accessibility frame measured in points, and
        # a device whose width is not a whole multiple of the logical width
        # would shift every one of them by a subpixel that nothing would report.
        self.scale = width / SCREEN_POINT_WIDTH
        if abs(self.scale - round(self.scale)) > 1e-6:
            sys.exit("%s is %d px wide, which is not a whole multiple of the "
                     "%.0f pt this harness measures frames in — wrong device?"
                     % (path, width, SCREEN_POINT_WIDTH))

    def region(self, box):
        """The raw bytes of a point-space rectangle, for comparing two frames.

        Used only to answer "has the screen changed / has it stopped changing",
        so it slices rows wholesale rather than unpacking pixels."""
        s = self.scale
        x0, y0 = int(box[0] * s), int(box[1] * s)
        x1, y1 = int(box[2] * s), int(box[3] * s)
        width = (x1 - x0) * 4
        return b"".join(
            self.data[self.offset + y * self.stride + x0 * 4:
                      self.offset + y * self.stride + x0 * 4 + width]
            for y in range(y0, y1))

    def pixels(self, rect, inset):
        """Every pixel inside `rect` (points), shrunk by `inset` of its side.

        The inset is not tidiness: a cell's outer few points carry the hairline
        separator, the neighbouring box's wash, and on the cursor cell an accent
        ring. Sampling them measures the grid, not the digit."""
        s = self.scale
        x0 = int((rect["x"] + rect["width"] * inset) * s)
        x1 = int((rect["x"] + rect["width"] * (1 - inset)) * s)
        y0 = int((rect["y"] + rect["height"] * inset) * s)
        y1 = int((rect["y"] + rect["height"] * (1 - inset)) * s)
        x0, x1 = max(0, x0), min(self.width, x1)
        y0, y1 = max(0, y0), min(self.height, y1)
        out = []
        data = self.data
        for y in range(y0, y1):
            base = self.offset + y * self.stride + x0 * 4
            for i in range(base, base + (x1 - x0) * 4, 4):
                out.append((data[i + 2], data[i + 1], data[i]))
        return out


def _linearize(channel):
    c = channel / 255.0
    return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4


# WCAG linearisation, precomputed. Every sample is an 8-bit channel, so there are
# 256 possible answers; computing `pow` per pixel instead turned the ranking sort
# below into most of the harness's CPU time.
LINEAR = [_linearize(v) for v in range(256)]
LUMA_R = [0.2126 * v for v in LINEAR]
LUMA_G = [0.7152 * v for v in LINEAR]
LUMA_B = [0.0722 * v for v in LINEAR]


def luminance(rgb):
    return LUMA_R[rgb[0]] + LUMA_G[rgb[1]] + LUMA_B[rgb[2]]


def contrast(a, b):
    x, y = luminance(a), luminance(b)
    return (max(x, y) + 0.05) / (min(x, y) + 0.05)


def median_rgb(samples):
    if not samples:
        return None
    return tuple(sorted(s[c] for s in samples)[len(samples) // 2] for c in range(3))


def ground(samples):
    """A cell's background: the median pixel. A digit covers well under half a
    cell, so the median is background by construction — and unlike the mode it
    does not mind that glass carries a gradient."""
    return median_rgb(samples)


def ink(samples, base, fraction=0.10, floor=24):
    """The drawn glyph: the median of the decile furthest in luminance from
    `base`. Returns None when there is no such decile — an empty cell has no
    ink, and inventing one would report the wash's contrast against itself."""
    if len(samples) < floor * 4:
        return None
    base_l = luminance(base)
    ranked = sorted(samples, key=lambda p: -abs(luminance(p) - base_l))
    take = max(floor, int(len(ranked) * fraction))
    core = median_rgb(ranked[:take])
    # A cell whose "extreme" decile is indistinguishable from its ground is a
    # cell with nothing drawn in it.
    return core if contrast(core, base) > 1.15 else None


# -------------------------------------------------------------- the board


class Geometry:
    """Where everything is, read from the accessibility tree exactly once.

    Every cell of the matrix photographs the same board on the same device with
    the same cursor, so the 81 cell frames, the nine box groupings and the ten
    petal frames are identical in all of them. A `describe-ui` costs 400 hit-test
    probes — 20 s on a loaded machine — and doing four of them per cell was most
    of this harness's wall clock, measuring geometry it already knew.

    So it is read once and reused, and the price of that is a readiness signal
    that no longer comes free with the tree. `has_rendered` is that signal:
    the board region has to *differ from the previous cell's* (the app really
    did relaunch into a new theme) and then *stop changing* (it finished
    animating). Both halves matter — stability alone would happily photograph
    the previous theme, twice."""

    def __init__(self, entries):
        self.classes, self.boxes = classify(entries)
        cells = [r for rects in self.boxes.values() for r in rects]
        self.board = (
            min(r["x"] for r in cells), min(r["y"] for r in cells),
            max(r["x"] + r["width"] for r in cells),
            max(r["y"] + r["height"] for r in cells))
        self.empty_label = first_empty_label(entries)
        self.empty_frame = next(
            e["frame"] for e in entries if e.get("label") == self.empty_label)
        # Both filled the first time the rose is opened, from the only other
        # accessibility read this harness makes.
        self.petals = None
        self.ring = None

    def learn_petals(self, entries):
        self.petals = [
            e["frame"] for e in entries
            if e.get("label", "").startswith(("Place ", "Note "))
        ]
        if len(self.petals) < 9:
            sys.exit("the rose showed %d petals, not 9 — the tap did not open it, "
                     "or the ring's accessibility tree collapsed (PRD-19)"
                     % len(self.petals))
        xs = [f["x"] for f in self.petals] + [f["x"] + f["width"] for f in self.petals]
        ys = [f["y"] for f in self.petals] + [f["y"] + f["height"] for f in self.petals]
        self.ring = (min(xs), min(ys), max(xs), max(ys))


def classify(entries):
    """Cell frames in points, grouped by what the board is drawing in them.

    The classification comes from the running app's own accessibility values —
    `"5, given"`, `"7, wrong"`, `"4"`, `"Empty"` — rather than from the fixture
    JSON. The tree is what the board actually rendered; the file is what it was
    asked to."""
    classes = {"givens": [], "entries": [], "coral": []}
    boxes = {}
    for entry in entries:
        label = entry.get("label", "")
        if not label.startswith("Row ") or "column " not in label:
            continue
        row = int(label.split("Row ")[1].split(",")[0]) - 1
        col = int(label.split("column ")[1].strip()) - 1
        index = row * 9 + col
        rect = entry["frame"]
        boxes.setdefault((row // 3) * 3 + col // 3, []).append(rect)
        if index == CURSOR_CELL:
            continue
        value = entry.get("value", "")
        if value.endswith(", given"):
            classes["givens"].append(rect)
        elif value.endswith(", wrong"):
            classes["coral"].append(rect)
        elif value[:1].isdigit():
            classes["entries"].append(rect)
    if len(boxes) != 9:
        sys.exit("found %d box groups, not 9 — the board's accessibility tree is "
                 "not what this harness samples from (see ax-snapshot.py)"
                 % len(boxes))
    return classes, boxes


def measure_board(frame, geometry):
    classes, boxes = geometry.classes, geometry.boxes
    grounds = {}
    for box, rects in boxes.items():
        per_cell = [ground(frame.pixels(r, 0.22)) for r in rects]
        grounds[box] = median_rgb([c for c in per_cell if c])

    out, inks = {}, []
    for name in ("givens", "entries", "coral"):
        cores = []
        for rect in classes[name]:
            samples = frame.pixels(rect, 0.18)
            local = ground(samples)
            core = ink(samples, local)
            if core:
                cores.append(core)
        if not cores:
            out[name], _ = None, inks.append(None)
            continue
        core = median_rgb(cores)
        inks.append(core)
        out[name] = min(contrast(core, g) for g in grounds.values() if g)
    # What this cell *is*, as opposed to how well it scores. Two cells of the
    # matrix can score the same and cannot look the same: within a theme the
    # accent moves the entry ink, and between themes the ground moves. See
    # `measure_cell`, which uses it to tell "the app relaunched into the new
    # prefs" from "the screen never changed".
    out["fingerprint"] = (tuple(inks), grounds.get(0))
    return out


def measure_petals(frame, petals):
    """The rose's nine glyphs, each against whatever is behind that petal.

    Returns `(worst, typical)`. Per petal rather than pooled-then-worst-ground,
    because with the disc gone every petal has a different thing behind it —
    that is the whole point of the change — and the number that matters is the
    worst one.

    **What this column is not.** With no opaque disc there is nothing to tell
    the petal's own glyph from a board digit magnifying underneath it, so on a
    petal sitting over dense givens the extreme decile may be the *board's* ink.
    That is a floor on legibility rather than a measurement of the glyph, which
    is the useful direction to be wrong in — a petal over a bright digit is the
    hardest one to read — but it is not the same claim.

    `typical` is the median, and it exists only to be compared between two
    frames. The *min* is the number to report and a terrible number to compare:
    which petal is worst flips frame to frame as the interactive glass moves,
    and two readings of a perfectly stable rose came out 14.40 and 15.21 — a 5%
    "disagreement" that is really two different petals."""
    ratios = []
    for rect in petals:
        samples = frame.pixels(rect, 0.20)
        base = ground(samples)
        core = ink(samples, base)
        if core:
            ratios.append(contrast(core, base))
    if not ratios:
        return None, None
    ratios.sort()
    return ratios[0], ratios[len(ratios) // 2]


# ------------------------------------------------------------------ driving


def blobs(prefs):
    with open(FIXTURE) as handle:
        library = handle.read()
    return {
        "default.nine.library.json": library,
        "default.nine.prefs.json": json.dumps(prefs, sort_keys=True),
        "default.help.seen.json": "true",
        "default.welcome.seen.json": "true",
        "default.nine.sessionCount.json": "9",
        "default.nine.drawerFound.json": "true",
        "default.nine.tips.json": json.dumps(
            {"shown": ["undo", "pencil", "highlight"]}, sort_keys=True),
    }


def first_empty_label(entries):
    for entry in entries:
        if entry.get("label", "").startswith("Row ") and entry.get("value") == "Empty":
            return entry["label"]
    sys.exit("the frozen board has no empty cell to open the rose on")


def shoot(udid, path):
    simrig.run(["xcrun", "simctl", "io", udid, "screenshot", "--type=bmp", path])
    return Frame(path)


def drawn(region, stride=37, floor=0.12):
    """Is there anything on this part of the screen?

    The reason this exists: an app that has launched but not yet drawn shows a
    flat white window, and a flat white window is both *different from the
    previous theme* and *stable* — so a change-then-settle check happily
    photographs it and reports a board with no digits in it. That happened on
    the harness's fourth cell, and the matrix printed a row of dashes rather
    than a wrong number, which is the only reason it was noticed.

    A drawn board always spans a wide luminance range (near-black ground and
    near-white digits, or the inverse); a blank window spans none. Strided so
    the check costs nothing next to the screenshot it guards."""
    lo, hi = 1.0, 0.0
    for i in range(0, len(region) - 3, stride * 4):
        value = LUMA_R[region[i + 2]] + LUMA_G[region[i + 1]] + LUMA_B[region[i]]
        lo, hi = min(lo, value), max(hi, value)
    return hi - lo > floor


def moved(a, b, stride=17):
    """Fraction of sampled bytes that differ between two region snapshots.

    A threshold rather than a boolean because "did the screen change" cannot
    tell a *dropped tap* from a tap that landed: tapping a board cell moves the
    cursor ring whether or not the rose then blooms, and one moved ring is a
    change. Opening the rose repaints most of the ring's area; moving a cursor
    repaints a few percent of it. On a machine at load 258 the tap really does
    get dropped, and without this the harness measured the board's digits
    through the petal frames and reported them as petal contrast."""
    if a is None or b is None or len(a) != len(b):
        return 1.0
    total = differing = 0
    for i in range(0, len(a), stride):
        total += 1
        if a[i] != b[i]:
            differing += 1
    return differing / max(1, total)


def settle(udid, path, box, previous, tries=20, pause=0.9,
           min_change=0.02, still=0.02):
    """Screenshot until the region under `box` is drawn, changed, and stopped.

    Returns `(frame, region)` on success and `(None, reason)` on failure, so the
    caller can say which of the two things it was watching gave up and name the
    cell — this function knows the pixels and not what they mean.

    `previous` is the same region from the last thing we measured — the ring's
    pixels just before the rose was tapped open. A run that never differs from
    it is a failure this catches: the tap missed, and the harness would
    otherwise measure the old screen."""
    changed, last = previous is None, None
    for _ in range(tries):
        frame = shoot(udid, path)
        current = frame.region(box)
        if drawn(current):
            if not changed:
                changed = moved(previous, current) > min_change
            elif last is not None and moved(last, current) < still:
                # "Stopped changing", not "is byte-identical". The glass
                # material is not deterministic frame to frame — two
                # screenshots of a resting board differ in a scatter of
                # pixels — and demanding equality made the rose look like it
                # never settled, which the retry below then read as a dropped
                # tap and closed the rose to prove it.
                return frame, current
            last = current
        else:
            last = None
        time.sleep(pause)
    return None, ("was never drawn at all" if last is None
                  else ("never changed" if not changed
                        else "never stopped changing"))


def measure_cell(udid, theme, accent, shots, geometry, previous, with_rose):
    """One (theme, accent) cell. Returns (values, this cell's fingerprint).

    The fingerprint is the next cell's `previous`, and it is how the harness
    knows the relaunch after it actually landed. Comparing *pixels* was the
    first attempt and it does not work down a column: within one theme only the
    accent moves, which is three entry glyphs and a cursor ring — 0.8% of the
    board, under any change threshold that screenshot noise does not also
    cross. The ink is unambiguous. Every accent is a different colour, so an
    entry-ink that has not moved means the app is still showing the last one."""
    prefs = {"appearance": theme, "accent": accent,
             "errorHighlight": True, "resumeOnLaunch": True}
    simrig.relaunch(udid, BUNDLE_ID, blobs(prefs))

    board_path = os.path.join(shots, "%s-%s.bmp" % (theme, accent))
    if geometry.get("cache") is None:
        # The one full accessibility read of the whole run. Everything after
        # this cell reuses its frames; see Geometry.
        data = simrig.wait_for(udid, "Row 1, column 1")
        geometry["cache"] = Geometry(data["entries"])
        previous = None
    cache = geometry["cache"]

    result, frame = None, None
    for _ in range(10):
        frame, why = settle(udid, board_path, cache.board, None)
        if frame is None:
            sys.exit("the board on %s/%s %s. The last screenshot taken is %s."
                     % (theme, accent, why, board_path))
        result = measure_board(frame, cache)
        if previous is None or result["fingerprint"] != previous:
            break
        result = None
        time.sleep(1.0)
    if result is None:
        sys.exit("the board on %s/%s is still showing the previous cell — every "
                 "digit is the same colour it was. The app did not relaunch into "
                 "the new prefs. Last screenshot: %s" % (theme, accent, board_path))
    fingerprint = result.pop("fingerprint")
    result["petal"] = None
    if with_rose:
        rose_path = os.path.join(shots, "%s-%s-rose.bmp" % (theme, accent))
        before = frame.region(cache.ring) if cache.ring else None
        petals, agreed = None, None
        for attempt in range(3):
            simrig.run([
                "sim-use", "tap", "--device", udid,
                "-x", str(int(cache.empty_frame["x"] + cache.empty_frame["width"] / 2)),
                "-y", str(int(cache.empty_frame["y"] + cache.empty_frame["height"] / 2)),
            ])
            if cache.petals is None:
                # The run's second and last accessibility read: the ten petal
                # frames, which are the same in every cell after this one.
                rose = simrig.wait_for(udid, "Place 5", hint_for_missing_board=False)
                cache.learn_petals(rose["entries"])
                petals = shoot(udid, rose_path)
                agreed, _ = measure_petals(petals, cache.petals)
                break
            # Two gates, and they check different things. `opened` is about the
            # *pixels*: the ring has to change by more than a moved cursor ring
            # would, which is how a dropped tap is told from a landed one.
            # `agreed` is about the *measurement*: the petal ratio has to come
            # out the same twice in a row.
            #
            # Pixel-stability was the first attempt at the second gate and it
            # was wrong twice over — the interactive glass keeps moving, so a
            # resting rose "never settled"; and a rose caught mid-bloom settles
            # perfectly well one frame later while reading 2.21:1 against the
            # board it has not covered yet. Measuring twice catches both.
            opened, why = settle(udid, rose_path, cache.ring, before,
                                 tries=10, min_change=0.15, still=0.15)
            if opened is not None:
                _, was = measure_petals(opened, cache.petals)
                for _ in range(6):
                    time.sleep(0.8)
                    frame_now = shoot(udid, rose_path)
                    worst, typical = measure_petals(frame_now, cache.petals)
                    if (typical is not None and was is not None
                            and abs(typical - was) <= 0.08 * max(typical, was)):
                        petals, agreed = frame_now, worst
                        break
                    was = typical
                if agreed is not None:
                    break
                why = "never read the same twice"
            print("    rose unreadable on %s/%s (%s) — tapping again (%d/3)"
                  % (theme, accent, why, attempt + 2))
            # Re-tapping an *open* rose lands on the cancel scrim and closes it,
            # so the next tap round-trips back to open. That costs a beat and is
            # the only way back to a known state.
        if agreed is None:
            sys.exit("the rose never read the same twice on %s/%s after three "
                     "taps. The last screenshot taken is %s."
                     % (theme, accent, rose_path))
        result["petal"] = agreed

    # The frozen board carries givens, correct entries, a wrong entry and an
    # open rose by construction, so a missing column is never "this board has
    # none of those" — it is the harness having measured the wrong screen. Say
    # so here rather than printing a dash that reads like an honest absence.
    missing = [c for c in COLUMNS
               if result.get(c) is None and (c != "petal" or with_rose)]
    if missing:
        sys.exit("%s/%s: found no %s on a board that always has them. The "
                 "screenshot measured is %s."
                 % (theme, accent, " or ".join(missing), board_path))
    return result, fingerprint


# ------------------------------------------------------------------ matrix


COLUMNS = ["givens", "entries", "coral", "petal"]


def first_accent(theme, pairs):
    return next(a for t, a in pairs if t == theme)


def rose_wanted(theme, accent, pairs, every):
    """Is this the cell that measures the rose?

    Once per theme by default, on that theme's first accent. The petal glyph is
    `Color.primary` over whatever the board is doing behind it, so what moves
    the number is the *theme*, not the accent — and each rose costs a tap, a
    bloom, and two or three 12 MB screenshots on top of the board's own.
    Measuring all eighty was most of this harness's wall clock and told us the
    same eight things ten times each. `--rose-all` is there for the change that
    touches the petals themselves.
    """
    return True if every else accent == first_accent(theme, pairs)


def cell_key(theme, accent, mode):
    return "%s/%s/%s" % (theme, accent, mode)


def render(rows, runtime, covered):
    lines = [
        "# nine board contrast — measured on the composited glass (PRD-22)",
        "# device: %s   runtime: %s   sim-use: %s"
        % (DEVICE_TYPE, runtime, simrig.sim_use_version()),
        "# floors: " + "  ".join("%s %.1f" % (c, FLOORS[c]) for c in COLUMNS),
        "#",
        "# Regenerate: nine/scripts/contrast-harness.py --record",
        "#",
        "# %s" % covered,
        "",
        "%-10s %-9s %-9s %s" % ("theme", "accent", "contrast",
                                "  ".join("%7s" % c for c in COLUMNS)),
    ]
    for (theme, accent, mode), values in rows:
        cells = "  ".join(
            "%7.2f" % values[c] if values.get(c) is not None else "%7s" % "—"
            for c in COLUMNS)
        lines.append("%-10s %-9s %-9s %s" % (theme, accent, mode, cells))
    return "\n".join(lines) + "\n"


def parse(text):
    out = {}
    for line in text.splitlines():
        if line.startswith("#") or not line.strip():
            continue
        parts = line.split()
        if len(parts) != 3 + len(COLUMNS) or parts[0] == "theme":
            continue
        theme, accent, mode = parts[:3]
        values = {}
        for name, raw in zip(COLUMNS, parts[3:]):
            values[name] = None if raw == "—" else float(raw)
        out[cell_key(theme, accent, mode)] = values
    return out


def gate(rows, recorded):
    """Two rules. A cell under its floor is a failure whatever the record says —
    the record is a photograph, not a permission slip. A cell that fell more than
    DRIFT below its recorded value is a regression even if it still clears, so a
    retune cannot be quietly eroded one release at a time."""
    failures = []
    for (theme, accent, mode), values in rows:
        for column in COLUMNS:
            value = values.get(column)
            if value is None:
                continue
            if value < FLOORS[column]:
                failures.append(
                    "%-10s %-9s %-9s %-7s %.2f:1 is below the %.1f:1 floor"
                    % (theme, accent, mode, column, value, FLOORS[column]))
                continue
            was = recorded.get(cell_key(theme, accent, mode), {}).get(column)
            if was is None:
                continue
            budget = max(DRIFT, was * RELATIVE_DRIFT.get(column, 0.0))
            if value < was - budget:
                failures.append(
                    "%-10s %-9s %-9s %-7s %.2f:1, was %.2f:1 — a %.2f drop "
                    "(budget %.2f)"
                    % (theme, accent, mode, column, value, was, was - value, budget))
    return failures


# ------------------------------------------------------------------- entry


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--record", action="store_true",
                        help="overwrite the matrix instead of gating on it")
    parser.add_argument("--app", help="prebuilt Nine.app (skips xcodebuild)")
    parser.add_argument("--themes", help="comma-separated subset")
    parser.add_argument("--accents", help="comma-separated subset")
    parser.add_argument("--quick", action="store_true",
                        help="the PR-lane subset (see QUICK_* above)")
    parser.add_argument("--contrast", action="store_true",
                        help="also run the whole matrix with Increase Contrast on")
    parser.add_argument("--no-rose", action="store_true",
                        help="skip the petal column entirely")
    parser.add_argument("--rose-all", action="store_true",
                        help="measure the petal column on every cell rather "
                             "than once per theme (see rose_wanted)")
    parser.add_argument("--out-dir", default=None,
                        help="where to keep the screenshots that were measured "
                             "(default: alongside the matrix, as .captured)")
    parser.add_argument("--no-erase", action="store_true",
                        help="reuse the harness simulator as-is; local iteration only")
    args = parser.parse_args()

    if not os.path.exists(FIXTURE):
        sys.exit("no frozen board at %s — freeze it first:\n"
                 "  NINE_FREEZE_AX_FIXTURE=1 swift test --filter AXFixture" % FIXTURE)

    pairs = []
    if args.quick:
        pairs = [(t, a) for t in QUICK_THEMES for a in QUICK_ACCENTS]
        pairs += [(t, a) for t in QUICK_EXTRA_THEMES for a in ACCENTS
                  if (t, a) not in pairs]
        covered = ("subset: %d of %d cells (--quick). Not covered: every other "
                   "theme x accent pairing." % (len(pairs), len(THEMES) * len(ACCENTS)))
    else:
        themes = args.themes.split(",") if args.themes else THEMES
        accents = args.accents.split(",") if args.accents else ACCENTS
        for name in themes:
            if name not in THEMES:
                sys.exit("no theme %r. Known: %s" % (name, ", ".join(THEMES)))
        for name in accents:
            if name not in ACCENTS:
                sys.exit("no accent %r. Known: %s" % (name, ", ".join(ACCENTS)))
        pairs = [(t, a) for t in themes for a in accents]
        full = len(pairs) == len(THEMES) * len(ACCENTS)
        covered = ("full matrix: %d cells (%d themes x %d accents; `auto` "
                   "delegates to Void/Paper and is not a cell of its own)"
                   % (len(pairs), len(THEMES), len(ACCENTS))) if full else (
                   "subset: %d cells (--themes/--accents). Not covered: "
                   "everything else." % len(pairs))

    modes = ["standard"] + (["increased"] if args.contrast else [])
    # Increase Contrast moves the box washes, the cell separators and the box
    # borders — every one of them theme-level. The ink does not move at all, so
    # running the increased pass across ten accents would re-measure the same
    # eight grounds ten times each. One accent per theme, and said out loud.
    increased_pairs = [(t, a) for (t, a) in pairs if a == first_accent(t, pairs)]
    covered += "  |  contrast modes: %s" % ", ".join(modes)
    if args.contrast:
        covered += (" (increased: %d cells, one accent per theme — the mode "
                    "moves grounds, not ink)" % len(increased_pairs))
    if args.no_rose:
        covered += "  |  petal column skipped (--no-rose)"
    elif not args.rose_all:
        covered += "  |  petal column: one cell per theme"

    runtime = simrig.newest_ios_runtime()
    print("runtime: %s  device: %s" % (runtime["name"], DEVICE_TYPE))
    print("%d cells standard%s" % (len(pairs),
          "" if not args.contrast else " + %d increased" % len(increased_pairs)))
    udid = simrig.prepare_simulator(
        runtime, SIM_NAME, DEVICE_TYPE, erase=not args.no_erase)
    simrig.build_and_install(udid, args.app, REPO)

    os.makedirs(BASELINES, exist_ok=True)
    shots = args.out_dir or os.path.join(BASELINES, ".captured")
    os.makedirs(shots, exist_ok=True)

    rows, started = [], time.time()
    geometry, previous = {"cache": None}, None
    for mode in modes:
        simrig.run(["xcrun", "simctl", "ui", udid, "increase_contrast",
                    "enabled" if mode == "increased" else "disabled"], check=False)
        # Flipping Increase Contrast redraws the board, so the last standard
        # cell's fingerprint is not a valid reference for the first increased
        # one — the ink is the same and the ground is not.
        previous = None
        for theme, accent in (increased_pairs if mode == "increased" else pairs):
            began = time.time()
            wants_rose = (not args.no_rose
                          and rose_wanted(theme, accent, pairs, args.rose_all))
            values, previous = measure_cell(
                udid, theme, accent, shots, geometry, previous, wants_rose)
            rows.append(((theme, accent, mode), values))
            print("  %-10s %-9s %-9s %s   (%.1fs)"
                  % (theme, accent, mode,
                     "  ".join("%s %s" % (c, "—" if values.get(c) is None
                                          else "%.2f" % values[c])
                               for c in COLUMNS),
                     time.time() - began))
    # Leave the simulator as we found it, so a later --no-erase run is not
    # silently measuring an Increase Contrast board.
    simrig.run(["xcrun", "simctl", "ui", udid, "increase_contrast", "disabled"],
               check=False)
    elapsed = time.time() - started

    text = render(rows, runtime["version"], covered)
    if args.record:
        with open(MATRIX, "w") as handle:
            handle.write(text)
        print("\nrecorded %s in %.0f s" % (os.path.relpath(MATRIX, REPO), elapsed))
        if not args.no_erase:
            simrig.run(["xcrun", "simctl", "shutdown", udid], check=False)
        return

    captured = os.path.join(shots, "matrix.txt")
    with open(captured, "w") as handle:
        handle.write(text)
    recorded = parse(open(MATRIX).read()) if os.path.exists(MATRIX) else {}
    failures = gate(rows, recorded)
    if not args.no_erase:
        simrig.run(["xcrun", "simctl", "shutdown", udid], check=False)

    print("\n%s" % text)
    print("measured %d cells in %.0f s (%.1f s per cell)"
          % (len(rows), elapsed, elapsed / max(1, len(rows))))
    if failures:
        print("\n".join(failures), file=sys.stderr)
        sys.exit("\n%d contrast failure(s). What was measured — the matrix and "
                 "the screenshots it was measured from — is in %s.\nIf the change "
                 "is intended, re-record: nine/scripts/contrast-harness.py --record"
                 % (len(failures), os.path.relpath(shots, REPO)))
    print("\nevery measured cell clears its floor")


if __name__ == "__main__":
    main()
