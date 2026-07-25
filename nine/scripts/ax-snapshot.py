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
import subprocess
import sys
import time

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # nine/
BASELINES = os.path.join(REPO, "Tests", "AXBaselines")
FIXTURE = os.path.join(BASELINES, "fixture.nine.library.json")
BUNDLE_ID = "com.couchsuite.nine"

# The device type fixes the point geometry every frame in the baselines is
# measured in. Changing it invalidates all of them at once.
DEVICE_TYPE = "iPhone 17 Pro"
SIM_NAME = "Nine-AX"

# Probe budget, pinned: `describe-ui` finds elements by quadtree hit-testing, so
# these two knobs decide what it can reach. A board cell is ~40pt on this
# device, comfortably above the 14pt floor.
MIN_CELL_SIZE = "14"
MAX_PROBES = "400"

# `CouchStored` writes one JSON file per key under Application Support/CouchKit,
# prefixed `default.`. Seeding them before first launch is indistinguishable
# from a player who already had this state.
STORE_DIR = "Library/Application Support/CouchKit"

# Only the keys that would otherwise vary. `NinePrefs` decodes tolerantly
# (`decodeIfPresent … ?? default`), so a partial object is legal and every
# unlisted preference keeps its shipping default — which is the point: the
# baselines should photograph defaults, not a bespoke configuration.
PREFS_ERRORS_ON = {"errorHighlight": True, "resumeOnLaunch": True}
PREFS_ERRORS_OFF = {"errorHighlight": False, "resumeOnLaunch": True}


def run(args, check=True, capture=True):
    result = subprocess.run(
        args, check=False, capture_output=capture, text=True
    )
    if check and result.returncode != 0:
        sys.exit(
            "command failed: %s\n%s%s"
            % (" ".join(args), result.stdout or "", result.stderr or "")
        )
    return result.stdout if capture else ""


# ---------------------------------------------------------------- simulator


def newest_ios_runtime():
    data = json.loads(run(["xcrun", "simctl", "list", "runtimes", "--json"]))
    ios = [
        r for r in data["runtimes"]
        if r.get("isAvailable") and r.get("platform") == "iOS"
    ]
    if not ios:
        sys.exit("no iOS simulator runtime installed")
    ios.sort(key=lambda r: [int(p) for p in r["version"].split(".")])
    return ios[-1]


def device_type_id(name):
    data = json.loads(run(["xcrun", "simctl", "list", "devicetypes", "--json"]))
    for dt in data["devicetypes"]:
        if dt["name"] == name:
            return dt["identifier"]
    sys.exit("device type %r not installed" % name)


def prepare_simulator(runtime, name, erase=True):
    """A dedicated, erased simulator. Erasing is not politeness: a reused
    container can carry a previous session's library, and on a host signed into
    iCloud the cloud library will restore one into a fresh install."""
    data = json.loads(run(["xcrun", "simctl", "list", "devices", "--json"]))
    udid = None
    for devices in data["devices"].values():
        for device in devices:
            if device["name"] == name:
                udid = device["udid"]
    if udid is None:
        udid = run([
            "xcrun", "simctl", "create", name,
            device_type_id(DEVICE_TYPE), runtime["identifier"],
        ]).strip()
        print("created simulator %s (%s)" % (name, udid))
    elif erase:
        run(["xcrun", "simctl", "shutdown", udid], check=False)
        run(["xcrun", "simctl", "erase", udid])
    run(["xcrun", "simctl", "boot", udid], check=False)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture=False)
    # Pin the appearance: `.auto` themes follow it, and a mid-run switch would
    # rewrite colours (harmless to the tree, but it also re-renders the board).
    run(["xcrun", "simctl", "ui", udid, "appearance", "light"], check=False)
    warm_up_bridge(udid)
    return udid


