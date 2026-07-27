// PhrasebookTests — the seam between Nine's formatting logic and its words.
//
// Four behaviours, and every one of them is a thing that only fails in a
// language nobody on this team reads:
//
//   • English is the default with nothing installed, so `swift test` — which
//     has no bundle to speak of, and `BoardSpeechTests` runs before CI has even
//     built a simulator — still produces the sentences PRD-19 pinned.
//   • A missing key returns the key. Loud in a screenshot, silent at runtime.
//   • Arguments are positional, so a translation may reorder them. German and
//     Japanese both front the column in Nine's cell label; if the resolver were
//     not positional this file is the only place anyone would find out.
//   • `install` is honoured, and the read path after it is a plain load.
//
// **This is the only test in the suite that calls `Phrasebook.install`.** There
// is deliberately no uninstall — `install` is launch-time and once, and a
// teardown hook would be a second writer to the very variable whose
// single-writer property is what makes the lock-free read path safe. So the
// book installed here *delegates to English*: after this test runs, every other
// test in the process still sees the same words it saw before, and the proof
// that the seam is live is a side-channel (the recorded keys) rather than a
// change of wording. Order-independence falls out of that, and out of
// `testDefaultsToEnglish…` asserting on `Phrasebook.english` by name.
import XCTest
import Foundation
@testable import NineShared

final class PhrasebookTests: XCTestCase {

    // MARK: - The four behaviours

    func testDefaultsToEnglishWithNothingInstalled() {
        XCTAssertEqual(Phrasebook.english.string("board.cell.label", .int(3), .int(5)),
                       "Row 3, column 5")
        // A `%@` argument, a two-argument sentence, and a format with no
        // arguments at all — the three shapes the table actually contains.
        XCTAssertEqual(Phrasebook.english.string("board.announce.placed", .text("four")),
                       "Placed four.")
        XCTAssertEqual(Phrasebook.english.string("board.progress.filled", .int(18), .int(51)),
                       "18 of 51 filled.")
        XCTAssertEqual(Phrasebook.english.string("board.announce.solved"), "Solved.")
        XCTAssertEqual(Phrasebook.english.string("board.value.noteSeparator"), ", ")
    }

    func testUnknownKeyReturnsTheKeyRatherThanCrashing() {
        // A missing key must be loud in a screenshot and silent at runtime: the
        // player sees "board.nope" and files a bug; nobody gets a crash on a
        // Tuesday because a translator deleted a row.
        XCTAssertEqual(Phrasebook.english.string("board.nope"), "board.nope")
        // …including when arguments were supplied. A key that vanished mid
        // release is exactly the case where the call site still passes two.
        XCTAssertEqual(Phrasebook.english.string("board.nope", .int(3), .text("x")), "board.nope")
        XCTAssertEqual(Phrasebook.english.string(""), "")
        XCTAssertEqual(Phrasebook.current.string("board.nope"), "board.nope",
                       "the fallback is a property of the resolver, not of `english` alone")
    }

    func testPositionalArgumentsSurviveReordering() {
        // German fronts the column in some phrasings. If the resolver is
        // positional, a translation can reorder; if it is not, this test is the
        // only place anyone finds out.
        let book = Phrasebook { _, args in Phrasebook.format("%2$lld/%1$lld", args) }
        XCTAssertEqual(book.string("k", .int(3), .int(5)), "5/3")

        // The real thing: Nine's cell label, reordered the way a German
        // translation of it would be, against the same call site.
        let german = Phrasebook { _, args in
            Phrasebook.format("Spalte %2$lld, Zeile %1$lld", args)
        }
        XCTAssertEqual(german.string("board.cell.label", .int(3), .int(5)),
                       "Spalte 5, Zeile 3")

        // Arguments reorder whatever their kind, and a position may be used
        // twice — `coach.boxLine.sentence.boxToRow` names its target unit twice
        // in English already, and its digit twice on top of that.
        let repeated = Phrasebook { _, args in Phrasebook.format("%2$@ %1$@ %2$@", args) }
        XCTAssertEqual(repeated.string("k", .text("a"), .text("b")), "b a b")

        XCTAssertEqual(
            Phrasebook.english.string("coach.boxLine.sentence.boxToRow",
                                      .int(7), .int(1), .int(1)),
            "Every 7 still possible in box 1 sits in row 1, "
                + "so no other square in row 1 can be a 7."
        )
    }

