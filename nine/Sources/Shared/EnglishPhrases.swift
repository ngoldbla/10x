// EnglishPhrases.swift — Nine's English, as data (PRD-20 "Nine Languages").
//
// This is the source language, and it has exactly one home. `Phrasebook.english`
// formats from it, so `swift test` and the Linux lane produce real sentences
// with no bundle in sight; Task 4 generates the catalog's `en` locale from it,
// so the strings a translator is handed cannot drift from the strings
// `BoardSpeechTests` asserts. One English, two consumers.
//
// **The shape is load-bearing, not tidiness.** A generator reads this file, so:
//
//   • a plain `[String: String]` literal — no `+`, no interpolation, no
//     computed values, nothing that has to be executed to know what the English
//     is;
//   • one `"key": "value",` per line, keys sorted, so a diff of this file is a
//     diff of the translation job and a bad merge shows up as a line;
//   • every specifier positional (`%1$lld`, `%2$@`), so a translation may
//     reorder — German and Japanese both front the column in the cell label.
//
// `PhrasebookTests` pins all three, including by re-parsing this file and
// checking the parse against the compiled dictionary.
//
// Key scheme: `<surface>.<group>.<role>`, dot-separated, lowerCamelCase inside a
// segment, so every key is also a legal Swift path (`Strings.board.cell.label`)
// for the App-layer accessors Task 4 generates. No key is a prefix of another —
// `board.streak.plain` rather than `board.streak` — because a leaf that is also
// a namespace cannot be spelled in that path form.
//
// SCOPE: the Shared keys, plus the Engine's two ID families. `BoardSpeech`,
// `TipCoach`, `SolveCardFacts` and `ArchiveCalendar` are the Shared consumers;
// Task 5 added the App layer's and Task 6 the widget's. The `widget.*` block is
// the one whose English is read in a SECOND bundle — `NineWidgets.appex`
// resolves it against its own `Bundle.main` — but it is one table either way:
// the appex links `Sources/Shared` too, so this file IS its English fallback.
// Tasks 5 and 6 reproduced today's wording character for character, because a
// move and a rewrite landing in one diff is a rewrite nobody reviewed. **Task 7
// is that rewrite**, and it is confined to the sentences the coach says and the
// board announces. The rule it lands: a sentence is one entry. Where the old
// English had one frame with a noun dropped into it — "…anywhere else in %3$@",
// fed "Row 1" or "Box 1" — there are now three entries with the noun written
// into each, because the hole in that frame carried English's grammar (one
// preposition, no inflection, this word order) into nine languages that do not
// share it. The number words are the single exception; the ruling that made it
// is in `BoardSpeech.swift`'s header, and `BoardSpeechTests` bounds it from
// both sides.
//
// The Engine's IDs are here rather than only in the catalog because the Engine
// itself no longer names anything (PRD-20 Task 2 deleted `Technique.displayName`
// and `Difficulty.title`) and *Shared* is one of the consumers:
// `BoardSpeech.coachTitle` speaks a technique's name and `SolveCardFacts` prints
// a difficulty's. Both run under `swift test` and on Linux with no bundle in
// sight, so if `technique.nakedSingle.name` lived only in the catalog,
// `BoardSpeechTests` would assert against the string "technique.nakedSingle.name"
// — the missing-key fallback, dressed up as a passing test.
// `CatalogTests.testEveryEngineIdentifierIsNamed` pins one entry per enum case,
// mechanically, so appending a `Technique` cannot silently ship unnamed.
import Foundation

public enum EnglishPhrases {