def warm_up_bridge(udid, timeout=300.0):
    """`simctl bootstatus` returning is not the same as the accessibility
    bridge being up. On a freshly erased simulator the gap is minutes, and every
    probe in it answers "No translation object returned for simulator" — which
    reads exactly like a collapsed tree. Wait for a real answer before the first
    screen, so a slow boot can never be mistaken for a regression."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if describe(udid, tolerate=True) is not None:
            return
        time.sleep(2.0)
    sys.exit(
        "the simulator's accessibility bridge never answered in %ds — nothing "
        "can be snapshotted, and this is not a Nine regression" % int(timeout)
    )


def build_and_install(udid, app_path):
    if app_path is None:
        print("building for the snapshot simulator…")
        run([
            "xcodebuild", "-project", os.path.join(REPO, "Nine.xcodeproj"),
            "-scheme", "Nine", "-destination", "id=%s" % udid,
            "-derivedDataPath", os.path.join(REPO, "build"), "build",
        ])
        app_path = os.path.join(
            REPO, "build", "Build", "Products", "Debug-iphonesimulator", "Nine.app"
        )
    if not os.path.isdir(app_path):
        sys.exit("no app bundle at %s" % app_path)
    run(["xcrun", "simctl", "install", udid, app_path])
    return app_path


def seed(udid, prefs):
    """Write the frozen library and the fixed chrome state into the container."""
    container = run([
        "xcrun", "simctl", "get_app_container", udid, BUNDLE_ID, "data"
    ]).strip()
    store = os.path.join(container, STORE_DIR)
    os.makedirs(store, exist_ok=True)
    with open(FIXTURE) as handle:
        library = handle.read()
    blobs = {
        "default.nine.library.json": library,
        "default.nine.prefs.json": json.dumps(prefs, sort_keys=True),
        # The first run is a first-launch screen; the baselines are of the app.
        # Both flags, because they are independent: `help.seen` alone would
        # still raise the welcome ledger over the shelf (PRD-18).
        "default.help.seen.json": "true",
        "default.welcome.seen.json": "true",
        # Past the drawer grabber's three-session budget, and found anyway —
        # the one piece of chrome designed to vanish is already gone.
        "default.nine.sessionCount.json": "9",
        "default.nine.drawerFound.json": "true",
        # The three lifetime tips, all spent. A tip is triggered by ordinary
        # play (placements, a wrong digit standing), and the game baselines are
        # captured on a mid-game board — so an unspent budget would put a glass
        # slab in the tree on whichever screen happened to cross a threshold.
        "default.nine.tips.json": json.dumps(
            {"shown": ["undo", "pencil", "highlight"]}, sort_keys=True
        ),
    }
    for name, body in blobs.items():
        with open(os.path.join(store, name), "w") as handle:
            handle.write(body)


# ------------------------------------------------------------------ driving


def describe(udid, point=None, tolerate=False):
    """One `describe-ui` call.

    `tolerate` returns None instead of exiting, and every polling caller uses
    it: the simulator's accessibility bridge is not up the instant the app is.
    A freshly erased simulator answers the first few probes with "No translation
    object returned for simulator" and then works for the rest of the run.
    Hard-failing on that is how a lane like this earns its reputation as flaky
    and gets deleted six weeks later."""
    args = [
        "sim-use", "describe-ui", "--device", udid, "--json",
        "--min-cell-size", MIN_CELL_SIZE, "--max-probes", MAX_PROBES,
    ]
    if point:
        args += ["--point", "%d,%d" % point]
    result = subprocess.run(args, check=False, capture_output=True, text=True)
    out = result.stdout or ""
    payload = None
    try:
        payload = json.loads(out)
    except ValueError:
        pass
    if payload and payload.get("ok"):
        return payload["data"]
    if tolerate:
        return None
    sys.exit("describe-ui failed: %s%s" % (out[:400], result.stderr or ""))


def wait_for(udid, label, timeout=40.0):
    """Poll until `label` is in the tree, tolerating a not-yet-ready bridge."""
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        data = describe(udid, tolerate=True)
        if data is not None:
            last = data
            if any(e.get("label") == label for e in data["entries"]):
                # One more settle pass: the label can appear mid-transition,
                # with frames still animating toward their resting values.
                time.sleep(0.6)
                return describe(udid)
        time.sleep(0.5)
    seen = sorted({e.get("label", "") for e in (last or {}).get("entries", [])})
    hint = ""
    if label.startswith("Row ") and not any(s.startswith("Row ") for s in seen):
        hint = (
            "\n\nNot one board cell is in the tree, but the chrome is — this is "
            "the PRD-19 regression itself: the Canvas's `.accessibilityChildren` "
            "have collapsed and the board is a blank rectangle to VoiceOver. "
            "Start at Sources/App/BoardAccessibility.swift.\n"
        )
    sys.exit(
        "timed out waiting for %r. Tree was:\n%s%s"
        % (label, "\n".join(seen) if seen else "(nothing — the bridge never answered)", hint)
    )


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


def tap(udid, data, label):
    """Tap the centre of `label`'s frame, using the tree we already hold.

    `sim-use tap --label` looks the element up in a *fresh* AX round-trip, and
    that round-trip is the flakiest part of the whole pipeline — it intermittently
    reports "no accessibility element matched" for a button that a dump one
    second earlier and one second later both list. Resolving the point from the
    tree we just read is one fewer thing that can be briefly not there; the
    coordinates are never stale, because they came from the frame we are acting
    on."""
    entry = next((e for e in data["entries"] if e.get("label") == label), None)
    if entry is None:
        sys.exit("cannot tap %r — not in the tree" % label)
    frame = entry["frame"]
    run([
        "sim-use", "tap", "--device", udid,
        "-x", str(int(frame["x"] + frame["width"] / 2)),
        "-y", str(int(frame["y"] + frame["height"] / 2)),
    ])


def relaunch(udid, prefs):
    run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], check=False)
    wait_until_dead(udid)
    seed(udid, prefs)
    run(["xcrun", "simctl", "launch", udid, BUNDLE_ID])


def wait_until_dead(udid, timeout=20.0):
    """`simctl terminate` returns when the *request* is sent, not when the
    process is gone — and `CouchStored` flushes on a 0.6 s debounce and again,
    best-effort, from `deinit`. Seed into that window and a dying Nine can
    rewrite `default.nine.prefs.json` on top of what was just written.

    The symptom would be `game-quiet` intermittently photographing
    `errorHighlight: true` — "9, wrong" where the baseline says "9" — which
    reads exactly like the privacy regression that baseline exists to catch.
    Nothing is worth a tripwire that cries wolf about that."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        listing = run(
            ["xcrun", "simctl", "spawn", udid, "launchctl", "list"], check=False
        )
        if BUNDLE_ID not in listing:
            return
        time.sleep(0.3)
    print("  warning: %s still listed after %ds; seeding anyway"
          % (BUNDLE_ID, int(timeout)))


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

