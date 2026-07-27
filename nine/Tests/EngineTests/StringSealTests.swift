// StringSealTests — the mechanical half of "every string goes through the catalog".
//
// The inventory that opened PRD-20 found ~397 shippable user-facing strings, of
// which ~321 were bare literals passed to a view constructor or an
// `.accessibilityLabel(_: String)`. Xcode's automatic extraction sees almost
// none of those, because they never take the `LocalizedStringKey` overload. So
// "we localized the app" is a claim that needs an instrument, and this is it.
//
// Deliberately a *source* check, like VariantChannelSealTests: it names the file
// and line, in the PR that adds it, when it is cheap to talk about. It has to
// be — `Sources/App` and `Sources/Widgets` are not SwiftPM targets, they build
// only through the generated Xcode project, so nothing that requires compiling
// them can run in the cheap lane.
//
// It is the same rule as `scripts/strings.py --audit`, ported rather than
// shelled out to, so that `swift test` alone is sufficient locally and on
// Linux. Two runners, one rule; when the rule changes, both change. The script
// is the one `--extract` will consume in Task 5.
//
// The baseline in `Tests/StringBaselines/offences.txt` is why this test is
// green today against ~135 offences: an all-or-nothing gate would sit red for
// the days Tasks 5-8 take, and a gate that is expected to be red is not a
// gate. It fails on any offence NOT already in that file, and on any baselined
// offence that has stopped firing — the second half is what turns the
// extraction into a countdown instead of a promise.
//
// Nothing here imports anything Darwin-only: EngineTests must keep running on
// Linux CI alongside the golden corpus.
import XCTest
import Foundation

final class StringSealTests: XCTestCase {

    /// View constructors whose String argument reaches a human.
    ///
    /// The second row is not used anywhere in the tree today and finds
    /// nothing. It is here anyway: this gate's whole job is stopping rot
    /// during Tasks 5-8, and a list that only covers what the app happens to
    /// call today lets the first `ContentUnavailableView("No boards yet")` of
    /// the extraction sail past both runners.
    private static let sinks = [
        "Text", "Label", "Button", "Toggle", "Picker", "Section", "TextField",
        "Link", "Menu", "NavigationLink", "Window", "CommandMenu", "GlassChip",
        "GlassIconButton",
        "Stepper", "ProgressView", "ContentUnavailableView", "LabeledContent",
        "SecureField", "TextEditor", "DatePicker", "GroupBox", "DisclosureGroup",
    ]

    /// Modifiers whose argument reaches a human — usually only a VoiceOver
    /// user, which is exactly why these were the ones nobody noticed were
    /// still English.
    private static let modifiers = [
        "navigationTitle", "accessibilityLabel", "accessibilityHint",
        "accessibilityValue", "accessibilityAction", "help",
        "configurationDisplayName", "description",
        // Same argument as the second row of `sinks`: silent today,
        // load-bearing the moment somebody adds a confirmation to
        // "Discard this board?".
        "alert", "confirmationDialog", "searchable", "accessibilityInputLabels",
        "tabItem", "navigationSubtitle", "accessibilityCustomContent", "prompt",
    ]

    private static let trees = ["Sources/App", "Sources/Widgets", "Sources/Shared"]

    /// Debug-only surfaces the player never sees. Each one is named, never
    /// pattern-matched: an exemption that can grow by accident is not an
    /// exemption, it is a hole.
    private static let exempt = [
        "Sources/App/PadProbeHUD.swift",     // --pad-probe launch arg only
    ]

    /// Argument labels that never carry prose. This list, rather than "look at
    /// the first argument only", is what keeps SF Symbol names out of the
    /// report: the first version of this rule read the first argument and so
    /// reported `GlassIconButton(symbol: "lightbulb", label: "Hint")` as the
    /// string "lightbulb" — wrong twice over, because it also missed "Hint".
    private static let nonProseLabels: Set<String> = [
        "symbol", "systemImage", "systemName", "image", "imageName", "asset",
        // SwiftUI's own "do not localize" spelling, honoured for the same
        // reason the `#"…"#` raw-literal marker is.
        "verbatim",
        "tableName", "bundle", "key", "identifier", "id",
    ]

