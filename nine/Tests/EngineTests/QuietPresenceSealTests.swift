// The seal on PRD-30's promise (no timers, no countdowns, no streak nagging
// ever), enforced against source text rather than against a comment.
//
// This is the shape `VariantChannelSealTests` established: a rule that cannot be
// expressed as a type is expressed as a grep, and the grep runs in `swift test`
// where nobody can forget it. The reason it is needed here is that PRD-30's
// headline requirement is a **negative**, and negatives erode without anything
// going red — a Live Activity that grows an elapsed-time line still builds, still
// passes every other test, and is exactly the app Nine promised not to be.
//
// The positive half of the same promise is `QuietPresenceTests`, which checks the
// *payload* has no clock in it. This checks the *views*, which is the other place a
// clock can appear: `Text(_:style: .timer)` needs no field in the content state at
// all, because ActivityKit renders it from `Date` on the system's side.
import XCTest

final class QuietPresenceSealTests: XCTestCase {

    static let nineRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()   // EngineTests
        .deletingLastPathComponent()   // Tests
        .deletingLastPathComponent()   // nine

    private func source(_ relative: String) throws -> String {
        try String(
            contentsOf: Self.nineRoot.appendingPathComponent(relative), encoding: .utf8
        )
    }

    /// Strip `//` and `/* */` comments, so the *prose* in these files — which
    /// discusses timers at length, on purpose — cannot fail the test that forbids
    /// them, and cannot mask a real one either.
    private func codeOnly(_ text: String) -> String {
        var out = ""
        var inBlock = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            var body = String(line)
            if inBlock {
                guard let end = body.range(of: "*/") else { continue }
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
            if let comment = body.range(of: "//") {
                body = String(body[..<comment.lowerBound])
            }
            out += body + "\n"
        }
        return out
    }

    /// The files that draw or drive a quiet surface.
    private static let presenceFiles = [
        "Sources/Widgets/DailyPresenceActivityViews.swift",
        "Sources/Widgets/BoardGlyphView.swift",
        "Sources/Shared/QuietPresence.swift",
        "Sources/Shared/DailyPresenceActivity.swift",
        "Sources/App/PresenceBridge.swift",
    ]

    /// Every API that puts a running clock on screen, and every word that would
    /// make one findable. `Text(…, style:)` is the dangerous one: it needs no field
    /// in the payload, because the *system* animates it from a `Date`.
    private static let forbiddenClockAPIs = [
        "timerInterval",
        "countsDown",
        "style: .timer",
        "style: .relative",
        "style: .offset",
        ".timeDataSource",
        "ProgressView(timerInterval",
        "Text(timerInterval",
    ]

    func testTheQuietSurfacesNameNoTimerApi() throws {
        for file in Self.presenceFiles {
            let code = codeOnly(try source(file))
            for api in Self.forbiddenClockAPIs {
                XCTAssertFalse(code.contains(api), """
                    \(file) names `\(api)`.

                    PRD-30 is explicit: **no timers, no countdowns, no \
                    streak-endangered nagging ever** — "PRD-13 grace exists so we \
                    never have to". A running clock on a Lock Screen is the single \
                    change that would turn a bookmark into a deadline, and it is one \
                    modifier away at all times. If a clock is genuinely wanted, that \
                    is a product decision that goes through the covenant and this \
                    test, in that order.
                    """)
            }
        }
    }

    /// Nothing on a quiet surface may mention the streak. Not the count, not the
    /// shield, not the words "day streak" — PRD-13 made the streak forgiving inside
    /// the app, and outside it the only safe amount is none.
    func testTheQuietSurfacesNameNoStreak() throws {
        for file in Self.presenceFiles {
            let code = codeOnly(try source(file)).lowercased()
            for word in ["streak", "flame", "displayedstreak"] {
                XCTAssertFalse(code.contains(word), """
                    \(file) names "\(word)". The Lock Screen, the Dynamic Island and \
                    the StandBy face carry no streak — that is what \
                    "no streak-endangered nagging ever" means, and the surface a \
                    player sees without choosing to is the worst possible place to \
                    put a number they can lose.
                    """)
            }
        }
    }

    /// `AlertConfiguration` is how a Live Activity buzzes, rings and pushes a
    /// banner. Nine's never does, and that absence is one of the three properties
    /// `NinePrefs.livePresence` leans on to argue it is not a notification.
    func testTheLiveActivityIsNeverAlerting() throws {
        for file in Self.presenceFiles {
            let code = codeOnly(try source(file))
            XCTAssertFalse(code.contains("AlertConfiguration"), """
                \(file) builds an `AlertConfiguration`. The Live Activity is on by \
                default (`NinePrefs.livePresence`) precisely because it cannot \
                alert: the covenant's rule is "no notifications beyond a single \
                opt-in silent daily reminder, off by default", and an alerting \
                activity is a notification whatever it is called. Either this goes, \
                or the pref's default does.
                """)
            XCTAssertFalse(code.contains("pushType: .token"), """
                \(file) requests a push token. Nine has no server and no APNs \
                plumbing; `pushType: nil` is the whole transport.
                """)
        }
    }

    /// The seal is only worth having if it can fail. This drives the same rule
    /// against text that *should* trip it — the lesson from PRD-31, where a test
    /// bucketed its inputs by which list they came from and measured its own
    /// labelling.
    func testTheSealFiresOnCodeAndNotOnProse() {
        let prose = """
            // This file has no timerInterval and no streak, and says so at length:
            // countsDown, AlertConfiguration, Text(timerInterval: …) are all named
            /* here in a block comment, and in `style: .timer` form too. */
            let glyph = BoardGlyph.blank
            """
        let stripped = codeOnly(prose)
        for needle in Self.forbiddenClockAPIs + ["AlertConfiguration"] {
            XCTAssertFalse(stripped.contains(needle),
                           "comment stripping let \"\(needle)\" through")
        }
        XCTAssertTrue(stripped.contains("BoardGlyph.blank"), "stripping ate the code")

        let real = """
            Text(state.deadline, style: .timer)
            let alert = AlertConfiguration(title: "x", body: "y", sound: .default)
            """
        let realStripped = codeOnly(real)
        XCTAssertTrue(realStripped.contains("style: .timer"), "the rule cannot fire")
        XCTAssertTrue(realStripped.contains("AlertConfiguration"), "the rule cannot fire")
    }
}
