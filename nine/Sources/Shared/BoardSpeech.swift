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
// This is also the Coach's phrasebook (PRD-19 §2 onward), and PRD-20 Task 7
// changed the shape of that. A coach sentence is now ONE catalog entry, never a
// frame with nouns dropped into it: the unit kind is baked into the *key*, so
// there is a `coach.hiddenSingle.sentence.row` and a `…sentence.box` rather than
// one sentence with a spliced "Row 4". Splicing a noun into a frame fixes
// English's grammar in the code, where no translator can reach it — English
// needs one preposition and no inflection, German inflects the noun, Japanese
// wants the whole clause in another order. Two rows where there was one
// function is the cost, and it is the point.
//
// The digit noun is the one permitted splice, and it is a ruling rather than an
// oversight (2026-07-26): speech synthesis reads "two fours remaining" naturally
// and "2 4's remaining" badly, and that surface is what PRD-19 exists to
// protect. So `digitWord`/`digitPlural` stay per-digit catalog entries a
// sentence may name, and nothing else does. `BoardSpeechTests` holds both halves
// — the seal over `coach.*` and the extent of the exception, which is every
// `.text(…)` argument in this file.
//
// Nothing here capitalizes a word. Sentence-casing a translated noun is an
// English-only operation — German capitalizes nouns wherever they stand,
// Japanese has no case at all — so every catalog entry carries its own
// capitalization and no argument ever lands sentence-initial.
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
    ///
    /// The `". "` between the two was a Swift literal until the test written for
    /// `board.announce.pair` found it — the same defect, in the same file, one
    /// screen further up. English separates two utterances with a full stop and
    /// a space; Japanese uses 。 and no space. Both halves are finished
    /// translated strings, so the join carries punctuation and order and nothing
    /// else, exactly like `coach.card.label`.
    public static func cellHint(_ cell: Int) -> String {
        guard isValidCell(cell) else { return "" }
        return Phrase.hintPair(firstSentence: boxLabel(cell),
                               secondSentence: Phrase.placeInstruction)
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

    /// Spoken after a digit lands. "Placed four. That leaves two fours."
    /// The caller owns the solved case — when the board completes it should say
    /// `solvedAnnouncement` instead, so the celebration is not buried behind a
    /// count of zero.
    ///
    /// Verb-first, and that is a localization decision rather than a stylistic
    /// one: "Four placed." puts a spliced noun at the head of a sentence, which
    /// is the position that needs a capital in English, needs none in Japanese,
    /// and needs one everywhere in German. A template that opens with its own
    /// word owns its own capital, and the code stops guessing.
    ///
    /// **The join is a catalog entry too**, for the same reason
    /// `coach.card.label` is one: the gap between two sentences is punctuation,
    /// and punctuation belongs to the language — Japanese ends a sentence with
    /// 。 and puts no space after it. This was a hard-coded `" "` in Swift, in
    /// the most frequently spoken string in the app: once per digit placed,
    /// roughly fifty times a board. Neither seal could see it, because string
    /// interpolation is not a `.text(…)` argument — which is exactly the shape
    /// of oversight this task exists to remove.
    public static func placementAnnouncement(digit: Int, in game: NineGame) -> String {
        guard isValidDigit(digit) else { return "" }
        return Phrase.pair(firstSentence: Phrase.placed(digitWord(digit)),
                           secondSentence: remainingClause(digit: digit, in: game))
    }

    /// "That leaves two fours." / "That leaves one four." / "All fours done."
    public static func remainingClause(digit: Int, in game: NineGame) -> String {
        guard isValidDigit(digit) else { return "" }
        // Clamped: a hand-built game could in principle carry more than nine of
        // a digit, and "minus one remaining" is not a sentence.
        let remaining = min(max(9 - game.count(of: digit), 0), 9)
        guard remaining > 0 else { return Phrase.allDone(digitWordPlural(digit)) }
        return Phrase.remaining(countWord(remaining), digitNoun(digit, count: remaining))
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

    /// "Cleared four."
    public static func eraseAnnouncement(digit: Int) -> String {
        guard isValidDigit(digit) else { return "" }
        return Phrase.cleared(digitWord(digit))
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

    // Every word here is lowercase, in its citation form, and stays that way.
    // These are the ONLY pre-formatted words this file splices into a sentence
    // (the ruling of 2026-07-26: VoiceOver reads "two fours remaining" and
    // mangles "2 4's remaining"), and the sentences that take them are written
    // so that none of them ever lands sentence-initial. A language that
    // capitalizes its number nouns capitalizes them in the catalog.

    /// `1...9` spelled out, for use as a noun inside a sentence ("placed four").
    /// Anything else returns "" — callers guard first.
    public static func digitWord(_ digit: Int) -> String {
        guard isValidDigit(digit) else { return "" }
        return Phrase.digitWord(digit)
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

    // MARK: - Coach (PRD-11)

    /// Which of the engine's three unit kinds an index names, and that unit's
    /// 1-based number: `0..<9` rows, `9..<18` columns, `18..<27` boxes.
    /// Anything else — a variant unit, a bad index — is nil, and the caller's
    /// sentence is empty rather than half-built.
    ///
    /// The *kind* comes back rather than a name, and that is the whole of Task
    /// 7 in one signature. A `unitLabel` returning "Row 4" could only ever be
    /// dropped into a hole in a sentence, and the grammar around that hole was
    /// English's: one preposition, no inflection, subject first. The kind picks
    /// a whole catalog entry instead, and every language writes its own.
    private static func unit(_ unitIndex: Int) -> Unit? {
        switch unitIndex {
        case 0..<9:   return Unit(kind: .row, number: unitIndex + 1)
        case 9..<18:  return Unit(kind: .column, number: unitIndex - 9 + 1)
        case 18..<27: return Unit(kind: .box, number: unitIndex - 18 + 1)
        default:      return nil
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

    /// Every branch here hands the phrase book numbers and a unit *kind*, and
    /// gets a whole sentence back. Nothing is assembled in this function, which
    /// is why a translator can move any part of any of these sentences.
    ///
    /// Numerals, not digit words: a coach sentence is read on the card as well
    /// as spoken, "7" is what the board draws, and VoiceOver says "seven" for it
    /// anyway. The spelled words earn their keep in the announcements, where
    /// speech is the only consumer.
    ///
    /// A unit index the engine's convention does not cover — a variant unit, an
    /// absent one — returns "" rather than a sentence with a hole in it. The old
    /// code spliced an empty label and said "…anywhere else in ."
    private static func stepSentence(_ coach: CoachStep) -> String {
        let step = coach.step
        let digit = step.digits.first ?? 0
        switch step.technique {
        case .nakedSingle:
            guard let cell = step.cells.first, isValidCell(cell), isValidDigit(digit) else { return "" }
            return Phrase.coachNakedSingle(row: Sudoku.row(of: cell) + 1,
                                           column: Sudoku.col(of: cell) + 1,
                                           digit: digit)

        case .hiddenSingle:
            guard let cell = step.cells.first, isValidCell(cell), isValidDigit(digit) else { return "" }
            guard let unit = unit(coach.patternUnit ?? -1) else {
                return Phrase.coachHiddenSingleInCell(row: Sudoku.row(of: cell) + 1,
                                                      column: Sudoku.col(of: cell) + 1,
                                                      digit: digit)
            }
            return Phrase.coachHiddenSingle(in: unit, digit: digit)

        case .nakedPair:
            guard step.digits.count == 2, step.digits.allSatisfy(isValidDigit),
                  let unit = unit(coach.targetUnit ?? -1) else { return "" }
            return Phrase.coachNakedPair(step.digits[0], step.digits[1], in: unit)

        case .hiddenPair:
            guard step.digits.count == 2, step.digits.allSatisfy(isValidDigit),
                  let unit = unit(coach.targetUnit ?? -1) else { return "" }
            return Phrase.coachHiddenPair(step.digits[0], step.digits[1], in: unit)

        case .boxLineReduction:
            guard isValidDigit(digit),
                  let source = unit(coach.patternUnit ?? -1),
                  let target = unit(coach.targetUnit ?? -1) else { return "" }
            return Phrase.coachBoxLine(digit: digit, from: source, to: target)

        case .xWing:
            guard isValidDigit(digit) else { return "" }
            // The four corners span two rows *and* two columns whichever axis
            // was the base, so they cannot say which it was. The victims can: a
            // row-based X-wing eliminates down the shared columns.
            let corners = Set(step.cells.map(Sudoku.col(of:)))
            let victims = Set(step.eliminations.map { Sudoku.col(of: $0.cell) })
            let baseIsRow = victims.isSubset(of: corners)
            return Phrase.coachXWing(digit: digit, baseIsRow: baseIsRow)

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

// MARK: - Units
//
/// One of the engine's three unit kinds, plus the unit's 1-based number.
///
/// A kind rather than a name, and the two are not interchangeable: a name is a
/// noun somebody has to put somewhere in a sentence, and *where* is the part
/// that differs per language. A kind picks the sentence.
private struct Unit {
    enum Kind { case row, column, box }
    let kind: Kind
    let number: Int
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
    /// The cell hint's join: a box label, then how to act on the cell. Same
    /// shape and same reasoning as `Phrase.pair`, a separate key because the two
    /// surfaces may want different punctuation — this one follows a label rather
    /// than a sentence.
    static func hintPair(firstSentence: String, secondSentence: String) -> String {
        Phrasebook.current.string("board.cell.hintPair",
                                  .text(firstSentence), .text(secondSentence))
    }

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
    /// **Not a catalog key** (PRD-20 Task 8) — the other half of the finding
    /// `plainValue` records. `board.voiceName.bare` was `"%1$lld %2$lld"`: two
    /// specifiers and a space, nothing a translator can translate and
    /// everything a string transform can break.
    ///
    /// What is left is the *separator*, and that stays a catalog entry — Task
    /// 7's rule, unchanged: whatever goes between two tokens is punctuation
    /// this language chose, and English's happens to be a space. So the numbers
    /// are formatted here and the join is translated, which is the same split
    /// `board.announce.pair` makes for two sentences. A separate key because a
    /// recogniser's input name and a spoken sentence are different registers
    /// and a language may well separate them differently.
    static func bareAddress(row: Int, column: Int) -> String {
        let rowNumeral = numeral(row)
        let columnNumeral = numeral(column)
        return Phrasebook.current.string("board.voiceName.pair",
                                         .text(rowNumeral), .text(columnNumeral))
    }

    // Cell contents
    static func givenValue(_ digit: Int) -> String {
        Phrasebook.current.string("board.value.given", .int(digit))
    }

    /// **Not a catalog key** (PRD-20 Task 8), and this one was measured.
    ///
    /// `board.value.plain` was `"%1$lld"` — a translation unit whose entire
    /// content is one format specifier. Run the app under
    /// `-NSDoubleLocalizedStrings YES` and every digit on the board reads
    /// **`lld 4`**: the pseudolocalizer rewrites the specifier, because to a
    /// string transform that is all there is in the string. Nothing shipped
    /// that way — the same build without the flag is correct — but the flag is
    /// only standing in for what a translator who does not read printf will do
    /// to a row that looks empty. `board.value.*` is what VoiceOver speaks for
    /// a filled cell, so the blast radius is every square on the board.
    ///
    /// A bare numeral is not language, so it is formatted rather than
    /// translated. `.formatted(.number)` is still locale-aware — this is where
    /// Eastern Arabic and Devanagari digits come from — and `.grouping(.never)`
    /// keeps a 1...9 digit a digit rather than risking a separator.
    static func plainValue(_ digit: Int) -> String { numeral(digit) }

    /// One numeral, in the reader's own digits. See `plainValue`.
    static func numeral(_ value: Int) -> String {
        value.formatted(.number.grouping(.never))
    }
    static func wrongValue(_ digit: Int) -> String {
        Phrasebook.current.string("board.value.wrong", .int(digit))
    }
    static var empty: String { Phrasebook.current.string("board.value.empty") }
    /// `noteList` is already joined, and it is a list of *numerals* — the only
    /// `.text(…)` in this file that is not a number word.
    static func emptyWithNotes(_ noteList: String) -> String {
        Phrasebook.current.string("board.value.notes", .text(noteList))
    }
    static var listSeparator: String { Phrasebook.current.string("board.value.noteSeparator") }

    // Move announcements. Spoken and never drawn — `announce(_:)` in `TouchUI`
    // and `MacUI` post them to VoiceOver — which is why the digit survives here
    // as a word while the coach card, which is read as well as spoken, uses the
    // numeral. Every one of these templates opens with its own word, so no
    // argument ever needs a capital it did not arrive with.
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
    /// Two finished utterances, in the order and with the separator this
    /// language joins utterances in. These two — and `Phrase.hintPair` below —
    /// are the only `.text(…)` arguments in this file that are not number
    /// words, and they are the sibling of `coach.card.label`: what a join
    /// chooses is punctuation and order, both of which belong to the language.
    /// What may never be spliced is a *noun*, because what is chosen around a
    /// noun is grammar, and that belongs to the sentence.
    ///
    /// The test that guards this reads the parameter names, so the name is the
    /// rule: whatever is passed must be able to stand alone as an utterance.
    /// "Box 2" and "Placed four." can. "rows" cannot.
    static func pair(firstSentence: String, secondSentence: String) -> String {
        Phrasebook.current.string("board.announce.pair",
                                  .text(firstSentence), .text(secondSentence))
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
    static var coachSlip: String { Phrasebook.current.string("coach.slip.sentence") }
    static var coachExhaustedTitle: String { Phrasebook.current.string("coach.exhausted.title") }
    static var coachExhausted: String { Phrasebook.current.string("coach.exhausted.sentence") }
    static var coachSolvedTitle: String { Phrasebook.current.string("coach.solved.title") }

    // One key per technique PER UNIT KIND, written out rather than assembled
    // from `"coach.hiddenSingle.sentence." + kind`. Three reasons, and the
    // first two are enough on their own:
    //
    //   • Every key is then a literal at the point it is used, so
    //     `scripts/strings.py --audit` can see it. A key built by interpolation
    //     reads as dead, and a dead key is one Task 9 does not pay to translate.
    //   • A `switch` over the kind is exhaustive; a string built from it is not.
    //     Adding a fourth unit kind (PRD-23's cages) stops compiling here
    //     instead of shipping "coach.hiddenSingle.sentence.cage" to a player.
    //   • The repetition is legible: this is the whole list of things the coach
    //     can say, in one place, in the language it says them.
    static func coachNakedSingle(row: Int, column: Int, digit: Int) -> String {
        Phrasebook.current.string("coach.nakedSingle.sentence",
                                  .int(row), .int(column), .int(digit))
    }
    static func coachHiddenSingle(in unit: Unit, digit: Int) -> String {
        switch unit.kind {
        case .row:
            return Phrasebook.current.string("coach.hiddenSingle.sentence.row",
                                             .int(unit.number), .int(digit))
        case .column:
            return Phrasebook.current.string("coach.hiddenSingle.sentence.col",
                                             .int(unit.number), .int(digit))
        case .box:
            return Phrasebook.current.string("coach.hiddenSingle.sentence.box",
                                             .int(unit.number), .int(digit))
        }
    }
    /// The hidden single whose confining unit the solver could not name. Says
    /// the same thing about the square instead, and never mentions a unit.
    static func coachHiddenSingleInCell(row: Int, column: Int, digit: Int) -> String {
        Phrasebook.current.string("coach.hiddenSingle.sentence.cell",
                                  .int(row), .int(column), .int(digit))
    }
    static func coachNakedPair(_ first: Int, _ second: Int, in unit: Unit) -> String {
        switch unit.kind {
        case .row:
            return Phrasebook.current.string("coach.nakedPair.sentence.row",
                                             .int(first), .int(second), .int(unit.number))
        case .column:
            return Phrasebook.current.string("coach.nakedPair.sentence.col",
                                             .int(first), .int(second), .int(unit.number))
        case .box:
            return Phrasebook.current.string("coach.nakedPair.sentence.box",
                                             .int(first), .int(second), .int(unit.number))
        }
    }
    static func coachHiddenPair(_ first: Int, _ second: Int, in unit: Unit) -> String {
        switch unit.kind {
        case .row:
            return Phrasebook.current.string("coach.hiddenPair.sentence.row",
                                             .int(first), .int(second), .int(unit.number))
        case .column:
            return Phrasebook.current.string("coach.hiddenPair.sentence.col",
                                             .int(first), .int(second), .int(unit.number))
        case .box:
            return Phrasebook.current.string("coach.hiddenPair.sentence.box",
                                             .int(first), .int(second), .int(unit.number))
        }
    }
    /// A box-line reduction is a box and a line, in one direction or the other:
    /// pointing gives box → line, claiming gives line → box (`Coach.swift`).
    /// Four sentences cover it, and the fifth case cannot arise — the pattern
    /// cells lie in exactly two units and one of them is always the box — so it
    /// says nothing rather than naming the wrong shapes.
    ///
    /// The target unit's number is spoken twice in English (`%3$lld` twice),
    /// which is the reason the specifiers are positional: a bare `%lld` cannot
    /// be reused, and a translation that moves one occurrence must move both.
    static func coachBoxLine(digit: Int, from source: Unit, to target: Unit) -> String {
        switch (source.kind, target.kind) {
        case (.box, .row):
            return Phrasebook.current.string("coach.boxLine.sentence.boxToRow",
                                             .int(digit), .int(source.number), .int(target.number))
        case (.box, .column):
            return Phrasebook.current.string("coach.boxLine.sentence.boxToCol",
                                             .int(digit), .int(source.number), .int(target.number))
        case (.row, .box):
            return Phrasebook.current.string("coach.boxLine.sentence.rowToBox",
                                             .int(digit), .int(source.number), .int(target.number))
        case (.column, .box):
            return Phrasebook.current.string("coach.boxLine.sentence.colToBox",
                                             .int(digit), .int(source.number), .int(target.number))
        default:
            return ""
        }
    }
    /// The base axis picks the sentence, and the cover axis is inside it. There
    /// is no "rows"/"columns" word to hand around any more: `coach.axis.rows`
    /// was a noun in whatever case English needed at both sites it landed in.
    static func coachXWing(digit: Int, baseIsRow: Bool) -> String {
        baseIsRow
            ? Phrasebook.current.string("coach.xWing.sentence.rowBase", .int(digit))
            : Phrasebook.current.string("coach.xWing.sentence.colBase", .int(digit))
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
