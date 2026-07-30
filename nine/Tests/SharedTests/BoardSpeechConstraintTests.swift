// BoardSpeechConstraintTests — what VoiceOver hears on a variant board (PRD-24).
//
// **This file exists because driving the app found the bug and no test could
// have.** With the thermo board on screen, `describe-ui` reported the cell under a
// tube as:
//
//     label: Row 3, column 5     value: Empty
//
// Nine tubes drawn on the board, and a VoiceOver player has no way to learn that
// any of them exist. Every gate was green: three platform builds, 470 tests, 81
// accessibility children in 9 box containers, the AX baselines matching. The tree
// was structurally perfect and semantically silent — which is the exact failure
// mode `EXECUTING-A-PRD.md` §4 opens with ("nothing on screen changes when it
// does"), one layer further in.
//
// The rule the fix follows, and the reason it is in the **label** rather than the
// hint: *a mark the sighted player can see without asking is part of the cell's
// identity, not a tip about it.* A cage's printed sum is the primary information on
// a killer board — closer to a given than to a hint — and VoiceOver hints can be
// turned off, so a hint-only clause would leave those players with an unplayable
// board that reported no error.
import XCTest
import Foundation
import CouchCore
@testable import NineShared
@testable import NineEngine

final class BoardSpeechConstraintTests: XCTestCase {

    private func cages(_ specs: [([Int], Int)]) -> ChannelRules {
        ChannelRules(
            variant: .killer, tier: .steady,
            constraints: specs.compactMap { Cage(cells: $0.0, sum: $0.1) }
                .map(VariantConstraint.cage))
    }

    private func tubes(_ specs: [[Int]]) -> ChannelRules {
        ChannelRules(
            variant: .thermo, tier: .gentle,
            constraints: specs.compactMap { Thermometer(cells: $0) }
                .map(VariantConstraint.thermometer))
    }

    // MARK: - Classic is byte-identical

    /// The clause is empty for a classic board, and every classic label is the
    /// string it was before PRD-24. This is the assertion that lets the change
    /// ship at all: `Tests/AXBaselines/*.txt` freeze those labels, and a clause
    /// that leaked onto a classic cell would move all four baselines.
    func testAClassicBoardSaysExactlyWhatItAlwaysSaid() {
        for cell in [0, 40, 80] {
            XCTAssertEqual(BoardSpeech.constraintClause(cell, rules: nil), "")
            XCTAssertEqual(
                BoardSpeech.cellLabel(cell, rules: nil), BoardSpeech.cellLabel(cell))
        }
    }

