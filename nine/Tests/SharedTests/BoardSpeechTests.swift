// BoardSpeechTests — the spoken board (PRD-19). These pin four things that
// are easy to regress and impossible to notice without a screen reader:
// 1-basing of row/column/box, the singular/plural boundaries in the
// announcements, the `showErrors: false` privacy branch — VoiceOver must
// never reveal a wrong entry the sighted player is not being shown — and, since
// PRD-20 Task 7, the shape of the sentences themselves.
//
// That last one is why this file is a specification rather than a regression
// net, and why CI runs it before it will build a simulator: a coach sentence
// assembled from fragments still reads perfectly in English, so English is the
// one language in which the bug is invisible. The three tests under "The rule
// this task landed" fail on a change that compiles, passes every other test,
// and would have shipped nine languages of grammatical-looking nonsense.
import XCTest
import Foundation
import NineEngine
@testable import NineShared

final class BoardSpeechTests: XCTestCase {

    private var puzzle: GeneratedPuzzle!
    private var game: NineGame!
    private var hole: Int! // first empty cell

    override func setUp() {
        super.setUp()
        puzzle = PuzzleGenerator.generate(seed: 1, difficulty: .gentle)
        game = NineGame(puzzle: puzzle)
        hole = (0..<81).first { puzzle.puzzle[$0] == 0 }
    }

    // MARK: - Cell identity

    func testCellLabelIsOneBasedAtCornersAndCentre() {
        XCTAssertEqual(BoardSpeech.cellLabel(0), "Row 1, column 1")
        XCTAssertEqual(BoardSpeech.cellLabel(8), "Row 1, column 9")
        XCTAssertEqual(BoardSpeech.cellLabel(72), "Row 9, column 1")
        XCTAssertEqual(BoardSpeech.cellLabel(80), "Row 9, column 9")
        XCTAssertEqual(BoardSpeech.cellLabel(40), "Row 5, column 5")
    }

    func testRowColumnAndBoxLabels() {
        XCTAssertEqual(BoardSpeech.rowLabel(40), "Row 5")
        XCTAssertEqual(BoardSpeech.columnLabel(40), "Column 5")
        XCTAssertEqual(BoardSpeech.boxLabel(0), "Box 1")
        XCTAssertEqual(BoardSpeech.boxLabel(5), "Box 2", "row 1, column 6 sits in the top-middle box")
        XCTAssertEqual(BoardSpeech.boxLabel(80), "Box 9")
    }

    func testCellHintCarriesTheBoxAndTheInstruction() {
        XCTAssertEqual(
            BoardSpeech.cellHint(5),
            "Box 2. Flick or use the actions rotor to place a digit."
        )
        XCTAssertFalse(
            BoardSpeech.cellLabel(5).contains("Box"),
            "the box belongs in the once-per-focus hint, not in all 81 labels"
        )
    }

    // MARK: - Switch Control group labels

    func testBoxGroupLabelIsOneBasedOnTheBoxIndexNotACell() {
        XCTAssertEqual(BoardSpeech.boxGroupLabel(0), "Box 1")
        XCTAssertEqual(BoardSpeech.boxGroupLabel(4), "Box 5")
        XCTAssertEqual(BoardSpeech.boxGroupLabel(8), "Box 9")
    }

    func testBoxGroupLabelAgreesWithTheCellLevelBoxLabel() {
        for cell in 0..<81 {
            XCTAssertEqual(
                BoardSpeech.boxGroupLabel(Sudoku.box(of: cell)),
                BoardSpeech.boxLabel(cell),
                "the group scan and the cell hint must name the same box"
            )
        }
    }

    /// Switch Control group scan lands on a box before its nine cells; the
    /// value is what makes skipping a finished box possible in one switch hit.
    func testBoxGroupValueCountsEmptiesAndSaysFilledWhenThereAreNone() {
        let box = Sudoku.box(of: hole)
        let empties = (0..<81).count(where: { Sudoku.box(of: $0) == box && game.entry(at: $0) == 0 })
        XCTAssertEqual(BoardSpeech.boxGroupValue(box, in: game), "\(empties) empty")

        for cell in 0..<81 where Sudoku.box(of: cell) == box && game.entry(at: cell) == 0 {
            XCTAssertTrue(game.place(puzzle.solution[cell], at: cell))
        }
        XCTAssertEqual(BoardSpeech.boxGroupValue(box, in: game), "Filled")
    }

    func testBoxGroupValueIsSingularForOneEmptyCell() {
        let box = Sudoku.box(of: hole)
        let empties = (0..<81).filter { Sudoku.box(of: $0) == box && game.entry(at: $0) == 0 }
        for cell in empties.dropLast() {
            XCTAssertTrue(game.place(puzzle.solution[cell], at: cell))
        }
        XCTAssertEqual(BoardSpeech.boxGroupValue(box, in: game), "1 empty")
    }

    /// A box full of wrong digits still reads "Filled" — the group value is a
    /// count of holes, never a verdict. Same privacy rule as `cellValue`.
    func testBoxGroupValueNeverJudgesCorrectness() {
        let box = Sudoku.box(of: hole)
        for cell in 0..<81 where Sudoku.box(of: cell) == box && game.entry(at: cell) == 0 {
            XCTAssertTrue(game.place(wrongDigit(for: cell), at: cell))
        }
        XCTAssertEqual(BoardSpeech.boxGroupValue(box, in: game), "Filled")
    }

