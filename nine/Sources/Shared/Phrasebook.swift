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
/// (a digit word, a unit name).
///
/// Deliberately not `CVarArg`. That protocol is how a `Float`, a pointer or a
/// `CGRect` gets into a format string and out the other side as undefined
/// behaviour, and closing the argument set to two cases keeps all of that out.
///
/// **It does not close the *specifier* set, and that is the dangerous half.**
/// `%1$@` against `.int` is not a wrong string, it is a segfault —
/// `String(format:)` reads the integer as an object pointer and messages it.
/// Measured on this machine, all three of these are reachable from a one-word
/// edit or a translator's typo:
///
///     String(format: "%1$@",   arguments: [5 as CVarArg])      // SIGSEGV
///     String(format: "%1$lld", arguments: ["abc" as CVarArg])  // -4868140715284934059
///     String(format: "%1$lld and %2$lld", arguments: [7])      // "7 and 0"
///
/// `Phrasebook.format` is where that is caught; see `specifierMismatch`.
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

    /// The same lookup with the arguments already collected.
    ///
    /// Swift cannot splat an array back into a variadic parameter, so a
    /// function that takes `PhraseArg...` and forwards it has nowhere to go —
    /// which is exactly what `Strings.string(_:_:)`, the App layer's one-line
    /// wrapper, needs to do. Found by the first Xcode build rather than by
    /// `swift test`, because `Sources/Strings` is deliberately not a SwiftPM
    /// target (`LocalizedStringResource` does not exist on Linux), so the cheap
    /// lane compiles neither that file nor this call.
    public func string(_ key: String, args: [PhraseArg]) -> String {
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
        return Phrasebook.format(Phrasebook.englishPlural(key, format, args), args)
    }

    /// The English category of a count-bearing phrase.
    ///
    /// English has exactly two cardinal categories and `one` is exactly n == 1,
    /// so this is a comparison rather than a rule engine — the rule engine is
    /// ICU's, and it runs in the shipping app, where the catalog's compiled
    /// `.stringsdict` answers instead of this. What reaches here is `swift
    /// test`, the Linux lane, and a key the catalog does not have.
    ///
    /// `EnglishPhrases.substitutions` is deliberately NOT implemented here; see
    /// that table's doc comment. Those three keys fall through to their `table`
    /// row, which is the all-`other` sentence.
    static func englishPlural(_ key: String, _ format: String, _ args: [PhraseArg]) -> String {
        guard let plural = EnglishPhrases.plurals[key],
              plural.count >= 1, plural.count <= args.count,
              case .int(1) = args[plural.count - 1] else { return format }
        return plural.one
    }

    // **Written exactly once per PROCESS, before the first read.** Not "from
    // `NineApp.init`" — that was the first version of this comment and it was
    // false on three of the four processes this file compiles into:
    //
    //   • `NineApp.init` exists only under `#if os(macOS)` (`NineApp.swift`),
    //     so on iOS and tvOS `NineApp` has no `init` at all and there is
    //     nowhere for the call to be.
    //   • `NineWidgets.appex` never runs `NineApp`. Left as is, `installed`
    //     stays nil there forever and `current` is permanently English — in the
    //     one bundle whose existence is half the argument for this seam
    //     existing. The widget consumes no Shared phrase today, so nothing is
    //     broken on this branch; it will be the moment one lands.
    //   • Even on macOS, `@State private var model = AppModel()` is a
    //     stored-property default, constructed BEFORE the `init` body runs. An
    //     install placed in `init` is one `AppModel` change away from being too
    //     late. `AppModel` builds no phrases today.
    //
    // So the invariant is process-local and read-ordered, and the wiring that
    // satisfies it is Task 4's: an `init` added on iOS/tvOS, a second install
    // in `NineWidgetBundle`, or `current` learning to self-install. Whichever
    // it is, `precondition` below is what makes a violation loud rather than
    // theoretical.
    //
    // No lock on the READ path. The perf line is real — 81 acquisitions per AX
    // dump (`BoardAccessibility` labels every cell) and 42 per archive body
    // evaluation — but it is not the reason: the reason is that this is a
    // single-writer value that is written before any reader exists, which makes
    // a lock a way of hiding a broken launch sequence rather than a way of
    // being correct. `ArchiveCalendar.cachedFormatter` sets the opposite house
    // precedent *with* a lock, and it is right to: its cache is written by
    // readers, on the render path, forever.
    //
    // `precondition`, not `assert`. `assert` is erased at `-O`, so in the
    // shipping app a second install would be exactly the silent shrug this is
    // here to prevent — and the shipping app is where a stray install is most
    // likely and least observable. One branch, once, at launch.
    nonisolated(unsafe) private static var installed: Phrasebook?

    public static var current: Phrasebook { installed ?? .english }

    public static func install(_ book: Phrasebook) {
        precondition(installed == nil, "Phrasebook.install is launch-time and once per process")
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
    ///
    /// **Validated before it is formatted**, because the failure mode is a
    /// segfault rather than a wrong word (see `PhraseArg`). A mismatch is an
    /// `assertionFailure` in Debug — it is always a bug in the table, in a
    /// translation, or in a call site — and in Release it returns the raw
    /// format string. That is deliberately the same shape as the missing-key
    /// fallback: the player sees `%1$@` where a word should be and reports it,
    /// which beats both a crash and a lie.
    public static func format(_ format: String, _ args: [PhraseArg]) -> String {
        if let mismatch = specifierMismatch(format, args) {
            assertionFailure("Phrasebook: \(mismatch) — in \"\(format)\"")
            return format
        }
        return String(format: format, arguments: args.map { arg -> CVarArg in
            switch arg {
            case .int(let number): return number
            case .text(let text): return text
            }
        })
    }

    /// What is wrong with this format/argument pair, or nil if nothing is.
    ///
    /// A state machine over `format.utf8`, allocating nothing on the success
    /// path, because this runs on the 81-label AX path and the first version of
    /// it did not. That version opened with `Array(format)` — a `[Character]`,
    /// so a grapheme-breaking pass and a heap allocation per call — and
    /// measured **518 ns per label, 33% of the whole `format` call**. Which is
    /// not a rounding error, and the comment that claimed it was got there by
    /// reasoning instead of measuring. This version measures 44-47 ns, 4.1% of
    /// a `format` call, over 810k calls in a `-O` build (method and numbers in
    /// the task report). Format specifiers are ASCII by definition, so bytes
    /// lose nothing.
    ///
    /// It deliberately does NOT track "index 3 is a `%@` here and a `%lld`
    /// there". That would need a per-call allocation to remember, and it buys
    /// nothing: an argument has one kind, so of two differing conversions at
    /// least one must already disagree with it and be caught below. The one
    /// case that escapes — `%1$d` and `%1$i` in the same string — is two
    /// spellings of the same thing. The whole-table version of that rule is a
    /// test (`testNoPositionalIndexCarriesTwoConversions`), where it is free.
    static func specifierMismatch(_ format: String, _ args: [PhraseArg]) -> String? {
        // Flags, width, precision and length modifiers. Nine's English uses
        // none of them; a translation may, and skipping them is cheaper than
        // being surprised by "%1$02lld" in a language that pads its numerals.
        func isModifier(_ byte: UInt8) -> Bool {
            switch byte {
            case UInt8(ascii: "0")...UInt8(ascii: "9"),
                 UInt8(ascii: "-"), UInt8(ascii: "+"), UInt8(ascii: " "),
                 UInt8(ascii: "#"), UInt8(ascii: "."),
                 UInt8(ascii: "l"), UInt8(ascii: "h"), UInt8(ascii: "q"),
                 UInt8(ascii: "j"), UInt8(ascii: "z"), UInt8(ascii: "t"):
                return true
            default:
                return false
            }
        }

        enum State { case literal, afterPercent, readingIndex, readingModifiers,
                          expectingSubstitution, readingSubstitution }
        var state = State.literal
        var index = 0

        for byte in format.utf8 {
            switch state {
            case .literal:
                if byte == UInt8(ascii: "%") { state = .afterPercent }

            case .afterPercent:
                if byte == UInt8(ascii: "%") { state = .literal; continue }   // an escaped percent
                // `%#@name@` — a substitution with no position, which is what
                // `xcstringstool` emits for a plural on a string that names one
                // argument. It means argument 1. See `readingSubstitution`.
                if byte == UInt8(ascii: "#") {
                    index = 1
                    state = .expectingSubstitution
                    continue
                }
                guard byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") else {
                    return Self.bareSpecifier
                }
                index = Int(byte - UInt8(ascii: "0"))
                state = .readingIndex

            case .readingIndex:
                if byte >= UInt8(ascii: "0"), byte <= UInt8(ascii: "9") {
                    index = index * 10 + Int(byte - UInt8(ascii: "0"))
                    continue
                }
                guard byte == UInt8(ascii: "$") else { return Self.bareSpecifier }
                state = .readingModifiers

            case .expectingSubstitution:
                guard byte == UInt8(ascii: "@") else { return Self.bareSpecifier }
                state = .readingSubstitution
                // The argument a substitution counts is always an integer —
                // `formatSpecifier: "lld"` in every one the generator writes.
                guard index >= 1, index <= args.count else {
                    return "%\(index)$#@ but only \(args.count) argument(s) were passed"
                }
                guard case .int = args[index - 1] else {
                    return "%\(index)$#@ counts argument \(index), which is text — "
                        + "a plural category is selected from a number"
                }

            case .readingSubstitution:
                // Names are `[A-Za-z0-9_]`, terminated by `@`. Nothing inside is
                // validated: the real conversions live in the compiled
                // .stringsdict's per-category values, which this process cannot
                // see. They are checked where they CAN be — over the whole
                // table, at build time, by `PhrasebookTests` and `CatalogTests`.
                if byte == UInt8(ascii: "@") { state = .literal }

            case .readingModifiers:
                // `%N$#@name@` — a substitution with its argument written down,
                // which is what the catalog emits for every plural whose count
                // is not the string's only number. This is the shape that
                // arrives at runtime from `String(localized:)`: the catalog
                // hands back `NSStringLocalizedFormatKey` and `String(format:)`
                // does the category selection. Before PRD-20 Task 8 this fell
                // through to "not a conversion Nine's phrases support", which
                // is an `assertionFailure` in Debug and the raw `%1$#@value@`
                // on screen in Release.
                if byte == UInt8(ascii: "#") { state = .expectingSubstitution; continue }
                if isModifier(byte) { continue }
                state = .literal
                let conversion = Character(UnicodeScalar(byte))
                guard index >= 1, index <= args.count else {
                    return "%\(index)$ but only \(args.count) argument(s) were passed "
                        + "— the missing slot reads as whatever is next on the stack"
                }
                switch (conversion, args[index - 1]) {
                case ("@", .text), ("d", .int), ("i", .int), ("u", .int),
                     ("x", .int), ("X", .int), ("o", .int):
                    continue
                case ("@", .int):
                    return "%\(index)$@ was given a number — String(format:) reads it "
                        + "as an object pointer and segfaults"
                case (_, .text):
                    return "%\(index)$\(conversion) was given text — String(format:) "
                        + "prints the string's raw bits as a number"
                default:
                    return "%\(index)$\(conversion) is not a conversion Nine's phrases "
                        + "support (%@ for text, %lld for numbers)"
                }
            }
        }
        // A specifier the string ended in the middle of: "%", "%1", "%1$", "%1$0".
        return state == .literal ? nil : "a specifier with no conversion character"
    }

    private static let bareSpecifier =
        "a bare specifier — every one must be positional (%1$lld, %2$@) "
        + "and a literal percent must be %%"
}
