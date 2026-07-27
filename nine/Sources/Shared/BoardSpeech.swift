// BoardSpeech.swift — every sentence Nine says about a board, in one pure
// place (PRD-19 "A Voice for the Board").
//
// VoiceOver is the first consumer: the board is 81 focusable elements, and an
// AX label read 81 times a minute has to be short, honest and identical every
// time. The rules that fall out of that, and that the tests pin:
//   • Label vs value vs hint are three different lengths for three different
//     jobs. The label ("Row 3, column 5") locates the cell and never changes.
//     The value ("7, given") is the part VoiceOver re-speaks on every focus
//     move, so it stays terse. The hint carries the box number and the "how do
//     I even play this" sentence, because VoiceOver speaks hints once and can
//     be configured off entirely.
//   • Wrongness is gated on `showErrors`. `NineGame.isError` compares against
//     the *proven solution*, so it knows things the sighted player has not
//     been told. Leaking that through the AX layer would make VoiceOver a
//     cheat mode — hence the explicit parameter on every function that could
//     leak, and a test for the false branch.
//   • The word is "wrong", not "conflicts". A conflict is a peer clash you
//     could see; this is the engine telling you the answer is not the answer.
//     Say the true thing.
//   • Nothing here traps. An out-of-range cell or digit returns "" rather than
//     crashing: an accessibility layer that can kill the app is worse than one
//     that occasionally says nothing.
//
// This is also the Coach's phrasebook (PRD-19 §2 onward), so the pieces are
// composable — `digitWord`, `boxLabel`, `remainingClause` are public and get
// reused inside future sentence templates rather than re-spelled there.
//
// Pure: no SwiftUI, no UIKit, no clocks, no globals. Every function is a
// deterministic map from its arguments to a String, which is what makes the
// whole surface unit-testable on Linux CI.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

/// Formats board state into the strings Nine speaks.
public enum BoardSpeech {

    // MARK: - Cell identity

    /// The VoiceOver *label* for a cell: where it is, 1-based for humans.
    /// Deliberately no box number — see `cellHint`.
    public static func cellLabel(_ cell: Int) -> String {
        guard isValidCell(cell) else { return "" }
        return Phrase.cellLabel(row: Sudoku.row(of: cell) + 1, column: Sudoku.col(of: cell) + 1)
    }

    /// "Row 3" — the row half of the label, for sentences that only need one axis.
    public static func rowLabel(_ cell: Int) -> String {
        guard isValidCell(cell) else { return "" }
        return Phrase.row(Sudoku.row(of: cell) + 1)
    }

    /// "Column 5".
    public static func columnLabel(_ cell: Int) -> String {
        guard isValidCell(cell) else { return "" }
        return Phrase.column(Sudoku.col(of: cell) + 1)
    }

    /// "Box 2" — 1-based, reading order (top-left box is 1, bottom-right is 9).
    public static func boxLabel(_ cell: Int) -> String {
        guard isValidCell(cell) else { return "" }
        return Phrase.box(Sudoku.box(of: cell) + 1)
    }

    /// The VoiceOver *hint*: box number plus how to act on the cell. Spoken
    /// once per focus (and only when hints are enabled), so it can afford the
    /// extra syllables the label cannot.
    public static func cellHint(_ cell: Int) -> String {
        guard isValidCell(cell) else { return "" }
        return "\(boxLabel(cell)). \(Phrase.placeInstruction)"
    }

    // MARK: - Group scan (Switch Control)

    /// "Box 1" for a *box index* rather than a cell. Switch Control's group
    /// scan steps 9 boxes before it steps 9 cells, so the box is a named stop
    /// in its own right — `boxLabel` answers "which box is this cell in",
    /// this answers "which box am I scanning".
    public static func boxGroupLabel(_ box: Int) -> String {
        guard isValidBox(box) else { return "" }
        return Phrase.box(box + 1)
    }

    /// "3 empty" / "1 empty" / "Filled" — the one fact that makes a nine-stop
    /// group scan worth having, because it lets a switch user skip a box
    /// without descending into it.
    ///
    /// Deliberately a count of holes and never a verdict: a box full of wrong
    /// digits reads "Filled", exactly as `cellValue` refuses to say "wrong"
    /// when the screen is not saying it either. Numerals, not words — this is
    /// a quantity to compare, like `progressSummary`.
    public static func boxGroupValue(_ box: Int, in game: NineGame) -> String {
        guard isValidBox(box) else { return "" }
        let empty = (0..<81).count(where: { Sudoku.box(of: $0) == box && game.entry(at: $0) == 0 })
        guard empty > 0 else { return Phrase.boxFilled }
        return Phrase.boxEmptyCount(empty)
    }