    func testBoxGroupOutOfRangeIsSilent() {
        for box in [-1, 9, 99, Int.min, Int.max] {
            XCTAssertEqual(BoardSpeech.boxGroupLabel(box), "")
            XCTAssertEqual(BoardSpeech.boxGroupValue(box, in: game), "")
        }
    }

    // MARK: - Voice Control addressing

    /// Voice Control speaks the *first* input label in "Show Names" and matches
    /// against all of them, so the canonical form leads and the alternates
    /// cover what a player would naturally say.
    func testCellInputLabelsLeadWithTheCompactSpokenForm() {
        XCTAssertEqual(
            BoardSpeech.cellInputLabels(40),
            ["Cell 5 5", "Row 5 column 5", "5 5"]
        )
        XCTAssertEqual(
            BoardSpeech.cellInputLabels(0).first,
            "Cell 1 1",
            "the leading name is the one the Show Names overlay draws on 81 cells"
        )
    }

    /// The label VoiceOver reads must be sayable: a player who hears
    /// "Row 3, column 5" has to be able to speak it at Voice Control, and
    /// commas are not spoken.
    func testCellInputLabelsIncludeTheSpokenFormOfTheVoiceOverLabel() {
        for cell in [0, 5, 40, 72, 80] {
            let spokenLabel = BoardSpeech.cellLabel(cell)
                .replacingOccurrences(of: ",", with: "")
            XCTAssertTrue(
                BoardSpeech.cellInputLabels(cell).contains(spokenLabel),
                "\(spokenLabel) is what VoiceOver just said; Voice Control must accept it"
            )
        }
    }

    func testEveryCellHasADistinctSetOfInputLabels() {
        var seen: Set<String> = []
        for cell in 0..<81 {
            let labels = BoardSpeech.cellInputLabels(cell)
            XCTAssertFalse(labels.isEmpty)
            for label in labels {
                XCTAssertTrue(
                    seen.insert(label).inserted,
                    "\(label) addresses two cells — Voice Control would pick one at random"
                )
            }
        }
    }

    /// Voice Control matches spoken text, so a name containing punctuation the
    /// recogniser never emits can never be matched.
    func testInputLabelsCarryNoPunctuation() {
        for cell in 0..<81 {
            for label in BoardSpeech.cellInputLabels(cell) {
                XCTAssertNil(
                    label.rangeOfCharacter(from: CharacterSet.punctuationCharacters),
                    "\(label) is not sayable"
                )
            }
        }
    }

    func testCellInputLabelsOutOfRangeAreEmpty() {
        for cell in [-1, 81, 999, Int.min, Int.max] {
            XCTAssertEqual(BoardSpeech.cellInputLabels(cell), [])
        }
    }

    // MARK: - Cell value branches

    func testGivenCellValueSaysGiven() {
        let given = (0..<81).first { puzzle.puzzle[$0] != 0 }!
        XCTAssertEqual(
            BoardSpeech.cellValue(given, in: game, showErrors: true),
            "\(puzzle.puzzle[given]), given"
        )
    }

    func testEmptyCellValue() {
        XCTAssertEqual(BoardSpeech.cellValue(hole, in: game, showErrors: true), "Empty")
    }

    func testEmptyCellWithNotesListsThemAscendingRegardlessOfEntryOrder() {
        XCTAssertTrue(game.togglePencil(9, at: hole))
        XCTAssertTrue(game.togglePencil(2, at: hole))
        XCTAssertTrue(game.togglePencil(5, at: hole))
        XCTAssertEqual(
            BoardSpeech.cellValue(hole, in: game, showErrors: true),
            "Empty, notes 2, 5, 9"
        )
    }

    func testCorrectUserEntryIsJustTheDigit() {
        let digit = puzzle.solution[hole]
        XCTAssertTrue(game.place(digit, at: hole))
        XCTAssertEqual(BoardSpeech.cellValue(hole, in: game, showErrors: true), "\(digit)")
    }

    func testWrongUserEntryIsMarkedWrongWhenErrorsAreShown() {
        let wrong = wrongDigit(for: hole)
        XCTAssertTrue(game.place(wrong, at: hole))
        XCTAssertTrue(game.isError(at: hole))
        XCTAssertEqual(BoardSpeech.cellValue(hole, in: game, showErrors: true), "\(wrong), wrong")
    }

    /// The load-bearing privacy test: with mistake-marking off, the AX value is
    /// indistinguishable from a correct entry. VoiceOver is not a cheat mode.
    func testWrongUserEntryLeaksNothingWhenErrorsAreHidden() {
        let wrong = wrongDigit(for: hole)
        XCTAssertTrue(game.place(wrong, at: hole))
        XCTAssertEqual(BoardSpeech.cellValue(hole, in: game, showErrors: false), "\(wrong)")

        var correct = NineGame(puzzle: puzzle)
        XCTAssertTrue(correct.place(puzzle.solution[hole], at: hole))
        XCTAssertNotEqual(
            BoardSpeech.cellValue(hole, in: game, showErrors: false),
            BoardSpeech.cellValue(hole, in: correct, showErrors: false),
            "different digits still read differently — only the wrongness is hidden"
        )
    }

    // MARK: - Placement announcements