    struct Offence: Equatable {
        let path: String
        let line: Int
        let literal: String
        /// What the baseline stores. No line number on purpose: a baseline
        /// keyed on lines turns every edit above an offence into a phantom
        /// regression, and a gate that cries wolf is a gate somebody adds
        /// `|| true` to.
        var key: String { "\(path)\t\"\(literal.replacingOccurrences(of: "\n", with: "\\n"))\"" }
    }

    // MARK: - The tests

    func testNoBareUserFacingLiteral() throws {
        let nine = Self.nineRoot()
        var current: [Offence] = []

        for tree in Self.trees {
            let root = nine.appendingPathComponent(tree)
            let files = try FileManager.default.subpathsOfDirectory(atPath: root.path)
                .filter { $0.hasSuffix(".swift") }
                .sorted()
            XCTAssertFalse(files.isEmpty, "\(tree) has no Swift files — did the tree move?")

            for file in files {
                let relative = "\(tree)/\(file)"
                if Self.exempt.contains(relative) { continue }
                let source = try String(contentsOf: root.appendingPathComponent(file),
                                        encoding: .utf8)
                current += Self.offences(in: source, path: relative)
            }
        }

        // The instrument must find something. If the extraction ever really is
        // finished this assertion is the line to delete, deliberately, in the
        // PR that empties the baseline — not the one to quietly weaken.
        XCTAssertFalse(current.isEmpty,
                       "The scanner found nothing at all in \(Self.trees.joined(separator: ", ")). "
                       + "That is not a clean tree, that is a broken detector.")

        let baseline = try Self.baseline(under: nine)
        let (new, stale) = Self.diff(current: current.map(\.key), baseline: baseline)

        let lineFor = Dictionary(current.map { ($0.key, "\($0.path):\($0.line)") },
                                 uniquingKeysWith: { first, _ in first })

        XCTAssertEqual(new, [], """
            \(new.count) NEW bare user-facing literal(s). Every string a player \
            reads goes through the catalog:
            \(new.map { "  \(lineFor[$0] ?? "?") \($0)" }.joined(separator: "\n"))
            Fix: move it into a `Phrase` block that names a `Strings.*` key, then \
            run `python3 scripts/strings.py --extract`. If it is genuinely never \
            localized — a mark, a symbol name, an identifier — write it as a raw \
            literal, `#"NINE"#`, the way `ShareCardMetrics.wordmark` does.
            """)

        XCTAssertEqual(stale, [], """
            \(stale.count) baselined offence(s) no longer fire. That is progress, \
            and the baseline has to record it — a stale baseline is a gate that \
            quietly stopped measuring, and PRD-20's whole claim is that the \
            extraction is countable:
            \(stale.map { "  \($0)" }.joined(separator: "\n"))
            Fix: `python3 scripts/strings.py --audit --write-baseline`.
            """)
    }