    // MARK: - Voice Control addressing

    /// The names Voice Control will accept for a cell, canonical first.
    ///
    /// Voice Control matches *spoken* text against every entry and draws only
    /// the first in its "Show Names" overlay, which on this screen means 81
    /// badges at once — so the leading name is the shortest thing that is
    /// still unmistakably a board cell ("Cell 5 5"), not the 4-word VoiceOver
    /// label. The alternates cover the two other things a player actually
    /// says: the label they just heard, minus the comma no recogniser emits
    /// ("Row 5 column 5"), and the bare coordinates ("5 5").
    ///
    /// Every string is punctuation-free and unique across the 81 cells; both
    /// are pinned by tests, because a duplicate name makes "Tap cell 5 5"
    /// choose a cell at random and a comma makes it never match at all.
    public static func cellInputLabels(_ cell: Int) -> [String] {
        guard isValidCell(cell) else { return [] }
        let row = Sudoku.row(of: cell) + 1, column = Sudoku.col(of: cell) + 1
        return [
            Phrase.cellAddress(row: row, column: column),
            Phrase.spokenCellLabel(row: row, column: column),
            Phrase.bareAddress(row: row, column: column),
        ]
    }

    // MARK: - Cell contents

    /// The VoiceOver *value* for a cell — spoken on every focus move, so short.
    ///
    /// - Parameter showErrors: mirror of the player's "show mistakes" setting.
    ///   When false the value never reveals that an entry is wrong, because the
    ///   sighted player is not being shown that either.
    public static func cellValue(_ cell: Int, in game: NineGame, showErrors: Bool) -> String {
        guard isValidCell(cell) else { return "" }
        let entry = game.entry(at: cell)
        if entry != 0 {
            if game.isGiven(cell) { return Phrase.givenValue(entry) }
            if showErrors, game.isError(at: cell) { return Phrase.wrongValue(entry) }
            return Phrase.plainValue(entry)
        }
        let notes = game.pencilDigits(at: cell) // Sudoku.digits(in:) is ascending
        guard !notes.isEmpty else { return Phrase.empty }
        return Phrase.emptyWithNotes(notes.map(String.init).joined(separator: Phrase.listSeparator))
    }

    // MARK: - Move announcements

    /// Spoken after a digit lands. "Four placed. Two fours remaining."
    /// The caller owns the solved case — when the board completes it should say
    /// `solvedAnnouncement` instead, so the celebration is not buried behind a
    /// count of zero.
    public static func placementAnnouncement(digit: Int, in game: NineGame) -> String {
        guard isValidDigit(digit) else { return "" }
        return "\(Phrase.placed(digitWordCapitalized(digit))) \(remainingClause(digit: digit, in: game))"
    }

    /// "Two fours remaining." / "One four remaining." / "All fours done."
    /// Split out because the Coach reuses it mid-sentence.
    public static func remainingClause(digit: Int, in game: NineGame) -> String {
        guard isValidDigit(digit) else { return "" }
        // Clamped: a hand-built game could in principle carry more than nine of
        // a digit, and "minus one remaining" is not a sentence.
        let remaining = min(max(9 - game.count(of: digit), 0), 9)
        guard remaining > 0 else { return Phrase.allDone(digitWordPlural(digit)) }
        return Phrase.remaining(countWordCapitalized(remaining), digitNoun(digit, count: remaining))
    }

    /// Spoken when the board is finished. The caller decides when — this type
    /// has no opinion about celebration timing.
    ///
    /// Computed, not a `static let`. A `let` here is a lazy global frozen at
    /// whatever the *first read* happened to see, and there is no ordering rule
    /// in this codebase that says when that read is. `Phrasebook.install` is
    /// once per **process**, before the first read — and today it has no call
    /// site at all on iOS, tvOS or in the widget extension (see
    /// `Phrasebook.swift`, which spells out why). An earlier version of this
    /// comment claimed the freeze was "fine today, because `Phrasebook.install`
    /// runs in `NineApp.init`". That was never true off macOS, and it was the
    /// wrong shape of argument besides: it made a caching decision depend on a
    /// launch sequence written in another target.
    ///
    /// What actually makes this safe in a process that never installs is
    /// `Phrasebook.current`'s fallback to English — the sentence is real either
    /// way, never empty and never a key. What the computed property buys on top
    /// is that a read landing *before* the install cannot poison the rest of
    /// the process: it turns a transient ordering mistake into one wrong
    /// sentence instead of a permanently wrong one, and it is what lets the
    /// wording follow a mid-session language change at all. Nothing else in
    /// this file caches a word; this should not either.
    public static var solvedAnnouncement: String { Phrase.solved }

