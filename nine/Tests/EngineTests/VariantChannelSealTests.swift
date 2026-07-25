// VariantChannelSealTests — the mechanical half of "no user-facing UI".
//
// PRD-23 is engine work landing in Wave 1; the product surface it feeds —
// Channels, the shelf page-turn, per-variant dailies and streaks — is PRD-24, in
// Wave 3, and that is the PRD the covenant's one-new-input-concept rule and the
// taste ritual apply to. So the variant engine must not be reachable from any
// app surface yet, and a comment saying so is not a guarantee: it survives
// exactly until somebody wants a debug menu.
//
// This walks the app-layer sources and fails if any of them so much as names the
// variant engine. It is deliberately a *source* check rather than a symbol check
// — it fires on the line that would introduce the coupling, in the PR that
// introduces it, which is when it is cheap to talk about.
//
// When PRD-24 does open the channel, this test is the thing to delete, and
// deleting it should feel like a decision.
import XCTest
import Foundation

final class VariantChannelSealTests: XCTestCase {

    /// Every type the variant engine exposes. Naming them individually rather
    /// than grepping for "Variant" keeps the test honest about what it forbids.
    private static let sealedSymbols = [
        "VariantChannel", "VariantGenerator", "VariantPuzzle", "VariantConstraint",
        "VariantTier", "VariantBand", "ConstraintContext", "ConstraintBacktrackSolver",
        "CageTiling",
    ]

    /// App-layer source trees. `Sources/Engine` is exempt: that is where this
    /// lives. `Sources/Shared` is included because it compiles into the widget.
    private static let sealedTrees = ["Sources/App", "Sources/Widgets", "Sources/Shared"]

    func testNoAppSurfaceCanReachTheVariantEngine() throws {
        let nine = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // nine
        var offences: [String] = []

        for tree in Self.sealedTrees {
            let root = nine.appendingPathComponent(tree)
            let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".swift") }
            XCTAssertFalse(files.isEmpty, "\(tree) has no Swift files — did the tree move?")

            for file in files {
                let source = try String(contentsOf: root.appendingPathComponent(file),
                                        encoding: .utf8)
                for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false)
                    .enumerated() {
                    for symbol in Self.sealedSymbols where line.contains(symbol) {
                        offences.append("\(tree)/\(file):\(number + 1) references \(symbol)")
                    }
                }
            }
        }

        XCTAssertEqual(offences, [], """
            The variant engine is sealed until PRD-24 opens the Channels surface, \
            and something in the app layer now reaches it:
            \(offences.joined(separator: "\n"))
            If that is deliberate, PRD-24 is the PR that deletes this test — and \
            deleting it is a decision, not a fix.
            """)
    }
}
