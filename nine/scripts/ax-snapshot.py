#!/usr/bin/env python3
"""Dump and diff Nine's accessibility tree, one baseline per screen (PRD-19).

The board is a single `Canvas` with 81 synthetic accessibility children hung off
it (`Sources/App/BoardAccessibility.swift`). Nothing on screen changes when that
tree collapses: the game looks and plays identically, and a blind player simply
finds a blank rectangle where the puzzle used to be. It has already happened
once — `describe-ui` on the shipped 1.1 build listed *zero* cells — so the tree
is a regression surface and this is its tripwire.

    nine/scripts/ax-snapshot.py            # compare against the baselines
    nine/scripts/ax-snapshot.py --record   # re-record them (deliberate act)

Determinism is the whole game here, and it comes from four things:

  1. **A frozen board.** A fresh launch would show today's daily, which is a
     different puzzle tomorrow, so every per-cell value in the baselines would
     rot overnight. Instead the simulator's container is seeded with the library
     blob owned by `Tests/EngineTests/AXFixtureTests.swift` before first launch,
     and `resumeOnLaunch` opens straight onto it.
  2. **A fixed device.** Frames are in points, so the device *type* fixes them;
     the runtime version does not. A dedicated simulator is created and erased
     each run, which also guarantees no iCloud-restored library sneaks in.
  3. **Fixed chrome state.** `sessionCount` is seeded past the drawer grabber's
     three-session budget and `drawerFound` is true, so the one piece of chrome
     that is *designed* to disappear is already gone.
  4. **Normalization.** The status bar (clock, battery, Wi-Fi) is dropped and
     `describe-ui`'s positional `@N` aliases are stripped: they renumber
     wholesale when a single element is added, which would bury the one line
     that actually changed.

What the dump cannot see, and is pinned by unit tests instead: Voice Control
input labels (`accessibilityUserInputLabels` is absent from the AX API
`describe-ui` reads) and the wording of every announcement. See
`Tests/SharedTests/BoardSpeechTests.swift`.
"""

import argparse
import json
import os
import re
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ninestate
import simrig
from simrig import describe, run, tap, wait_for

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # nine/
BASELINES = os.path.join(REPO, "Tests", "AXBaselines")
FIXTURE = os.path.join(BASELINES, "fixture.nine.library.json")
BUNDLE_ID = "com.couchsuite.nine"

# The device type fixes the point geometry every frame in the baselines is
# measured in. Changing it invalidates all of them at once.
DEVICE_TYPE = "iPhone 17 Pro"
SIM_NAME = "Nine-AX"

# Shared with the localization lane, so the two cannot drift — see `ninestate`.
PREFS_ERRORS_ON = ninestate.PREFS_ERRORS_ON
PREFS_ERRORS_OFF = ninestate.PREFS_ERRORS_OFF


# ------------------------------------------------------------------ driving


def seed(udid, prefs):
    """Write the frozen library and the fixed chrome state into the container."""
    simrig.seed(udid, BUNDLE_ID, ninestate.quiet_blobs(prefs))


def settled(udid, anchor, screen, attempts=6):
    """Wait for the anchor, then for two consecutive dumps that agree.

    A label appears the instant its view is inserted, which on a sheet or a
    spring transition is well before the frames stop moving — and a frame that
    is still moving lands in the baseline a fraction of a point off, so the
    *next* run diffs against it for no reason. Requiring two identical reads is
    the difference between a tripwire and a coin flip."""
    previous = element_lines_only(wait_for(udid, anchor))
    for _ in range(attempts):
        time.sleep(0.7)
        data = describe(udid)
        current = element_lines_only(data)
        if current == previous:
            return data
        previous = current
    sys.exit(
        "%s never stopped moving: six reads, no two alike. Something on this "
        "screen animates forever, or the anchor appears before the layout "
        "resolves." % screen
    )


def element_lines_only(data):
    """The comparable part of a dump — everything but the header, which carries
    no per-run state anyway."""
    return [
        element_line(e) for e in data["entries"]
        if e.get("region", {}).get("kind") != "Top"
    ]