    /// "Four cleared."
    public static func eraseAnnouncement(digit: Int) -> String {
        guard isValidDigit(digit) else { return "" }
        return Phrase.cleared(digitWordCapitalized(digit))
    }

    /// "Note four added." / "Note four removed."
    public static func noteAnnouncement(digit: Int, added: Bool) -> String {
        guard isValidDigit(digit) else { return "" }
        return added ? Phrase.noteAdded(digitWord(digit)) : Phrase.noteRemoved(digitWord(digit))
    }

    // MARK: - Board summary

    /// "18 of 51 filled. 3 wrong." — the answer to "how am I doing", spoken
    /// from a progress control or a rotor action. Numerals, not words: these
    /// are quantities to compare, not sentence subjects.
    ///
    /// - Parameter showErrors: as in `cellValue`; false drops the wrong clause
    ///   entirely rather than saying "0 wrong", which would itself be a hint.
    public static func progressSummary(_ game: NineGame, showErrors: Bool = true) -> String {
        let holes = game.puzzle.puzzle.emptyCount
        let filled = (0..<81).count(where: { game.entry(at: $0) != 0 && !game.isGiven($0) })
        var sentence = Phrase.filled(filled, of: holes)
        let wrong = game.errorCells.count
        if showErrors, wrong > 0 {
            sentence += " " + Phrase.wrongCount(wrong)
        }
        return sentence
    }

    // MARK: - Number words

    /// `1...9` spelled out, for use as a sentence subject ("four placed").
    /// Anything else returns "" — callers guard first.
    public static func digitWord(_ digit: Int) -> String {
        guard isValidDigit(digit) else { return "" }
        return Phrase.digitWord(digit)
    }

    /// `digitWord` with a leading capital, for sentence-initial position.
    public static func digitWordCapitalized(_ digit: Int) -> String {
        capitalizedFirst(digitWord(digit))
    }

    /// The plural noun for a digit: "fours", "sixes".
    public static func digitWordPlural(_ digit: Int) -> String {
        guard isValidDigit(digit) else { return "" }
        return Phrase.digitPlural(digit)
    }

    /// The digit as a noun agreeing with `count`: 1 → "four", else "fours".
    public static func digitNoun(_ digit: Int, count: Int) -> String {
        count == 1 ? digitWord(digit) : digitWordPlural(digit)
    }

    /// `0...9` spelled out, for counts inside sentences. Larger values fall
    /// back to numerals rather than growing an English number generator here.
    public static func countWord(_ count: Int) -> String {
        guard (0...9).contains(count) else { return String(count) }
        return Phrase.digitWord(count)
    }

    public static func countWordCapitalized(_ count: Int) -> String {
        capitalizedFirst(countWord(count))
    }

    // MARK: - Coach (PRD-11)

    /// A unit's name from its index in the engine's `units` table: `0..<9`
    /// rows, `9..<18` columns, `18..<27` boxes. Anything else — a variant
    /// unit, a bad index — returns "" and the caller's sentence falls back.
    public static func unitLabel(_ unitIndex: Int) -> String {
        switch unitIndex {
        case 0..<9:   return Phrase.row(unitIndex + 1)
        case 9..<18:  return Phrase.column(unitIndex - 9 + 1)
        case 18..<27: return Phrase.box(unitIndex - 18 + 1)
        default:      return ""
        }
    }

    /// The coach card's heading — the technique's name, or the state's.
    public static func coachTitle(_ advice: CoachAdvice) -> String {
        switch advice {
        case .step(let coach): return Phrase.techniqueName(coach.step.technique)
        case .contradiction:   return Phrase.coachSlipTitle
        case .exhausted:       return Phrase.coachExhaustedTitle
        case .solved:          return Phrase.coachSolvedTitle
        }
    }

