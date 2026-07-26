// BoardSpeechTests — the spoken board (PRD-19). These pin three things that
// are easy to regress and impossible to notice without a screen reader:
// 1-basing of row/column/box, the singular/plural boundaries in the
// announcements, and the `showErrors: false` privacy branch — VoiceOver must
// never reveal a wrong entry the sighted player is not being shown.
import XCTest
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
        let word = BoardSpeech.digitWordCapitalized(digit)
        let plural = BoardSpeech.digitWordPlural(digit)
        let singular = BoardSpeech.digitWord(digit)

        for cell in holes.dropLast(2) {
            XCTAssertTrue(game.place(digit, at: cell))
        }
        XCTAssertEqual(game.count(of: digit), 7)
        XCTAssertEqual(
            BoardSpeech.placementAnnouncement(digit: digit, in: game),
            "\(word) placed. Two \(plural) remaining."
        )

        XCTAssertTrue(game.place(digit, at: holes[holes.count - 2]))
        XCTAssertEqual(
            BoardSpeech.placementAnnouncement(digit: digit, in: game),
            "\(word) placed. One \(singular) remaining.",
            "one left is singular"
        )

        XCTAssertTrue(game.place(digit, at: holes[holes.count - 1]))
        XCTAssertTrue(game.isDigitComplete(digit))
        XCTAssertEqual(
            BoardSpeech.placementAnnouncement(digit: digit, in: game),
            "\(word) placed. All \(plural) done."
        )
    }

    func testSolvedAnnouncementAndEraseAndNotes() {
        XCTAssertEqual(BoardSpeech.solvedAnnouncement, "Solved.")
        XCTAssertEqual(BoardSpeech.eraseAnnouncement(digit: 4), "Four cleared.")
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
        XCTAssertEqual(BoardSpeech.digitWordCapitalized(7), "Seven")
        XCTAssertEqual(BoardSpeech.digitWordPlural(6), "sixes", "not 'sixs'")
        XCTAssertEqual(BoardSpeech.digitNoun(4, count: 1), "four")
        XCTAssertEqual(BoardSpeech.digitNoun(4, count: 2), "fours")
        XCTAssertEqual(BoardSpeech.countWord(0), "zero")
        XCTAssertEqual(BoardSpeech.countWord(12), "12", "past nine we fall back to numerals")
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
            XCTAssertEqual(BoardSpeech.digitWordCapitalized(digit), "")
            XCTAssertEqual(BoardSpeech.digitWordPlural(digit), "")
            XCTAssertEqual(BoardSpeech.placementAnnouncement(digit: digit, in: game), "")
            XCTAssertEqual(BoardSpeech.remainingClause(digit: digit, in: game), "")
            XCTAssertEqual(BoardSpeech.eraseAnnouncement(digit: digit), "")
            XCTAssertEqual(BoardSpeech.noteAnnouncement(digit: digit, added: true), "")
        }
    }

    // MARK: - Coach sentences (PRD-11)

    func testUnitLabelFollowsTheEnginesUnitsConvention() {
        XCTAssertEqual(BoardSpeech.unitLabel(0), "Row 1")
        XCTAssertEqual(BoardSpeech.unitLabel(8), "Row 9")
        XCTAssertEqual(BoardSpeech.unitLabel(9), "Column 1")
        XCTAssertEqual(BoardSpeech.unitLabel(17), "Column 9")
        XCTAssertEqual(BoardSpeech.unitLabel(18), "Box 1")
        XCTAssertEqual(BoardSpeech.unitLabel(26), "Box 9")
        XCTAssertEqual(BoardSpeech.unitLabel(27), "", "a variant unit has no classic label")
        XCTAssertEqual(BoardSpeech.unitLabel(-1), "")
        XCTAssertEqual(BoardSpeech.unitLabel(Int.max), "")
    }

    func testNakedSingleNamesTheCellAndTheDigit() {
        let advice = Self.advice(.nakedSingle, cells: [40], digits: [7],
                                 placement: Placement(cell: 40, digit: 7))
        XCTAssertEqual(BoardSpeech.coachTitle(advice), "Naked Single")
        XCTAssertEqual(
            BoardSpeech.coachSentence(advice),
            "Row 5, column 5 has one candidate left: seven."
        )
    }

    func testHiddenSingleNamesTheUnitThatConfinesTheDigit() {
        let advice = Self.advice(.hiddenSingle, cells: [40], digits: [7],
                                 placement: Placement(cell: 40, digit: 7), patternUnit: 22)
        XCTAssertEqual(BoardSpeech.coachTitle(advice), "Hidden Single")
        XCTAssertEqual(
            BoardSpeech.coachSentence(advice),
            "Only one square in Box 5 can take a seven."
        )
    }

    func testHiddenSingleFallsBackToTheCellWhenNoUnitWasDerived() {
        let advice = Self.advice(.hiddenSingle, cells: [40], digits: [7],
                                 placement: Placement(cell: 40, digit: 7))
        XCTAssertEqual(
            BoardSpeech.coachSentence(advice),
            "Row 5, column 5 is the only square left that can take a seven."
        )
    }

    func testNakedPairNamesBothDigitsAndTheUnitTheyClear() {
        let advice = Self.advice(.nakedPair, cells: [0, 1], digits: [3, 7],
                                 eliminations: [Elimination(cell: 2, digit: 3)],
                                 patternUnit: 18, targetUnit: 0)
        XCTAssertEqual(
            BoardSpeech.coachSentence(advice),
            "Three and seven fill these two squares between them, "
                + "so neither can go anywhere else in Row 1."
        )
    }

    func testHiddenPairNamesTheUnitTheDigitsAreConfinedTo() {
        let advice = Self.advice(.hiddenPair, cells: [0, 1], digits: [3, 7],
                                 eliminations: [Elimination(cell: 0, digit: 5)],
                                 targetUnit: 0)
        XCTAssertEqual(
            BoardSpeech.coachSentence(advice),
            "Three and seven fit only these two squares in Row 1, so nothing else fits there."
        )
    }

    func testBoxLineReductionNamesTheSourceUnitThenTheClearedOne() {
        let advice = Self.advice(.boxLineReduction, cells: [0, 1], digits: [7],
                                 eliminations: [Elimination(cell: 5, digit: 7)],
                                 patternUnit: 18, targetUnit: 0)
        XCTAssertEqual(
            BoardSpeech.coachSentence(advice),
            "Every seven still possible in Box 1 sits in Row 1, "
                + "so no other square in Row 1 can be a seven."
        )
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
            "Sevens in these two rows can only sit in two columns, "
                + "so no other square in those columns can be a seven."
        )
        // Same corners, victims sharing the rows instead.
        let columnBased = Self.advice(
            .xWing, cells: [1, 5, 37, 41], digits: [7],
            eliminations: [Elimination(cell: 3, digit: 7), Elimination(cell: 39, digit: 7)]
        )
        XCTAssertEqual(
            BoardSpeech.coachSentence(columnBased),
            "Sevens in these two columns can only sit in two rows, "
                + "so no other square in those rows can be a seven."
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
    }

    // MARK: - Helpers

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
}
