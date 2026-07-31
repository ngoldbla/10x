"""The simulator rig two Nine harnesses share.

`ax-snapshot.py` grew this machinery first — create a dedicated simulator, erase
it, wait for the accessibility bridge, seed the container before first launch,
poll `describe-ui` until a label appears, tap from a tree you already hold. Every
one of those pieces exists because of a specific way the naive version was flaky,
and the comments below are the record of which.

PRD-22's contrast harness needs all of it and none of the baselines, so it lives
here rather than being copied. The three things that were module constants are
arguments now: the device type, the bundle id, and the repo root.

Nothing in this file knows what is being measured.
"""

import json
import subprocess
import sys
import time

# `CouchStored` writes one JSON file per key under Application Support/CouchKit,
# prefixed `default.`. Seeding them before first launch is indistinguishable
# from a player who already had this state.
STORE_DIR = "Library/Application Support/CouchKit"

# Probe budget, pinned: `describe-ui` finds elements by quadtree hit-testing, so
# these two knobs decide what it can reach. A board cell is ~40pt on an iPhone 17
# Pro, comfortably above the 14pt floor.
MIN_CELL_SIZE = "14"
MAX_PROBES = "400"


def run(args, check=True, capture=True):
    result = subprocess.run(args, check=False, capture_output=capture, text=True)
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


def prepare_simulator(runtime, name, device_type, erase=True, appearance="light"):
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
            device_type_id(device_type), runtime["identifier"],
        ]).strip()
        print("created simulator %s (%s)" % (name, udid))
    elif erase:
        run(["xcrun", "simctl", "shutdown", udid], check=False)
        run(["xcrun", "simctl", "erase", udid])
    run(["xcrun", "simctl", "boot", udid], check=False)
    run(["xcrun", "simctl", "bootstatus", udid, "-b"], capture=False)
    # Pin the appearance: `.auto` themes follow it, and a mid-run switch would
    # rewrite colours (harmless to the tree, but it also re-renders the board).
    if appearance:
        run(["xcrun", "simctl", "ui", udid, "appearance", appearance], check=False)
    pin_status_bar(udid)
    warm_up_bridge(udid)
    return udid


def pin_status_bar(udid):
    """Freeze the clock, the carrier and the meters at their demo values.

    **Every lane that records a baseline records the status bar with it**, and
    an unpinned clock makes those baselines rot by the minute. Measured: a
    verify run half an hour after its own recording drifted two screens on
    nothing but `StaticText "3:27 PM"` → `"4:10 PM"` — and the *frame* moved with
    the text (36x20 → 35x20, 37x20 → 32x20), because a different time is a
    different string width. So this is not something the AX lane's `mask()` can
    absorb: masking hides the characters and leaves the geometry drifting.

    9:41 is Apple's own demo time, which also makes the visual lane's frames
    look like the marketing shots they are meant to be judged against.

    Applied in `simrig` rather than in any one harness because all four lanes —
    the AX tree, the composited-contrast matrix, the localization baselines and
    the shotlist — boot through this function and all four record the bar.
    """
    run(["xcrun", "simctl", "status_bar", udid, "override",
         "--time", "9:41",
         "--dataNetwork", "wifi",
         "--wifiMode", "active",
         "--wifiBars", "3",
         "--cellularMode", "active",
         "--cellularBars", "4",
         "--batteryState", "charged",
         "--batteryLevel", "100"], check=False)


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


def build_and_install(udid, app_path, repo, derived="build"):
    import os
    if app_path is None:
        print("building for the snapshot simulator…")
        run([
            "xcodebuild", "-project", os.path.join(repo, "Nine.xcodeproj"),
            "-scheme", "Nine", "-destination", "id=%s" % udid,
            "-derivedDataPath", os.path.join(repo, derived), "build",
        ])
        app_path = os.path.join(
            repo, derived, "Build", "Products", "Debug-iphonesimulator", "Nine.app"
        )
    if not os.path.isdir(app_path):
        sys.exit("no app bundle at %s" % app_path)
    run(["xcrun", "simctl", "install", udid, app_path])
    return app_path


def seed(udid, bundle_id, blobs):
    """Write `blobs` (filename → body) into the app's CouchStored directory."""
    import os
    container = run([
        "xcrun", "simctl", "get_app_container", udid, bundle_id, "data"
    ]).strip()
    store = os.path.join(container, STORE_DIR)
    os.makedirs(store, exist_ok=True)
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


def wait_for(udid, label, timeout=40.0, hint_for_missing_board=True):
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
    if not seen:
        # The accessibility bridge never answered, which is a *machine* problem
        # and not a Nine one. Saying otherwise is how a lane earns its
        # reputation for crying wolf: this exact path once printed the PRD-19
        # board-collapse hint below on a contended host that simply never got
        # a dump back, which reads as the one regression the lane exists for.
        hint = (
            "\n\nThe tree was empty on every read, so this is the bridge and not "
            "the app: nothing was reachable, not even the chrome. Re-run when the "
            "host is quieter, or without --no-erase so the bridge is warmed from "
            "a known state.\n"
        )
    elif (hint_for_missing_board and label.startswith("Row ")
            and not any(s.startswith("Row ") for s in seen)):
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


def relaunch(udid, bundle_id, blobs, args=()):
    """Terminate, reseed, launch — optionally with launch arguments.

    `args` is how the localization lane selects a language, a pseudolanguage or
    a right-to-left layout: those are launch arguments, not build settings, so
    the same installed binary answers for every mode. It is the last parameter
    and defaults to empty because the two older lanes pass none.

    There must be exactly one launch path. `ax-snapshot.py` used to inline these
    four steps itself, and a copy that cannot pass arguments is not a harmless
    duplicate: a loc harness built on it would drop every mode flag silently and
    record five baselines of an ordinary English build that look entirely
    plausible. No error, no symptom, no way to tell from the output."""
    run(["xcrun", "simctl", "terminate", udid, bundle_id], check=False)
    wait_until_dead(udid, bundle_id)
    seed(udid, bundle_id, blobs)
    run(["xcrun", "simctl", "launch", udid, bundle_id, *args])


def wait_until_dead(udid, bundle_id, timeout=20.0):
    """`simctl terminate` returns when the *request* is sent, not when the
    process is gone — and `CouchStored` flushes on a 0.6 s debounce and again,
    best-effort, from `deinit`. Seed into that window and a dying Nine can
    rewrite `default.nine.prefs.json` on top of what was just written.

    For the AX lane the symptom would be `game-quiet` intermittently
    photographing `errorHighlight: true`; for the contrast lane it is a cell
    measured against the *previous* theme, which reads as a retune that did
    nothing. Nothing is worth a tripwire that cries wolf about either."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        listing = run(
            ["xcrun", "simctl", "spawn", udid, "launchctl", "list"], check=False
        )
        if bundle_id not in listing:
            return
        time.sleep(0.3)
    print("  warning: %s still listed after %ds; seeding anyway"
          % (bundle_id, int(timeout)))


def sim_use_version(_cache=[]):
    """In a harness header for the same reason the runtime is: `describe-ui`'s
    output is the measuring instrument, and CI installs whatever version
    Homebrew has today."""
    if not _cache:
        result = subprocess.run(
            ["sim-use", "--version"], check=False, capture_output=True, text=True
        )
        _cache.append((result.stdout or "?").strip() or "?")
    return _cache[0]
