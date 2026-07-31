// TableSealTests.swift — the seal on PRD-29's two negatives.
//
// Both are negatives, and negatives erode without anything going red:
//
//   1. **The table never notifies.** The covenant's clause, and the reason it
//      needs a seal rather than a comment is sitting in the same file the table
//      submits from: `GameCenter.progress(_:fraction:)` already sets
//      `showsCompletionBanner = true` on achievements, so the API is one line
//      away from a weekly standing that could announce itself.
//   2. **Nothing can be demoted, because nothing has a position.** PRD-29 §2's
//      whole design argument is that twenty rows are a *window* on one global
//      board rather than a cohort in it — so there is no Table 3 to fall out of,
//      and nothing anywhere stores a previous seat. That is a claim about types
//      (`DailyTableTests` reflects over them) and about vocabulary, which is
//      what this file adds: a word for rank on the surface or in the catalog
//      would name a thing that does not exist, and it would look like a
//      clarification in review.
//
// Plus the third seal every demo lane in this repo has now: the constructed
// standing is not reachable in Release. Same shape as `ParlorSealTests`,
// including the comment stripper — the prose in these files discusses ranks and
// banners at length, on purpose, and must not be able to fail the test that
// forbids them, or to mask a real one.
import XCTest
@testable import NineShared

final class TableSealTests: XCTestCase {

    static let nineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EngineTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // nine