    func testPlacementAnnouncementPluralSingularAndCompletionBoundaries() throws {
        // A digit with at least three holes, so the count walks 7 → 8 → 9.
        let digit = try XCTUnwrap((1...9).first { d in
            (0..<81).count(where: { !game.isGiven($0) && puzzle.solution[$0] == d }) >= 3
        })
        let holes = (0..<81).filter { !game.isGiven($0) && puzzle.solution[$0] == digit }
        let plural = BoardSpeech.digitWordPlural(digit)
        let singular = BoardSpeech.digitWord(digit)

        for cell in holes.dropLast(2) {
            XCTAssertTrue(game.place(digit, at: cell))
        }
        XCTAssertEqual(game.count(of: digit), 7)
        XCTAssertEqual(
            BoardSpeech.placementAnnouncement(digit: digit, in: game),
            "Placed \(singular). That leaves two \(plural)."
        )

        XCTAssertTrue(game.place(digit, at: holes[holes.count - 2]))
        XCTAssertEqual(
            BoardSpeech.placementAnnouncement(digit: digit, in: game),
            "Placed \(singular). That leaves one \(singular).",
            "one left is singular"
        )

        XCTAssertTrue(game.place(digit, at: holes[holes.count - 1]))
        XCTAssertTrue(game.isDigitComplete(digit))
        XCTAssertEqual(
            BoardSpeech.placementAnnouncement(digit: digit, in: game),
            "Placed \(singular). All \(plural) done."
        )
    }

    /// Every announcement is verb-first, and that is the shape of the rule
    /// rather than a preference: an argument standing at the head of a sentence
    /// is an argument something has to capitalize, and capitalizing a translated
    /// noun is an English-only operation. The word arrives in its citation form
    /// and the template owns the capital.
    func testNoAnnouncementOpensWithASplicedWord() {
        for digit in 1...9 {
            for sentence in [
                BoardSpeech.placementAnnouncement(digit: digit, in: game),
                BoardSpeech.eraseAnnouncement(digit: digit),
                BoardSpeech.noteAnnouncement(digit: digit, added: true),
                BoardSpeech.noteAnnouncement(digit: digit, added: false),
                BoardSpeech.remainingClause(digit: digit, in: game),
            ] {
                let opening = String(sentence.prefix(while: { $0 != " " }))
                XCTAssertFalse(
                    (1...9).map(BoardSpeech.digitWord).contains(opening.lowercased()),
                    "\"\(sentence)\" opens with the digit word — a position that needs a capital"
                )
                XCTAssertFalse(
                    (0...9).map(BoardSpeech.countWord).contains(opening.lowercased()),
                    "\"\(sentence)\" opens with a count word — the same trap one argument over"
                )
                XCTAssertEqual(
                    opening, opening.prefix(1).uppercased() + opening.dropFirst(),
                    "\"\(sentence)\" starts lowercase, so its capital went missing with the helper"
                )
            }
        }
    }

    /// The gap between two spoken sentences is punctuation, and punctuation
    /// belongs to the language: Japanese ends a sentence with 。 and puts no
    /// space after it. This is the app's most frequently spoken string — once
    /// per digit placed — and the join was a hard-coded `" "` in Swift until
    /// PRD-20 Task 7's review caught it, invisible to both seals because string
    /// interpolation is not a `.text(…)` argument.
    func testTheSentenceJoinIsACatalogEntryAndNotASpaceInSwift() throws {
        XCTAssertEqual(EnglishPhrases.table["board.announce.pair"], "%1$@ %2$@", """
            board.announce.pair is how two spoken sentences are joined. A \
            translation replaces the separator; English's happens to be a space.
            """)

        // The half-sentences it joins, composed independently of the code under
        // test, so this pins the join rather than restating it.
        XCTAssertEqual(
            BoardSpeech.placementAnnouncement(digit: 4, in: game),
            Phrasebook.english.string(
                "board.announce.pair",
                .text(Phrasebook.english.string("board.announce.placed", .text("four"))),
                .text(BoardSpeech.remainingClause(digit: 4, in: game))
            )
        )

        // …and the shape that would put the space back. Two runtime values
        // interpolated into one Swift literal IS a sentence assembled in code;
        // there is no other reason to write one in this file.
        let source = try String(contentsOf: Self.boardSpeechSource(), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.components(separatedBy: "//").first ?? "" }
        for (offset, line) in source.enumerated()
        where line.components(separatedBy: #"\("#).count - 1 >= 2 {
            XCTFail("""
                BoardSpeech.swift:\(offset + 1) builds a string out of two \
                interpolated values: \(line.trimmingCharacters(in: .whitespaces)). \
                Whatever separates them is punctuation this language chose for \
                every other language. Give it a catalog key.
                """)
        }
    }

    func testSolvedAnnouncementAndEraseAndNotes() {
        XCTAssertEqual(BoardSpeech.solvedAnnouncement, "Solved.")
        XCTAssertEqual(BoardSpeech.eraseAnnouncement(digit: 4), "Cleared four.")
        XCTAssertEqual(BoardSpeech.noteAnnouncement(digit: 4, added: true), "Note four added.")
        XCTAssertEqual(BoardSpeech.noteAnnouncement(digit: 4, added: false), "Note four removed.")
    }

    func testSentencesEndInPeriodsAndValuesDoNot() {
        XCTAssertTrue(BoardSpeech.eraseAnnouncement(digit: 1).hasSuffix("."))
        XCTAssertTrue(BoardSpeech.placementAnnouncement(digit: 1, in: game).hasSuffix("."))
        XCTAssertTrue(BoardSpeech.progressSummary(game).hasSuffix("."))
        XCTAssertTrue(BoardSpeech.cellHint(0).hasSuffix("."))
        XCTAssertFalse(BoardSpeech.cellLabel(0).hasSuffix("."))
        XCTAssertFalse(BoardSpeech.cellValue(hole, in: game, showErrors: true).hasSuffix("."))
    }