def relaunch(udid, prefs):
    """Delegates, and must keep delegating.

    This inlined `simrig.relaunch`'s four steps for as long as there was only
    one caller, which stayed invisible until `simrig.relaunch` grew a
    launch-argument path for the localization lane and this copy did not. A
    harness reusing `capture()` would then have dropped every mode flag in
    silence and recorded baselines of an ordinary English build."""
    simrig.relaunch(udid, BUNDLE_ID, ninestate.quiet_blobs(prefs))


# ------------------------------------------------------------- normalization


def cell_label(index):
    return "Row %d, column %d" % (index // 9 + 1, index % 9 + 1)


def fixture_probe_labels():
    """One cell per `BoardSpeech.cellValue` branch, chosen from the frozen blob
    so a re-freeze moves the probes with it rather than silently probing the
    wrong kind of cell."""
    with open(FIXTURE) as handle:
        game = json.load(handle)["entries"][0]["game"]
    givens = game["puzzle"]["puzzle"]["cells"]
    solution = game["puzzle"]["solution"]["cells"]
    current = game["entries"]["cells"] if isinstance(game["entries"], dict) else game["entries"]
    pencil = game["pencil"]

    def first(predicate):
        return next((i for i in range(81) if predicate(i)), None)

    noted = first(lambda i: current[i] == 0 and _has_notes(pencil, i))
    return [
        ("given", first(lambda i: givens[i] != 0)),
        ("correct entry", first(
            lambda i: givens[i] == 0 and current[i] == solution[i]
        )),
        ("wrong entry", first(
            lambda i: givens[i] == 0 and current[i] != 0 and current[i] != solution[i]
        )),
        ("empty", first(
            lambda i: current[i] == 0 and not _has_notes(pencil, i)
        )),
        ("noted", noted),
    ]


def _has_notes(pencil, index):
    """`pencil` is a mask per cell however it happens to be encoded — a list of
    ints, a list of lists, or a dict wrapper. Truthiness is all we need."""
    cells = pencil["cells"] if isinstance(pencil, dict) else pencil
    if index >= len(cells):
        return False
    value = cells[index]
    return bool(value)


def region_header(region):
    kind = region.get("kind", "")
    label = region.get("label")
    return 'Group "%s"' % label if label else "[%s]" % kind


TODAY = re.compile(r"\b[A-Z][a-z]{2} \d{1,2}, \d{4}\b")

# In the header for the same reason the runtime is: `describe-ui`'s output is
# the measuring instrument, and CI installs whatever version Homebrew has today.
# A tool bump that changes the shape of a dump should announce itself on line two
# rather than as an unexplained diff on every screen.
sim_use_version = simrig.sim_use_version


def normalize(data, screen, runtime):
    """One line per element, indented by AX depth, status bar dropped, `@N`
    aliases stripped, today's date masked.

    The runtime version is in the header on purpose. Frames are in points, so
    the *device type* fixes them — but sheet metrics and system control sizes
    move between OS releases, and CI runners upgrade their Xcode image without
    asking. Putting the version in line two means a runner bump announces itself
    as the first line of the diff instead of as 300 mysterious frame changes."""
    lines = [
        "# nine accessibility tree — screen: %s" % screen,
        "# device: %s   runtime: %s   sim-use: %s"
        % (DEVICE_TYPE, runtime, sim_use_version()),
        "#",
        "# Regenerate: nine/scripts/ax-snapshot.py --record",
        "",
    ]
    # Gathered by container, not left in `describe-ui`'s order. The JSON
    # `entries` array is sorted geometrically (row-major across the whole
    # board), so the nine box containers would otherwise interleave — nine
    # repeated "Box 1 / Box 2 / Box 3" headers per board row, which reads like
    # a tree that alternates between boxes. Grouping shows the containment that
    # actually exists.
    grouped = []
    by_header = {}
    for entry in data["entries"]:
        if entry.get("region", {}).get("kind") == "Top":
            continue  # clock, battery, Wi-Fi bars
        header = region_header(entry.get("region", {}))
        if header not in by_header:
            by_header[header] = []
            grouped.append((header, by_header[header]))
        by_header[header].append(entry)

    count = 0
    for header, entries in grouped:
        lines.append(header)
        for entry in entries:
            lines.append(element_line(entry))
            count += 1
    lines.append("")
    lines.append("# %d elements in %d container%s"
                 % (count, len(grouped), "" if len(grouped) == 1 else "s"))
    return lines


def mask(text):
    """Today's date is as non-deterministic as the clock. The home shelf's daily
    card is labelled "Today, Jul 25, 2026, One a day"."""
    return TODAY.sub("<today>", text or "")


def element_line(entry):
    frame = entry["frame"]
    parts = [
        "  " * max(1, entry.get("depth", 1)),
        entry.get("role", "?"),
        ' "%s"' % mask(entry.get("label", "")),
    ]
    if "value" in entry:
        parts.append(' = "%s"' % mask(entry["value"]))
    states = entry.get("states") or []
    if states:
        parts.append(" [%s]" % ",".join(sorted(states)))
    parts.append(
        "  (%d,%d %dx%d)"
        % (frame["x"], frame["y"], frame["width"], frame["height"])
    )
    return "".join(parts)


def probe_lines(udid, data, targets):
    """Values and custom actions are only visible on a per-point probe, so the
    rotor is sampled rather than dumped 81 times: one cell per value branch is
    enough to catch a vanished rotor or a reversed one, at 5 probes instead of
    81 (which would take minutes)."""
    lines = ["", "# actions rotor + hint, one cell per value branch", ""]
    by_label = {e.get("label"): e for e in data["entries"]}
    for kind, index in targets:
        if index is None:
            lines.append("%-14s (absent from the frozen board)" % kind)
            continue
        label = cell_label(index)
        entry = by_label.get(label)
        if entry is None:
            lines.append("%-14s %r MISSING FROM TREE" % (kind, label))
            continue
        frame = entry["frame"]
        centre = (
            int(frame["x"] + frame["width"] / 2),
            int(frame["y"] + frame["height"] / 2),
        )
        raw = describe(udid, point=centre).get("raw", {})
        lines.append('%-14s "%s"' % (kind, label))
        lines.append('  value  "%s"' % (raw.get("AXValue") or ""))
        lines.append('  hint   "%s"' % (raw.get("help") or ""))
        lines.append("  rotor  %s" % (" | ".join(raw.get("custom_actions") or []) or "(none)"))
    return lines


# ---------------------------------------------------------------- the screens


def screens():
    """Each screen relaunches from a seeded container rather than navigating
    back, so no screen inherits another's transient state."""
    return [
        # The board itself, with mistake-marking on: 9 box groups, 81 cells,
        # 4 chrome buttons at 44pt.
        dict(name="game", prefs=PREFS_ERRORS_ON, taps=[], anchor="Row 9, column 9", probe=True),
        # Mistake-marking off. The wrong cell must read exactly like a right
        # one and the Wrong Digits rotor must be gone — the privacy rule, in
        # the real tree rather than in a unit test.
        dict(name="game-quiet", prefs=PREFS_ERRORS_OFF, taps=[], anchor="Row 9, column 9", probe=True),
        # Rose open: the board leaves the tree entirely (`.accessibilityHidden`)
        # and the modal ring is all that is reachable.
        dict(name="game-rose", prefs=PREFS_ERRORS_ON, taps=["FIRST_EMPTY"],
             anchor="Place 1", probe=False),
        # The prefs sheet. Elements from the board appear here too: `describe-ui`
        # finds elements by point hit-test, and a hit-test ignores AX modality —
        # so this baseline is a structural fingerprint of the sheet, not a claim
        # that VoiceOver can reach the board behind it.
        dict(name="prefs", prefs=PREFS_ERRORS_ON, taps=["Settings"],
             anchor="Resume on launch, On", probe=False),
        # The shelf, with the frozen board's fingerprint and progress caption.
        #
        # **Scrolled to the bottom before it is read**, and PRD-25 is why: the
        # deep end went from one full-width card to three, which pushed the
        # learn row past the fold on an iPhone 17 Pro. Anchoring on the last
        # card still on screen would have kept the lane green and quietly
        # dropped the tutorial, records and School cards out of the baseline —
        # a shorter file that looks like a passing diff.
        #
        # Scrolling to the *bottom* rather than by a measured amount: the
        # bottom is a hard stop, so where it lands is a property of the content
        # rather than of the swipe, and the frames do not move between runs.
        dict(name="home", prefs=PREFS_ERRORS_ON, taps=["Home", "SCROLL_BOTTOM"],
             anchor="How to play", probe=False),
        # A channel page (PRD-24), and it needs its own baseline rather than
        # riding on `home`'s: `home` scrolls to the bottom before it reads, so the
        # pager rail at the top of the shelf is structurally invisible to it. A
        # baseline that cannot see the new surface is a baseline that will not
        # catch the new surface regressing.
        #
        # Reached by tapping the pager's own chevron rather than by a swipe,
        # deliberately — the chevron is the route that has to keep working for
        # VoiceOver and Switch Control, and driving it here is what proves it is
        # in the tree at all. The first version of the rail put an
        # `accessibilityLabel` on the enclosing `HStack`, which made SwiftUI merge
        # the leading chevron away entirely; three platform builds passed and only
        # a live dump disagreed.
        dict(name="channel", prefs=PREFS_ERRORS_ON, taps=["Home", "Next channel"],
             anchor="Thermo, page 2 of 3", probe=False),
        # The History sheet, for PRD-29's table (`TableView.swift`). Its own
        # baseline for the reason `channel` has one: no existing screen can see
        # this surface, and a baseline that cannot see a surface will not catch
        # it regressing.
        #
        # Captured in the **opted-out** state, which is the default and therefore
        # the one every player meets: the invitation and the control that changes
        # it. The twenty seats need a Game Center session and an App Store Connect
        # record that does not exist, so what a baseline could pin there today is
        # nothing — see PRD-29 §10, which says so rather than implying the lane
        # covers more than it does.
        dict(name="history", prefs=PREFS_ERRORS_ON,
             taps=["Home", "SCROLL_BOTTOM", "History", "SCROLL_BOTTOM"],
             anchor="Join the table", probe=False),
    ]


def first_empty_label(targets):
    for kind, index in targets:
        if kind == "empty" and index is not None:
            return cell_label(index)
    sys.exit("the frozen board has no empty cell to open the rose on")


def scroll_to_bottom(udid, swipes=3):
    """Flick up until the scroll view is against its bottom stop.

    Repeated rather than one long drag: a single fling carries momentum, and
    where momentum stops is not deterministic. Short swipes against the stop
    are, and the stop is what we want to be standing on.
    """
    for _ in range(swipes):
        run(["sim-use", "swipe", "--device", udid,
             "--start-x", "200", "--start-y", "700",
             "--end-x", "200", "--end-y", "220", "--duration", "0.35"])
        time.sleep(0.6)


def capture(udid, screen, targets, runtime):
    relaunch(udid, screen["prefs"])
    data = wait_for(udid, "Row 1, column 1")
    for step in screen["taps"]:
        if step == "SCROLL_BOTTOM":
            scroll_to_bottom(udid)
            continue
        label = first_empty_label(targets) if step == "FIRST_EMPTY" else step
        data = wait_for(udid, label)
        tap(udid, data, label)
    data = settled(udid, screen["anchor"], screen["name"])
    lines = normalize(data, screen["name"], runtime)
    if screen["probe"]:
        lines += probe_lines(udid, data, targets)
    return "\n".join(lines) + "\n"


# ------------------------------------------------------------------- entry


def main():
    parser = argparse.ArgumentParser(
        description=__doc__,
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--record", action="store_true",
                        help="overwrite the baselines instead of diffing them")
    parser.add_argument("--app", help="prebuilt Nine.app (skips xcodebuild)")
    parser.add_argument("--only", help="capture one screen by name")
    parser.add_argument("--out-dir", default=None,
                        help="where to write what was actually captured "
                             "(default: alongside the baselines, as .captured). "
                             "CI uploads this so a failed run is reviewable "
                             "without a Mac.")
    parser.add_argument("--no-erase", action="store_true",
                        help="reuse the snapshot simulator as-is. Local "
                             "iteration only: an un-erased container can carry "
                             "a previous library, and on an iCloud-signed-in "
                             "host the cloud library restores one.")
    args = parser.parse_args()

    if not os.path.exists(FIXTURE):
        sys.exit(
            "no frozen board at %s — freeze it first:\n"
            "  NINE_FREEZE_AX_FIXTURE=1 swift test --filter AXFixture" % FIXTURE
        )

    known = {s["name"] for s in screens()}
    if args.only and args.only not in known:
        # Without this, a typo captures nothing, compares nothing, and prints
        # "all accessibility trees match their baselines".
        sys.exit("no screen named %r. Known: %s"
                 % (args.only, ", ".join(sorted(known))))

    runtime = simrig.newest_ios_runtime()
    print("runtime: %s  device: %s" % (runtime["name"], DEVICE_TYPE))
    udid = simrig.prepare_simulator(
        runtime, SIM_NAME, DEVICE_TYPE, erase=not args.no_erase)
    simrig.build_and_install(udid, args.app, REPO)

    targets = fixture_probe_labels()
    os.makedirs(BASELINES, exist_ok=True)
    captured_dir = args.out_dir or os.path.join(BASELINES, ".captured")
    os.makedirs(captured_dir, exist_ok=True)
    failures = []
    for screen in screens():
        if args.only and screen["name"] != args.only:
            continue
        print("capturing %s…" % screen["name"])
        dump = capture(udid, screen, targets, runtime["version"])
        path = os.path.join(BASELINES, "%s.txt" % screen["name"])
        if args.record:
            with open(path, "w") as handle:
                handle.write(dump)
            print("  recorded %s" % os.path.relpath(path, REPO))
            continue
        # Always kept, pass or fail. A diff in a log is a diff you have to
        # reconstruct; the file is the thing you copy over the baseline once
        # you have decided the change was intended.
        with open(os.path.join(captured_dir, "%s.txt" % screen["name"]), "w") as handle:
            handle.write(dump)
        # A screenshot beside it, because "the anchor never appeared" is a
        # question about what was on screen, and CI has no screen to look at.
        run([
            "xcrun", "simctl", "io", udid, "screenshot",
            os.path.join(captured_dir, "%s.png" % screen["name"]),
        ], check=False)
        if not os.path.exists(path):
            failures.append((screen["name"], "no baseline; run with --record"))
            continue
        with open(path) as handle:
            expected = handle.read()
        if expected != dump:
            failures.append((screen["name"], unified_diff(expected, dump, screen["name"])))

    if not args.no_erase:
        run(["xcrun", "simctl", "shutdown", udid], check=False)

    if failures:
        for name, detail in failures:
            print("\n=== %s ===\n%s" % (name, detail), file=sys.stderr)
        sys.exit(
            "\n%d accessibility tree(s) drifted. What was captured (dumps and "
            "screenshots) is in %s.\nIf the change is intended, re-record: "
            "nine/scripts/ax-snapshot.py --record"
            % (len(failures), os.path.relpath(captured_dir, REPO))
        )
    print("\nall accessibility trees match their baselines")


def unified_diff(expected, actual, name):
    import difflib
    return "".join(difflib.unified_diff(
        expected.splitlines(keepends=True),
        actual.splitlines(keepends=True),
        fromfile="baseline/%s.txt" % name,
        tofile="captured/%s.txt" % name,
    ))


if __name__ == "__main__":
    main()
