"""The quiet state every Nine harness photographs against.

`simrig.py` deliberately knows nothing about what is being measured. This does:
it holds the one seeded container that makes Nine deterministic to photograph,
so the AX lane (PRD-19), the contrast lane (PRD-22) and the localization lane
(PRD-20) all suppress the same chrome instead of three drifting copies.

That drift is the whole reason this file exists rather than a comment saying
"copy this". A tip budget is spent by ordinary play, so a lane that forgets one
flag does not fail — it intermittently photographs a glass slab on whichever
screen happened to cross a threshold, and the reader blames the app.
"""

import json
import os

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))  # nine/
FIXTURE = os.path.join(REPO, "Tests", "AXBaselines", "fixture.nine.library.json")

# Only the preferences that would otherwise vary. `NinePrefs` decodes tolerantly
# (`decodeIfPresent … ?? default`), so a partial object is legal and every
# unlisted preference keeps its shipping default — which is the point: a
# baseline should photograph defaults, not a bespoke configuration.
PREFS_ERRORS_ON = {"errorHighlight": True, "resumeOnLaunch": True}
PREFS_ERRORS_OFF = {"errorHighlight": False, "resumeOnLaunch": True}


def quiet_blobs(prefs):
    """`CouchStored` filename → body for a Nine with nothing transient on screen.

    The frozen board comes from `Tests/AXBaselines/fixture.nine.library.json`,
    owned by `Tests/EngineTests/AXFixtureTests.swift`: a fresh launch would show
    *today's* daily, so every per-cell value in every baseline would rot
    overnight.
    """
    with open(FIXTURE) as handle:
        library = handle.read()
    return {
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