    /// The one sentence the card shows *and* VoiceOver speaks.
    ///
    /// Deliberately takes no `NineGame`. The coach must never be able to reach
    /// `puzzle.solution`, and the cheapest way to guarantee that is to give it
    /// nothing to reach it through — the rule becomes a signature rather than a
    /// comment somebody has to remember.
    public static func coachSentence(_ advice: CoachAdvice) -> String {
        switch advice {
        case .contradiction:   return Phrase.coachSlip
        case .exhausted:       return Phrase.coachExhausted
        case .solved:          return solvedAnnouncement
        case .step(let coach): return stepSentence(coach)
        }
    }

    private static func stepSentence(_ coach: CoachStep) -> String {
        let step = coach.step
        let digit = step.digits.first ?? 0
        switch step.technique {
        case .nakedSingle:
            guard let cell = step.cells.first, isValidDigit(digit) else { return "" }
            return Phrase.coachNakedSingle(cellLabel(cell), digitWord(digit))

        case .hiddenSingle:
            guard let cell = step.cells.first, isValidDigit(digit) else { return "" }
            let unit = unitLabel(coach.patternUnit ?? -1)
            guard !unit.isEmpty else {
                return Phrase.coachHiddenSingleFallback(cellLabel(cell), digitWord(digit))
            }
            return Phrase.coachHiddenSingle(unit, digitWord(digit))

        case .nakedPair:
            guard step.digits.count == 2 else { return "" }
            return Phrase.coachNakedPair(
                digitWordCapitalized(step.digits[0]), digitWord(step.digits[1]),
                unitLabel(coach.targetUnit ?? -1)
            )

        case .hiddenPair:
            guard step.digits.count == 2 else { return "" }
            return Phrase.coachHiddenPair(
                digitWordCapitalized(step.digits[0]), digitWord(step.digits[1]),
                unitLabel(coach.targetUnit ?? -1)
            )

        case .boxLineReduction:
            guard isValidDigit(digit) else { return "" }
            return Phrase.coachBoxLine(
                digitWord(digit),
                unitLabel(coach.patternUnit ?? -1),
                unitLabel(coach.targetUnit ?? -1)
            )

        case .xWing:
            guard isValidDigit(digit) else { return "" }
            // The four corners span two rows *and* two columns whichever axis
            // was the base, so they cannot say which it was. The victims can: a
            // row-based X-wing eliminates down the shared columns.
            let corners = Set(step.cells.map(Sudoku.col(of:)))
            let victims = Set(step.eliminations.map { Sudoku.col(of: $0.cell) })
            let baseIsRow = victims.isSubset(of: corners)
            return Phrase.coachXWing(
                digitWordPlural(digit),
                base: baseIsRow ? Phrase.rowsWord : Phrase.columnsWord,
                cover: baseIsRow ? Phrase.columnsWord : Phrase.rowsWord,
                digitWord(digit)
            )

        default:
            // The four variant techniques (PRD-23). Naming them here would trip
            // the channel seal, and they are unreachable on a classic board.
            return ""
        }
    }

    // MARK: - Guards

    private static func isValidCell(_ cell: Int) -> Bool { (0..<81).contains(cell) }

    private static func isValidDigit(_ digit: Int) -> Bool { (1...9).contains(digit) }

    private static func isValidBox(_ box: Int) -> Bool { (0..<9).contains(box) }

    /// Uppercases the first character only. `String.capitalized` would also
    /// touch later words and is locale-sensitive; this is a display tweak on a
    /// known ASCII word list.
    private static func capitalizedFirst(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst()
    }

    /// The streak chip's spoken label (PRD-13 §3).
    ///
    /// "Held" rather than "shielded", and no count anywhere: the shield is a
    /// glyph, not a currency, and speech is the one surface where a mechanic
    /// the covenant says does not exist could announce itself by accident.
    /// Without this, VoiceOver reads the SF Symbol's own name — "shield, left
    /// half filled, 12 day streak".
    public static func streakChip(days: Int, held: Bool) -> String {
        held ? Phrase.streakHeld(days) : Phrase.streak(days)
    }
}

