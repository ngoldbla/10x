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
// SCOPE: the Shared keys only — what `BoardSpeech`, `TipCoach`, `SolveCardFacts`
// and `ArchiveCalendar` say. Task 5 adds the App layer's. The English below
// reproduces today's wording exactly, character for character; Task 7 is where
// the coach sentences get rewritten under their own grammar rules, and doing it
// here would mean two changes landing in one diff with only one of them tested.
import Foundation

public enum EnglishPhrases {

    /// key → English format string.
    public static let table: [String: String] = [
        "archive.day.inProgress": "in progress",
        "archive.day.notPlayed": "not played",
        "archive.day.solved": "solved",
        "archive.day.today": "today",
        "board.announce.allDone": "All %1$@ done.",
        "board.announce.cleared": "%1$@ cleared.",
        "board.announce.noteAdded": "Note %1$@ added.",
        "board.announce.noteRemoved": "Note %1$@ removed.",
        "board.announce.placed": "%1$@ placed.",
        "board.announce.remaining": "%1$@ %2$@ remaining.",
        "board.announce.solved": "Solved.",
        "board.box.empty": "%1$lld empty",
        "board.box.filled": "Filled",
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
        "board.progress.filled": "%1$lld of %2$lld filled.",
        "board.progress.wrong": "%1$lld wrong.",
        "board.streak.held": "%1$lld day streak, held",
        "board.streak.plain": "%1$lld day streak",
        "board.unit.box": "Box %1$lld",
        "board.unit.column": "Column %1$lld",
        "board.unit.row": "Row %1$lld",
        "board.value.empty": "Empty",
        "board.value.given": "%1$lld, given",
        "board.value.noteSeparator": ", ",
        "board.value.notes": "Empty, notes %1$@",
        "board.value.plain": "%1$lld",
        "board.value.wrong": "%1$lld, wrong",
        "board.voiceName.bare": "%1$lld %2$lld",
        "board.voiceName.cell": "Cell %1$lld %2$lld",
        "board.voiceName.rowColumn": "Row %1$lld column %2$lld",
        "card.daily": "Nine · daily puzzle",
        "card.streak": "%1$lld day streak",
        "card.time": "Solved in %1$@",
        "coach.axis.columns": "columns",
        "coach.axis.rows": "rows",
        "coach.boxLine.body": "Every %1$@ still possible in %2$@ sits in %3$@, so no other square in %3$@ can be a %1$@.",
        "coach.exhausted.body": "Nothing at this board's level follows from here.",
        "coach.exhausted.title": "Nothing follows",
        "coach.hiddenPair.body": "%1$@ and %2$@ fit only these two squares in %3$@, so nothing else fits there.",
        "coach.hiddenSingle.body": "Only one square in %1$@ can take a %2$@.",
        "coach.hiddenSingle.fallback": "%1$@ is the only square left that can take a %2$@.",
        "coach.nakedPair.body": "%1$@ and %2$@ fill these two squares between them, so neither can go anywhere else in %3$@.",
        "coach.nakedSingle.body": "%1$@ has one candidate left: %2$@.",
        "coach.slip.body": "Two of these squares disagree, so nothing can follow from here.",
        "coach.slip.title": "A slip somewhere",
        "coach.solved.title": "Done",
        "coach.xWing.body": "%1$@ in these two %2$@ can only sit in two %3$@, so no other square in those %3$@ can be a %4$@.",
        "tip.highlight": "Tap any placed digit to light up every one of its kind.",
        "tip.pencil": "Tap the pencil, then flick — the rose leaves corner notes instead.",
        "tip.undo": "Undo takes the last digit back. Nothing here is ever stuck.",
    ]
}
