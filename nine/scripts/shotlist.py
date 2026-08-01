#!/usr/bin/env python3
"""The visual lane: every Nine surface, photographed the same way twice.

The three older harnesses read the *accessibility tree* (`ax-snapshot.py`), the
*composited pixels under a cell* (`contrast-harness.py`) or *strings in a
locale* (`loc-harness.py`). None of them can answer "does this screen look
good", because none of them ever keeps the picture.

This one keeps the picture and nothing else. It drives to a named surface on a
named device in a named appearance, screenshots it as PNG, and writes it to a
directory a human — or a critic with eyes — can page through. There are no
baselines and no gates: a screenshot diff of a Liquid Glass surface is noise
(the material samples a live blur), and a lane that cries wolf on noise gets
deleted. What this lane produces is *evidence*, and the judgement stays with
the reader.

Determinism comes from `ninestate.py`, the same seeded container the AX and
contrast lanes photograph against — a frozen board, the first run already
seen, the tip budget already spent. Without it every shot would show *today's*
daily and a scatter of transient chrome, and two runs an hour apart would not
be comparable.

    scripts/shotlist.py --list
    scripts/shotlist.py --device iphone --appearance dark
    scripts/shotlist.py --scenes home,game,rose --device both --appearance both
"""

import argparse
import json
import os
import subprocess
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import ninestate
import simrig
from simrig import run

REPO = ninestate.REPO
BUNDLE_ID = "com.couchsuite.nine"

# Two devices, deliberately not five. The compositions that actually differ are
# "one column" and "the regular-width split" (`BoardCompositionRules`), and
# these two straddle that boundary. Adding an iPhone 17 Pro Max would double
# the runtime to re-photograph the same layout 40pt wider.
DEVICES = {
    "iphone": dict(device_type="iPhone 17 Pro", sim_name="Nine-Shotlist-iPhone",
                   scale=3),
    "ipad": dict(device_type="iPad Pro 11-inch (M5)", sim_name="Nine-Shotlist-iPad",
                 scale=2),
}

APPEARANCES = ("light", "dark")


# ---------------------------------------------------------------- the scenes
#
# A scene is a name, the prefs it needs, and the taps to get there from a fresh
# launch. Every scene relaunches rather than navigating back, for the reason
# `ax-snapshot.py` gives: no scene should inherit another's transient state —
# a toast that has not yet faded is exactly the kind of thing a critic would
# (correctly) call a defect, and exactly the kind of thing that is not one.
#
# `anchor` is the label whose appearance means the surface has arrived. It is
# waited for, not slept on, because a fixed sleep either flakes or is slow.

PREFS_ON = ninestate.PREFS_ERRORS_ON

#
# `resumeOnLaunch` is on in the quiet fixture, so a launch lands on the *board*
# and every shelf scene starts with a "Home" tap. That is not incidental: it is
# the path a returning player takes, so the shelf is always photographed as it
# is actually reached rather than as a cold start nobody sees twice.

SCENES = [
    dict(name="game", taps=[], anchor="Row 9, column 9",
         note="The board mid-game, mistake-marking on. The app's centre of gravity."),
    dict(name="rose", taps=["FIRST_EMPTY"], anchor="Place 1",
         note="The flick rose open over a cell — Nine's signature gesture."),
    dict(name="prefs", taps=["Settings"], anchor="Resume on launch",
         note="The preferences sheet."),
    dict(name="home", taps=["Home"], anchor="Classic, page 1 of 3",
         note="The shelf at rest — the app's front door."),
    dict(name="home-bottom", taps=["Home", "SCROLL_BOTTOM"], anchor="How to play",
         note="The deep end of the shelf: variants, learn row, records, School."),
    dict(name="channel", taps=["Home", "Next channel"], anchor="Thermo, page 2 of 3",
         note="A variant channel page (PRD-24)."),
    dict(name="history", taps=["Home", "SCROLL_BOTTOM", "History"],
         # Two, because the compact sheet and the regular-width panel show
         # different empty states — see `wait_for_any`.
         anchor=("Join the table",
                 "Solve a board and it lands here \u2014 time, difficulty and points."),
         note="The History sheet and the daily table (PRD-29)."),
    dict(name="school", taps=["Home", "SCROLL_BOTTOM", "Technique School"],
         anchor="Technique School",
         note="The Technique School index (PRD-25)."),
    dict(name="tutorial", taps=["Home", "SCROLL_BOTTOM", "How to play"],
         anchor="How to play",
         note="The tutorial's first page."),
]