// MARK: - Phrase book
//
// EVERY user-facing literal in this file lives here and nowhere else, and as of
// PRD-20 none of them is a literal at all: each body is one `Phrasebook` key.
// That was the whole point of the block — the formatting logic above did not
// move a line when the words became data.
//
// Nothing here reaches for a bundle. `Phrasebook.current` is English until the
// App installs a resolver (see `Phrasebook.swift` for the three independent
// reasons `LocalizedStringResource` cannot appear in this target), which is what
// keeps `BoardSpeechTests` runnable as the first, cheapest step in CI — before
// the simulator exists.
//
// Sentences end in a period so VoiceOver takes a breath between them. Labels
// and values do not: they are fragments VoiceOver stitches together itself. That
// distinction now lives in `EnglishPhrases`, and
// `testSentencesEndInPeriodsAndValuesDoNot` still holds it from this side.
private enum Phrase {
    // Cell identity
    static func cellLabel(row: Int, column: Int) -> String {
        Phrasebook.current.string("board.cell.label", .int(row), .int(column))
    }
    static func row(_ n: Int) -> String { Phrasebook.current.string("board.unit.row", .int(n)) }
    static func column(_ n: Int) -> String { Phrasebook.current.string("board.unit.column", .int(n)) }
    static func box(_ n: Int) -> String { Phrasebook.current.string("board.unit.box", .int(n)) }
    static var placeInstruction: String { Phrasebook.current.string("board.cell.placeHint") }

    // Streak chip (PRD-13). Values, not sentences: no trailing period.
    static func streak(_ days: Int) -> String {
        Phrasebook.current.string("board.streak.plain", .int(days))
    }
    static func streakHeld(_ days: Int) -> String {
        Phrasebook.current.string("board.streak.held", .int(days))
    }

    // Group scan. A value, so no trailing period.
    static var boxFilled: String { Phrasebook.current.string("board.box.filled") }
    static func boxEmptyCount(_ count: Int) -> String {
        Phrasebook.current.string("board.box.empty", .int(count))
    }

    // Voice Control names. No punctuation anywhere: these are matched against
    // a speech recogniser's output, which never emits a comma.
    static func cellAddress(row: Int, column: Int) -> String {
        Phrasebook.current.string("board.voiceName.cell", .int(row), .int(column))
    }
    static func spokenCellLabel(row: Int, column: Int) -> String {
        Phrasebook.current.string("board.voiceName.rowColumn", .int(row), .int(column))
    }
    static func bareAddress(row: Int, column: Int) -> String {
        Phrasebook.current.string("board.voiceName.bare", .int(row), .int(column))
    }

    // Cell contents
    static func givenValue(_ digit: Int) -> String {
        Phrasebook.current.string("board.value.given", .int(digit))
    }
    static func plainValue(_ digit: Int) -> String {
        Phrasebook.current.string("board.value.plain", .int(digit))
    }
    static func wrongValue(_ digit: Int) -> String {
        Phrasebook.current.string("board.value.wrong", .int(digit))
    }
    static var empty: String { Phrasebook.current.string("board.value.empty") }
    static func emptyWithNotes(_ list: String) -> String {
        Phrasebook.current.string("board.value.notes", .text(list))
    }
    static var listSeparator: String { Phrasebook.current.string("board.value.noteSeparator") }

    // Move announcements
    static func placed(_ digitWord: String) -> String {
        Phrasebook.current.string("board.announce.placed", .text(digitWord))
    }
    static func remaining(_ countWord: String, _ digitNoun: String) -> String {
        Phrasebook.current.string("board.announce.remaining", .text(countWord), .text(digitNoun))
    }
    static func allDone(_ digitPlural: String) -> String {
        Phrasebook.current.string("board.announce.allDone", .text(digitPlural))
    }
    static func cleared(_ digitWord: String) -> String {
        Phrasebook.current.string("board.announce.cleared", .text(digitWord))
    }
    static func noteAdded(_ digitWord: String) -> String {
        Phrasebook.current.string("board.announce.noteAdded", .text(digitWord))
    }
    static func noteRemoved(_ digitWord: String) -> String {
        Phrasebook.current.string("board.announce.noteRemoved", .text(digitWord))
    }
    static var solved: String { Phrasebook.current.string("board.announce.solved") }

    // Board summary
    static func filled(_ filled: Int, of total: Int) -> String {
        Phrasebook.current.string("board.progress.filled", .int(filled), .int(total))
    }
    static func wrongCount(_ count: Int) -> String {
        Phrasebook.current.string("board.progress.wrong", .int(count))
    }