    // MARK: - Progress summary

    func testProgressSummaryCountsFilledHolesAndGatesWrongOnShowErrors() {
        let holes = puzzle.puzzle.emptyCount
        XCTAssertEqual(BoardSpeech.progressSummary(game), "0 of \(holes) filled.")

        let empties = (0..<81).filter { !game.isGiven($0) }
        for cell in empties.prefix(3) {
            XCTAssertTrue(game.place(puzzle.solution[cell], at: cell))
        }
        XCTAssertEqual(BoardSpeech.progressSummary(game), "3 of \(holes) filled.")

        let bad = empties[3]
        XCTAssertTrue(game.place(wrongDigit(for: bad), at: bad))
        XCTAssertEqual(game.errorCells.count, 1)
        XCTAssertEqual(BoardSpeech.progressSummary(game, showErrors: true), "4 of \(holes) filled. 1 wrong.")
        XCTAssertEqual(
            BoardSpeech.progressSummary(game, showErrors: false),
            "4 of \(holes) filled.",
            "hiding mistakes hides the count too — '0 wrong' would itself be a hint"
        )
    }

    // MARK: - Number words

    func testDigitWords() {
        XCTAssertEqual((1...9).map(BoardSpeech.digitWord), [
            "one", "two", "three", "four", "five", "six", "seven", "eight", "nine",
        ])
        XCTAssertEqual(BoardSpeech.digitWordPlural(6), "sixes", "not 'sixs'")
        XCTAssertEqual(BoardSpeech.digitNoun(4, count: 1), "four")
        XCTAssertEqual(BoardSpeech.digitNoun(4, count: 2), "fours")
        XCTAssertEqual(BoardSpeech.countWord(0), "zero")
        XCTAssertEqual(BoardSpeech.countWord(12), "12", "past nine we fall back to numerals")
    }

    /// The words are lowercase, in every position, because nothing in the app
    /// capitalizes them any more. A catalog whose German says "Vier" says it in
    /// the catalog; this is the English half of that promise.
    func testEveryNumberWordArrivesInItsCitationForm() {
        for digit in 1...9 {
            for word in [BoardSpeech.digitWord(digit), BoardSpeech.digitWordPlural(digit),
                         BoardSpeech.digitNoun(digit, count: 2), BoardSpeech.countWord(digit)] {
                XCTAssertEqual(word, word.lowercased(),
                               "\(word) arrived capitalized — some caller is still casing words")
            }
        }
    }

    // MARK: - Out-of-range safety

    func testOutOfRangeInputsReturnEmptyStringsAndDoNotTrap() {
        for cell in [-1, 81, 999, Int.min, Int.max] {
            XCTAssertEqual(BoardSpeech.cellLabel(cell), "")
            XCTAssertEqual(BoardSpeech.rowLabel(cell), "")
            XCTAssertEqual(BoardSpeech.columnLabel(cell), "")
            XCTAssertEqual(BoardSpeech.boxLabel(cell), "")
            XCTAssertEqual(BoardSpeech.cellHint(cell), "")
            XCTAssertEqual(BoardSpeech.cellValue(cell, in: game, showErrors: true), "")
        }
        for digit in [-1, 0, 10, Int.min, Int.max] {
            XCTAssertEqual(BoardSpeech.digitWord(digit), "")
            XCTAssertEqual(BoardSpeech.digitWordPlural(digit), "")
            XCTAssertEqual(BoardSpeech.placementAnnouncement(digit: digit, in: game), "")
            XCTAssertEqual(BoardSpeech.remainingClause(digit: digit, in: game), "")
            XCTAssertEqual(BoardSpeech.eraseAnnouncement(digit: digit), "")
            XCTAssertEqual(BoardSpeech.noteAnnouncement(digit: digit, added: true), "")
        }
    }

    // MARK: - Coach sentences (PRD-11)

    /// The engine's `units` convention — `0..<9` rows, `9..<18` columns,
    /// `18..<27` boxes — pinned at both ends of all three bands.
    ///
    /// This used to assert on `BoardSpeech.unitLabel`, which returned the noun
    /// "Box 5" for a sentence to drop into a hole. The nouns are inside the
    /// sentences now (one catalog entry per unit kind), so the convention is
    /// pinned through a sentence instead — same six boundaries, plus what
    /// happens past the end of the table.
    func testCoachSentencesFollowTheEnginesUnitsConvention() {
        let expected: [(unit: Int, sentence: String)] = [
            (0,  "Only one square in row 1 can take a 7."),
            (8,  "Only one square in row 9 can take a 7."),
            (9,  "Only one square in column 1 can take a 7."),
            (17, "Only one square in column 9 can take a 7."),
            (18, "Only one square in box 1 can take a 7."),
            (26, "Only one square in box 9 can take a 7."),
        ]
        for (unit, sentence) in expected {
            XCTAssertEqual(
                BoardSpeech.coachSentence(Self.advice(.hiddenSingle, cells: [40], digits: [7],
                                                      placement: Placement(cell: 40, digit: 7),
                                                      patternUnit: unit)),
                sentence
            )
        }
        // A variant unit (PRD-23) and a bad index are not classic units, so the
        // hidden single says the thing that needs no unit at all.
        for unit in [27, -1, Int.max] {
            XCTAssertEqual(
                BoardSpeech.coachSentence(Self.advice(.hiddenSingle, cells: [40], digits: [7],
                                                      placement: Placement(cell: 40, digit: 7),
                                                      patternUnit: unit)),
                "Row 5, column 5 is the only square left that can take a 7.",
                "unit \(unit) is not one of the engine's 27"
            )
        }
    }

