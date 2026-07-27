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
        XCTAssertEqual(Phrasebook.english.string("board.announce.placed", .text("Four")),
                       "Four placed.")
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

        // Text arguments reorder too, and a position may be used twice —
        // `coach.boxLine.body` names its target unit twice in English already.
        let repeated = Phrasebook { _, args in Phrasebook.format("%2$@ %1$@ %2$@", args) }
        XCTAssertEqual(repeated.string("k", .text("a"), .text("b")), "b a b")

        XCTAssertEqual(
            Phrasebook.english.string("coach.boxLine.body", .text("seven"), .text("Box 1"), .text("Row 1")),
            "Every seven still possible in Box 1 sits in Row 1, "
                + "so no other square in Row 1 can be a seven."
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