    /// The Engine is Linux-clean and never localizes (PRD-20).
    ///
    /// The structural enforcement is that SwiftPM does not compile
    /// `Sources/App` — but that only catches an `import SwiftUI`, not a
    /// `displayName` returning English, which is what was actually there:
    /// `Technique.displayName`, `Difficulty.title` and `VariantTier.title` each
    /// held a `switch` full of English inside the module the 56 golden-corpus
    /// hashes are made of. This catches the second kind.
    ///
    /// Comments are stripped first, and that is not a detail — all three enums
    /// now carry doc comments that *name* the deleted properties, because the
    /// most useful thing at the site of a deletion is why the thing is not
    /// there. A rule reading raw text would fail on its own explanation.
    func testEngineNamesNothing() throws {
        // Substrings, not identifiers, on purpose: `var title` catches a
        // computed property while leaving `title:` argument labels and any
        // `titleCase` helper alone, and none of the other four is a word that
        // means anything here except "human-readable words live below".
        let banned = ["displayName", "var title", "blurb", "explainer", "caption"]
        let engine = Self.nineRoot().appendingPathComponent("Sources/Engine")
        let files = try FileManager.default.subpathsOfDirectory(atPath: engine.path)
            .filter { $0.hasSuffix(".swift") }
            .sorted()
        XCTAssertFalse(files.isEmpty, "Sources/Engine has no Swift files — did the tree move?")

        var offences: [String] = []
        for file in files {
            let raw = try String(contentsOf: engine.appendingPathComponent(file), encoding: .utf8)
            let source = String(Self.stripComments(Array(raw)))
            let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
            for (offset, line) in lines.enumerated() {
                for needle in banned where line.contains(needle) {
                    offences.append("Sources/Engine/\(file):\(offset + 1) — \"\(needle)\"")
                }
            }
        }

        XCTAssertEqual(offences, [], """
            The Engine named something:
            \(offences.joined(separator: "\n"))
            `Sources/Engine` emits IDs and nothing else. It compiles on Linux, \
            where there is no bundle to look a translation up in, and its \
            `Technique`/`Difficulty` raw values are frozen inside 56 \
            golden-corpus hashes — which is what makes the raw value the \
            localization identity, and a `displayName` beside it a second, \
            unfrozen list of the same thing.
            Fix: put the English in `EnglishPhrases.table` under \
            `<enum>.<rawValue>.<role>` and read it through \
            `Strings.technique(_:)` in the App layer, or `Phrasebook.current` \
            in Shared.
            """)
    }

    /// The detector, tested against source it is handed rather than against the
    /// tree — because the tree passes, and a rule that only ever runs against
    /// passing input can rot into `return []` without anyone noticing.
    ///
    /// Every negative case here is a real false positive this rule produced at
    /// some point while it was being written.
    func testDetectorFiresOnProseAndOnlyOnProse() throws {
        let fixture = """
            struct Fixture: View {
                var body: some View {
                    Text("Discard saved game")                      // 1: plain prose
                    Text("Solved in \\(elapsed) flat")              // 2: prose around an interpolation
                    Label("Undo", systemImage: "arrow.uturn.backward")  // 3: prose, not the symbol
                    GlassIconButton(symbol: "lightbulb", label: "Hint") // 4: prose is the SECOND argument
                    Label(inline, systemImage: hot ? "flame.fill" : "flame")
                    Button(deskMode ? "Exit Desk Mode" : "Enter Desk Mode") { }  // 5, 6: both arms
                    Text(verbatim: "NINE")
                    Text(#"NINE"#)
                    Text("9")
                    Text("—")
                    Text("\\(digit). \\(rest)")
                    Toggle("Show Timer", isOn: $timer)              // 7
                    // Text("A commented-out surface")
                    /* Text("A block-commented surface") */

                    // The shape rule, exercised where it actually runs. These
                    // sat outside any sink until review caught it — as a bare
                    // `var` body and an `Image(systemName:)`, neither of which
                    // the scanner reads — so deleting both shape branches left
                    // every test green. They are arguments to real sinks now,
                    // and mutating the rule reddens this test.
                    Text("arrow.uturn.backward")
                    Text("com.couchsuite.nine.points")
                    Text("nine.history")
                    Text("AppIcon-Ember")
                    Text("pad-probe")
                    Text("UTF-8")
                    // ...and the boundary the shape rule used to overrun.
                    // Prose that ends in punctuation is prose.
                    Text("Time:")                                   // 8
                    Button("Undone.") { }                           // 9
                    // Hyphenated English. Uniformly-cased kebab is a machine
                    // name, mixed-case kebab is a phrase — the round-2 rule
                    // dropped all five of these as if they were asset sets.
                    Text("Sign-in")                                 // 10
                    Text("Auto-save")                               // 11
                    Text("Auto-Save")                               // 12
                    Text("Best-of-3")                               // 13
                }
                .accessibilityLabel("Board")                        // 10
                .accessibilityAction(named: "Show board stats") { } // 11
                .alert("Discard this board?", isPresented: $ask) { } // 12
                .searchable(text: $query, prompt: "Search boards")   // 13
            }
            """
        let found = Self.offences(in: fixture, path: "Fixture.swift").map(\.literal)

        XCTAssertEqual(Set(found), [
            "Discard saved game",
            "Solved in \\(elapsed) flat",
            "Undo",
            "Hint",
            "Exit Desk Mode",
            "Enter Desk Mode",
            "Show Timer",
            "Time:",
            "Undone.",
            "Sign-in",
            "Auto-save",
            "Auto-Save",
            "Best-of-3",
            "Board",
            "Show board stats",
            "Discard this board?",
            "Search boards",
        ], """
            The detector no longer sees what it exists to see, or has started \
            seeing machine names as prose. Found:
            \(found.map { "  \"\($0)\"" }.joined(separator: "\n"))
            """)
    }