    func testNakedSingleNamesTheCellAndTheDigit() {
        let advice = Self.advice(.nakedSingle, cells: [40], digits: [7],
                                 placement: Placement(cell: 40, digit: 7))
        XCTAssertEqual(BoardSpeech.coachTitle(advice), "Naked Single")
        XCTAssertEqual(
            BoardSpeech.coachSentence(advice),
            "Row 5, column 5 has one candidate left: 7."
        )
        // 1-based on both axes, from the corner where an off-by-one shows.
        XCTAssertEqual(
            BoardSpeech.coachSentence(Self.advice(.nakedSingle, cells: [0], digits: [1],
                                                  placement: Placement(cell: 0, digit: 1))),
            "Row 1, column 1 has one candidate left: 1."
        )
        XCTAssertEqual(
            BoardSpeech.coachSentence(Self.advice(.nakedSingle, cells: [80], digits: [9],
                                                  placement: Placement(cell: 80, digit: 9))),
            "Row 9, column 9 has one candidate left: 9."
        )
    }

    /// One sentence per unit kind, and this is what says they all exist. A
    /// missing key would resolve to itself — "coach.hiddenSingle.sentence.col"
    /// spoken aloud — which no assertion about *shape* would catch.
    func testHiddenSingleHasItsOwnSentenceForEachUnitKind() {
        let advice = Self.advice(.hiddenSingle, cells: [40], digits: [7],
                                 placement: Placement(cell: 40, digit: 7), patternUnit: 22)
        XCTAssertEqual(BoardSpeech.coachTitle(advice), "Hidden Single")
        XCTAssertEqual(
            BoardSpeech.coachSentence(advice),
            "Only one square in box 5 can take a 7."
        )
        XCTAssertEqual(
            BoardSpeech.coachSentence(Self.advice(.hiddenSingle, cells: [40], digits: [7],
                                                  placement: Placement(cell: 40, digit: 7),
                                                  patternUnit: 4)),
            "Only one square in row 5 can take a 7."
        )
        XCTAssertEqual(
            BoardSpeech.coachSentence(Self.advice(.hiddenSingle, cells: [40], digits: [7],
                                                  placement: Placement(cell: 40, digit: 7),
                                                  patternUnit: 13)),
            "Only one square in column 5 can take a 7."
        )
    }

    func testHiddenSingleFallsBackToTheCellWhenNoUnitWasDerived() {
        let advice = Self.advice(.hiddenSingle, cells: [40], digits: [7],
                                 placement: Placement(cell: 40, digit: 7))
        XCTAssertEqual(
            BoardSpeech.coachSentence(advice),
            "Row 5, column 5 is the only square left that can take a 7."
        )
    }

    func testNakedPairNamesBothDigitsAndTheUnitTheyClear() {
        let advice = Self.advice(.nakedPair, cells: [0, 1], digits: [3, 7],
                                 eliminations: [Elimination(cell: 2, digit: 3)],
                                 patternUnit: 18, targetUnit: 0)
        XCTAssertEqual(
            BoardSpeech.coachSentence(advice),
            "3 and 7 fill these two squares between them, "
                + "so neither can go anywhere else in row 1."
        )
        XCTAssertEqual(
            BoardSpeech.coachSentence(Self.advice(.nakedPair, cells: [0, 9], digits: [3, 7],
                                                  eliminations: [Elimination(cell: 18, digit: 3)],
                                                  patternUnit: 18, targetUnit: 9)),
            "3 and 7 fill these two squares between them, "
                + "so neither can go anywhere else in column 1."
        )
        XCTAssertEqual(
            BoardSpeech.coachSentence(Self.advice(.nakedPair, cells: [0, 1], digits: [3, 7],
                                                  eliminations: [Elimination(cell: 2, digit: 3)],
                                                  patternUnit: 0, targetUnit: 18)),
            "3 and 7 fill these two squares between them, "
                + "so neither can go anywhere else in box 1."
        )
    }

    func testHiddenPairNamesTheUnitTheDigitsAreConfinedTo() {
        let advice = Self.advice(.hiddenPair, cells: [0, 1], digits: [3, 7],
                                 eliminations: [Elimination(cell: 0, digit: 5)],
                                 targetUnit: 0)
        XCTAssertEqual(
            BoardSpeech.coachSentence(advice),
            "3 and 7 fit only these two squares in row 1, so nothing else fits there."
        )
        XCTAssertEqual(
            BoardSpeech.coachSentence(Self.advice(.hiddenPair, cells: [0, 9], digits: [3, 7],
                                                  eliminations: [Elimination(cell: 0, digit: 5)],
                                                  targetUnit: 17)),
            "3 and 7 fit only these two squares in column 9, so nothing else fits there."
        )
        XCTAssertEqual(
            BoardSpeech.coachSentence(Self.advice(.hiddenPair, cells: [0, 1], digits: [3, 7],
                                                  eliminations: [Elimination(cell: 0, digit: 5)],
                                                  targetUnit: 26)),
            "3 and 7 fit only these two squares in box 9, so nothing else fits there."
        )
    }

