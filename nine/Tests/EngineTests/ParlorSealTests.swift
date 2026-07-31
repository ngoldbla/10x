// The seal on PRD-28's two negatives, enforced against source text rather than
// against a comment.
//
// PRD-28 makes two promises that nothing goes red for breaking:
//
//   1. **no times until everyone finishes** — and the *payload* half of that is
//      `ParlorTests.testPresenceCarriesNoClockAndCanNotGrowOne`, which reflects
//      over `ParlorPresence`'s encoded keys. This is the *surface* half. Both
//      are needed, and PRD-30 is why: `Text(_:style: .timer)` needed no field in
//      the Live Activity's content state at all, so a view can render a clock
//      the wire never carried.
//   2. **the loopback transport is not in Release** — the arrangement PRD-23
//      used to keep the variant channel out of shipping builds, re-used here
//      because a demo transport that survived into Release would be a feature
//      nobody asked for wired to a launch argument anybody can pass.
//
// The shape is `QuietPresenceSealTests`', including the comment stripper: the
// prose in these files discusses clocks at length, on purpose, and must not be
// able to fail the test that forbids them — or to mask a real one.
import XCTest

final class ParlorSealTests: XCTestCase {

    static let nineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EngineTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // nine

    /// Every file that draws or carries a parlor.
    ///
    /// A hand-written list rather than a directory sweep, for the reason
    /// `VariantInputSealTests` gives: a tree is a location, and this is an
    /// argument about responsibility. Each of these is on the path between a
    /// participant's board and a pixel on somebody else's.
    private static let surfaces = [
        "Sources/Shared/Parlor.swift",
        "Sources/App/ParlorSession.swift",
        "Sources/App/ParlorViews.swift",
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

    // MARK: - No clock on a parlor surface

    /// A live clock has no business on any of these files. The elapsed time of a
    /// *finished* solve does — that is §6's caption — so what is forbidden is
    /// the machinery that makes a number tick, not the number itself.
    func testNoParlorSurfaceRendersALiveClock() throws {
        let forbidden = [
            "style: .timer",        // renders from Date on the system's side
            "timerInterval",        // ActivityKit's own countdown
            "TimelineView",         // a parlor surface that redraws on a schedule
            "Date()",               // a clock read
            ".now",
        ]
        for path in Self.surfaces {
            let code = codeOnly(try source(path))
            for needle in forbidden {
                XCTAssertFalse(
                    code.contains(needle),
                    "\(path) contains \(needle) — PRD-28 §4 and the craft charter's "
                        + "idle-pixel rule: a parlor surface changes when a message "
                        + "arrives and at no other time.")
            }
        }
    }

    /// The reveal has exactly one gate, and it is on the room rather than on a
    /// view. `ParlorRoom.members` is the only place `finishes` is read out, and
    /// it reads `isComplete` first — so a surface handed an unfinished room is
    /// handed nils and *cannot* print a time.
    func testTheRevealGateIsInTheRoomAndNowhereElse() throws {
        let room = codeOnly(try source("Sources/Shared/Parlor.swift"))
        XCTAssertTrue(
            room.contains("let reveal = isComplete"),
            "the reveal gate moved out of ParlorRoom.members — if a view decides "
                + "when to show a time, the rule is a discipline again")

        // No parlor view reaches for a finish without going through a member.
        for path in ["Sources/App/ParlorViews.swift", "Sources/App/ParlorSession.swift"] {
            let code = codeOnly(try source(path))
            XCTAssertFalse(
                code.contains(".finishes"),
                "\(path) reads the room's held finishes directly, around the gate")
        }
    }

    // MARK: - The loopback is not in Release

    /// Every mention of the demo transport is inside a `#if DEBUG`.
    ///
    /// Counted rather than pattern-matched: the check is that the name appears
    /// only in fenced regions, which a `grep` for the name plus a scan of the
    /// fences answers exactly.
    func testTheLoopbackTransportCannotBeReachedInRelease() throws {
        for path in ["Sources/App/ParlorSession.swift", "Sources/App/AppModel.swift"] {
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
                let names = ["LoopbackParlorTransport", "parlor-demo",
                             "startLoopbackParlorIfRequested"]
                for name in names where line.contains(name) {
                    XCTAssertNotNil(
                        debugDepth,
                        "\(path): \(name) is outside #if DEBUG — a demo transport in "
                            + "Release is a launch argument anybody can pass")
                }
            }
        }
    }

    // MARK: - Nothing a parlor draws is a ranking

    /// The one line that would turn this feature into a leaderboard.
    ///
    /// §6's order is the dots' order, which is by opaque participant id. A sort
    /// by time anywhere in these files is that line, and it would look like an
    /// improvement in review.
    func testNoParlorSurfaceSortsBySeconds() throws {
        for path in Self.surfaces {
            let code = codeOnly(try source(path))
            for needle in ["sorted { $0.seconds", "sorted(by: { $0.seconds",
                           "sorted { $0.finish", "min(by:", "max(by:"] {
                XCTAssertFalse(
                    code.contains(needle),
                    "\(path) orders participants by their solve — PRD-28 §6 and "
                        + "PRD-27 §7: no winner is ever declared")
            }
        }
    }
}
