// VariantInputSealTests — the seal PRD-24 put back after taking PRD-23's away.
//
// PRD-23 shipped `VariantChannelSealTests`, which walked `Sources/App`,
// `Sources/Widgets`, `Sources/Shared` and `Sources/Watch` and failed if any of
// them so much as named the variant engine. Its own header said: *"When PRD-24
// does open the channel, this test is the thing to delete, and deleting it should
// feel like a decision."*
//
// It has been deleted, and this is the decision. The old seal asserted a
// temporary fact — "no variant surface exists yet" — which stops being true by
// definition on the day the Channels shelf ships. Replacing it with nothing would
// have thrown away the mechanism along with the claim, so what is sealed instead
// is the claim PRD-24 actually makes, which is narrower, stronger, and permanent:
//
//   **The input covenant is variant-agnostic, and the watch stays classic-only.**
//
// That is not a tidiness rule. It is the strategic point of the whole PRD, stated
// in PROGRAM-2.0 §Pillar B as "the rose is unchanged across variants — the input
// covenant is variant-agnostic, which is the strategic point", and it is what pays
// for the release's one new input concept (the shelf page-turn). A killer board is
// played with the same flick, the same four buttons and the same pencil as a
// classic one; the day someone writes `if variant == .killer` inside
// `FlickRoseView`, that claim is false and 1.x's three-PRD input covenant has been
// quietly spent.
//
// Two things follow from sealing the *input* layer rather than the app layer:
//
//   • `Sources/App/GameScreen.swift` and `TouchUI.swift` are **not** sealed — they
//     have to name a channel, because they draw the shelf and route the board.
//   • `Sources/App/BoardView.swift` is **not** sealed either, and that is worth
//     being explicit about: it *renders* cages and tubes, which is a display
//     concern. Rendering a constraint is not reading input under it.
import XCTest
import Foundation

final class VariantInputSealTests: XCTestCase {

    /// Every type the variant engine exposes. Named individually rather than
    /// grepping for "Variant", which keeps the test honest about what it forbids —
    /// PRD-23's rule, kept.
    private static let sealedSymbols = [
        "VariantChannel", "VariantGenerator", "VariantPuzzle", "VariantConstraint",
        "VariantTier", "VariantBand", "VariantShape", "ConstraintContext",
        "ConstraintBacktrackSolver", "CageTiling", "ThermoTiling",
        "ChannelRules", "ChannelRuleStore", "ChannelLedger",
        // `Channel` itself is deliberately absent from this list. It is the shelf's
        // page axis and the app layer is supposed to name it; what the input layer
        // may not do is branch on a *ruleset*, which is what the symbols above are.
        "Cage(", "Thermometer(",
    ]

    /// The files that turn a human gesture into a move, plus the wrist.
    ///
    /// This is a hand-written list rather than a directory sweep, and that is the
    /// substantive difference from PRD-23's seal. A tree is a location; this is an
    /// argument about *responsibility*, and each entry is here because it is on the
    /// path between a finger and `NineGame.place`.
    private static let inputFiles = [
        "Sources/App/FlickRoseView.swift",   // the rose itself
        "Sources/App/BoardKeys.swift",       // keyboard and Mac key handling
        "Sources/App/PadSession.swift",      // the tvOS remote
        "Sources/App/PencilInk.swift",       // Apple Pencil strokes
        "Sources/Shared/Handwriting.swift",  // glyph recognition
        "Sources/Shared/CrownDial.swift",    // the Digital Crown
        "Sources/Shared/RoseLens.swift",     // petal geometry
    ]

    /// The watch, whole. PROGRAM-2.0 §Pillar B: "Watch stays classic-only."
    ///
    /// `WatchSealTests` already asserts this from the other direction — that the
    /// watch composes nothing above its own ceiling and couriers the classic daily.
    /// This asserts it from the source side, which is the half that catches a
    /// well-meaning "the watch could show the thermo streak too".
    private static let sealedTrees = ["Sources/Watch"]

    private func nineRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // nine
    }

    private func offences(in source: String, path: String) -> [String] {
        var found: [String] = []
        for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false)
            .enumerated() {
            // Comments are allowed to *discuss* the seal — this file's own header
            // does, and so does the note in `FlickRoseView`. What is forbidden is
            // code that reads a ruleset.
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("//") || trimmed.hasPrefix("///") { continue }
            for symbol in Self.sealedSymbols where line.contains(symbol) {
                found.append("\(path):\(number + 1) references \(symbol)")
            }
        }
        return found
    }

    /// The rose, the remote, the keyboard, the Pencil and the Crown do not know
    /// which ruleset they are playing.
    func testTheInputLayerIsVariantAgnostic() throws {
        let nine = nineRoot()
        var offences: [String] = []
        for path in Self.inputFiles {
            let url = nine.appendingPathComponent(path)
            let source = try String(contentsOf: url, encoding: .utf8)
            XCTAssertFalse(source.isEmpty, "\(path) is empty — did the file move?")
            offences.append(contentsOf: self.offences(in: source, path: path))
        }
        XCTAssertEqual(offences, [], """
            The input covenant is variant-agnostic and something now breaks that:
            \(offences.joined(separator: "\n"))
            The rose being unchanged across variants is PRD-24's strategic point \
            and what pays for the shelf page-turn as the release's one new input \
            concept (PROGRAM-2.0 §Pillar B). If a variant genuinely needs a \
            different input, that is a PRD and a covenant conversation, not a \
            branch in here.
            """)
    }

    /// The watch stays classic-only.
    func testTheWatchStaysClassicOnly() throws {
        let nine = nineRoot()
        var offences: [String] = []
        for tree in Self.sealedTrees {
            let root = nine.appendingPathComponent(tree)
            let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".swift") }
            XCTAssertFalse(files.isEmpty, "\(tree) has no Swift files — did the tree move?")
            for file in files {
                let source = try String(
                    contentsOf: root.appendingPathComponent(file), encoding: .utf8)
                offences.append(contentsOf: self.offences(in: source, path: "\(tree)/\(file)"))
            }
        }
        XCTAssertEqual(offences, [], """
            The watch is classic-only (PROGRAM-2.0 §Pillar B) and something now \
            reaches a variant from it:
            \(offences.joined(separator: "\n"))
            A wrist cannot render a cage sum legibly and cannot compose above \
            gentle (`WatchComposePolicy`), so a channel on the watch is a new PRD.
            """)
    }

    /// The file the old seal lived in is gone, asserted rather than assumed.
    ///
    /// Without this, a merge that resurrected `VariantChannelSealTests` would put
    /// back a test that now *must* fail — it greps `Sources/App` for `VariantTier`,
    /// which the shelf legitimately names — and the failure would read as a
    /// PRD-24 regression rather than as a bad merge.
    func testThePRD23ChannelSealIsGoneRatherThanDisabled() {
        let old = nineRoot()
            .appendingPathComponent("Tests/EngineTests/VariantChannelSealTests.swift")
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: old.path),
            """
            VariantChannelSealTests.swift is back. It sealed the whole app layer \
            away from the variant engine, which was right for PRD-23 and is \
            incompatible with PRD-24's shelf. This file replaced it deliberately; \
            if it returned in a merge, delete it again.
            """)
    }
}