_SIM_USE_VERSION = []


def sim_use_version():
    """In the header for the same reason the runtime is: `describe-ui`'s output
    is the measuring instrument, and CI installs whatever version Homebrew has
    today. A tool bump that changes the shape of a dump should announce itself
    on line two rather than as an unexplained diff on every screen."""
    if not _SIM_USE_VERSION:
        result = subprocess.run(
            ["sim-use", "--version"], check=False, capture_output=True, text=True
        )
        _SIM_USE_VERSION.append((result.stdout or "?").strip() or "?")
    return _SIM_USE_VERSION[0]


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
        dict(name="home", prefs=PREFS_ERRORS_ON, taps=["Home"],
             anchor="How to play", probe=False),
    ]


def first_empty_label(targets):
    for kind, index in targets:
        if kind == "empty" and index is not None:
            return cell_label(index)
    sys.exit("the frozen board has no empty cell to open the rose on")


def capture(udid, screen, targets, runtime):
    relaunch(udid, screen["prefs"])
    data = wait_for(udid, "Row 1, column 1")
    for step in screen["taps"]:
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

    runtime = newest_ios_runtime()
    print("runtime: %s  device: %s" % (runtime["name"], DEVICE_TYPE))
    udid = prepare_simulator(runtime, SIM_NAME, erase=not args.no_erase)
    build_and_install(udid, args.app)

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
