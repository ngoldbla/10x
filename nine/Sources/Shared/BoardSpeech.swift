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
    public static let solvedAnnouncement = Phrase.solved

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
        return Phrase.digitWords[digit - 1]
    }

    /// `digitWord` with a leading capital, for sentence-initial position.
    public static func digitWordCapitalized(_ digit: Int) -> String {
        capitalizedFirst(digitWord(digit))
    }

    /// The plural noun for a digit: "fours", "sixes".
    public static func digitWordPlural(_ digit: Int) -> String {
        guard isValidDigit(digit) else { return "" }
        return Phrase.digitPlurals[digit - 1]
    }

    /// The digit as a noun agreeing with `count`: 1 → "four", else "fours".
    public static func digitNoun(_ digit: Int, count: Int) -> String {
        count == 1 ? digitWord(digit) : digitWordPlural(digit)
    }

    /// `0...9` spelled out, for counts inside sentences. Larger values fall
    /// back to numerals rather than growing an English number generator here.
    public static func countWord(_ count: Int) -> String {
        guard (0...9).contains(count) else { return String(count) }
        return count == 0 ? Phrase.zeroWord : Phrase.digitWords[count - 1]
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
        case .step(let coach): return coach.step.technique.displayName
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
}

// MARK: - Phrase book
//
// EVERY user-facing literal in this file lives here and nowhere else. That is
// the whole point: PRD-20 (localization) replaces the bodies below with
// `LocalizedStringResource` lookups and the formatting logic above does not
// move a line. Do not interpolate an English word anywhere outside this block,
// and do not add a String Catalog yet — the seam is the deliverable, the
// catalog comes with PRD-20.
//
// Sentences end in a period so VoiceOver takes a breath between them. Labels
// and values do not: they are fragments VoiceOver stitches together itself.
private enum Phrase {
    // Cell identity
    static func cellLabel(row: Int, column: Int) -> String { "Row \(row), column \(column)" }
    static func row(_ n: Int) -> String { "Row \(n)" }
    static func column(_ n: Int) -> String { "Column \(n)" }
    static func box(_ n: Int) -> String { "Box \(n)" }
    static let placeInstruction = "Flick or use the actions rotor to place a digit."

    // Group scan. A value, so no trailing period.
    static let boxFilled = "Filled"
    static func boxEmptyCount(_ count: Int) -> String { "\(count) empty" }

    // Voice Control names. No punctuation anywhere: these are matched against
    // a speech recogniser's output, which never emits a comma.
    static func cellAddress(row: Int, column: Int) -> String { "Cell \(row) \(column)" }
    static func spokenCellLabel(row: Int, column: Int) -> String { "Row \(row) column \(column)" }
    static func bareAddress(row: Int, column: Int) -> String { "\(row) \(column)" }

    // Cell contents
    static func givenValue(_ digit: Int) -> String { "\(digit), given" }
    static func plainValue(_ digit: Int) -> String { "\(digit)" }
    static func wrongValue(_ digit: Int) -> String { "\(digit), wrong" }
    static let empty = "Empty"
    static func emptyWithNotes(_ list: String) -> String { "Empty, notes \(list)" }
    static let listSeparator = ", "

    // Move announcements
    static func placed(_ digitWord: String) -> String { "\(digitWord) placed." }
    static func remaining(_ countWord: String, _ digitNoun: String) -> String {
        "\(countWord) \(digitNoun) remaining."
    }
    static func allDone(_ digitPlural: String) -> String { "All \(digitPlural) done." }
    static func cleared(_ digitWord: String) -> String { "\(digitWord) cleared." }
    static func noteAdded(_ digitWord: String) -> String { "Note \(digitWord) added." }
    static func noteRemoved(_ digitWord: String) -> String { "Note \(digitWord) removed." }
    static let solved = "Solved."

    // Board summary
    static func filled(_ filled: Int, of total: Int) -> String { "\(filled) of \(total) filled." }
    static func wrongCount(_ count: Int) -> String { "\(count) wrong." }

    // Coach (PRD-11). Every one of these is a claim about the board the player
    // could check by hand — not one of them consults the solution, which is why
    // the wording is identical whether "show mistakes" is on or off.
    static let coachSlipTitle = "A slip somewhere"
    static let coachSlip = "Two of these squares disagree, so nothing can follow from here."
    static let coachExhaustedTitle = "Nothing follows"
    static let coachExhausted = "Nothing at this board's level follows from here."
    static let coachSolvedTitle = "Done"
    static let rowsWord = "rows"
    static let columnsWord = "columns"
    static func coachNakedSingle(_ cell: String, _ digit: String) -> String {
        "\(cell) has one candidate left: \(digit)."
    }
    static func coachHiddenSingle(_ unit: String, _ digit: String) -> String {
        "Only one square in \(unit) can take a \(digit)."
    }
    static func coachHiddenSingleFallback(_ cell: String, _ digit: String) -> String {
        "\(cell) is the only square left that can take a \(digit)."
    }
    static func coachNakedPair(_ first: String, _ second: String, _ unit: String) -> String {
        "\(first) and \(second) fill these two squares between them, "
            + "so neither can go anywhere else in \(unit)."
    }
    static func coachHiddenPair(_ first: String, _ second: String, _ unit: String) -> String {
        "\(first) and \(second) fit only these two squares in \(unit), so nothing else fits there."
    }
    static func coachBoxLine(_ digit: String, _ source: String, _ target: String) -> String {
        "Every \(digit) still possible in \(source) sits in \(target), "
            + "so no other square in \(target) can be a \(digit)."
    }
    static func coachXWing(_ plural: String, base: String, cover: String, _ digit: String) -> String {
        "\(sentenceCased(plural)) in these two \(base) can only sit in two \(cover), "
            + "so no other square in those \(cover) can be a \(digit)."
    }
    /// `BoardSpeech.capitalizedFirst` is private to the formatter above; the
    /// phrase book needs the same tweak for a sentence-initial plural.
    private static func sentenceCased(_ word: String) -> String {
        guard let first = word.first else { return word }
        return String(first).uppercased() + word.dropFirst()
    }

    // Number words. Index 0 is the digit 1 — there is no zero digit on a board,
    // and `zeroWord` is only ever a *count*.
    static let digitWords = [
        "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
    ]
    static let digitPlurals = [
        "ones", "twos", "threes", "fours", "fives", "sixes", "sevens", "eights", "nines",
    ]
    static let zeroWord = "zero"
}