    // Coach (PRD-11). Every one of these is a claim about the board the player
    // could check by hand — not one of them consults the solution, which is why
    // the wording is identical whether "show mistakes" is on or off.
    /// The technique's name, keyed off the frozen raw value rather than a
    /// `switch`. `Technique.displayName` used to answer this and lived in the
    /// Engine, which compiles on Linux and must never reach a bundle (PRD-20).
    /// Built by interpolation on purpose: a `switch` here would be a second list
    /// that can disagree with the enum, and appending a case would compile.
    /// `CatalogTests.testEveryEngineIdentifierIsNamed` is what catches the
    /// append instead.
    static func techniqueName(_ technique: Technique) -> String {
        Phrasebook.current.string("technique.\(technique.rawValue).name")
    }

    static var coachSlipTitle: String { Phrasebook.current.string("coach.slip.title") }
    static var coachSlip: String { Phrasebook.current.string("coach.slip.body") }
    static var coachExhaustedTitle: String { Phrasebook.current.string("coach.exhausted.title") }
    static var coachExhausted: String { Phrasebook.current.string("coach.exhausted.body") }
    static var coachSolvedTitle: String { Phrasebook.current.string("coach.solved.title") }
    static var rowsWord: String { Phrasebook.current.string("coach.axis.rows") }
    static var columnsWord: String { Phrasebook.current.string("coach.axis.columns") }
    static func coachNakedSingle(_ cell: String, _ digit: String) -> String {
        Phrasebook.current.string("coach.nakedSingle.body", .text(cell), .text(digit))
    }
    static func coachHiddenSingle(_ unit: String, _ digit: String) -> String {
        Phrasebook.current.string("coach.hiddenSingle.body", .text(unit), .text(digit))
    }
    static func coachHiddenSingleFallback(_ cell: String, _ digit: String) -> String {
        Phrasebook.current.string("coach.hiddenSingle.fallback", .text(cell), .text(digit))
    }
    static func coachNakedPair(_ first: String, _ second: String, _ unit: String) -> String {
        Phrasebook.current.string("coach.nakedPair.body", .text(first), .text(second), .text(unit))
    }
    static func coachHiddenPair(_ first: String, _ second: String, _ unit: String) -> String {
        Phrasebook.current.string("coach.hiddenPair.body", .text(first), .text(second), .text(unit))
    }
    /// The target unit is named twice in English and once in the arguments —
    /// `%3$@` appears twice in `coach.boxLine.body`. That is the reason the
    /// specifiers are positional rather than bare: a bare `%@` cannot be reused.
    static func coachBoxLine(_ digit: String, _ source: String, _ target: String) -> String {
        Phrasebook.current.string("coach.boxLine.body",
                                  .text(digit), .text(source), .text(target))
    }
    static func coachXWing(_ plural: String, base: String, cover: String, _ digit: String) -> String {
        Phrasebook.current.string("coach.xWing.body",
                                  .text(sentenceCased(plural)), .text(base), .text(cover),
                                  .text(digit))
    }
    /// `BoardSpeech.capitalizedFirst` is private to the formatter above; the
    /// phrase book needs the same tweak for a sentence-initial plural.
    private static func sentenceCased(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst()
    }

    // Number words, one catalog key per digit — the ruling on PRD-20's plan, so
    // that a language whose "four" inflects by case can spell each one. Indexed
    // by the number itself: `digitWordKeys[0]` is "zero", which is only ever a
    // *count*, never a digit on a board.
    static func digitWord(_ number: Int) -> String {
        Phrasebook.current.string(digitWordKeys[number])
    }
    /// The plural noun for a digit, 1...9.
    static func digitPlural(_ digit: Int) -> String {
        Phrasebook.current.string(digitPluralKeys[digit - 1])
    }
    private static let digitWordKeys = [
        "board.digitWord.zero", "board.digitWord.one", "board.digitWord.two",
        "board.digitWord.three", "board.digitWord.four", "board.digitWord.five",
        "board.digitWord.six", "board.digitWord.seven", "board.digitWord.eight",
        "board.digitWord.nine",
    ]
    private static let digitPluralKeys = [
        "board.digitPlural.one", "board.digitPlural.two", "board.digitPlural.three",
        "board.digitPlural.four", "board.digitPlural.five", "board.digitPlural.six",
        "board.digitPlural.seven", "board.digitPlural.eight", "board.digitPlural.nine",
    ]
}