    // MARK: - The rule (mirrors scripts/strings.py)

    static func offences(in raw: String, path: String) -> [Offence] {
        let source = stripComments(Array(raw))
        // Keyed by the literal's offset: `Section(header: Text("Recent"))`
        // matches both the `Section` rule and the `Text` rule, and that is one
        // English string, not two.
        var hits: [Int: String] = [:]

        for name in sinks {
            for open in callSites(source, name: name, isModifier: false) {
                collect(source, open: open, into: &hits)
            }
        }
        for name in modifiers {
            for open in callSites(source, name: name, isModifier: true) {
                collect(source, open: open, into: &hits)
            }
        }

        var newlines: [Int] = []      // prefix count of "\n" before each offset
        var running = 0
        for character in source {
            newlines.append(running)
            if character == "\n" { running += 1 }
        }

        return hits.keys.sorted().map {
            Offence(path: path, line: newlines[$0] + 1, literal: String(source[$0 + 1 ..< endOfLiteral(source, $0) - 1]))
        }
    }

    private static func collect(_ source: [Character], open: Int, into hits: inout [Int: String]) {
        for argument in arguments(source, openParen: open) {
            if let label = argument.label, nonProseLabels.contains(label) { continue }
            for literal in literals(source, in: argument.range) {
                if literal.isRaw { continue }        // `#"NINE"#`, the never-localize marker
                // Also per literal, so a `Text(verbatim: "NINE")` nested inside
                // a `Section(header:)` is judged by its own label, not its
                // parent's.
                if let label = precedingLabel(source, at: literal.start),
                   nonProseLabels.contains(label) { continue }
                let body = String(source[literal.start + 1 ..< literal.end - literal.hashes - 1])
                if isTranslatable(body) { hits[literal.start] = body }
            }
        }
    }

    /// Offsets of the `(` opening each call to `name`. A bare `Text(` — not
    /// `Color.Text(`, not `TextStyle(`; a modifier must be preceded by a dot.
    private static func callSites(_ source: [Character], name: String, isModifier: Bool) -> [Int] {
        let needle = Array(name)
        var found: [Int] = []
        var i = 0
        while i + needle.count < source.count {
            guard startsWith(source, i, needle) else { i += 1; continue }
            let before = i > 0 ? source[i - 1] : " "
            let boundary = isModifier
                ? before == "."
                : !(before.isLetter || before.isNumber || before == "_" || before == ".")
            var j = i + needle.count
            while j < source.count, source[j] == " " || source[j] == "\n" { j += 1 }
            if boundary, j < source.count, source[j] == "(" { found.append(j) }
            i += 1
        }
        return found
    }

    struct Argument { let label: String?; let range: Range<Int> }