    /// key → English format string.
    public static let table: [String: String] = [
        "accent.crimson": "Crimson",
        "accent.ember": "Ember",
        "accent.glacier": "Glacier",
        "accent.gold": "Gold",
        "accent.lilac": "Lilac",
        "accent.magenta": "Magenta",
        "accent.meadow": "Meadow",
        "accent.moss": "Moss",
        "accent.orchid": "Orchid",
        "accent.teal": "Teal",
        "ambientSlot.clock": "Clock",
        "ambientSlot.streak": "Streak",
        "appIcon.ember": "Ember",
        "appIcon.mono": "Mono",
        "appIcon.original": "Original",
        "appIcon.tide": "Tide",
        "archive.close": "Close archive",
        "archive.day.inProgress": "in progress",
        "archive.day.notPlayed": "not played",
        "archive.day.solved": "solved",
        "archive.day.today": "today",
        "archive.footnote": "Every past day, rebuilt from its date. Solving one never touches your streak.",
        "archive.nextMonth": "Next month",
        "archive.previousMonth": "Previous month",
        "archive.title": "Archive",
        "board.action.erase": "Erase",
        "board.action.note": "Note %1$lld",
        "board.action.place": "Place %1$lld",
        "board.announce.allDone": "All %1$@ done.",
        "board.announce.cleared": "Cleared %1$@.",
        "board.announce.noteAdded": "Note %1$@ added.",
        "board.announce.noteRemoved": "Note %1$@ removed.",
        "board.announce.pair": "%1$@ %2$@",
        "board.announce.placed": "Placed %1$@.",
        "board.announce.remaining": "That leaves %1$@ %2$@.",
        "board.announce.solved": "Solved.",
        "board.box.empty": "%1$lld empty",
        "board.box.filled": "Filled",
        "board.cell.hintPair": "%1$@. %2$@",
        "board.cell.label": "Row %1$lld, column %2$lld",
        "board.cell.placeHint": "Flick or use the actions rotor to place a digit.",
        "board.digitPlural.eight": "eights",
        "board.digitPlural.five": "fives",
        "board.digitPlural.four": "fours",
        "board.digitPlural.nine": "nines",
        "board.digitPlural.one": "ones",
        "board.digitPlural.seven": "sevens",
        "board.digitPlural.six": "sixes",
        "board.digitPlural.three": "threes",
        "board.digitPlural.two": "twos",
        "board.digitWord.eight": "eight",
        "board.digitWord.five": "five",
        "board.digitWord.four": "four",
        "board.digitWord.nine": "nine",
        "board.digitWord.one": "one",
        "board.digitWord.seven": "seven",
        "board.digitWord.six": "six",
        "board.digitWord.three": "three",
        "board.digitWord.two": "two",
        "board.digitWord.zero": "zero",
        "board.progress.begun": "Just started",
        "board.progress.filled": "%1$lld of %2$lld filled.",
        "board.progress.full": "Full",
        "board.progress.untouched": "Untouched",
        "board.progress.wrong": "%1$lld wrong.",
        "board.rose.digit": "Digit rose",
        "board.rose.note": "Note rose",
        "board.rotor.empty": "Empty cells",
        "board.rotor.errors": "Wrong digits",
        "board.rotor.notes": "Cells with notes",
        "board.stats.digitDone": "%1$lld, done",
        "board.stats.digitLeft": "%1$lld, %2$lld left",
        "board.stats.hints": "hints",
        "board.stats.notes": "notes",
        "board.stats.pace": "pace",
        "board.stats.paceSeconds": "%1$llds",
        "board.stats.time": "time",
        "board.stats.undos": "undos",
        "board.streak.held": "%1$lld day streak, held",
        "board.streak.plain": "%1$lld day streak",
        "board.unit.box": "Box %1$lld",
        "board.unit.column": "Column %1$lld",
        "board.unit.row": "Row %1$lld",
        "board.value.empty": "Empty",
        "board.value.given": "%1$lld, given",
        "board.value.noteSeparator": ", ",
        "board.value.notes": "Empty, notes %1$@",
        "board.value.wrong": "%1$lld, wrong",
        "board.voiceName.cell": "Cell %1$lld %2$lld",
        "board.voiceName.pair": "%1$@ %2$@",
        "board.voiceName.rowColumn": "Row %1$lld column %2$lld",
        "boardAnchor.bottom": "Bottom",
        "boardAnchor.center": "Center",
        "boardAnchor.top": "Top",
        "boards.close": "Close boards",
        "boards.empty": "Start a board and it lands here — resume it any time, or archive it for later.",
        "boards.fresh.label": "New %1$@ board",
        "boards.fresh.note": "Your current board stays in this list",
        "boards.fresh.title": "Fresh board",
        "boards.row.archive": "Archive board",
        "boards.row.delete": "Delete board",
        "boards.section.inProgress": "In progress",
        "boards.section.played": "Previously played",
        "boards.status.archived": "Archived · %1$@",
        "boards.status.solved": "Solved · %1$@ · %2$@",
        "boards.title": "Boards",
        "card.daily": "Nine · daily puzzle",
        "card.streak": "%1$lld day streak",
        "card.time": "Solved in %1$@",
        "coach.action.markIt": "Mark it",
        "coach.action.placeIt": "Place it",
        "coach.boxLine.sentence.boxToCol": "Every %1$lld still possible in box %2$lld sits in column %3$lld, so no other square in column %3$lld can be a %1$lld.",
        "coach.boxLine.sentence.boxToRow": "Every %1$lld still possible in box %2$lld sits in row %3$lld, so no other square in row %3$lld can be a %1$lld.",
        "coach.boxLine.sentence.colToBox": "Every %1$lld still possible in column %2$lld sits in box %3$lld, so no other square in box %3$lld can be a %1$lld.",
        "coach.boxLine.sentence.rowToBox": "Every %1$lld still possible in row %2$lld sits in box %3$lld, so no other square in box %3$lld can be a %1$lld.",
        "coach.card.label": "%1$@. %2$@",
        "coach.exhausted.sentence": "Nothing at this board's level follows from here.",
        "coach.exhausted.title": "Nothing follows",
        "coach.hiddenPair.sentence.box": "%1$lld and %2$lld fit only these two squares in box %3$lld, so nothing else fits there.",
        "coach.hiddenPair.sentence.col": "%1$lld and %2$lld fit only these two squares in column %3$lld, so nothing else fits there.",
        "coach.hiddenPair.sentence.row": "%1$lld and %2$lld fit only these two squares in row %3$lld, so nothing else fits there.",
        "coach.hiddenSingle.sentence.box": "Only one square in box %1$lld can take a %2$lld.",
        "coach.hiddenSingle.sentence.cell": "Row %1$lld, column %2$lld is the only square left that can take a %3$lld.",
        "coach.hiddenSingle.sentence.col": "Only one square in column %1$lld can take a %2$lld.",
        "coach.hiddenSingle.sentence.row": "Only one square in row %1$lld can take a %2$lld.",
        "coach.nakedPair.sentence.box": "%1$lld and %2$lld fill these two squares between them, so neither can go anywhere else in box %3$lld.",
        "coach.nakedPair.sentence.col": "%1$lld and %2$lld fill these two squares between them, so neither can go anywhere else in column %3$lld.",
        "coach.nakedPair.sentence.row": "%1$lld and %2$lld fill these two squares between them, so neither can go anywhere else in row %3$lld.",
        "coach.nakedSingle.sentence": "Row %1$lld, column %2$lld has one candidate left: %3$lld.",
        "coach.slip.sentence": "Two of these squares disagree, so nothing can follow from here.",
        "coach.slip.title": "A slip somewhere",
        "coach.solved.title": "Done",
        "coach.xWing.sentence.colBase": "In these two columns, %1$lld can only sit in two rows, so no other square in those rows can be a %1$lld.",
        "coach.xWing.sentence.rowBase": "In these two rows, %1$lld can only sit in two columns, so no other square in those columns can be a %1$lld.",
        "difficulty.composeCaption": "%1$@ takes a moment to compose",
        "difficulty.gentle.blurb": "Singles & scans",
        "difficulty.gentle.explainer": "Every step is a single: one place a digit can go. A calm first board.",
        "difficulty.gentle.title": "Gentle",
        "difficulty.nocturne.blurb": "Fewer clues, deeper logic",
        "difficulty.nocturne.explainer": "Sharp's logic at the clue floor: fewer givens, more of the hard steps.",
        "difficulty.nocturne.title": "Nocturne",
        "difficulty.sharp.blurb": "X-wings & deep logic",
        "difficulty.sharp.explainer": "Demands X-wings and layered deductions. Bring notes and patience.",
        "difficulty.sharp.title": "Sharp",
        "difficulty.steady.blurb": "Pairs & box lines",
        "difficulty.steady.explainer": "Needs naked pairs and box-line eliminations. Pencil marks start to pay.",
        "difficulty.steady.title": "Steady",
        "firstrun.beat.detail": "The rose is open on the empty cell. Drag from its middle toward the %1$lld and let go — or just tap the %2$lld. That is the whole game.",
        "firstrun.beat.doneDetail": "Every board works exactly like that. Today's is waiting on the shelf.",
        "firstrun.beat.doneTitle": "That's it.",
        "firstrun.beat.hint": "One cell, one digit. You can skip this at any time.",
        "firstrun.beat.prompt": "Flick to the %1$lld.",
        "firstrun.beat.skip": "Skip",
        "firstrun.beat.title": "Your first digit",
        "firstrun.begin": "Begin",
        "firstrun.ledger.covenant": "No ads, no subscription, nothing else to buy",
        "firstrun.ledger.daily": "A new board every day, and a streak that keeps count",
        "firstrun.ledger.proof": "Three difficulties, every board proved solvable by logic",
        "firstrun.ledger.stats": "Your times, points and trends — kept honestly",
        "firstrun.ledger.sync": "Boards, streak and stats follow you between devices",
        "firstrun.ledger.themes": "%1$lld themes and %2$lld accents, all of them yours",
        "firstrun.onePurchase": "One purchase · iPhone, iPad, Mac & Apple TV",
        "firstrun.welcome.tagline": "Couch sudoku — everywhere you sit.",
        "firstrun.welcome.title": "Welcome to Nine",
        "game.another.label": "Another %1$@ board",
        "game.another.title": "Another",
        "game.autoNotes.chip": "Auto notes · filled %1$lld candidates",
        "game.chip.archive": "Archive · %1$@",
        "game.chip.pencil": "Pencil",
        "game.completion.streak": "Solved · %1$lld day streak",
        "game.control.autoNotes": "Auto notes",
        "game.control.hint": "Hint",
        "game.control.home": "Home",
        "game.control.pencil": "Pencil marks",
        "game.control.settings": "Settings",
        "game.control.undo": "Undo",
        "game.drawer.hide": "Hide board stats",
        "game.drawer.show": "Show board stats",
        "game.mac.exitDesk": "Exit desk mode",
        "game.mac.homeLabel": "Back to home",
        "game.tv.disconnected": "Controller disconnected",
        "game.tv.padHint": "Right stick places · Circle undoes · Create for settings",
        "game.tv.remoteHint": "Click a cell for digits · Hold ▶︎ for settings",
        "game.undo.autoNotes": "Undid auto notes",
        "game.undo.note": "Undid note %1$lld",
        "game.undo.placement": "Undid %1$lld",
        "game.undo.restored": "Restored %1$lld",
        "grammar.keyboard.advanceHint": "Arrows move · digits place · ⌘Z undoes",
        "grammar.keyboard.highlightDetail": "Move the cursor onto any placed digit and press Space. Every copy lights up — pencil notes too. Space again switches the lights off.",
        "grammar.keyboard.highlightVerb": "Space",
        "grammar.keyboard.pencilDetail": "Hold Shift and press a digit to pencil a note — small in the corner until a real digit lands. Press P for sticky pencil.",
        "grammar.keyboard.pencilVerb": "Shift-type",
        "grammar.keyboard.placeDetail": "Walk to the glowing cell with the arrow keys, then press %1$@. Digits type straight in — no rose, no modes.",
        "grammar.keyboard.placeVerb": "type",
        "grammar.pad.advanceHint": "Left stick moves · right stick flicks a digit · Circle taps undo, holds to erase",
        "grammar.pad.highlightDetail": "Rest on any placed digit and press Triangle — every copy lights up, pencil notes too. Hold L2 to dim everything except that kind. Triangle again switches the lights off.",
        "grammar.pad.highlightVerb": "Triangle",
        "grammar.pad.pencilDetail": "Press Square for sticky pencil, then flick a note into an empty cell — small in the corner until a real digit lands. Square again turns pencil off.",
        "grammar.pad.pencilVerb": "Square",
        "grammar.pad.placeDetail": "Walk to the glowing cell with the left stick, then flick the right stick toward %1$@ — the cell is always armed, so it's one flick per digit, no rose to open. (Cross opens the rose if you'd rather learn the petals; R3 places 5.)",
        "grammar.pad.placeVerb": "flick the right stick",
        "grammar.remote.advanceHint": "Swipe to move · click for the rose · ▶︎ undoes",
        "grammar.remote.highlightDetail": "Park the cursor on any placed digit and every copy of it lights up — pencil notes too.",
        "grammar.remote.highlightVerb": "park the cursor",
        "grammar.remote.pencilDetail": "Hold-click an empty cell for the pencil rose. Notes sit small in the corner until a real digit lands.",
        "grammar.remote.pencilVerb": "hold-click",
        "grammar.remote.placeDetail": "Swipe to the glowing cell and click for the rose, then flick toward %1$@ — or swipe to a petal and click.",
        "grammar.remote.placeVerb": "flick",
        "grammar.touch.advanceHint": "Tap a cell for the rose · tap a petal to place",
        "grammar.touch.highlightDetail": "Tap any placed digit on the board. Every copy of it lights up — pencil notes too. Tap one again to switch the lights off.",
        "grammar.touch.highlightVerb": "tap a placed digit",
        "grammar.touch.pencilDetail": "Pencil is on. Tap an empty cell and note a digit you're considering — notes sit small in the corner until a real digit lands.",
        "grammar.touch.pencilVerb": "pencil toggle",
        "grammar.touch.placeDetail": "Tap the glowing cell, then tap the %1$@ in the rose. (You can also flick toward it — the rose is a 3×3 keypad.)",
        "grammar.touch.placeVerb": "tap a petal",
        "help.tv.tagline": "Couch sudoku.",
        "history.close": "Close history",
        "history.empty": "Solve a board and it lands here — time, difficulty and points.",
        "history.gameCenter.in": "Leaderboards & achievements",
        "history.gameCenter.out": "Sign in via Settings to compete",
        "history.gameCenter.title": "Game Center",
        "history.recent.daily": "Daily · %1$@",
        "history.recent.title": "Recent",
        "history.section.avgVsBest": "Average vs. best",
        "history.section.heat": "Last 12 weeks",
        "history.section.trend": "Solve time trend",
        "history.stat.bestStreak": "best streak",
        "history.stat.points": "points",
        "history.stat.solved": "solved",
        "history.title": "History",
        "history.trend.faster": "▼ faster",
        "legend.keyboard.arrows.action": "Move the cursor (wraps at edges)",
        "legend.keyboard.arrows.gesture": "Arrow keys",
        "legend.keyboard.digits.action": "Place the digit",
        "legend.keyboard.digits.gesture": "1–9",
        "legend.keyboard.highlight.action": "Light up the digit under the cursor",
        "legend.keyboard.highlight.gesture": "Space",
        "legend.keyboard.pencil.action": "Pencil a note · sticky pencil",
        "legend.keyboard.pencil.gesture": "⇧1–9 · P",
        "legend.keyboard.tab.action": "Next / previous empty cell",
        "legend.keyboard.tab.gesture": "Tab / ⇧Tab",
        "legend.keyboard.undo.action": "Undo",
        "legend.keyboard.undo.gesture": "⌘Z",
        "legend.pad.circle.action": "Undo · hold to erase the cell",
        "legend.pad.circle.gesture": "Circle tap · hold",
        "legend.pad.controller.action": "Just start playing — the guide appears in-game",
        "legend.pad.controller.gesture": "Controller",
        "legend.pad.create.action": "Settings",
        "legend.pad.create.gesture": "Create",
        "legend.pad.cross.action": "Open the rose · confirm a petal",
        "legend.pad.cross.gesture": "Cross",
        "legend.pad.menu.action": "Save + home",
        "legend.pad.menu.gesture": "Menu",
        "legend.pad.move.action": "Move around the board",
        "legend.pad.move.gesture": "Left stick / d-pad",
        "legend.pad.peek.action": "Peek — dim all but one kind",
        "legend.pad.peek.gesture": "Hold L2 · R2",
        "legend.pad.place.action": "Place a digit (R3 = 5)",
        "legend.pad.place.gesture": "Right stick flick",
        "legend.pad.square.action": "Sticky pencil",
        "legend.pad.square.gesture": "Square",
        "legend.pad.triangle.action": "Light up all of a digit",
        "legend.pad.triangle.gesture": "Triangle",
        "legend.remote.back.action": "Save + home",
        "legend.remote.back.gesture": "Back",
        "legend.remote.click.action": "Open the digit rose",
        "legend.remote.click.gesture": "Click",
        "legend.remote.flick.action": "Place instantly",
        "legend.remote.flick.gesture": "Flick (8-way remote)",
        "legend.remote.holdPlayPause.action": "Settings",
        "legend.remote.holdPlayPause.gesture": "Hold ▶︎",
        "legend.remote.playPause.action": "Undo",
        "legend.remote.playPause.gesture": "▶︎",
        "legend.remote.rose.action": "Preview, then place",
        "legend.remote.rose.gesture": "Swipe + Click (in rose)",
        "legend.remote.swipe.action": "Move around the board",
        "legend.remote.swipe.gesture": "Swipe",
        "legend.touch.flick.action": "Place instantly",
        "legend.touch.flick.gesture": "Flick in the rose",
        "legend.touch.highlight.action": "Light up all of its kind",
        "legend.touch.highlight.gesture": "Tap a placed digit",
        "legend.touch.pencil.action": "Corner notes instead",
        "legend.touch.pencil.gesture": "Pencil toggle",
        "legend.touch.tapCell.action": "Open the digit rose",
        "legend.touch.tapCell.gesture": "Tap a cell",
        "legend.touch.tapPetal.action": "Place that digit",
        "legend.touch.tapPetal.gesture": "Tap a petal",
        "legend.touch.undo.action": "Take back a move",
        "legend.touch.undo.gesture": "Undo button",
        "menu.edit.undo": "Undo",
        "menu.game.boards": "Boards…",
        "menu.game.discard": "Discard Board",
        "menu.game.newGame": "New Game",
        "menu.game.title": "Game",
        "menu.game.today": "Today's Puzzle",
        "menu.help.howToPlay": "How to Play",
        "menu.view.accent": "Accent",
        "menu.view.appearance": "Appearance",
        "menu.view.enterDesk": "Enter Desk Mode",
        "menu.view.errorHighlight": "Error Highlight",
        "menu.view.exitDesk": "Exit Desk Mode",
        "menu.view.floatDesk": "Float Desk on Top",
        "menu.view.numberHighlight": "Number Highlight",
        "menu.view.showTimer": "Show Timer",
        "prefs.accent.title": "Accent",
        "prefs.ambient.title": "Ambient display",
        "prefs.appIcon.title": "App icon",
        "prefs.boardPosition.title": "Board position",
        "prefs.controllerHaptics.title": "Controller haptics",
        "prefs.controls.bottom": "Bottom",
        "prefs.controls.title": "Controls",
        "prefs.controls.top": "Top",
        "prefs.errorHighlight.title": "Error highlight",
        "prefs.haptics.title": "Haptics",
        "prefs.newGame.note": "Your current board stays on the shelf",
        "prefs.newGame.title": "New game",
        "prefs.numberHighlight.title": "Number highlight",
        "prefs.resume.title": "Resume on launch",
        "prefs.section.appearance": "Appearance",
        "prefs.section.feel": "Feel",
        "prefs.section.layout": "Layout",
        "prefs.section.play": "Play",
        "prefs.theme.title": "Theme",
        "prefs.timer.hidden": "Hidden",
        "prefs.timer.shown": "Shown",
        "prefs.timer.title": "Timer",
        "prefs.toggle.off": "Off",
        "prefs.toggle.on": "On",
        "share.button": "Share",
        "share.label": "Share your solve",
        "sheet.dismiss.remote": "Press Back to return",
        "sheet.dismiss.touch": "Tap outside to return",
        "shelf.ambient.empty": "No solves yet",
        "shelf.archive.hint": "Every past daily, on a month grid",
        "shelf.boards.seeAll": "See all",
        "shelf.boards.seeAllLabel": "See all boards",
        "shelf.boards.subtitleCount": "%1$lld in progress",
        "shelf.boards.subtitleEmpty": "Resume, archive, replay",
        "shelf.continue.caption": "%1$@ · %2$@",
        "shelf.continue.captionMore": "%1$@ · %2$@ · +%3$lld more",
        "shelf.continue.discard": "Discard saved game",
        "shelf.continue.title": "Continue",
        "shelf.daily.date": "Daily · %1$@",
        "shelf.difficulty.label": "%1$@, %2$@",
        "shelf.grace.body": "You took yesterday off; one rest day won't cost you.",
        "shelf.grace.hint": "Dismisses this card",
        "shelf.grace.label": "%1$@. %2$@",
        "shelf.grace.title": "Your streak held",
        "shelf.history.subtitle": "Points & best times",
        "shelf.points.chip": "%1$lld pts",
        "shelf.today.continueProgress": "Continue · %1$@",
        "shelf.today.oneADay": "One a day",
        "shelf.today.title": "Today",
        "shelf.variants.answer": "In the works — they'll simply appear here.",
        "shelf.variants.subtitle": "New variants, coming soon.",
        "shelf.variants.title": "Killer · Thermo",
        "status.composing": "Composing…",
        "status.solved": "Solved",
        "technique.boxLineReduction.name": "Box-Line Reduction",
        "technique.cageCombination.name": "Cage Combination",
        "technique.cageSingle.name": "Cage Single",
        "technique.hiddenPair.name": "Hidden Pair",
        "technique.hiddenSingle.name": "Hidden Single",
        "technique.innieOutie.name": "Rule of 45",
        "technique.nakedPair.name": "Naked Pair",
        "technique.nakedSingle.name": "Naked Single",
        "technique.thermoBound.name": "Thermometer Bound",
        "technique.xWing.name": "X-Wing",
        "theme.auto": "Auto",
        "theme.blueprint": "Blueprint",
        "theme.camel": "Camel",
        "theme.dark": "Void",
        "theme.ember": "Ember",
        "theme.forest": "Forest",
        "theme.light": "Paper",
        "theme.mono": "Mono",
        "theme.tide": "Tide",
        "tip.highlight": "Tap any placed digit to light up every one of its kind.",
        "tip.pencil": "Tap the pencil, then flick — the rose leaves corner notes instead.",
        "tip.undo": "Undo takes the last digit back. Nothing here is ever stuck.",
        "tutorial.button.done": "Done",
        "tutorial.button.skipStep": "Skip this step",
        "tutorial.button.tryIt": "Try it",
        "tutorial.close": "Close tutorial",
        "tutorial.difficulty.body": "Every difficulty is provably solvable by logic alone — no guessing, ever. Solves earn points; faster and harder earns more.",
        "tutorial.difficulty.title": "Pick your poison",
        "tutorial.digit.placeholder": "digit",
        "tutorial.goal.body": "Fill every row, column and 3×3 box with 1–9 — each digit exactly once. This board is nearly done; you'll finish a piece of it.",
        "tutorial.goal.title": "The goal",
        "tutorial.highlight.title": "Find every 9 (or 5, or 2…)",
        "tutorial.nice": "Nice",
        "tutorial.pad.beginBody": "%1$@ Press Cross to begin.",
        "tutorial.pad.finish": "Press Cross — done",
        "tutorial.pad.readyBody": "%1$@ Press Cross when you're ready.",
        "tutorial.pad.skip": "Press Menu to skip the tutorial",
        "tutorial.pad.tryIt": "Press Cross to try it",
        "tutorial.pencil.title": "Pencil notes",
        "tutorial.place.title": "Place a digit",
        "tutorial.title": "How to play",
        "tutorial.titlePad": "How to play — controller",
        "tutorial.today.body": "One shared %1$@ board a day. Solve it daily to grow your streak — streaks multiply your points.",
        "watch.app.name": "Nine",
        "watch.dial.empty": "Nothing dialled",
        "watch.dial.erase": "Erase",
        "watch.nav.home": "Home",
        "watch.nav.map": "Whole board",
        "watch.rail.column": "Column so far",
        "watch.rail.empty": "nothing yet",
        "watch.rail.row": "Row so far",
        "watch.today.waiting": "On your iPhone",
        "watch.today.waitingHint": "Open Nine on your iPhone to send today's board.",
        "widget.board.cta": "Tap to start today's puzzle",
        "widget.board.description": "Play today's puzzle right on your Home Screen.",
        "widget.board.name": "Playable Daily",
        "widget.brand.daily": "Nine · Daily",
        "widget.caption.awaits": "Today's puzzle awaits",
        "widget.caption.done": "Daily done",
        "widget.caption.inProgress": "In progress",
        "widget.caption.waiting": "New puzzle waiting",
        "widget.daily.description": "Today's puzzle, your streak and points at a glance.",
        "widget.daily.header": "Daily",
        "widget.daily.name": "Daily",
        "widget.daily.points": "%1$lld pts",
        "widget.daily.startStreak": "Start a streak",
        "widget.daily.streak": "%1$lld day streak",
        "widget.status.filled": "%1$@ filled",
        "widget.status.notStarted": "Not started",
        "widget.status.openNine": "Open Nine",
        "widget.status.ready": "Ready",
        "widget.status.solved": "Solved",
        "widget.status.solvedIn": "Solved %1$@",
        "widget.streak.description": "Your daily streak on the Lock Screen.",
        "widget.streak.inline": "Nine · %1$lld day streak",
        "widget.streak.name": "Streak",
        "widget.streak.ready": "Nine · Daily ready",
    ]