    /// A box-line reduction runs in two directions — pointing (box → line) and
    /// claiming (line → box), `Coach.swift` — and each direction crosses two
    /// line kinds. Four sentences, all four pinned, because the old single
    /// template hid the difference behind two spliced nouns.
    func testBoxLineReductionSpeaksAllFourDirections() {
        func sentence(pattern: Int, target: Int) -> String {
            BoardSpeech.coachSentence(
                Self.advice(.boxLineReduction, cells: [0, 1], digits: [7],
                            eliminations: [Elimination(cell: 5, digit: 7)],
                            patternUnit: pattern, targetUnit: target))
        }
        XCTAssertEqual(
            sentence(pattern: 18, target: 0),
            "Every 7 still possible in box 1 sits in row 1, "
                + "so no other square in row 1 can be a 7."
        )
        XCTAssertEqual(
            sentence(pattern: 18, target: 9),
            "Every 7 still possible in box 1 sits in column 1, "
                + "so no other square in column 1 can be a 7."
        )
        XCTAssertEqual(
            sentence(pattern: 0, target: 18),
            "Every 7 still possible in row 1 sits in box 1, "
                + "so no other square in box 1 can be a 7."
        )
        XCTAssertEqual(
            sentence(pattern: 9, target: 18),
            "Every 7 still possible in column 1 sits in box 1, "
                + "so no other square in box 1 can be a 7."
        )
        // A box-line reduction is a box and a line by construction, so row →
        // column cannot arise. Silence beats a sentence naming the wrong shapes.
        XCTAssertEqual(sentence(pattern: 0, target: 9), "")
        XCTAssertEqual(sentence(pattern: 18, target: 26), "")
    }

    func testXWingOrientationComesFromTheVictimsNotTheCorners() {
        // The four corners span two rows *and* two columns either way, so only
        // the victims can say which axis was the base.
        let rowBased = Self.advice(
            .xWing, cells: [1, 5, 37, 41], digits: [7],
            eliminations: [Elimination(cell: 19, digit: 7), Elimination(cell: 23, digit: 7)]
        )
        XCTAssertEqual(
            BoardSpeech.coachSentence(rowBased),
            "In these two rows, 7 can only sit in two columns, "
                + "so no other square in those columns can be a 7."
        )
        // Same corners, victims sharing the rows instead.
        let columnBased = Self.advice(
            .xWing, cells: [1, 5, 37, 41], digits: [7],
            eliminations: [Elimination(cell: 3, digit: 7), Elimination(cell: 39, digit: 7)]
        )
        XCTAssertEqual(
            BoardSpeech.coachSentence(columnBased),
            "In these two columns, 7 can only sit in two rows, "
                + "so no other square in those rows can be a 7."
        )
    }

    func testContradictionExhaustedAndSolvedWording() {
        XCTAssertEqual(BoardSpeech.coachTitle(.contradiction(cells: [0, 5])), "A slip somewhere")
        XCTAssertEqual(
            BoardSpeech.coachSentence(.contradiction(cells: [0, 5])),
            "Two of these squares disagree, so nothing can follow from here."
        )
        XCTAssertEqual(BoardSpeech.coachTitle(.exhausted), "Nothing follows")
        XCTAssertEqual(
            BoardSpeech.coachSentence(.exhausted),
            "Nothing at this board's level follows from here."
        )
        XCTAssertEqual(BoardSpeech.coachTitle(.solved), "Done")
        XCTAssertEqual(BoardSpeech.coachSentence(.solved), BoardSpeech.solvedAnnouncement)
    }

    /// The privacy rule PRD-19 established, held for the coach: the sentence is
    /// a function of the advice alone. There is no `NineGame` parameter, so
    /// there is nothing for `puzzle.solution` to leak through — and a wrong
    /// digit standing on the board cannot change a word of it.
    func testCoachSentenceIsIndependentOfBoardState() {
        let advice = Self.advice(.nakedSingle, cells: [40], digits: [7],
                                 placement: Placement(cell: 40, digit: 7))
        let before = BoardSpeech.coachSentence(advice)
        XCTAssertTrue(game.place(wrongDigit(for: hole), at: hole))
        XCTAssertEqual(BoardSpeech.coachSentence(advice), before)
        XCTAssertFalse(before.contains("wrong"))
    }