    /// The top-level arguments of a call, split on top-level commas.
    ///
    /// The label has to be tracked per argument rather than per literal because
    /// of ternaries — `Label(x, systemImage: hot ? "flame.fill" : "flame")`
    /// reported the SF Symbol "flame" until this did, since the token
    /// immediately before that literal is the `:` of `?:`, not an argument's.
    static func arguments(_ source: [Character], openParen: Int) -> [Argument] {
        var out: [Argument] = []
        var depth = 0
        var start = openParen + 1
        var i = openParen

        func close(_ end: Int) {
            let range = start ..< max(start, end)
            out.append(Argument(label: argumentLabel(source, in: range), range: range))
        }

        while i < source.count {
            let ch = source[i]
            if ch == "(" || ch == "[" || ch == "{" {
                depth += 1
            } else if ch == ")" || ch == "]" || ch == "}" {
                depth -= 1
                if depth == 0 { close(i); return out }
            } else if ch == "\"" {
                i = endOfLiteral(source, i)
                continue
            } else if ch == "," && depth == 1 {
                close(i)
                start = i + 1
            }
            i += 1
        }
        close(source.count)
        return out
    }

    /// `label:` at the head of an argument, if there is one.
    private static func argumentLabel(_ source: [Character], in range: Range<Int>) -> String? {
        var i = range.lowerBound
        while i < range.upperBound, source[i].isWhitespace { i += 1 }
        var name = ""
        while i < range.upperBound, source[i].isLetter || source[i].isNumber || source[i] == "_" {
            name.append(source[i])
            i += 1
        }
        guard !name.isEmpty, let first = name.first, first.isLetter || first == "_" else { return nil }
        while i < range.upperBound, source[i] == " " { i += 1 }
        guard i < range.upperBound, source[i] == ":" else { return nil }
        guard i + 1 >= range.upperBound || source[i + 1] != ":" else { return nil }
        return name
    }

    /// The argument label immediately before a literal, if any. Looked up in
    /// the raw source rather than in the slice a particular sink matched.
    private static func precedingLabel(_ source: [Character], at offset: Int) -> String? {
        var i = offset - 1
        while i >= 0, source[i] == "#" { i -= 1 }
        while i >= 0, source[i].isWhitespace { i -= 1 }
        guard i >= 0, source[i] == ":" else { return nil }
        guard i == 0 || source[i - 1] != ":" else { return nil }
        i -= 1
        while i >= 0, source[i] == " " { i -= 1 }
        var name = ""
        while i >= 0, source[i].isLetter || source[i].isNumber || source[i] == "_" {
            name.append(source[i])
            i -= 1
        }
        guard let last = name.last, last.isLetter || last == "_" else { return nil }
        return String(name.reversed())
    }

    struct Literal { let start: Int; let end: Int; let hashes: Int; let isRaw: Bool }

    /// Every double-quoted literal inside `range`, as offsets into `source`.
    static func literals(_ source: [Character], in range: Range<Int>) -> [Literal] {
        var found: [Literal] = []
        var i = range.lowerBound
        while i < range.upperBound {
            guard source[i] == "\"" else { i += 1; continue }
            var hashes = 0
            var j = i - 1
            while j >= range.lowerBound, source[j] == "#" { hashes += 1; j -= 1 }
            let end = endOfLiteral(source, i)
            found.append(Literal(start: i, end: end, hashes: hashes, isRaw: hashes > 0))
            i = max(end, i + 1)
        }
        return found
    }

    /// The index just past the literal whose opening `"` is at `start`.
    static func endOfLiteral(_ source: [Character], _ start: Int) -> Int {
        var hashes = 0
        var j = start - 1
        while j >= 0, source[j] == "#" { hashes += 1; j -= 1 }
        let triple = Array("\"\"\"")

        func closes(at index: Int, _ marker: [Character]) -> Bool {
            guard startsWith(source, index, marker) else { return false }
            var k = index + marker.count
            var remaining = hashes
            while remaining > 0 {
                guard k < source.count, source[k] == "#" else { return false }
                k += 1
                remaining -= 1
            }
            return true
        }

        if startsWith(source, start, triple) {
            var i = start + 3
            while i < source.count {
                if source[i] == "\\" && hashes == 0 { i += 2; continue }
                if closes(at: i, triple) { return i + 3 + hashes }
                i += 1
            }
            return source.count
        }
        var i = start + 1
        while i < source.count {
            if source[i] == "\\" && hashes == 0 { i += 2; continue }
            if closes(at: i, ["\""]) { return i + 1 + hashes }
            if source[i] == "\n" { return i }     // unterminated; give up on this line
            i += 1
        }
        return source.count
    }

