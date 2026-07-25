# AX baselines — the board's accessibility tree, frozen (PRD-19)

Five `sim-use describe-ui` dumps, one per screen, diffed on every pull request
by `.github/workflows/nine-accessibility.yml`.

```bash
python3 nine/scripts/ax-snapshot.py             # diff
python3 nine/scripts/ax-snapshot.py --record    # re-record, deliberately
```

The board is one `Canvas` with 81 synthetic accessibility children in nine box
containers. When that tree collapses **nothing on screen changes** — the game
looks identical and plays identically, and a blind player finds a blank
rectangle where the puzzle used to be. It has happened once already: the shipped
1.1 build listed zero cells and nobody noticed for months. These files are how
that stops being possible.

## The files

| File | What it pins |
|---|---|
| `game.txt` | 9 box containers, 81 cells with values, 4 chrome buttons at 44×44, and the actions rotor sampled once per value branch |
| `game-quiet.txt` | the same board with `errorHighlight` off — the wrong cell reads `"9"`, not `"9, wrong"` |
| `game-rose.txt` | rose open: the board leaves the tree entirely, 9 petals and nothing else |
| `prefs.txt` | the settings sheet |
| `home.txt` | the shelf |
| `fixture.nine.library.json` | the frozen board all of the above are photographs of |

## Reading a diff

Line two of every baseline carries the device type, the iOS runtime version and
the `sim-use` version. If that line is the only thing that moved, a tool or
runner image was upgraded — re-record and say so. If cell lines moved, something
in `Sources/App/BoardAccessibility.swift`, `Sources/Shared/BoardSpeech.swift` or
a game screen changed the tree, and the question is whether that was intended.

`prefs.txt` lists board cells behind the sheet. `describe-ui` finds elements by
point hit-test and a hit-test ignores AX modality, so that is a structural
fingerprint, not a claim that VoiceOver can reach them.

## The one coupling that will bite you

`fixture.nine.library.json` is owned by `Tests/EngineTests/AXFixtureTests.swift`,
not by hand. Changing the seeded board is two commands, together, or every
baseline becomes a photograph of a board that no longer exists:

```bash
NINE_FREEZE_AX_FIXTURE=1 swift test --filter AXFixture
python3 nine/scripts/ax-snapshot.py --record
```

## What these files cannot see

The *actions* rotor is here — sampled once per value branch at the foot of
`game.txt` and `game-quiet.txt`, which is what pins `Place 1 … Place 9 | Erase`
in that order. Everything below is not, and lives in
`Tests/SharedTests/BoardSpeechTests.swift` or in a manual pass:

- **Voice Control input labels.** `accessibilityUserInputLabels` is absent from
  the AX API `describe-ui` reads, and Voice Control does not run on a simulator
  at all.
- **The custom rotors** (Empty cells / Cells with notes / Wrong digits). No dump
  carries them, so "an empty rotor does not appear" is untested here.
- **Box container values** ("3 empty" / "Filled"). `describe-ui` finds elements
  by point hit-test, which returns the leaf cell — a container's own value is
  unreachable. Its label survives, as the `Group "Box 4"` headers.
- **VoiceOver's traversal order.** The JSON entry list is sorted geometrically,
  not by traversal, so grouping the output by container is as close as the
  instrument gets to showing the hierarchy.
- **The wording of any announcement.** Nothing spoken transiently is in a tree.