    func testInstallIsHonouredAndIdempotentReadsAreCheap() {
        // Before anything is installed, `current` *is* `english`. This holds
        // whatever order XCTest runs the suite in, because this method is the
        // only caller of `install` anywhere in it (see the file header).
        XCTAssertEqual(Phrasebook.current.string("board.unit.box", .int(2)), "Box 2")

        let log = KeyLog()
        Phrasebook.install(Phrasebook { key, args in
            log.record(key)
            guard let format = EnglishPhrases.table[key] else { return key }
            return Phrasebook.format(format, args)
        })

        XCTAssertEqual(Phrasebook.current.string("board.unit.box", .int(2)), "Box 2")
        XCTAssertEqual(log.recorded, ["board.unit.box"],
                       "the installed resolver is what `current` reads")

        // Every read goes through the installed book — there is no caching of
        // the first answer, which is what makes a mid-session language change
        // possible at all. Ten reads, ten recorded keys, same answer each time.
        for _ in 0..<10 {
            XCTAssertEqual(Phrasebook.current.string("board.value.empty"), "Empty")
        }
        XCTAssertEqual(log.recorded.count, 11)
        XCTAssertEqual(Set(log.recorded), ["board.unit.box", "board.value.empty"])

        // Installing does not mutate the default. `english` is the fallback the
        // App's own resolver falls back *to* (Task 4), so it has to survive.
        XCTAssertEqual(Phrasebook.english.string("board.unit.box", .int(2)), "Box 2")
        XCTAssertEqual(log.recorded.count, 11, "`english` does not route through `current`")

        // And the seam is actually wired: `BoardSpeech` — the thing 81 AX
        // labels a minute come out of — asks `Phrasebook.current`, not a
        // literal. Same words, but now they arrive through the installed book.
        log.clear()
        XCTAssertEqual(BoardSpeech.cellLabel(40), "Row 5, column 5")
        XCTAssertEqual(log.recorded, ["board.cell.label"],
                       "BoardSpeech reads its words through the seam")
    }

    // MARK: - The table's shape

    /// Every specifier in the table is positional. Not just the multi-argument
    /// ones: a bare `%lld` in a one-argument string is a trap set for the day a
    /// translator needs a second argument, and "all of them" is a rule a script
    /// can check where "the ones with two arguments" is not.
    func testEveryFormatSpecifierIsPositional() {
        for (key, format) in EnglishPhrases.table {
            XCTAssertEqual(
                Self.nonPositionalSpecifiers(in: format), [],
                """
                \(key) = "\(format)" uses a bare specifier. Write %1$lld / %2$@ \
                so a translation may reorder — German and Japanese both front \
                the column in Nine's cell label.
                """
            )
        }
    }

    /// The table is one sorted `"key": "value",` per line, because Task 4
    /// generates the catalog's `en` locale by *reading this file*. A dictionary
    /// literal the compiler accepts and a script cannot parse would put the
    /// English in two places that agree only by luck — so the parse and the
    /// compiled dictionary are checked against each other here.
    func testTableIsOneSortedEntryPerLineSoAScriptCanReadIt() throws {
        let source = try String(contentsOf: Self.englishPhrasesSource(), encoding: .utf8)
        let parsed = Self.parseTableSource(source)

        XCTAssertEqual(parsed.count, EnglishPhrases.table.count,
                       "the file's lines and the compiled table disagree on how many phrases exist")
        XCTAssertEqual(parsed.map(\.key), EnglishPhrases.table.keys.sorted(),
                       "keys must be sorted, one per line — a generator diffs this file")
        for (key, value) in parsed {
            XCTAssertEqual(EnglishPhrases.table[key], value,
                           "\(key) reads differently from the file than from the dictionary")
        }
    }