    /// Blank out comments and keep every offset. Offsets are how an offence
    /// gets a line number, so nothing here may change the length of the text —
    /// comment bodies become spaces, newlines survive.
    ///
    /// Swift block comments nest, which a naive scan gets wrong on exactly the
    /// kind of commented-out UI code this is aimed at.
    static func stripComments(_ source: [Character]) -> [Character] {
        var out = source
        var i = 0
        var depth = 0
        let lineComment = Array("//"), openComment = Array("/*"), closeComment = Array("*/")
        while i < source.count {
            if depth > 0 {
                if startsWith(source, i, openComment) {
                    depth += 1; out[i] = " "; out[i + 1] = " "; i += 2; continue
                }
                if startsWith(source, i, closeComment) {
                    depth -= 1; out[i] = " "; out[i + 1] = " "; i += 2; continue
                }
                if source[i] != "\n" { out[i] = " " }
                i += 1
                continue
            }
            if startsWith(source, i, lineComment) {
                while i < source.count, source[i] != "\n" { out[i] = " "; i += 1 }
                continue
            }
            if startsWith(source, i, openComment) {
                depth = 1; out[i] = " "; out[i + 1] = " "; i += 2; continue
            }
            if source[i] == "\"" {
                // Skip the literal wholesale so a `//` inside a string cannot
                // open a comment.
                i = endOfLiteral(source, i)
                continue
            }
            i += 1
        }
        return out
    }

    /// Does this literal carry words a translator would have to touch?
    ///
    /// Precision matters here, but not much more than recall: the fix for a
    /// false positive is cheap (move it into a `Phrase` block, or mark it
    /// `#"…"#`), while a false negative ships English to a Japanese player. So
    /// the bar is low — two letters of prose — and the exclusions are
    /// shape-based and few.
    static func isTranslatable(_ body: String) -> Bool {
        let prose = stripInterpolations(body)
            .replacingOccurrences(of: "\\n", with: " ")
            .replacingOccurrences(of: "\\t", with: " ")
        let letters = prose.filter(\.isLetter).count
        // "9", "—", "%d" — glyphs and separators. Also what is left of
        // `"\(a). \(b)"` once the interpolations go, which is right: the
        // translatable parts of that line live in whatever `a` and `b` are.
        guard letters >= 2 else { return false }

        let trimmed = prose.trimmingCharacters(in: .whitespaces)
        let identifierish = !trimmed.isEmpty && trimmed.allSatisfy {
            $0.isLetter || $0.isNumber || "_.:/-+%".contains($0)
        }
        // Has a space, or punctuation prose alone has.
        guard identifierish else { return true }

        // Sentence punctuation is the one thing an identifier never ends in,
        // and the shape rule below used to swallow anything carrying a dot or
        // a colon — so `Text("Time:")` in the stats drawer and
        // `Button("Undone.")` in the undo toast were silently dropped as if
        // they were SF Symbols. Prose that stops wins over shape every time.
        if let last = trimmed.last, ".:!?".contains(last) { return true }

        // SF Symbol, bundle id, key path, URL — no spaces, and punctuation
        // where prose would have none.
        if trimmed.contains(where: { "._:/".contains($0) }) { return false }

        // Kebab. This branch has now been wrong twice, in opposite directions,
        // and each time only a probe caught it — so the reasoning is written
        // out.
        //
        // Round 1 required all-lowercase, which let `AppIcon-Ember` through as
        // prose: the exact asset name PRD-20 says must never fire. Round 2
        // dropped case entirely, which swallowed `Sign-in`, `Auto-save` and
        // `Best-of-3`.
        //
        // What separates the two sets is not *whether* segments are
        // capitalised but *how*. Every hyphenated machine name in this repo is
        // either uniformly lowercase or contains a CamelCase segment:
        //
        //   AppIcon-Ember  AppIcon-Mono  AppIcon-Tide  UTF-8   <- CamelCase
        //   pad-probe  cloud-sync  widget-bridge  d-pad        <- all lower
        //
        // while hyphenated English never has an uppercase letter *inside* a
        // word and is not uniformly lowercase, because at least one segment
        // starts a phrase:
        //
        //   Sign-in  Re-solve  Auto-save  Multi-line  Best-of-3  Auto-Save
        //
        // "All segments share a case class" was the first thing tried and is
        // not enough: it drops `Auto-Save` and `Well-Being`, and Title Case is
        // exactly what the Mac menu bar uses ("New Game", "Float Desk on
        // Top"), so that is a shape this app will really produce.
        //
        // Residual false negative, and it is a real string in this tree rather
        // than a hypothetical: `TutorialGrammar.pencilVerb` is `"hold-click"`
        // on one platform and `"Shift-type"` on another. `Shift-type` flags,
        // `hold-click` does not — nothing distinguishes it from `pad-probe`.
        // Neither reaches the rule today (they are struct fields, not sink
        // arguments), but whoever does Tasks 5-8 should extract that pair by
        // hand.
        let segments = trimmed.split(separator: "-", omittingEmptySubsequences: false)
        let alphanumericSegments = segments.count >= 2 && segments.allSatisfy { segment in
            !segment.isEmpty && segment.allSatisfy { $0.isLetter || $0.isNumber }
        }
        if alphanumericSegments {
            let uniformlyLower = segments.allSatisfy { !$0.contains(where: \.isUppercase) }
            let hasCamelSegment = segments.contains { $0.dropFirst().contains(where: \.isUppercase) }
            if uniformlyLower || hasCamelSegment { return false }
        }
        return true
    }