    /// A board whose rules this build cannot enforce says nothing about them
    /// either — for `BoardView.drawRules`'s reason, one sense over: describing a
    /// mark whose meaning is unknown is worse than describing nothing, because the
    /// player would reason about it.
    func testAnUnenforceableRuleIsNotSpoken() throws {
        let arrow = try CouchJSON.decode(
            VariantConstraint.self,
            from: Data(#"{"kind": "arrow", "cells": [0, 1, 2]}"#.utf8))
        let rules = ChannelRules(variant: .killer, tier: .steady, constraints: [arrow])
        XCTAssertFalse(rules.isPlayable)
        XCTAssertEqual(BoardSpeech.constraintClause(0, rules: rules), "")
        XCTAssertEqual(BoardSpeech.cellLabel(0, rules: rules), BoardSpeech.cellLabel(0))
    }

    // MARK: - Cages

    /// The sum is what a cage *is*, so it is what gets said.
    func testACagedCellNamesItsSum() {
        let rules = cages([([0, 1, 9], 15), ([2, 3], 11)])
        let label = BoardSpeech.cellLabel(0, rules: rules)
        XCTAssertTrue(label.contains("15"), label)
        XCTAssertTrue(label.contains(BoardSpeech.cellLabel(0)), label)
        // A cell in the other cage names the other sum, not the first one.
        let other = BoardSpeech.cellLabel(2, rules: rules)
        XCTAssertTrue(other.contains("11"), other)
        XCTAssertFalse(other.contains("15"), other)
    }

    /// A cell in no cage on a killer board says nothing extra. Our tiler produces
    /// full tilings, so this is the hand-built and received-board case — but a
    /// label that claimed a cage where there is none would be a lie the player
    /// cannot check.
    func testAnUncagedCellOnAKillerBoardIsSilent() {
        let rules = cages([([0, 1, 9], 15)])
        XCTAssertEqual(BoardSpeech.constraintClause(40, rules: rules), "")
    }

    // MARK: - Thermometers

    /// A tube's information is **positional**, so position is what gets said: the
    /// bulb end and the tip are what the constraint is about, and a clause that
    /// only said "on a thermometer" would tell a player the one thing they could
    /// already infer from the cage-free board.
    func testACellOnATubeNamesItsPositionAlongIt() {
        let rules = tubes([[40, 41, 42, 43]])
        let bulb = BoardSpeech.cellLabel(40, rules: rules)
        let middle = BoardSpeech.cellLabel(41, rules: rules)
        let tip = BoardSpeech.cellLabel(43, rules: rules)
        for label in [bulb, middle, tip] {
            XCTAssertTrue(label.contains(BoardSpeech.cellLabel(40).prefix(3)), label)
        }
        // Three different positions must produce three different clauses, or the
        // clause is not carrying the information it exists for.
        XCTAssertNotEqual(bulb, middle)
        XCTAssertNotEqual(middle, tip)
        XCTAssertTrue(bulb.contains("1"), bulb)
        XCTAssertTrue(tip.contains("4"), tip)
    }

    /// A cell on two tubes reports both, rather than picking one and being quietly
    /// wrong about the board. Our tiler never builds these — `ThermoTilingTests`
    /// asserts the layout is disjoint — but `ConstraintContext.thermoPositions` is
    /// `[[ThermoPosition]]` precisely because a received board may.
    func testACellOnTwoTubesReportsBoth() {
        let rules = tubes([[40, 41, 42], [40, 49, 58]])
        let clause = BoardSpeech.constraintClause(40, rules: rules)
        XCTAssertFalse(clause.isEmpty)
        // Two clauses joined, so the count of position words is two.
        XCTAssertEqual(clause.components(separatedBy: "3").count - 1, 2, clause)
    }

    func testACellOnNoTubeIsSilent() {
        XCTAssertEqual(BoardSpeech.constraintClause(0, rules: tubes([[40, 41, 42]])), "")
    }

    /// Out-of-range cells return empty rather than trapping, which every other
    /// `BoardSpeech` entry point also does — the guards exist because the AX tree
    /// is built from indices and a bad one must not crash a blind player's app.
    func testAnInvalidCellIsSilent() {
        let rules = cages([([0, 1], 5)])
        XCTAssertEqual(BoardSpeech.constraintClause(-1, rules: rules), "")
        XCTAssertEqual(BoardSpeech.constraintClause(81, rules: rules), "")
    }

    // MARK: - The four variant techniques

    /// PRD-11 left these as `default: return ""` because naming them in
    /// `Sources/Shared` would have tripped PRD-23's channel seal
    /// (`DEVIATIONS.md:1559`). The seal is gone, the boards exist, and a coach
    /// that goes silent on the only techniques a killer board uses is a coach the
    /// channel cannot ship with.
    func testEveryVariantTechniqueNowHasASentence() {
        let steps: [SolveStep] = [
            SolveStep(technique: .cageSingle, cells: [0, 1, 9], digits: [7],
                      placement: Placement(cell: 9, digit: 7)),
            SolveStep(technique: .innieOutie, cells: Array(0..<9), digits: [4],
                      placement: Placement(cell: 3, digit: 4)),
            SolveStep(technique: .cageCombination, cells: [0, 1], digits: [2, 3],
                      eliminations: [Elimination(cell: 0, digit: 2),
                                     Elimination(cell: 1, digit: 3)]),
            SolveStep(technique: .thermoBound, cells: [40, 41, 42], digits: [1, 9],
                      eliminations: [Elimination(cell: 40, digit: 9),
                                     Elimination(cell: 42, digit: 1)]),
        ]
        for step in steps {
            // Both units nil, which is the honest answer for all four: a cage is
            // not a unit (`ConstraintContext.units` is emphatic about why), and a
            // thermometer is not either. `innieOutie` reasons *about* a unit, and
            // `BoardSpeech.unit(of:)` reads which one off the step's cells rather
            // than being told — so nothing here needs `patternUnit`.
            let advice = CoachAdvice.step(
                CoachStep(step: step, patternUnit: nil, targetUnit: nil))
            let sentence = BoardSpeech.coachSentence(advice)
            XCTAssertFalse(
                sentence.isEmpty,
                "\(step.technique.rawValue) still falls to the empty default")
            // A sentence, not a key — the missing-key fallback returns the key
            // itself, which is how a "passing" test can assert nothing.
            XCTAssertFalse(sentence.contains("coach."), sentence)
            XCTAssertFalse(BoardSpeech.coachTitle(advice).isEmpty)
            XCTAssertFalse(BoardSpeech.coachTitle(advice).contains("technique."))
        }
    }
}
