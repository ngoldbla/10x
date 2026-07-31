// DuelSealTests.swift — a duel solve is nobody's solve, held by reading the
// source (PRD-27 §7).
//
// `swift test` compiles Engine and Shared, so `AppModel.finishSolve` cannot be
// called from here at all. `VariantInputSealTests` and `QuietPresenceSealTests`
// already answer that the same way: these invariants are about *which lines
// exist*, so the check reads the file. A seal is weaker than a unit test and
// very much stronger than a comment, and PRD-24 recorded why the seal is worth
// having — a comment stating a rule survives exactly until the first refactor.
//
// Two of the four cases below are **negatives**: things this PRD promised not to
// add. Those are the ones that erode without anything going red.
import XCTest

final class DuelSealTests: XCTestCase {

    private func source(_ relative: String) throws -> String {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // nine
            .appendingPathComponent(relative)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// Everything `finishSolve` writes that belongs to *a player* must sit
    /// behind the duel guard. Named individually rather than checked as a lump,
    /// so adding a sixth solo ledger and forgetting the guard fails here.
    func testFinishSolveGuardsEverySoloLedgerBehindTheDuelCheck() throws {
        let app = try source("Sources/App/AppModel.swift")
        let start = try XCTUnwrap(app.range(of: "private func finishSolve()"))
        let end = try XCTUnwrap(app.range(of: "// MARK: - Replays (PRD-26)"))
        let body = String(app[start.lowerBound..<end.lowerBound])

        XCTAssertTrue(
            body.contains("let isDuel = self.isDuel"),
            "finishSolve must read the duel guard once, up front — PRD-27 §7")

        // **Each guard is anchored to the line it guards**, and that is not
        // fussiness — it is this test's own first bug. `} else if !isDuel {`
        // occurs twice in this function (the classic history, and Game Center),
        // so an assertion that merely found the substring stayed green when the
        // history guard was deleted, because the Game Center one still matched.
        // A seal that greps for a string appearing more than once cannot detect
        // one of them going missing. Falsified against both deletions.
        for (ledger, guarded) in [
            ("the classic streak and archive", "if !isDuel, case .daily(let day)? = kind"),
            ("the channel ledger", "if !isDuel, case .channel(let c, _, let day)? = kind"),
            ("the classic history", "} else if !isDuel {\n            history.record(record)"),
            ("Game Center", "} else if !isDuel {\n            // A duel reports nothing."),
        ] {
            XCTAssertTrue(
                body.contains(guarded),
                "PRD-27 §7: a duel solve must not reach \(ledger) — missing `\(guarded)`")
        }
    }

    /// The board-level work that *does* still happen. Without this the guard
    /// above could be satisfied by skipping the solve entirely, which would
    /// silently cost the duel its comet and its debrief.
    func testADuelStillMintsItsReplayAndMarksTheBoardSolved() throws {
        let app = try source("Sources/App/AppModel.swift")
        let start = try XCTUnwrap(app.range(of: "private func finishSolve()"))
        let end = try XCTUnwrap(app.range(of: "// MARK: - Replays (PRD-26)"))
        let body = String(app[start.lowerBound..<end.lowerBound])
        XCTAssertTrue(body.contains("library.markSolved(id: id, at: now)"))
        XCTAssertTrue(body.contains("mintReplay("))
        XCTAssertFalse(
            body.contains("guard !isDuel else { return }"),
            "PRD-27 §10 — a duel has a debrief, so it needs its replay. An early "
            + "return here would satisfy every ledger assertion above and delete "
            + "the feature.")
    }

    /// The duel has its own start door, and it cannot reach the daily.
    func testTheDuelStartsAFreeBoardAndOnlyAFreeBoard() throws {
        let app = try source("Sources/App/AppModel.swift")
        let start = try XCTUnwrap(app.range(of: "func startDuel("))
        let body = String(app[start.lowerBound...].prefix(600))
        XCTAssertTrue(body.contains("startFree(difficulty)"))
        XCTAssertFalse(
            body.contains("openToday") || body.contains(".daily"),
            "PRD-27 §7 — two people on a sofa must not be able to spend the "
            + "streak of whoever owns the device")
        XCTAssertTrue(
            app.contains("CouchStored(wrappedValue: DuelLedger(), \"nine.duel\")"),
            "the duel's state belongs in its own sibling key (EXECUTING-A-PRD §2)")
    }

    // MARK: - The two negatives

    /// A duel board is an ordinary `.free(difficulty)` board (PRD-27 §3).
    func testGameKindGainsNoDuelCase() throws {
        let engine = try source("Sources/Engine/BoardLibrary.swift")
        XCTAssertFalse(
            engine.lowercased().contains("case duel"),
            """
            PRD-27 §3 — a duel board is .free(difficulty), and a GameKind case \
            would quarantine it on older builds for no reason. That inverts \
            PRD-24 deliberately: .channel exists BECAUSE an older build renders a \
            killer board wrong and marks correct entries as errors. There is \
            nothing an older build renders wrong about a classic sudoku two \
            people filled in.
            """)
    }

    /// The Engine is not in this PRD's diff at all.
    func testLoggedMoveGainsNoPlayerField() throws {
        let game = try source("Sources/Engine/Game.swift")
        let start = try XCTUnwrap(game.range(of: "public struct LoggedMove"))
        let end = try XCTUnwrap(game.range(of: "public struct NineGame"))
        let declaration = String(game[start.lowerBound..<end.lowerBound])
        XCTAssertFalse(
            declaration.contains("player"),
            """
            PRD-27 §2 — attribution is a boundary list in nine.duel, not a field \
            on 300 moves. A field here would move SolveReplay.packed, every \
            autosaved board's bytes, and therefore the golden corpus.
            """)
    }

    /// The whole Engine, not just the two files above.
    func testNothingInTheEngineKnowsAboutDuels() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/Engine")
        let files = try FileManager.default
            .contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
        XCTAssertFalse(files.isEmpty, "found no Engine sources — the path is wrong")
        for file in files {
            let text = try String(contentsOf: file, encoding: .utf8).lowercased()
            XCTAssertFalse(
                text.contains("duel"),
                "\(file.lastPathComponent) mentions duels. PRD-27 is App-layer and "
                + "Shared-layer only; the Engine is what the golden corpus hashes.")
        }
    }
}