    // MARK: - Counts

    /// One count-bearing phrase's `one` form. The `other` form is the row in
    /// `table`, which is why this table names only the minority — there is
    /// still exactly one row per key per language, and `--audit`, the sorting
    /// rule and the catalog-versus-table test all keep working unchanged.
    public struct EnglishPlural: Sendable {
        /// 1-based index of the argument holding the count. Not always 1:
        /// `board.stats.digitLeft` is `"%1$lld, %2$lld left"`, where argument 1
        /// is *which digit* and argument 2 is how many are left.
        public let count: Int
        /// The CLDR `one` category, in full. A whole sentence rather than the
        /// word that changes, for the reason Task 7 gave: the hole in a frame
        /// carries English's grammar into languages that do not share it.
        public let one: String

        public init(count: Int, one: String) {
            self.count = count
            self.one = one
        }
    }

    /// Every phrase whose grammar depends on a number.
    ///
    /// **English `one` and `other` being identical is not redundancy.**
    /// **Eleven of the fourteen rows** below read the same in both categories —
    /// English uses "day" attributively in "12 day streak" and does not inflect
    /// it. The entry exists so that German, French, Spanish and Portuguese
    /// *can* differ, and so that `CatalogTests`' plural gate has something to
    /// enforce when Task 9 hands the catalog to nine translators. A key with no
    /// plural entry is a key a translator cannot inflect at all.
    ///
    /// The **other three** were wrong in English before this table existed:
    /// `game.autoNotes.chip` read "filled 1 candidates", and both point chips
    /// read "1 pts".
    ///
    /// Counts, since a wrong one here is what the next reader trusts:
    /// **14 rows in this table, 3 in `substitutions` below (4 axes between
    /// them), 17 keys and 18 axes in all.** The compiled `.stringsdict` carries
    /// one entry per key, so **17**.
    ///
    /// Shape contract, same as `table`: one `"key": EnglishPlural(…),` per
    /// line, keys sorted, nothing that has to be executed. `scripts/strings.py`
    /// reads this file to generate the catalog's `en` plural variations, and
    /// `PhrasebookTests` re-parses it and checks the parse against the compiled
    /// dictionary.
    public static let plurals: [String: EnglishPlural] = [
        "board.box.empty": EnglishPlural(count: 1, one: "%1$lld empty"),
        "board.progress.wrong": EnglishPlural(count: 1, one: "%1$lld wrong."),
        "board.stats.paceSeconds": EnglishPlural(count: 1, one: "%1$llds"),
        "board.streak.held": EnglishPlural(count: 1, one: "%1$lld day streak, held"),
        "board.streak.plain": EnglishPlural(count: 1, one: "%1$lld day streak"),
        "card.streak": EnglishPlural(count: 1, one: "%1$lld day streak"),
        "game.autoNotes.chip": EnglishPlural(count: 1, one: "Auto notes · filled %1$lld candidate"),
        "game.completion.streak": EnglishPlural(count: 1, one: "Solved · %1$lld day streak"),
        "shelf.boards.subtitleCount": EnglishPlural(count: 1, one: "%1$lld in progress"),
        "shelf.continue.captionMore": EnglishPlural(count: 3, one: "%1$@ · %2$@ · +%3$lld more"),
        "shelf.points.chip": EnglishPlural(count: 1, one: "%1$lld pt"),
        "widget.daily.points": EnglishPlural(count: 1, one: "%1$lld pt"),
        "widget.daily.streak": EnglishPlural(count: 1, one: "%1$lld day streak"),
        "widget.streak.inline": EnglishPlural(count: 1, one: "Nine · %1$lld day streak"),
    ]

