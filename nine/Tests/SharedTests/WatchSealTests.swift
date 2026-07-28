// WatchSealTests.swift — the two rules the watch tree has to keep, checked
// against its source rather than against its behaviour (PRD-6).
//
// Both of these are invisible at runtime on the machine that would notice.
// A watch composing a Nocturne board does not crash; it sits there, warm,
// for a minute. A watch reaching into the variant engine does not crash
// either; it just ships a channel nobody approved. A source grep is the
// cheapest instrument that fires before either reaches a wrist, and it is the
// shape `VariantChannelSealTests` already established here.
//
// In `SharedTests` rather than beside that one, because `WatchComposePolicy`
// lives in `Sources/Shared` and the ceiling should be quoted from the constant
// rather than re-typed into a failure message.
import XCTest
import NineEngine
@testable import NineShared

final class WatchSealTests: XCTestCase {

    private static var watchTree: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SharedTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // nine
            .appendingPathComponent("Sources/Watch")
    }

    private static func watchSources() throws -> [(name: String, source: String)] {
        let root = watchTree
        let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        return try files.map {
            ($0, try String(contentsOf: root.appendingPathComponent($0), encoding: .utf8))
        }
    }

    /// The tree exists and has files in it. Without this every assertion below
    /// passes vacuously the day someone renames the directory — the exact
    /// failure mode PRD-20 found in its own plural gate.
    func testTheWatchTreeIsWhereTheseTestsThinkItIs() throws {
        let sources = try Self.watchSources()
        XCTAssertFalse(sources.isEmpty, """
            Sources/Watch has no Swift files. Either the tree moved — in which \
            case fix this test — or these seals have been measuring nothing.
            """)
        XCTAssertTrue(sources.contains { $0.name.hasSuffix("WatchApp.swift") },
                      "Sources/Watch has no @main entry point.")
    }

    // MARK: - The compose ceiling

    /// **The watch never generates above catalog-easy** (PROGRAM-2.0
    /// "Engineering foundations").
    ///
    /// Enforced as: nothing under `Sources/Watch` may name a `Difficulty` case
    /// other than through `WatchComposePolicy`. The generator is a pure
    /// function of `(seed, difficulty)`, so the difficulty literal at the call
    /// site *is* the rule — and a literal is exactly the thing a well-meaning
    /// change adds without noticing that the daily takes 50× longer to compose
    /// on an S9 than the gentle board it was tested against.
    func testTheWatchNamesNoDifficultyExceptThroughThePolicy() throws {
        let bands = Difficulty.allCases.map { ".\($0.rawValue)" }
        var offences: [String] = []

        for (name, source) in try Self.watchSources() {
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                // The policy is the sanctioned way to say it, and a comment is
                // allowed to discuss the rule it is documenting.
                let code = line.contains("//") ? String(line[..<line.range(of: "//")!.lowerBound])
                                               : String(line)
                guard !code.contains("WatchComposePolicy") else { continue }
                for band in bands where code.contains(band) {
                    offences.append("Sources/Watch/\(name):\(number + 1) names \(band)")
                }
            }
        }

        XCTAssertEqual(offences, [], """
            The watch may only compose \(WatchComposePolicy.ceiling.rawValue), and the \
            way it says so is `WatchComposePolicy`. A difficulty named directly in \
            the watch tree is a compose ceiling that exists in a comment instead \
            of in code.
            """)
    }

    /// The other half of the same rule: exactly one call into the generator,
    /// so the ceiling has one door rather than several.
    func testTheWatchCallsTheGeneratorInExactlyOnePlace() throws {
        let calls = try Self.watchSources().flatMap { name, source in
            source.split(separator: "\n", omittingEmptySubsequences: false).enumerated()
                .filter { $0.element.contains("PuzzleGenerator.generate") }
                .map { "Sources/Watch/\(name):\($0.offset + 1)" }
        }
        XCTAssertEqual(calls.count, 1, """
            The watch reaches the generator \(calls.count) time(s): \(calls). \
            One call site is what makes the compose ceiling checkable; two is a \
            rule and an exception.
            """)
    }

    // MARK: - Classic only

    /// **Watch stays classic-only** (PROGRAM-2.0, PRD-24). Belt to
    /// `VariantChannelSealTests`'s braces: that test now covers `Sources/Watch`
    /// too, and this one says out loud that the watch is *meant* to be in its
    /// list, so removing it there is a deliberate act rather than a tidy-up.
    func testTheWatchIsInsideTheVariantSeal() throws {
        let seal = try String(
            contentsOf: URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent()   // SharedTests
                .deletingLastPathComponent()   // Tests
                .appendingPathComponent("EngineTests/VariantChannelSealTests.swift"),
            encoding: .utf8)
        XCTAssertTrue(seal.contains("\"Sources/Watch\""), """
            VariantChannelSealTests no longer seals Sources/Watch. The watch is \
            classic-only (PROGRAM-2.0); a variant reaching it would ship a \
            channel with no surface, no daily and no leaderboard.
            """)
    }

    // MARK: - No clocks

    /// PRD-6 §3: "No timer display anywhere on watch (even the pref; calm ×
    /// glance = no clock anxiety on a device that is a clock)."
    ///
    /// `ElapsedTimer` is still *kept* — a solve reports its seconds to the
    /// phone — so the rule is about what reaches the screen, which is what
    /// `WidgetFormat.time`-style formatting would mean here.
    func testTheWatchShowsNoClock() throws {
        var offences: [String] = []
        for (name, source) in try Self.watchSources() {
            for (number, line) in source.split(separator: "\n", omittingEmptySubsequences: false)
                .enumerated() {
                let code = line.contains("//") ? String(line[..<line.range(of: "//")!.lowerBound])
                                               : String(line)
                for banned in ["showTimer", "elapsedLabel", "formatted(.timer", ".timer)"]
                where code.contains(banned) {
                    offences.append("Sources/Watch/\(name):\(number + 1) shows \(banned)")
                }
            }
        }
        XCTAssertEqual(offences, [], """
            PRD-6 §3 rules out a timer display on the watch, even as a \
            preference. The elapsed seconds still travel to the phone with a \
            solve; they never reach the wrist's screen.
            """)
    }
}