    /// Drop `\(…)` segments, counting paren depth so nesting is unbounded.
    ///
    /// Depth, not a regex. The Python side started as a regex that nested
    /// exactly one level, left half of
    /// `"\(a) · \(Self.format(entry.game.timer.elapsed(at: Date())))"` behind
    /// as "prose", and disagreed with this function by one line of
    /// BoardsSheet. That disagreement is the argument for keeping both runners.
    private static func stripInterpolations(_ body: String) -> String {
        let chars = Array(body)
        var out = ""
        var i = 0
        while i < chars.count {
            if chars[i] == "\\", i + 1 < chars.count, chars[i + 1] == "(" {
                var depth = 0
                var j = i + 1
                while j < chars.count {
                    if chars[j] == "(" { depth += 1 }
                    if chars[j] == ")" { depth -= 1; if depth == 0 { break } }
                    j += 1
                }
                i = j + 1
                continue
            }
            out.append(chars[i])
            i += 1
        }
        return out
    }

    private static func startsWith(_ source: [Character], _ index: Int, _ needle: [Character]) -> Bool {
        guard index + needle.count <= source.count else { return false }
        for (offset, character) in needle.enumerated() where source[index + offset] != character {
            return false
        }
        return true
    }

    // MARK: - The baseline

    private static func nineRoot() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // EngineTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // nine
    }

    private static func baseline(under nine: URL) throws -> [String] {
        let path = nine.appendingPathComponent("Tests/StringBaselines/offences.txt")
        let text = try String(contentsOf: path, encoding: .utf8)
        return text.split(separator: "\n", omittingEmptySubsequences: false)
            .map(String.init)
            .filter { !$0.isEmpty && !$0.hasPrefix("#") }
    }

    /// Multiset difference, so a literal that appears twice in a file and is
    /// fixed once still registers as progress.
    static func diff(current: [String], baseline: [String]) -> (new: [String], stale: [String]) {
        var remaining: [String: Int] = [:]
        for key in baseline { remaining[key, default: 0] += 1 }
        var new: [String] = []
        for key in current {
            if let count = remaining[key], count > 0 {
                remaining[key] = count - 1
            } else {
                new.append(key)
            }
        }
        let stale = remaining.flatMap { key, count in Array(repeating: key, count: count) }
        return (new.sorted(), stale.sorted())
    }
}