    /// One axis of a phrase whose plural cannot be a whole-string variation.
    ///
    /// A `plurals` row above inflects the whole string against a single number,
    /// and it works because **`xcstringstool` infers which argument the count
    /// is, and can only do that when the string names exactly one of them.**
    /// Three of Nine's phrases fail that, in two different ways.
    ///
    /// *Two counts in one sentence.* `firstrun.ledger.themes` is `"%1$lld
    /// themes and %2$lld accents, all of them yours"`, so there is no single
    /// `one` form at all. A plural on the first count would hand German one
    /// form for "themes" and no way to inflect "accents" — the second number's
    /// grammar frozen at whatever the translator picked.
    ///
    /// *A number that is not the count.* `board.stats.digitLeft` is `"%1$lld,
    /// %2$lld left"`, where argument 1 is **which digit** and argument 2 is how
    /// many are left. Written as a plain plural it compiles with a warning and
    /// then, measured on this machine against the compiled `.stringsdict`,
    /// selects on the digit:
    ///
    ///     digit 5, 1 left  ->  OTHER      (the count is 1; the digit is 5)
    ///     digit 1, 5 left  ->  ONE        (the count is 5; the digit is 1)
    ///
    /// Exactly inverted, silently, in every language that inflects. So the
    /// choice is not between rigour and pragmatism — a whole-string plural is
    /// simply wrong here, and `scripts/strings.py` refuses to write one.
    ///
    /// CLDR substitutions are the mechanism for both. The catalog carries a
    /// frame (`"%1$#@themes@ and %2$#@accents@, all of them yours"`,
    /// `"%1$lld, %2$#@left@"`) and one independent plural per axis, each with
    /// its `argNum` written down instead of guessed. `xcstringstool compile`
    /// was measured accepting it and the compiled `.stringsdict` driven at 1/1
    /// and 9/10 before this table was written.
    ///
    /// The frame is **derived**, not stored: `scripts/strings.py` builds it by
    /// replacing `%N$lld` with `%N$#@name@` in the `table` row, and then splices
    /// the `other` forms back in and refuses to write a catalog unless the
    /// result is the `table` row character for character. So the sentence still
    /// has exactly one home, which is the rule this whole file exists to hold.
    ///
    /// `%arg` is the catalog's own placeholder for "the number this axis
    /// counts"; `xcstringstool` expands it to `%N$lld` from `argNum`.
    ///
    /// **`Phrasebook.english` does not implement substitutions**, deliberately.
    /// It falls back to the `table` row, which is the all-`other` sentence and
    /// is correct English for every pair of counts the app can produce — they
    /// are `ThemeChoice.allCases.count` and `AccentChoice.allCases.count`,
    /// 9 and 10 today. Building a second, hand-rolled plural engine inside the
    /// one formatter in Nine that is load-bearing against segfaults, to serve a
    /// path that only Linux and a missing catalog row can reach, would be a
    /// worse trade than the sentence it bought.
    public struct EnglishSubstitution: Sendable {
        /// The name of the axis, as it appears in the frame's `%N$#@name@`.
        public let name: String
        /// 1-based index of the argument this axis counts.
        public let count: Int
        public let one: String
        public let other: String

        public init(name: String, count: Int, one: String, other: String) {
            self.name = name
            self.count = count
            self.one = one
            self.other = other
        }
    }

    public static let substitutions: [String: [EnglishSubstitution]] = [
        "board.progress.filled": [
            EnglishSubstitution(name: "filled", count: 1, one: "%arg of %2$lld", other: "%arg of %2$lld"),
        ],
        "board.stats.digitLeft": [
            EnglishSubstitution(name: "left", count: 2, one: "%arg left", other: "%arg left"),
        ],
        "firstrun.ledger.themes": [
            EnglishSubstitution(name: "themes", count: 1, one: "%arg theme", other: "%arg themes"),
            EnglishSubstitution(name: "accents", count: 2, one: "%arg accent", other: "%arg accents"),
        ],
    ]
}