    func testMalformedStepsReturnEmptyRatherThanTrapping() {
        XCTAssertEqual(BoardSpeech.coachSentence(Self.advice(.nakedSingle, cells: [], digits: [])), "")
        XCTAssertEqual(BoardSpeech.coachSentence(Self.advice(.nakedPair, cells: [0, 1], digits: [3])), "")
        XCTAssertEqual(BoardSpeech.coachSentence(Self.advice(.hiddenPair, cells: [0, 1], digits: [])), "")
        // A cell or a digit outside the board. The sentence takes numbers now,
        // so an unguarded one would be *printed* rather than dropped: "Row 0,
        // column 0 has one candidate left: 12."
        XCTAssertEqual(BoardSpeech.coachSentence(Self.advice(.nakedSingle, cells: [99], digits: [7])), "")
        XCTAssertEqual(BoardSpeech.coachSentence(Self.advice(.nakedSingle, cells: [40], digits: [12])), "")
        XCTAssertEqual(BoardSpeech.coachSentence(Self.advice(.hiddenSingle, cells: [-1], digits: [7])), "")
        XCTAssertEqual(BoardSpeech.coachSentence(Self.advice(.nakedPair, cells: [0, 1], digits: [3, 0],
                                                             targetUnit: 0)), "")
        // A pair or a reduction whose unit the solver could not name. There is
        // no unit-free sentence for these — the old code spliced an empty label
        // and said "…anywhere else in ."
        XCTAssertEqual(BoardSpeech.coachSentence(Self.advice(.nakedPair, cells: [0, 1], digits: [3, 7])), "")
        XCTAssertEqual(BoardSpeech.coachSentence(Self.advice(.hiddenPair, cells: [0, 1], digits: [3, 7])), "")
        XCTAssertEqual(BoardSpeech.coachSentence(Self.advice(.boxLineReduction, cells: [0, 1], digits: [7],
                                                             patternUnit: 18)), "")
        XCTAssertEqual(BoardSpeech.coachSentence(Self.advice(.nakedPair, cells: [0, 1], digits: [3, 7],
                                                             targetUnit: 27)), "",
                       "a variant unit is not a row, a column or a box")
    }

    // MARK: - The rule this task landed (PRD-20 Task 7)
    //
    // Three tests, and they are the difference between "the coach's English was
    // rewritten once" and "the coach's English cannot go back". Every one of
    // them fails on a change that still compiles and still reads correctly in
    // English — which is the only kind of regression this seam has.

    /// **The seal.** No coach sentence takes a pre-formatted word.
    ///
    /// A `%@` in a coach entry is a hole a noun gets dropped into, and the
    /// grammar around that hole is English's: one preposition, no inflection,
    /// subject before object. A translator cannot fix it from the catalog,
    /// because the catalog is not where it is wrong. The arguments are numbers;
    /// the unit kind is baked into the key.
    ///
    /// Note the specifiers are positional, so the string to look for is
    /// `%1$@`, not `%@` — a `contains("%@")` here would pass on every table
    /// this repo can produce and pin nothing at all.
    func testNoCoachSentenceSplicesAPreFormattedWord() {
        // The one entry that is not a sentence: it joins a heading and a
        // sentence, both already translated, into one VoiceOver utterance.
        // Named rather than pattern-matched, and pinned to its exact shape —
        // an exemption that can grow by accident is not an exemption.
        let exempt = "coach.card.label"
        XCTAssertEqual(EnglishPhrases.table[exempt], "%1$@. %2$@", """
            \(exempt) is exempt from the seal below because it splices two whole \
            translated strings rather than a noun. If its English has grown \
            words around those two arguments, it has become a sentence and the \
            exemption no longer applies to it.
            """)

        for (key, format) in EnglishPhrases.table where key.hasPrefix("coach.") && key != exempt {
            let spliced = PhrasebookTests.positionalSpecifiers(in: format)
                .filter { $0.conversion == "@" }
            XCTAssertEqual(spliced.map(\.index), [], """
                \(key) = "\(format)" splices a pre-formatted word. Only the digit \
                noun may be spliced (board.digitWord.*, board.digitPlural.*), and \
                only outside coach.*. Bake the noun into the key instead — one \
                entry per unit kind — the way coach.hiddenSingle.sentence.row and \
                coach.hiddenSingle.sentence.box already are.
                """)
            XCTAssertFalse(format.contains("%@"), "\(key) uses a bare, non-positional %@")
        }
    }

