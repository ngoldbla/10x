// Phrasebook.swift — the one seam between Nine's formatting logic and its words
// (PRD-20 "Nine Languages").
//
// `Sources/Shared` cannot use `LocalizedStringResource`, and there are three
// independent reasons for that, any one of which is sufficient:
//
//   1. It is the `NineShared` SwiftPM target (`Package.swift`), which must build
//      on Linux, where that type does not exist.
//   2. It compiles into TWO bundles — `Nine.app` and `NineWidgets.appex`
//      (`project.yml`). Inside an app extension `Bundle.main` IS the extension,
//      so "look it up in the main bundle" means two different things from one
//      source file. `swift test` makes a third (`Bundle.module`).
//   3. `BoardSpeechTests` runs FIRST in CI, before the simulator is built at all
//      (`.github/workflows/nine-accessibility.yml`), and asserts exact wording.
//      A design that needs a bundle to produce a sentence destroys that
//      tripwire — the cheapest test in the repo would become the most expensive.
//
// Rather than three conditionals in every formatter, there is one indirection
// here: the App installs a resolver at launch, and everything in Shared asks
// `Phrasebook.current`. The default is English, held as data in
// `EnglishPhrases` — which is both what `BoardSpeechTests` asserts against and
// what Task 4 generates the catalog's `en` locale from. One English, two
// consumers, no bundle.
import Foundation

/// An argument to a phrase. Two cases because two is what Nine's sentences
/// take: a number (a row, a count, a streak) and an already-formatted fragment
/// (a digit word, a unit name). Deliberately not `CVarArg` — that protocol is
/// how a `Float` or a pointer gets into a format string and out the other side
/// as undefined behaviour, and this enum is the closed set that cannot.
public enum PhraseArg: Sendable {
    case int(Int)
    case text(String)
}

/// Nine's words, behind one function.
public struct Phrasebook: Sendable {
    public typealias Resolve = @Sendable (_ key: String, _ args: [PhraseArg]) -> String

    private let resolve: Resolve

    public init(resolve: @escaping Resolve) {
        self.resolve = resolve
    }

    public func string(_ key: String, _ args: PhraseArg...) -> String {
        resolve(key, args)
    }

    /// The floor. Data in, format out, no bundle anywhere.
    ///
    /// **A missing key returns the key**, not "" and not a trap. A player who
    /// sees `board.nope` on screen files a bug with the key in it; an empty
    /// string is a blank label nobody reports, and a crash on a Tuesday because
    /// a translator deleted a row is not a trade anyone would take. Task 4
    /// layers an English fallback on top of this so a *translated* catalog with
    /// a hole falls back to English rather than to the key.
    public static let english = Phrasebook { key, args in
        guard let format = EnglishPhrases.table[key] else { return key }
        return Phrasebook.format(format, args)
    }

    // Written exactly once, from `NineApp.init`, before the first SwiftUI body
    // evaluates. A lock on the READ path would cost 81 acquisitions per AX dump
    // (`BoardAccessibility` labels every cell) and 42 per archive body
    // evaluation (`ArchiveCalendar`'s own comment above `cachedFormatter`
    // explains why that path is measured rather than assumed) — for a value
    // that never changes after launch. The `assert` is what keeps "written
    // once" true: it is the only thing standing between this and a data race,
    // so a second `install` has to be a development-time crash rather than a
    // shrug. `PhrasebookTests` is the only caller in the test suite, and the
    // book it installs delegates to English so nothing else's wording moves.
    nonisolated(unsafe) private static var installed: Phrasebook?

    public static var current: Phrasebook { installed ?? .english }

    public static func install(_ book: Phrasebook) {
        assert(installed == nil, "Phrasebook.install is launch-time and once")
        installed = book
    }

    /// Positional `String(format:)` over `PhraseArg`.
    ///
    /// Positional so a translation may reorder: `%1$lld` / `%2$@`, never a bare
    /// `%lld`. This is not a style preference. German and Japanese both front
    /// the column in Nine's cell label, and with bare specifiers the only way to
    /// say "Spalte 5, Zeile 3" is to ship a different call site per language.
    /// `PhrasebookTests.testEveryFormatSpecifierIsPositional` is what keeps the
    /// table honest about it.
    ///
    /// `%lld` rather than `%d` because `Int` is 64-bit on every platform Nine
    /// ships to, and `%d` would read the low half of a 64-bit vararg.
    public static func format(_ format: String, _ args: [PhraseArg]) -> String {
        String(format: format, arguments: args.map { arg -> CVarArg in
            switch arg {
            case .int(let number): return number
            case .text(let text): return text
            }
        })
    }
}