    /// Every file that draws or carries a table.
    ///
    /// A hand-written list rather than a directory sweep, for the reason
    /// `VariantInputSealTests` and `ParlorSealTests` both give: a tree is a
    /// location, and this is an argument about responsibility. Each of these is
    /// on the path between a week of solves and a row on a screen.
    private static let surfaces = [
        "Sources/Shared/DailyTable.swift",
        "Sources/App/TableView.swift",
        "Sources/App/GameCenter.swift",
    ]

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: Self.nineRoot.appendingPathComponent(relative), encoding: .utf8)
    }

    /// Blank out `//` and `/* */` comments, keeping every byte offset.
    private func codeOnly(_ text: String) -> String {
        var out = ""
        var inBlock = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var body = String(line)
            if inBlock {
                guard let end = body.range(of: "*/") else { out += "\n"; continue }
                body = String(body[end.upperBound...])
                inBlock = false
            }
            if let start = body.range(of: "/*") {
                let head = String(body[..<start.lowerBound])
                if let end = body.range(of: "*/", range: start.upperBound..<body.endIndex) {
                    body = head + String(body[end.upperBound...])
                } else {
                    body = head
                    inBlock = true
                }
            }
            if let slashes = body.range(of: "//") { body = String(body[..<slashes.lowerBound]) }
            out += body + "\n"
        }
        return out
    }

    // MARK: - It never notifies

    /// No table surface can raise anything the player has to dismiss.
    func testNoTableSurfaceCanRaiseANotification() throws {
        let forbidden = [
            "UNUserNotificationCenter",
            "UNNotificationRequest",
            "UNMutableNotificationContent",
            "requestAuthorization",
            "GKNotificationBanner",   // Game Center's own in-app banner
            "AlertConfiguration",     // ActivityKit's, which buzzes
        ]
        for path in Self.surfaces {
            let code = codeOnly(try source(path))
            for needle in forbidden {
                XCTAssertFalse(
                    code.contains(needle),
                    "\(path) contains \(needle) — PRD-29 §8 and the anti-bloat "
                        + "constitution: the table never notifies.")
            }
        }
    }

    /// The one that is already in the building.
    ///
    /// `showsCompletionBanner` is set on achievements today and that is
    /// deliberate — an achievement is a thing Game Center announces. Forbidding
    /// the API outright would fail on unmodified code, so the seal is a **count**
    /// instead: exactly one use, and it is the achievement one. A second, on a
    /// table submission, fails here.
    func testTheOnlyCompletionBannerIsTheAchievementOne() throws {
        let code = codeOnly(try source("Sources/App/GameCenter.swift"))
        let uses = code.components(separatedBy: "showsCompletionBanner").count - 1
        XCTAssertEqual(
            uses, 1,
            "GameCenter.swift sets showsCompletionBanner \(uses) times. Exactly one "
                + "is expected — `progress(_:fraction:)`'s, for achievements. A "
                + "weekly standing that announced itself would be a notification "
                + "by another name.")
        XCTAssertTrue(
            code.contains("achievement.showsCompletionBanner = true"),
            "the one permitted use moved or was renamed; re-aim this seal rather "
                + "than deleting it")
    }

    // MARK: - Nothing has a position, so nothing can be demoted

    /// The vocabulary of a hierarchy, forbidden on the surface that draws the
    /// table.
    ///
    /// **`DailyTable.swift` is deliberately not in this list** and the exclusion
    /// is the interesting half: it takes GameKit's `rank` as an input, because
    /// converting a rank into a window is exactly what makes the cohort
    /// disappear. What must not happen is a rank reaching a *pixel*, and
    /// `TableView.swift` is where that would occur.
    func testTheDrawnTableHasNoVocabularyOfPosition() throws {
        let code = codeOnly(try source("Sources/App/TableView.swift"))
        for needle in ["rank", "position", "podium", "medal", "promot", "demot",
                       "relegat", "division", "tier", "standingNumber", "place("] {
            XCTAssertFalse(
                code.lowercased().contains(needle.lowercased()),
                "TableView.swift names `\(needle)` — PRD-29 §2 and §6: the order "
                    + "of the rows IS the standing, and printing it invites "
                    + "arithmetic the covenant has no answer for.")
        }
    }

    /// A seat cannot be re-ordered on the way to the screen. The order is the
    /// leaderboard's, and a sort here would be a second ranking rule that can
    /// disagree with the one `DailyTable.score` defines — the same line
    /// `ParlorSealTests` forbids for the same reason.
    func testTheDrawnTableDoesNotReorderTheLeaderboardsAnswer() throws {
        let code = codeOnly(try source("Sources/App/TableView.swift"))
        for needle in ["sorted", "reversed()", "min(by:", "max(by:"] {
            XCTAssertFalse(
                code.contains(needle),
                "TableView.swift reorders the seats — the leaderboard is the "
                    + "authority on its own order")
        }
    }

    /// And the same question of the words the player actually reads. A catalog
    /// key is where a promise like this really dies: the code stays clean and a
    /// translator is handed "Rank 4 of 20".
    func testNoTableStringNamesARankOrAMovement() {
        let forbidden = ["rank", "position", "podium", "medal", "promoted",
                         "demoted", "relegated", "division", "league table",
                         "moved up", "moved down", "you beat", "loser", "winner"]
        for (key, english) in EnglishPhrases.table
        where key.hasPrefix("table.") || key == "history.section.table" {
            let lower = english.lowercased()
            for needle in forbidden {
                XCTAssertFalse(
                    lower.contains(needle),
                    "\(key) says \"\(needle)\" — PRD-29 §2: there is no cohort, so "
                        + "there is no position to name and nothing to be moved "
                        + "between.")
            }
        }
    }

    /// The persisted footprint, counted rather than promised: one `Bool`.
    ///
    /// A seat, a previous seat or a past week stored anywhere is what would make
    /// a demotion computable, so the seal is on the storage rather than on the
    /// arithmetic that would use it.
    func testTheTablePersistsExactlyOneBoolean() throws {
        let code = codeOnly(try source("Sources/App/AppModel.swift"))
        XCTAssertTrue(
            code.contains(#"CouchStored(wrappedValue: false, "nine.table", cloudSynced: true)"#),
            "the table's opt-in is no longer one cloud-synced Bool at nine.table")
        for key in ["nine.tableSeats", "nine.tableRank", "nine.tableHistory",
                    "nine.standing", "nine.league"] {
            XCTAssertFalse(
                code.contains(key),
                "\(key) exists — PRD-29 §2: a delta needs two observations and "
                    + "Nine keeps one, which is why \"you dropped four places\" is "
                    + "a message no code path can construct.")
        }
    }

    // MARK: - The constructed standing is not in Release

    /// Every mention of the demo standing is inside a `#if DEBUG`.
    ///
    /// Counted the way `ParlorSealTests` counts the loopback transport: a grep
    /// for the names plus a scan of the fences answers "is this reachable in
    /// Release" exactly. Twenty invented people on a shipping leaderboard is a
    /// worse failure than a demo that does not run.
    func testTheDemoStandingCannotBeReachedInRelease() throws {
        for path in ["Sources/App/AppModel.swift", "Sources/App/TableView.swift"] {
            let code = codeOnly(try source(path))
            var depth = 0
            var debugDepth: Int?
            for line in code.split(separator: "\n", omittingEmptySubsequences: false) {
                let trimmed = line.trimmingCharacters(in: .whitespaces)
                if trimmed.hasPrefix("#if") {
                    depth += 1
                    if trimmed.contains("DEBUG"), debugDepth == nil { debugDepth = depth }
                } else if trimmed.hasPrefix("#endif") {
                    if debugDepth == depth { debugDepth = nil }
                    depth -= 1
                }
                for name in ["demoTableSeats", "tableDemoArgument", "-table-demo"]
                where line.contains(name) {
                    XCTAssertNotNil(
                        debugDepth,
                        "\(path): \(name) is outside #if DEBUG — a constructed "
                            + "standing in Release is a launch argument anybody "
                            + "can pass")
                }
            }
        }
    }
}