    /// **The extent of the exception**, from the code's side.
    ///
    /// The ruling of 2026-07-26 kept the spelled digit words, because VoiceOver
    /// reads "two fours remaining" naturally and "2 4's remaining" badly. It
    /// kept nothing else. So every `.text(…)` argument in `BoardSpeech.swift` is
    /// a number word — plus the pencil-mark list, which is numerals with a
    /// separator, and the two arguments of `board.announce.pair`, which are
    /// whole finished sentences. All seven are named here, one at a time, so an
    /// eighth cannot join them in silence. Splice a unit name or a cell label
    /// back in and this fails.
    ///
    /// **A whole sentence is the one other thing a splice may carry**, and the
    /// reason is the one that keeps `coach.card.label` in the catalog: what is
    /// being chosen there is punctuation and order, and both belong to the
    /// language. A *noun* is what may not be spliced, because what is being
    /// chosen around a noun is grammar, and that belongs to the sentence.
    ///
    /// This test's radius is **one file**. `CoachCard.swift:137` performs the
    /// sanctioned `coach.card.label` join and is not read here; a second splice
    /// added in `Sources/App` would be invisible to it.
    func testTheOnlySplicedWordsAreTheNumberWords() throws {
        // Code only. The comments in that file discuss `.text(…)` by name —
        // they have to, it is the thing they are about — and prose is not a
        // call site. No string literal in the file contains "//".
        let source = try String(contentsOf: Self.boardSpeechSource(), encoding: .utf8)
            .split(separator: "\n", omittingEmptySubsequences: false)
            .map { $0.components(separatedBy: "//").first ?? "" }
            .joined(separator: "\n")
        let allowed: Set<String> = [
            "digitWord",     // "four"  — board.announce.placed / .cleared / .note*
            "digitNoun",     // "fours" or "four", agreeing with the count
            "digitPlural",   // "fours" — board.announce.allDone
            "countWord",     // "two"   — board.announce.remaining
            "noteList",      // "2, 5, 9" — numerals, already joined
            // board.announce.pair: two finished sentences, not two nouns.
            "firstSentence", "secondSentence",
        ]
        let pattern = try NSRegularExpression(pattern: #"\.text\(([A-Za-z_][A-Za-z0-9_]*)\)"#)
        let range = NSRange(source.startIndex..., in: source)
        let matches = pattern.matches(in: source, range: range)

        XCTAssertEqual(
            matches.count, source.components(separatedBy: ".text(").count - 1,
            """
            a `.text(…)` argument in BoardSpeech.swift is not a plain identifier. \
            That is how `sentenceCased(plural)` used to hide, and this test cannot \
            read what it does not match.
            """
        )
        XCTAssertFalse(matches.isEmpty, "read no `.text(…)` at all — did the file move?")
        for match in matches {
            let name = String(source[Range(match.range(at: 1), in: source)!])
            XCTAssertTrue(allowed.contains(name), """
                BoardSpeech splices `\(name)` into a sentence. Only the number \
                words may be spliced (the ruling of 2026-07-26, for VoiceOver); \
                everything else belongs inside its own catalog entry.
                """)
        }
    }

    /// Sentence-casing a translated noun is an English-only operation — German
    /// capitalizes nouns wherever they stand, Japanese has no case at all — and
    /// it is invisible in review because in English it looks like politeness.
    /// The catalog entry carries its own capitalization now, and no argument
    /// lands sentence-initial for it to be needed.
    func testNoSentenceCasingHelperSurvives() throws {
        let source = try String(contentsOf: Self.boardSpeechSource(), encoding: .utf8)
        for helper in ["sentenceCased", "capitalizedFirst", ".uppercased()", ".capitalized"] {
            XCTAssertFalse(source.contains(helper), """
                BoardSpeech.swift still names `\(helper)`. Casing a word the \
                catalog supplied assumes English's rules for where a capital \
                goes; the catalog entry carries its own.
                """)
        }
    }

    /// The unit-kind expansion, as a number. Six functions became seventeen
    /// entries, and the duplication is the point — so a diff that quietly folds
    /// two of them back into one template has to say so here.
    func testEveryCoachSentenceKeyIsAccountedFor() {
        let sentences = EnglishPhrases.table.keys
            .filter { $0.hasPrefix("coach.") && $0.contains(".sentence") }
            .sorted()
        XCTAssertEqual(sentences, [
            "coach.boxLine.sentence.boxToCol",
            "coach.boxLine.sentence.boxToRow",
            "coach.boxLine.sentence.colToBox",
            "coach.boxLine.sentence.rowToBox",
            "coach.exhausted.sentence",
            "coach.hiddenPair.sentence.box",
            "coach.hiddenPair.sentence.col",
            "coach.hiddenPair.sentence.row",
            "coach.hiddenSingle.sentence.box",
            "coach.hiddenSingle.sentence.cell",
            "coach.hiddenSingle.sentence.col",
            "coach.hiddenSingle.sentence.row",
            "coach.nakedPair.sentence.box",
            "coach.nakedPair.sentence.col",
            "coach.nakedPair.sentence.row",
            "coach.nakedSingle.sentence",
            "coach.slip.sentence",
            "coach.xWing.sentence.colBase",
            "coach.xWing.sentence.rowBase",
        ])
    }

    // MARK: - Helpers

    /// The file two of the tests above read rather than call. Some of what this
    /// task landed is the *absence* of code, and absence has no API.
    private static func boardSpeechSource() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SharedTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // nine
            .appendingPathComponent("Sources/Shared/BoardSpeech.swift")
    }

    /// A digit that is definitely not the solution for `cell`.
    private func wrongDigit(for cell: Int) -> Int {
        let solution = puzzle.solution[cell]
        return solution == 9 ? 1 : solution + 1
    }

    /// Advice built by hand, so a sentence test never depends on which
    /// technique a generated board happens to offer next.
    private static func advice(
        _ technique: Technique,
        cells: [Int],
        digits: [Int],
        placement: Placement? = nil,
        eliminations: [Elimination] = [],
        patternUnit: Int? = nil,
        targetUnit: Int? = nil
    ) -> CoachAdvice {
        .step(CoachStep(
            step: SolveStep(
                technique: technique, cells: cells, digits: digits,
                placement: placement, eliminations: eliminations
            ),
            patternUnit: patternUnit,
            targetUnit: targetUnit
        ))
    }

    // MARK: - Streak chip (PRD-13 §3)

    func testStreakSpeechNamesTheHoldWithoutNamingTheMiss() {
        XCTAssertEqual(BoardSpeech.streakChip(days: 12, held: false), "12 day streak")
        XCTAssertEqual(BoardSpeech.streakChip(days: 12, held: true), "12 day streak, held")
        XCTAssertEqual(BoardSpeech.streakChip(days: 1, held: false), "1 day streak")
    }

    /// No count, no currency, no "remaining", and no naming the day the player
    /// missed — PRD-13 §3 and the covenant forbid all four, and the spoken
    /// string is the one place they would sneak back in unnoticed.
    func testStreakSpeechNeverCountsShieldsOrShamesTheMiss() {
        for days in [1, 2, 30] {
            for held in [true, false] {
                let text = BoardSpeech.streakChip(days: days, held: held).lowercased()
                for banned in ["shield", "remaining", "left", "missed", "lost", "danger"] {
                    XCTAssertFalse(text.contains(banned), "\(text) must not say \(banned)")
                }
            }
        }
    }
}