    /// No positional index carries two different conversion characters in the
    /// same string. `coach.boxLine.sentence.boxToRow` names `%1$lld` and
    /// `%3$lld` twice each and `coach.xWing.sentence.rowBase` names `%1$lld`
    /// twice — exactly the shape a translator breaks, because reordering a
    /// sentence means editing one occurrence and it is the second one that gets
    /// forgotten. `%1$@ … %1$lld` is a segfault at one of the two sites,
    /// whichever the argument turns out not to be.
    ///
    /// This lives here rather than inside `Phrasebook.format` on purpose: at
    /// runtime it would cost a per-call allocation to remember what it had
    /// already seen, and the only case it uniquely catches is one the kind
    /// check catches anyway. Over the whole table, once, it is free.
    func testNoPositionalIndexCarriesTwoConversions() {
        for (key, format) in EnglishPhrases.table {
            var seen: [Int: Character] = [:]
            for (index, conversion) in Self.positionalSpecifiers(in: format) {
                if let first = seen[index] {
                    XCTAssertEqual(
                        conversion, first,
                        """
                        \(key) = "\(format)" spells argument \(index) as \
                        %\(index)$\(first) in one place and %\(index)$\(conversion) in \
                        another. One of the two will be handed the wrong kind.
                        """
                    )
                }
                seen[index] = conversion
            }
        }
    }

    /// The guard `Phrasebook.format` runs before `String(format:)`. The first
    /// three cases are a measured crash and two measured lies on this machine,
    /// not hypotheticals — `%1$@` against an `Int` is a SIGSEGV, `%1$lld`
    /// against a `String` prints the string's raw bits, and a slot with no
    /// argument reads whatever is next on the stack. All three are one word's
    /// edit away at any call site, and Task 9 puts them one typo away in nine
    /// catalogs at once.
    ///
    /// Asserted through `specifierMismatch` rather than through `format`,
    /// because `format` is *supposed* to trap in Debug and XCTest cannot
    /// survive an `assertionFailure`. What `format` then does with the answer —
    /// trap in Debug, hand back the raw format string in Release — is the one
    /// line here that a unit test cannot reach.
    func testFormatRefusesAnArgumentTheSpecifierCannotTake() {
        XCTAssertNotNil(Phrasebook.specifierMismatch("%1$@", [.int(5)]),
                        "%@ against an Int is a segfault, not a wrong string")
        XCTAssertNotNil(Phrasebook.specifierMismatch("%1$lld", [.text("abc")]),
                        "%lld against a String prints its raw bits")
        XCTAssertNotNil(Phrasebook.specifierMismatch("%1$lld and %2$lld", [.int(7)]),
                        "a slot with no argument reads the stack")

        // Bare specifiers, a stray percent, and conversions Nine does not use.
        XCTAssertNotNil(Phrasebook.specifierMismatch("Row %lld", [.int(3)]))
        XCTAssertNotNil(Phrasebook.specifierMismatch("50% done", [.int(3)]))
        XCTAssertNotNil(Phrasebook.specifierMismatch("%1$f", [.int(3)]))
        XCTAssertNotNil(Phrasebook.specifierMismatch("%1$s", [.text("x")]))
        XCTAssertNotNil(Phrasebook.specifierMismatch("%0$lld", [.int(3)]),
                        "positional indices are 1-based")

        // Strings that stop in the middle of a specifier. The state machine
        // reads one byte at a time and cannot look ahead, so "ran off the end"
        // has to be answered after the loop rather than inside it.
        for truncated in ["%", "%1", "%1$", "%1$0", "Row %1$"] {
            XCTAssertNotNil(Phrasebook.specifierMismatch(truncated, [.int(3)]),
                            "\"\(truncated)\" ends mid-specifier")
        }

        // …and the shapes that are fine, so this is a rule and not a veto.
        XCTAssertNil(Phrasebook.specifierMismatch("Row %1$lld, column %2$lld", [.int(3), .int(5)]))
        XCTAssertNil(Phrasebook.specifierMismatch("%1$@ placed.", [.text("Four")]))
        XCTAssertNil(Phrasebook.specifierMismatch("Solved.", []))
        XCTAssertNil(Phrasebook.specifierMismatch("50%% done", [.int(3)]),
                     "an escaped percent is a percent")
        XCTAssertNil(Phrasebook.specifierMismatch("%2$@ %1$@ %2$@", [.text("a"), .text("b")]),
                     "reordering and reuse are the whole point")
        XCTAssertNil(Phrasebook.specifierMismatch("%1$02lld", [.int(3)]),
                     "width and flags belong to the translation, not to us")

        // Every phrase in the table, against the arguments its own specifiers
        // ask for. `BoardSpeechTests` covers the table against the arity the
        // code really calls it with; this is the table against itself, so an
        // entry no call site has reached yet still cannot be malformed.
        for (key, format) in EnglishPhrases.table {
            XCTAssertNil(Phrasebook.specifierMismatch(format, Self.plausibleArguments(for: format)),
                         "\(key) = \"\(format)\" cannot be formatted by its own specifiers")
        }
    }