SCENES_BY_NAME = {s["name"]: s for s in SCENES}


# ------------------------------------------------------------------ driving


def first_empty_label(_data):
    """The first cell the frozen fixture leaves empty, as its AX label.

    Read out of the fixture rather than out of the live tree, because a cell's
    emptiness is not in its label — `BoardSpeech` puts "Row 9, column 9" in the
    label and the digit (or its absence) in the *value*, which `describe-ui`
    does not carry. `ax-snapshot.py` resolves the same question the same way
    against the same file, so a re-freeze moves both lanes together.
    """
    with open(ninestate.FIXTURE) as handle:
        game = json.load(handle)["entries"][0]["game"]
    current = game["entries"]
    current = current["cells"] if isinstance(current, dict) else current
    pencil = game["pencil"]
    cells = pencil["cells"] if isinstance(pencil, dict) else pencil
    for index in range(81):
        noted = bool(cells[index]) if index < len(cells) else False
        if current[index] == 0 and not noted:
            return "Row %d, column %d" % (index // 9 + 1, index % 9 + 1)
    sys.exit("the frozen board has no empty cell — the rose has nothing to open on")


def point_size(udid, scale):
    """The device's logical size, from a throwaway screenshot.

    `ax-snapshot.py` can hard-code its swipe at x=200 because it only ever runs
    on one device in one orientation. This lane runs on four geometries, and a
    swipe measured for a 402pt-wide phone lands 200pt left of centre on a
    landscape iPad — where it still scrolls, which is the dangerous part: the
    shot looks plausible and is of the wrong scroll offset.
    """
    import struct
    path = "/tmp/nine-shotlist-probe.png"
    run(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", path])
    with open(path, "rb") as handle:
        header = handle.read(24)
    width, height = struct.unpack(">II", header[16:24])
    return width / scale, height / scale


def scroll_to_bottom(udid, size, swipes=3):
    """Flick up until the scroll view is against its bottom stop.

    Short repeated swipes rather than one fling, copied from `ax-snapshot.py`
    for the same reason: momentum stops somewhere non-deterministic, a hard
    stop does not.
    """
    width, height = size
    x = int(width / 2)
    for _ in range(swipes):
        run(["sim-use", "swipe", "--device", udid,
             "--start-x", str(x), "--start-y", str(int(height * 0.80)),
             "--end-x", str(x), "--end-y", str(int(height * 0.25)),
             "--duration", "0.35"])
        time.sleep(0.6)


def verify_tap_space(udid, fb_size, landscape=False):
    """Prove that a tap lands where the accessibility tree says it will.

    `sim-use tap` acts in the device's fixed framebuffer space; `describe-ui`
    reports frames in the app's *rotated* logical space. On any orientation but
    upright portrait the two disagree, and every tap lands somewhere else —
    silently. A simulator left in portrait-upside-down mirrors each tap to
    `(W - x, H - y)`, so a tap aimed at a board cell lands on a keypad key two
    thirds of the way down the screen: the cursor moves, the board reacts, and
    the surface under test never appears.

    **That cost a full false-positive bug hunt**, complete with a corroborating
    second symptom — the probes `describe-ui` uses are themselves hit-tests, so
    they miss in the mirrored space too, and a modal surface then reports as
    four status-bar entries, which reads exactly like a collapsed tree. Two
    independent artefacts of one root cause, both mimicking real app bugs.

    Detecting this from pixels does not work: the obvious signal is "which edge
    carries the status bar", and on a light theme the whole frame is bright, so
    the strips are indistinguishable. What cannot be fooled is doing it and
    looking: tap a control whose effect is unambiguous and see whether the
    effect happened. If it did not, the tap space is mirrored — turn the device
    half a turn and try once more.
    """
    # Portrait keeps the original behaviour exactly: assume the tap space is the
    # tree's own, and if that fails the device really is upside down — which a
    # coordinate flip must NOT paper over, because the *screenshots* would be
    # upside down too. There the physical half-turn is the fix.
    #
    # Landscape is a different failure and needs a different remedy. There the
    # framebuffer stays portrait while the app does not, so the two spaces are a
    # quarter turn apart — an error no half-turn can cancel, which is why this
    # preflight used to exhaust both attempts and refuse the run. Which of the
    # two landscapes it is cannot be predicted, so both are tried and whichever
    # actually lands is registered.
    candidates = ["cw", "ccw"] if landscape else ["identity", "identity"]
    for attempt, space in enumerate(candidates):
        simrig.set_tap_space(udid, space, fb_size)
        simrig.relaunch(udid, BUNDLE_ID, ninestate.quiet_blobs(PREFS_ON))
        data = simrig.wait_for(udid, "Row 1, column 1")
        entry = next((e for e in data["entries"] if e.get("label") == "Settings"), None)
        if entry is None:
            sys.exit("no Settings control on the board screen — the app changed "
                     "shape and this preflight needs a new probe")
        simrig.tap(udid, data, "Settings")
        deadline = time.time() + 10.0
        while time.time() < deadline:
            probe = simrig.describe(udid, tolerate=True) or {"entries": []}
            if any(e.get("label") == "Resume on launch" for e in probe["entries"]):
                simrig.run(["xcrun", "simctl", "terminate", udid, BUNDLE_ID], check=False)
                print("  taps land: tap space %r" % space)
                return
            time.sleep(0.5)
        if attempt == 0 and not landscape:
            print("  taps are not landing where the tree says — turning the device "
                  "half a turn and retrying")
            rotate_half_turn(udid)
        elif attempt == 0:
            print("  taps are not landing where the tree says — trying the other "
                  "landscape's tap space")
    sys.exit(
        "taps do not land where the accessibility tree reports, in either of the "
        "two %s tried. Every screenshot from this run would be of the "
        "wrong taps, so nothing is captured. Check the simulator is not in a "
        "landscape or upside-down orientation, and that Simulator.app has "
        "Accessibility permission for synthetic clicks."
        % ("tap spaces" if landscape else "orientations")
    )


def rotate_half_turn(udid):
    """Two quarter-turns, by name, on whichever simulator owns `udid`."""
    name = None
    data = json.loads(run(["xcrun", "simctl", "list", "devices", "--json"]))
    for devices in data["devices"].values():
        for device in devices:
            if device["udid"] == udid:
                name = device["name"]
    if name is None:
        sys.exit("cannot name the simulator for %s" % udid)
    script = """
    tell application "Simulator" to activate
    delay 0.6
    tell application "System Events" to tell process "Simulator"
      set w to first window whose name contains "%s"
      set {wx, wy} to position of w
      set {ww, wh} to size of w
    end tell
    tell application "System Events" to click at {wx + (ww / 2), wy + 12}
    delay 0.6
    repeat 2 times
      tell application "System Events" to tell process "Simulator"
        click menu item "Rotate Left" of menu 1 of menu bar item "Device" of menu bar 1
      end tell
      delay 2
    end repeat
    """ % name
    run(["osascript", "-e", script], check=False)


def straighten(path):
    """Turn a landscape screenshot upright, by measurement rather than by rule.

    `simctl io screenshot` always photographs the framebuffer in the device's
    *native* orientation, so a landscape iPad comes back as a portrait PNG with
    the content on its side — and there are **two** landscapes, needing opposite
    corrections. Nothing in `simctl` or in the accessibility tree reports which
    one the device is in: `describe-ui` gives frames in interface points, where
    the clock sits at y≈20 in both.

    **Predicting the turn from the framebuffer does not work, and this function
    is the second attempt.** The first measured which long edge carried the
    status bar and mapped that to a rotation direction; it was reasoned
    correctly and still produced upside-down frames, because the device also
    turns *between* the probe and the shot. So this one does not predict. It
    turns the picture, then checks the picture, and turns it again if the check
    fails — a loop that cannot be wrong about its own output.

    The check: the status bar is a strip of bright glyphs along the interface's
    top edge, and the opposite edge carries only the home indicator. Whichever
    of the two horizontal strips is brighter is the top. That is the worst kind
    of bug to leave to a rule — the file is there, it is the right scene, and
    every judgement made from it is made upside down.
    """
    from PIL import Image

    def brighter_half(image):
        width, height = image.size
        band = max(8, int(height * 0.035))
        top = image.crop((0, 0, width, band))
        bottom = image.crop((0, height - band, width, height))
        lit = lambda tile: sum(1 for pixel in tile.getdata() if pixel > 180)
        return lit(top), lit(bottom)

    image = Image.open(path).convert("L")
    if image.size[0] < image.size[1]:
        run(["sips", "-r", "90", path])
        image = Image.open(path).convert("L")
    top, bottom = brighter_half(image)
    if bottom > top:
        run(["sips", "-r", "180", path])


def shoot(udid, path, rotate=False):
    """PNG, not the BMP the contrast lane insists on.

    That lane reads individual pixel values, so it cannot afford even lossless
    re-encoding ambiguity. This one is read by eyes and by models, both of which
    want a file they can open — and a 12 MB BMP per shot across 4 devices ×
    2 appearances × 9 scenes is 800 MB of evidence nobody will page through.

    `rotate` because `simctl io screenshot` photographs the framebuffer in the
    device's *native* orientation regardless of how the device is held: a
    landscape iPad comes back as a portrait PNG with the content lying on its
    side. Nothing downstream should have to know that, so it is straightened
    here and every consumer sees an upright picture.
    """
    os.makedirs(os.path.dirname(path), exist_ok=True)
    run(["xcrun", "simctl", "io", udid, "screenshot", "--type=png", path])
    if rotate:
        straighten(path)


# ------------------------------------------------------------- orientation


def rotate_device(udid, sim_name, landscape):
    """Rotate a simulator by driving Simulator.app's own Device menu.

    There is no `simctl` verb for this — orientation lives in the Simulator UI,
    not in the device — so this is AppleScript or nothing, and the drafting
    table (PRD-31) is an iPad-*landscape* composition that no other harness in
    this repo can reach.

    **The window must be clicked, not merely raised.** `AXRaise` reorders the
    windows and leaves key focus where it was, so the Device menu keeps acting
    on whichever simulator was already frontmost — measured: three attempts in
    a row rotated nothing, and a fourth rotated the wrong device. Clicking the
    title bar is what makes the menu's implicit target the window we mean.

    Named rather than by udid because the window title is the only handle
    AppleScript has on a simulator.
    """
    script = """
    tell application "Simulator" to activate
    delay 0.8
    tell application "System Events" to tell process "Simulator"
      set w to first window whose name contains "%s"
      set {wx, wy} to position of w
      set {ww, wh} to size of w
    end tell
    tell application "System Events" to click at {wx + (ww / 2), wy + 12}
    delay 0.8
    tell application "System Events" to tell process "Simulator"
      click menu item "Rotate Left" of menu 1 of menu bar item "Device" of menu bar 1
    end tell
    delay 2.5
    tell application "System Events" to tell process "Simulator"
      get size of (first window whose name contains "%s")
    end tell
    """ % (sim_name, sim_name)

    # Up to four quarter-turns rather than one, because the menu item is a
    # *relative* rotation and the device's current orientation is not knowable
    # up front: a simulator left landscape by a previous run takes "Rotate Left"
    # to upside-down portrait, which is the shape this asked for the opposite of.
    # Turning until the window has the aspect we want is the only formulation
    # that is correct from every starting pose.
    for _ in range(4):
        out = run(["osascript", "-e", script], check=False) or ""
        parts = [p.strip() for p in out.strip().split(",")]
        if len(parts) != 2 or not all(p.replace(".", "").isdigit() for p in parts):
            break
        # Aspect only. Portrait and portrait-upside-down are the same shape,
        # so this cannot tell them apart — `verify_tap_space` settles that by
        # doing a tap and checking it landed.
        if (float(parts[0]) > float(parts[1])) == landscape:
            return
    sys.exit(
        "the simulator never reached %s after four quarter-turns. Simulator.app "
        "needs Accessibility permission for synthetic clicks; without it this "
        "fails silently and every landscape shot would be a portrait one under a "
        "landscape filename." % ("landscape" if landscape else "portrait")
    )


def wait_for_any(udid, anchors, timeout=40.0):
    """Poll until *any* of `anchors` is in the tree.

    A single anchor per scene was enough while every surface looked the same on
    every width. It stopped being enough at the History sheet: the phone's
    compact sheet and the iPad's regular-width panel show **different empty
    states**, so no one label is present on both, and the phone run timed out on
    a label the iPad run had just matched. Listing the alternatives is honest
    about that; picking a lowest-common-denominator label like the sheet grabber
    would only prove that *a* sheet arrived.
    """
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        data = simrig.describe(udid, tolerate=True)
        if data is not None:
            last = data
            labels = {e.get("label") for e in data["entries"]}
            if labels & set(anchors):
                time.sleep(0.6)
                return simrig.describe(udid)
        time.sleep(0.5)
    seen = sorted(l for l in {e.get("label", "") for e in (last or {}).get("entries", [])} if l)
    sys.exit("timed out waiting for any of %s. Tree was:\n%s"
             % (list(anchors), "\n".join(seen) or "(nothing — the bridge never answered)"))


def settle(udid, anchor, tries=8, pause=0.7):
    """Wait for `anchor`, then wait for the frames under it to stop moving.

    Arriving is not the same as having arrived. A sheet's anchor label enters
    the tree the instant the presentation begins, and a screenshot taken then
    photographs a half-presented sheet at 60% scale — which reads, to a critic,
    as a badly designed modal rather than as a race in the harness.
    """
    data = wait_for_any(udid, anchor if isinstance(anchor, tuple) else (anchor,))
    previous = None
    for _ in range(tries):
        frames = sorted(
            (e.get("label", ""), tuple(sorted(e["frame"].items())))
            for e in data["entries"]
        )
        if frames == previous:
            return data
        previous = frames
        time.sleep(pause)
        data = simrig.describe(udid)
    return data


def capture(udid, scene, out_dir, device_key, appearance, size, turn):
    simrig.relaunch(udid, BUNDLE_ID, ninestate.quiet_blobs(PREFS_ON))
    data = simrig.wait_for(udid, "Row 1, column 1")

    for step in scene["taps"]:
        if step == "SCROLL_BOTTOM":
            scroll_to_bottom(udid, size)
            data = simrig.describe(udid)
            continue
        label = first_empty_label(data) if step == "FIRST_EMPTY" else step
        data = simrig.wait_for(udid, label)
        simrig.tap(udid, data, label)
        time.sleep(0.5)

    settle(udid, scene["anchor"])
    suffix = "-landscape" if turn else ""
    path = os.path.join(
        out_dir, "%s%s-%s-%s.png" % (device_key, suffix, appearance, scene["name"]))
    shoot(udid, path, rotate=turn)
    return path


# ------------------------------------------------------------------- entry


def build(udid, derived):
    print("building for %s…" % udid)
    run([
        "xcodebuild", "-project", os.path.join(REPO, "Nine.xcodeproj"),
        "-scheme", "Nine", "-destination", "id=%s" % udid,
        "-configuration", "Debug",
        "-derivedDataPath", os.path.join(REPO, derived), "build",
        "CODE_SIGNING_ALLOWED=NO",
    ])
    return os.path.join(
        REPO, derived, "Build", "Products", "Debug-iphonesimulator", "Nine.app"
    )


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--device", default="iphone",
                        choices=list(DEVICES) + ["both"])
    parser.add_argument("--appearance", default="dark",
                        choices=list(APPEARANCES) + ["both"])
    parser.add_argument("--scenes", default="all",
                        help="comma-separated scene names, or 'all'")
    parser.add_argument("--out", default=os.path.join(REPO, "..", ".context", "shots"),
                        help="where the PNGs land")
    parser.add_argument("--no-erase", action="store_true",
                        help="reuse the simulator's container (faster, less pure)")
    parser.add_argument("--no-build", action="store_true",
                        help="install whatever is already in the derived data")
    parser.add_argument("--derived", default=".build/shots")
    parser.add_argument("--landscape", action="store_true",
                        help="rotate the device first — the only way to reach the "
                             "iPad drafting table (PRD-31)")
    parser.add_argument("--list", action="store_true", help="print the scenes and exit")
    args = parser.parse_args()

    if args.list:
        for scene in SCENES:
            print("%-14s %s" % (scene["name"], scene["note"]))
        return

    scenes = SCENES if args.scenes == "all" else [
        SCENES_BY_NAME[n] for n in args.scenes.split(",")
        if n in SCENES_BY_NAME or sys.exit("unknown scene %r" % n)
    ]
    devices = list(DEVICES) if args.device == "both" else [args.device]
    appearances = list(APPEARANCES) if args.appearance == "both" else [args.appearance]

    out_dir = os.path.abspath(args.out)
    runtime = simrig.newest_ios_runtime()
    written = []

    for device_key in devices:
        spec = DEVICES[device_key]
        udid = simrig.prepare_simulator(
            runtime, spec["sim_name"], spec["device_type"],
            erase=not args.no_erase, appearance=appearances[0],
        )
        app_path = None if not args.no_build else os.path.join(
            REPO, args.derived, "Build", "Products", "Debug-iphonesimulator", "Nine.app"
        )
        if app_path is None:
            app_path = build(udid, args.derived)
        run(["xcrun", "simctl", "install", udid, app_path])

        turn = args.landscape
        # **Unconditional, not only when `--landscape` was asked for.** A
        # simulator left rotated by a previous run mirrors every tap against the
        # accessibility tree without erroring, so a plain portrait run on a
        # simulator someone else rotated silently photographs the wrong taps.
        # Correcting to upright portrait costs one screenshot when it is already
        # right, and it is the difference between a harness and a rumour.
        rotate_device(udid, spec["sim_name"], landscape=bool(args.landscape))
        # Measured before the preflight, not after: the preflight needs the
        # framebuffer's own size to convert a logical point into a tap, and the
        # framebuffer stays portrait even when the app is landscape.
        fb_size = point_size(udid, spec["scale"])
        verify_tap_space(udid, fb_size, landscape=bool(args.landscape))
        size = (fb_size[1], fb_size[0]) if args.landscape else fb_size
        for appearance in appearances:
            run(["xcrun", "simctl", "ui", udid, "appearance", appearance], check=False)
            for scene in scenes:
                path = capture(udid, scene, out_dir, device_key, appearance,
                               size, turn)
                print("  %s" % path)
                written.append(path)
        if args.landscape:
            rotate_device(udid, spec["sim_name"], landscape=False)

    index = os.path.join(out_dir, "index.json")
    with open(index, "w") as handle:
        json.dump({
            "runtime": runtime["version"],
            "sim_use": simrig.sim_use_version(),
            "shots": [os.path.basename(p) for p in written],
            "scenes": {s["name"]: s["note"] for s in scenes},
        }, handle, indent=2, sort_keys=True)
    print("\n%d shots in %s" % (len(written), out_dir))


if __name__ == "__main__":
    main()