    /// Nothing in the table is empty, and nothing is a key repeated as its own
    /// value — both are what a half-finished extraction looks like, and both
    /// would sail past every other test in this file.
    func testNoPhraseIsEmptyOrEchoesItsKey() {
        for (key, value) in EnglishPhrases.table {
            XCTAssertFalse(value.isEmpty, "\(key) has no English")
            XCTAssertNotEqual(value, key, "\(key) is its own value — the missing-key fallback in disguise")
        }
    }

    // MARK: - Helpers

    /// `(index, conversionCharacter)` for every positional specifier, in order.
    /// Deliberately a second, dumber reader than `Phrasebook.specifierMismatch`
    /// — a helper that shared the production parser could not catch the
    /// production parser being wrong.
    static func positionalSpecifiers(in format: String) -> [(index: Int, conversion: Character)] {
        let characters = Array(format)
        var found: [(index: Int, conversion: Character)] = []
        var i = 0
        while i < characters.count {
            guard characters[i] == "%" else { i += 1; continue }
            i += 1
            guard i < characters.count else { break }
            if characters[i] == "%" { i += 1; continue }
            var digits = ""
            while i < characters.count, characters[i].isNumber {
                digits.append(characters[i])
                i += 1
            }
            guard let index = Int(digits), i < characters.count, characters[i] == "$" else { continue }
            i += 1
            while i < characters.count, "-+ #0.lhqjzt".contains(characters[i]) || characters[i].isNumber {
                i += 1
            }
            guard i < characters.count else { break }
            found.append((index, characters[i]))
            i += 1
        }
        return found
    }

    /// Arguments of the kind a format's own specifiers ask for, so the whole
    /// table can be checked without hard-coding an arity per key.
    static func plausibleArguments(for format: String) -> [PhraseArg] {
        var args: [PhraseArg] = []
        for (index, conversion) in positionalSpecifiers(in: format) {
            while args.count < index { args.append(.int(0)) }
            args[index - 1] = conversion == "@" ? .text("x") : .int(0)
        }
        return args
    }

    /// Specifiers that are not `%<n>$…`. `%%` is a literal percent and is fine.
    static func nonPositionalSpecifiers(in format: String) -> [String] {
        let characters = Array(format)
        var found: [String] = []
        var i = 0
        while i < characters.count {
            guard characters[i] == "%" else { i += 1; continue }
            guard i + 1 < characters.count else { found.append("%"); break }
            if characters[i + 1] == "%" { i += 2; continue }
            var j = i + 1
            while j < characters.count, characters[j].isNumber { j += 1 }
            if j > i + 1, j < characters.count, characters[j] == "$" {
                i = j + 1
                continue
            }
            found.append(String(characters[i ..< min(characters.count, i + 4)]))
            i += 1
        }
        return found
    }

    /// `"key": "value",` lines, in file order. Keys never contain a quote, so
    /// the first `": "` after the opening quote is always the separator.
    static func parseTableSource(_ source: String) -> [(key: String, value: String)] {
        var entries: [(key: String, value: String)] = []
        for line in source.split(separator: "\n", omittingEmptySubsequences: false) {
            let text = line.trimmingCharacters(in: .whitespaces)
            guard text.hasPrefix("\""), text.hasSuffix("\","), text.count > 5 else { continue }
            let body = String(text.dropFirst().dropLast(2))
            guard let separator = body.range(of: "\": \"") else { continue }
            entries.append((key: String(body[body.startIndex ..< separator.lowerBound]),
                            value: String(body[separator.upperBound...])))
        }
        return entries
    }

    private static func englishPhrasesSource() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // SharedTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // nine
            .appendingPathComponent("Sources/Shared/EnglishPhrases.swift")
    }
}

/// Which keys the installed book was asked for. A class, and locked, because
/// `Phrasebook.Resolve` is `@Sendable` and the compiler is right to insist.
private final class KeyLog: @unchecked Sendable {
    private let lock = NSLock()
    private var keys: [String] = []

    func record(_ key: String) {
        lock.lock()
        defer { lock.unlock() }
        keys.append(key)
    }

    func clear() {
        lock.lock()
        defer { lock.unlock() }
        keys.removeAll()
    }

    var recorded: [String] {
        lock.lock()
        defer { lock.unlock() }
        return keys
    }
}
