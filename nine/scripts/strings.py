"""Nine's string instrument — the audit, and (later) the extraction.

PRD-20 localizes Nine into nine languages. The inventory that opened it counted
~397 shippable user-facing strings, of which ~321 were *bare* `String` literals
handed to a view constructor or an `.accessibilityLabel(_: String)`. Xcode's
automatic extraction sees almost none of those: it only harvests the
`LocalizedStringKey` overloads, and a `String` argument silently takes the other
one. So "we localized the app" was, before this file, a claim with no
instrument behind it — the catalog could be 100% translated and the app still
ship in English.

This is that instrument. `--audit` is the whole rule:

  1. a source grep for bare literals reaching a human (the same rule
     `Tests/EngineTests/StringSealTests.swift` runs in-process, so `swift test`
     alone is enough locally), and
  2. the checks that need the catalog and therefore cannot live in a grep —
     keys used in Swift but missing from the catalog, keys in the catalog that
     no Swift file names, and whether `xcstringstool` will compile it at all.

Group (2) degrades to a printed note while `Sources/Strings/Localizable.xcstrings`
does not exist. Task 1 builds the instrument; Task 4 builds the catalog. An
audit that crashed on the missing file would make Task 1 unmergeable on its own,
which is the wrong shape for the first task in a program.

Why a source-text check and not a compiler plugin: `Sources/App` and
`Sources/Widgets` are not SwiftPM targets — they build only through the
generated Xcode project — so nothing that requires compiling them can run in the
cheap lane. Text is what CI can afford on every PR.

Usage:

    python3 scripts/strings.py --audit             # exit 1 on regression
    python3 scripts/strings.py --audit --verbose   # list every offence
    python3 scripts/strings.py --audit --write-baseline
    python3 scripts/strings.py --build-catalog     # regenerate the catalog's `en`
    python3 scripts/strings.py --extract           # Task 5+
    python3 scripts/strings.py --pseudo            # not implemented, and not planned
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile

REPO_NINE = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

# The trees a player can see. `Sources/Engine` is absent on purpose: the engine
# never localizes (it must stay Linux-clean and its `Technique`/`Difficulty` raw
# values are frozen inside 56 golden-corpus hashes), and `Sources/Shared`
# is here because it compiles into the widget extension.
TREES = ["Sources/App", "Sources/Widgets", "Sources/Shared", "Sources/Watch"]

# Debug-only surfaces the player never sees. Each one is named, never
# pattern-matched: an exemption that can grow by accident is not an exemption,
# it is a hole.
EXEMPT = [
    "Sources/App/PadProbeHUD.swift",     # --pad-probe launch arg only
]

# View constructors whose `String` arguments reach a human.
#
# The second row is not used anywhere in the tree today and finds nothing. It
# is here anyway: this gate's whole job is stopping rot during Tasks 5-8, and a
# list that only covers what the app happens to call today lets the first
# `ContentUnavailableView("No boards yet")` of the extraction sail past both
# runners. Cheap to add now, invisible to add later.
SINKS = [
    "Text", "Label", "Button", "Toggle", "Picker", "Section", "TextField",
    "Link", "Menu", "NavigationLink", "Window", "CommandMenu", "GlassChip",
    "GlassIconButton",
    "Stepper", "ProgressView", "ContentUnavailableView", "LabeledContent",
    "SecureField", "TextEditor", "DatePicker", "GroupBox", "DisclosureGroup",
]

# Modifiers whose arguments reach a human — usually only a VoiceOver user,
# which is exactly why they were the ones nobody noticed were English.
MODIFIERS = [
    "navigationTitle", "accessibilityLabel", "accessibilityHint",
    "accessibilityValue", "accessibilityAction", "help",
    "configurationDisplayName", "description",
    # Same argument as the second row of SINKS: silent today, load-bearing the
    # moment somebody adds a confirmation to "Discard this board?".
    "alert", "confirmationDialog", "searchable", "accessibilityInputLabels",
    "tabItem", "navigationSubtitle", "accessibilityCustomContent", "prompt",
]

# Argument labels that never carry prose. This list, not "the first argument
# only", is what keeps SF Symbol names out of the report: the first version of
# this scanner read only the first argument and so reported
# `GlassIconButton(symbol: "lightbulb", label: "Hint")` as the string
# "lightbulb" — wrong twice over, because it also missed "Hint".
NON_PROSE_LABELS = {
    "symbol", "systemImage", "systemName", "image", "imageName", "asset",
    # SwiftUI's own "do not localize" spelling, honoured for the same reason
    # the `#"…"#` raw-literal marker is.
    "verbatim",
    "tableName", "bundle", "key", "identifier", "id",
}

BASELINE = os.path.join(REPO_NINE, "Tests", "StringBaselines", "offences.txt")
CATALOG = os.path.join(REPO_NINE, "Sources", "Strings", "Localizable.xcstrings")

# The catalog and its accessor. Not in `TREES` — the offence scanner must not
# walk it, because it is the one tree whose job is to hold string keys — but
# `swift_referenced_keys` must, because `Strings.swift` names keys.
STRINGS_TREE = "Sources/Strings"
ENGLISH_PHRASES = os.path.join(REPO_NINE, "Sources", "Shared", "EnglishPhrases.swift")

# There is deliberately no locale list in this file.
#
# There was one — `LOCALES`, ten entries, "in the order `project.yml` declares
# them" — and it was referenced by nothing, derived from nothing, and its
# comment named `CatalogTests.testDeclaredLocalizationsAreExactlyTheNine\
# LaunchLocales` as the thing keeping it equal to `project.yml`. That test has
# never existed. So a hand-maintained copy of the launch locales sat here
# claiming to be verified — which is the exact failure this PRD spent eight
# tasks removing from everywhere else.
#
# The locale set has one source of truth: the locales that carry translations
# in the catalog. `project.yml` declares the same set twice (the app's
# Info.plist and the widget extension's, which is a separate bundle), and
# `CatalogTests.testDeclaredLocalizationsMatchTranslatedLocales` fails the
# moment any of the three disagree, in either direction. If this script ever
# needs the list, read it off the catalog. Do not retype it.

# `"key": "value",` — the one shape `EnglishPhrases.table` is allowed to take.
# `PhrasebookTests.testTableIsOneSortedEntryPerLineSoAScriptCanReadIt` is the
# other half of this contract: it re-parses the same file from Swift and checks
# the parse against the compiled dictionary, so this reader cannot drift from
# what the app actually says.
TABLE_ENTRY_RE = re.compile(r'^\s*"([^"]+)"\s*:\s*"(.*)",\s*$')

# `"key": EnglishPlural(count: 1, one: "…"),` — `EnglishPhrases.plurals`, whose
# rows name only the CLDR `one` category. `other` is the row in `table`, so
# there is still exactly one line per key per category and the sorted-table rule
# above keeps meaning what it means.
PLURAL_ENTRY_RE = re.compile(
    r'^\s*"([^"]+)"\s*:\s*EnglishPlural\(count:\s*(\d+),\s*one:\s*"(.*)"\),\s*$')

# `EnglishSubstitution(name: "themes", count: 1, one: "…", other: "…"),` — one
# axis of `EnglishPhrases.substitutions`. The key it belongs to is the
# `"key": [` line above it, which is why this is parsed with a tiny state
# machine rather than a single regex.
SUBSTITUTION_OWNER_RE = re.compile(r'^\s*"([^"]+)"\s*:\s*\[\s*$')
SUBSTITUTION_ENTRY_RE = re.compile(
    r'^\s*EnglishSubstitution\(name:\s*"([^"]+)",\s*count:\s*(\d+),'
    r'\s*one:\s*"(.*)",\s*other:\s*"(.*)"\),\s*$')

# The `%N$lld` a substitution axis replaces in the frame, and the `%arg` token
# the catalog uses for it inside a substitution's own value.
ARG_SPECIFIER = "%%%d$lld"
SUBSTITUTION_ARG = "%arg"

# Which positional arguments a format names as integers. Used to refuse a
# whole-string plural on a string with more than one number in it — see
# `english_localization` for the measurement that makes that a hard failure.
INTEGER_SPECIFIER_RE = re.compile(r"%(\d+)\$[-+ #.0-9]*(?:ll|l|h|q|j|z|t)?[diu]")

# A key handed to the Phrasebook as a literal: `Phrasebook.current.string("…")`,
# `Strings.string("…")`. Shared cannot name `Strings`, so this — not a
# `Strings.foo.bar` path — is how most of Nine's keys are actually written.
#
# `.resource(…)` is the same key through `Strings.resource(_:)`, which returns a
# `LocalizedStringResource` instead of a `String`. Only the widget gallery uses
# it (`.configurationDisplayName`, `.description`), and it was added to this
# rule the moment those six keys landed: without it they read as dead, because
# `CATALOG_KEY_RE` excludes a single segment followed by `(` on purpose.
PHRASEBOOK_KEY_RE = re.compile(r'\.(?:string|resource)\(\s*"([^"\\\n]+)"')

# The same call with a ternary inside it: `.string(isOn ? "x.on" : "x.off")`.
#
# The rule above is anchored on the open paren, so a *condition* standing in
# front of the literal hides the whole ternary from it — both arms, not just the
# second. That is not hypothetical: it is the only shape in this repo that
# reader (4) of `swift_referenced_keys` was covering up, and it is thirteen keys
# across six call sites (`prefs.toggle.on`, `game.drawer.hide`/`.show`,
# `history.gameCenter.in`/`.out`, `menu.view.enterDesk`/`.exitDesk`,
# `prefs.controls.bottom`/`.top`, `prefs.timer.hidden`/`.shown`,
# `shelf.variants.answer`/`.subtitle`). Twelve of the thirteen are a pair whose
# BOTH halves were invisible; `prefs.toggle.off` survived only because
# `AppModel` happens to name it a second time on its own.
#
# The condition may not contain a paren or a quote, which is what keeps this
# from running away across a nested call; every one of Nine's six sites is a
# plain property or comparison, and a condition that grows a call gets caught as
# a dead key rather than silently mis-parsed.
PHRASEBOOK_TERNARY_KEY_RE = re.compile(
    r'\.(?:string|resource)\(\s*[^()"]*?\?\s*"([^"\\\n]+)"\s*:\s*"([^"\\\n]+)"')

# `case a` / `case a, b, c` on its own line. A `switch`'s `case .foo:` cannot
# match: leading dot, trailing colon.
ENUM_CASE_RE = re.compile(r"^\s*case\s+([A-Za-z_][A-Za-z0-9_]*"
                          r"(?:\s*,\s*[A-Za-z_][A-Za-z0-9_]*)*)\s*$")

# Key families built by interpolation rather than written out — one key per enum
# case, invisible to any grep. (enum name, file that declares it, key pattern).
INTERPOLATED_FAMILIES = [
    ("Technique", "Sources/Engine/LogicSolver.swift", "technique.%s.name"),
    ("Difficulty", "Sources/Engine/Generator.swift", "difficulty.%s.title"),
    ("NineTip", "Sources/Shared/TipCoach.swift", "tip.%s"),
    # PRD-24. `Channel` carries two suffixes rather than one, so it is listed
    # twice — the shelf page needs a name and a one-line blurb, and both are
    # reached only by interpolation off the frozen raw value.
    ("Channel", "Sources/Engine/ChannelLedger.swift", "channel.%s.title"),
    ("Channel", "Sources/Engine/ChannelLedger.swift", "channel.%s.blurb"),
    ("VariantTier", "Sources/Engine/VariantConstraint.swift", "variantTier.%s.title"),
]

# Key families built as `scope + ".field"` — a *prefix* held as data, crossed
# with a fixed set of suffixes. 86 of Nine's 394 keys are one of these two, and
# no grep sees any of them: the whole key exists only at runtime, and neither
# half is a key on its own.
#
# (name, file that declares it, key prefix). BOTH halves are read out of that
# file rather than listed here — the scopes are its literals beginning with the
# prefix, the suffixes are its `+ ".field"` concatenations — so adding a fifth
# `TutorialGrammar` platform or a tenth `legend.pad` row makes its keys used,
# and *forgetting the catalog row* shows up as `missing` instead of sailing
# through. A hand-kept list of 86 keys here would be a second copy of the app,
# which is the failure this whole file exists to stop.
SCOPE_SUFFIX_FAMILIES = [
    ("TutorialGrammar", "Sources/App/TutorialGrammar.swift", "grammar."),
    ("NineLegend", "Sources/App/HomeView.swift", "legend."),
]

# `scope + ".placeVerb"` — the concatenation half of the rule above.
SCOPE_SUFFIX_RE = re.compile(r'\+\s*"\.([A-Za-z_][A-Za-z0-9_]*)"')

# Keys held in a `[String]` and reached by index — the one shape that is a
# perfectly good way to write the code and hopeless to grep for.
#
# **Named, one array at a time, never pattern-matched.** `EXEMPT` above makes
# the same argument: `board.digitWord.*` as a wildcard would be an exemption
# that grows by accident. These two arrays are read out of the source, so an
# entry that leaves the array stops being a used key immediately.
#
# (declaring type, file, array name).
KEY_ARRAYS = [
    ("BoardSpeech.Phrase", "Sources/Shared/BoardSpeech.swift", "digitWordKeys"),
    ("BoardSpeech.Phrase", "Sources/Shared/BoardSpeech.swift", "digitPluralKeys"),
]

BASELINE_HEADER = """\
# Nine — bare user-facing literals. The countdown, at zero.
#
# This file was a COUNTDOWN, never a permit: each line was one string that still
# reached a player without passing through the catalog. `StringSealTests` fails
# on any offence NOT in this list, so the rot could not grow while Tasks 5-6
# extracted. Task 6 took the last fourteen — all of them in `Sources/Widgets` —
# and the list below is now empty.
#
# **Empty, and still here.** Deleting it does not mean "no offences are
# allowed"; it means `read_baseline` returns None, which `--audit` reports as
# "not calibrated" and exits 1 on, forever. An empty list is the strict state:
# every offence is a new offence. The file earns its place by being the thing
# that says so.
#
# It is also an error for a line here to no longer be an offence: a stale
# baseline is a gate that quietly stopped measuring. Regenerate with
#
#     python3 scripts/strings.py --audit --write-baseline
#
# Format: <path><TAB>"<literal>". Line numbers are deliberately absent — they
# would make every unrelated edit above an offence look like a new one.
"""


# ------------------------------------------------------------------ scanning


def strip_comments(source):
    """Blank out comments and keep every byte offset. Offsets are how an
    offence gets a line number, so nothing here may change the length of the
    text — comment bodies become spaces, newlines survive.

    Swift block comments nest (`/* /* */ */` is one comment), which a naive
    non-greedy `.*?` gets wrong on exactly the kind of commented-out UI code
    this scanner is aimed at.
    """
    out = list(source)
    i, n = 0, len(source)
    depth = 0
    while i < n:
        ch = source[i]
        if depth:
            if source.startswith("/*", i):
                depth += 1
                out[i] = out[i + 1] = " "
                i += 2
                continue
            if source.startswith("*/", i):
                depth -= 1
                out[i] = out[i + 1] = " "
                i += 2
                continue
            if ch != "\n":
                out[i] = " "
            i += 1
            continue
        if source.startswith("//", i):
            while i < n and source[i] != "\n":
                out[i] = " "
                i += 1
            continue
        if source.startswith("/*", i):
            depth = 1
            out[i] = out[i + 1] = " "
            i += 2
            continue
        if ch == '"':
            # Skip the literal wholesale so a `//` or `/*` inside a string
            # cannot open a comment. Raw and multi-line forms included.
            i = end_of_literal(source, i)
            continue
        i += 1
    return "".join(out)


def end_of_literal(source, start):
    """Index just past the literal beginning at `start` (which must be a `"`,
    optionally preceded by `#` marks the caller has already stepped over)."""
    hashes = 0
    j = start - 1
    while j >= 0 and source[j] == "#":
        hashes += 1
        j -= 1
    pad = "#" * hashes
    if source.startswith('"""', start):
        close = '"""' + pad
        i = start + 3
        while i < len(source):
            if source[i] == "\\" and not hashes:
                i += 2
                continue
            if source.startswith(close, i):
                return i + len(close)
            i += 1
        return len(source)
    i = start + 1
    while i < len(source):
        if source[i] == "\\" and not hashes:
            i += 2
            continue
        if source[i] == '"' and source.startswith(pad, i + 1):
            return i + 1 + hashes
        if source[i] == "\n":       # unterminated; give up on this line
            return i
        i += 1
    return len(source)


ARG_LABEL_RE = re.compile(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*:(?!:)")


def arguments(source, open_paren):
    """The top-level arguments of the call whose `(` is at `open_paren`, as
    (label, text, offset). Balanced over parens, brackets, braces and string
    literals; split on top-level commas.

    Every argument, not just the first: `GlassIconButton(symbol:label:)` puts
    the prose second. Which arguments are prose is decided by
    `NON_PROSE_LABELS`, not by position.

    The label has to be tracked per argument rather than per literal because of
    ternaries — `Label(x, systemImage: streak > 0 ? "flame.fill" : "flame")`
    reported the SF Symbol "flame" until this did, since the token immediately
    before that literal is a `:` belonging to `?:`, not to an argument.
    """
    depth = 0
    i = open_paren
    n = len(source)
    start = open_paren + 1
    out = []

    def close(end):
        text = source[start:end]
        label = ARG_LABEL_RE.match(text)
        out.append((label.group(1) if label else None, text, start))

    while i < n:
        ch = source[i]
        if ch in "([{":
            depth += 1
        elif ch in ")]}":
            depth -= 1
            if depth == 0:
                close(i)
                return out
        elif ch == '"':
            i = end_of_literal(source, i)
            continue
        elif ch == "," and depth == 1:
            close(i)
            start = i + 1
        i += 1
    close(n)
    return out


LABEL_RE = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*:\s*#*$")


def preceding_label(source, offset):
    """The argument label immediately before the literal at `offset`, or None.

    Checked against the raw source rather than against the slice a particular
    sink matched, so a nested `Text(verbatim: "NINE")` inside a `Section(…)`
    is judged by its own label and not by its parent's. Doing this at the
    literal, once, is also what makes deduplicating by offset correct.
    """
    window = source[max(0, offset - 80):offset]
    match = LABEL_RE.search(window)
    return match.group(1) if match else None


LITERAL_RE = re.compile(r'(#*)"')

# A string that is plainly a machine name, not prose. SF Symbols
# ("arrow.uturn.backward"), asset-catalog sets ("AppIcon-Ember"), Game Center
# and CloudKit ids ("com.couchsuite.nine.points"), `CouchStored` keys
# ("nine.history"), URLs, `#file` paths. All of them share a shape: no spaces,
# and punctuation where prose would have none.
IDENTIFIERISH = re.compile(r"^[A-Za-z0-9_.:/\-+%]+$")


def literals_in(text, base_offset):
    """Every double-quoted literal in `text`, as (offset, body, is_raw).

    Raw literals (`#"NINE"#`) are reported with `is_raw` set: PRD-20 uses the
    raw form as the never-localize marker (see `ShareCardMetrics.wordmark`),
    so the caller drops them. A marker you have to type is a marker somebody
    had to mean.
    """
    found = []
    i = 0
    while i < len(text):
        m = LITERAL_RE.search(text, i)
        if not m:
            break
        quote = m.end() - 1
        end = end_of_literal(text, quote)
        hashes = len(m.group(1))
        body = text[quote + 1:end - hashes - 1]
        if text.startswith('"""', quote):
            body = text[quote + 3:max(quote + 3, end - hashes - 3)]
        found.append((base_offset + quote, body, hashes > 0))
        i = max(end, quote + 1)
    return found


def strip_interpolations(body):
    """Drop `\\(…)` segments to any depth.

    This was a regex, `\\\\\\((?:[^()]|\\([^()]*\\))*\\)`, which nests exactly one
    level and therefore left half of
    `"\\(a) · \\(Self.format(entry.game.timer.elapsed(at: Date())))"` behind as
    "prose". The Swift port counted depth properly, the two runners disagreed on
    one line of BoardsSheet, and that disagreement is how this was found — which
    is the argument for keeping both runners.
    """
    out = []
    i = 0
    while i < len(body):
        if body[i] == "\\" and i + 1 < len(body) and body[i + 1] == "(":
            depth = 0
            j = i + 1
            while j < len(body):
                if body[j] == "(":
                    depth += 1
                elif body[j] == ")":
                    depth -= 1
                    if depth == 0:
                        break
                j += 1
            i = j + 1
            continue
        out.append(body[i])
        i += 1
    return "".join(out)


def is_translatable(body):
    """Does this literal carry words a translator would have to touch?

    Precision matters here, but not much more than recall: the fix for a
    false positive is cheap (move it into a `Phrase` block), while a false
    negative ships English to a Japanese player. So the bar is low — two
    letters of prose — and the exclusions are shape-based and few.
    """
    prose = strip_interpolations(body)
    prose = prose.replace("\\n", " ").replace("\\t", " ")
    letters = sum(1 for c in prose if c.isalpha())
    if letters < 2:
        # "9", "—", ". ", "%d" — glyphs and separators. Also what is left of
        # `"\(a). \(b)"` once the interpolations go, which is right: the
        # translatable parts of that line live in whatever `a` and `b` are.
        return False
    trimmed = prose.strip()
    if not IDENTIFIERISH.match(trimmed):
        return True           # has a space, or punctuation prose alone has

    # Sentence punctuation is the one thing an identifier never ends in, and
    # the shape rule below used to swallow anything carrying a dot or a colon
    # — so `Text("Time:")` in the stats drawer and `Button("Undone.")` in the
    # undo toast were silently dropped as if they were SF Symbols. Prose that
    # stops wins over shape every time.
    if trimmed[-1] in ".:!?":
        return True

    if re.search(r"[._:/]", trimmed):
        return False          # SF Symbol, bundle id, key path, URL

    # Kebab. This branch has now been wrong twice, in opposite directions, and
    # each time only a probe caught it — so the reasoning is written out.
    #
    # Round 1 required `.islower()`, which let `AppIcon-Ember` through as prose:
    # the exact asset name PRD-20 says must never fire. Round 2 dropped case
    # entirely, which swallowed `Sign-in`, `Auto-save` and `Best-of-3`.
    #
    # What actually separates the two sets is not *whether* segments are
    # capitalised but *how*. Every hyphenated machine name in this repo is
    # either uniformly lowercase or contains a CamelCase segment:
    #
    #   AppIcon-Ember  AppIcon-Mono  AppIcon-Tide               <- CamelCase segment
    #   pad-probe  cloud-sync  widget-bridge  d-pad  hold-click <- all lowercase
    #
    # while hyphenated English is not uniformly lowercase, because at least one
    # segment starts a phrase:
    #
    #   Sign-in  Re-solve  Auto-save  Multi-line  Best-of-3  Auto-Save  X-Ray
    #
    # "All segments share a case class" was the first thing tried and is not
    # enough: it drops `Auto-Save` and `Well-Being`, and Title Case is exactly
    # what the Mac menu bar uses ("New Game", "Float Desk on Top"), so that is a
    # shape this app will really produce.
    #
    # **CamelCase means a lowercase letter followed by an uppercase one**, and
    # not merely an uppercase letter somewhere after the first character. This
    # comment used to claim that "hyphenated English never has an uppercase
    # letter inside a word", which is false and was silently dropping six real
    # forms: `Face-ID`, `non-ASCII`, `PDF-only`, `AI-powered`, `TV-connected`
    # and `iOS-only` all took the machine-name exit and never reached a catalog
    # key. An all-caps acronym is not CamelCase, and the `s[1:]` test could not
    # tell the difference.
    #
    # The cost is `UTF-8`, which is now prose. That is the right direction to
    # be wrong in: a false positive is a literal somebody has to exempt, and a
    # false negative is English shipped to nine locales behind a green gate.
    #
    # Two residual false negatives, both real strings in this tree rather than
    # hypotheticals, and both pinned as fixtures so they are a test rather than
    # a sentence:
    #
    #   `iOS-only` — `i`→`O` is a genuine CamelCase boundary, indistinguishable
    #   by shape from `AppIcon`. Nothing short of a word list separates them.
    #
    #   `hold-click` — `TutorialGrammar.pencilVerb` is `"hold-click"` on one
    #   platform and `"Shift-type"` on another. `Shift-type` flags, `hold-click`
    #   does not; nothing distinguishes it from `pad-probe`. Neither reaches the
    #   rule today (they are struct fields, not sink arguments).
    segments = trimmed.split("-")
    if len(segments) >= 2 and all(s.isalnum() for s in segments):
        uniformly_lower = all(not any(c.isupper() for c in s) for s in segments)
        has_camel_segment = any(
            any(s[i].isupper() and s[i - 1].islower() for i in range(1, len(s)))
            for s in segments)
        if uniformly_lower or has_camel_segment:
            return False
    return True


def scan_file(path, relative):
    """Offences in one file, as (relative, line, literal)."""
    with open(path, "r", encoding="utf-8") as handle:
        raw = handle.read()
    source = strip_comments(raw)
    # Keyed by the literal's byte offset: `Section(header: Text("Recent"))`
    # matches both the `Section` rule and the `Text` rule, and that is one
    # English string, not two.
    offences = {}

    # A bare `Sink(` — not `foo.Sink(`, not `SinkStyle(`. The negative
    # lookbehind on `.` matters: `Color.Text(` is not SwiftUI's `Text`.
    calls = [(r"(?<![\w.])" + name + r"\s*\(") for name in SINKS]
    calls += [(r"\." + name + r"\s*\(") for name in MODIFIERS]

    for pattern in calls:
        for m in re.finditer(pattern, source):
            for label, text, offset in arguments(source, m.end() - 1):
                if label in NON_PROSE_LABELS:
                    continue
                for at, body, is_raw in literals_in(text, offset):
                    if is_raw:
                        continue    # `#"NINE"#` — the never-localize marker
                    # Also per literal, so a `Text(verbatim: "NINE")` nested
                    # inside a `Section(header:)` is judged by its own label
                    # rather than by its parent's.
                    if preceding_label(source, at) in NON_PROSE_LABELS:
                        continue
                    if is_translatable(body):
                        offences[at] = body

    return [(relative, source.count("\n", 0, at) + 1, body)
            for at, body in sorted(offences.items())]


def scan_tree(nine=REPO_NINE):
    """Every offence under `TREES`, sorted by file then line."""
    offences = []
    for tree in TREES:
        root = os.path.join(nine, tree)
        if not os.path.isdir(root):
            sys.exit("missing source tree %s — did it move?" % tree)
        for dirpath, _dirs, files in os.walk(root):
            for name in sorted(files):
                if not name.endswith(".swift"):
                    continue
                path = os.path.join(dirpath, name)
                relative = os.path.relpath(path, nine)
                if relative in EXEMPT:
                    continue
                offences.extend(scan_file(path, relative))
    offences.sort(key=lambda o: (o[0], o[1], o[2]))
    return offences


# ------------------------------------------------------------------ baseline


def baseline_key(offence):
    """`path\\t"literal"` — the form the baseline stores.

    No line number on purpose. A baseline keyed on lines turns every edit
    above an offence into a phantom regression, and a gate that cries wolf is
    a gate somebody adds `|| true` to.
    """
    relative, _line, body = offence
    return "%s\t\"%s\"" % (relative, body.replace("\n", "\\n"))


def read_baseline(path=BASELINE):
    if not os.path.exists(path):
        return None
    with open(path, "r", encoding="utf-8") as handle:
        return [line.rstrip("\n") for line in handle
                if line.strip() and not line.startswith("#")]


def write_baseline(offences, path=BASELINE):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    lines = sorted(baseline_key(o) for o in offences)
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(BASELINE_HEADER)
        handle.write("\n")
        handle.write("\n".join(lines))
        handle.write("\n")
    return len(lines)


def multiset_diff(current, baseline):
    """`(new, stale)` as multisets, so a literal that appears twice and is
    fixed once still registers."""
    remaining = list(baseline)
    new = []
    for key in current:
        if key in remaining:
            remaining.remove(key)
        else:
            new.append(key)
    return new, remaining


# ------------------------------------------------------------------- catalog


def xcstringstool():
    """`xcrun --find` first; the absolute path is the fallback because on this
    machine (and on a runner where `xcode-select` points at CLT rather than a
    full Xcode) the tool is present but not on PATH."""
    try:
        found = subprocess.run(["xcrun", "--find", "xcstringstool"],
                               capture_output=True, text=True, check=False)
        if found.returncode == 0 and found.stdout.strip():
            return found.stdout.strip()
    except OSError:
        pass
    fallback = "/Applications/Xcode.app/Contents/Developer/usr/bin/xcstringstool"
    return fallback if os.path.exists(fallback) else None


# `Strings.board.cell.label` — the App-layer accessor path Task 5 generates.
#
# At least two segments, and not followed by a `(`. Both clauses are load-bearing
# and neither was, until the catalog existed to run this against: the first
# version matched one segment and no call, so `Strings.difficulty(difficulty)`
# and `Strings.install()` were reported as the catalog keys "difficulty" and
# "install", missing from it. Every key is `<surface>.<group>.<role>` or at
# least `<surface>.<role>`, so one segment is never a key — it is a function.
CATALOG_KEY_RE = re.compile(r"Strings\.([a-z][A-Za-z0-9_]*"
                            r"(?:\.[A-Za-z_][A-Za-z0-9_]*)+)(?!\s*\()")


def catalog_keys(tool, catalog=CATALOG):
    """The catalog's keys, via `xcstringstool print` — it lists them with no
    build and no simulator, which is the entire reason these checks can live in
    the cheap lane.

    One bare key per line, unquoted:

        home.subtitle
        home.title

    This parser used to require a leading `"`, which is what a `.strings` file
    looks like, not what `print` emits. The set therefore came back empty every
    time — `missing` would have named every key in the app and `dead` would have
    been permanently green. Nothing caught it because C1 below meant this
    function was never reached at all. Both are now driven by
    `--selftest-catalog`.
    """
    result = subprocess.run([tool, "print", catalog],
                            capture_output=True, text=True, check=False)
    if result.returncode != 0:
        return None, (result.stderr.strip() or result.stdout.strip())
    keys = {line.strip() for line in result.stdout.splitlines() if line.strip()}
    return keys, None


def swift_referenced_keys(nine=REPO_NINE, strict=True):
    """Every catalog key this app actually asks for.

    A `Strings.foo.bar` grep is only one of the ways a key is named here, and on
    its own it is wrong in the loudest possible direction: from the moment the
    catalog exists it reports **every one of the Shared keys as a dead string**
    and turns the cheap lane red. That is not a nuisance to suppress, it is the
    check disagreeing with the design — `Sources/Shared` cannot name `Strings`
    (it is Linux-clean and compiles into two bundles), so it reaches its words
    through `Phrasebook.current.string("…")` instead, with the key as a literal.

    So the used-set is a union of readers, one per shape a key is written in:

      1. `Strings.foo.bar` — the App-layer accessor paths Task 5 generates.
      2. `.string("board.cell.label")` — the literal handed to `Phrasebook`, in
         `Sources/Shared` and in `Sources/Strings`.
      2b. the same call with a ternary in it, `.string(isOn ? "x.on" : "x.off")`
         — see `PHRASEBOOK_TERNARY_KEY_RE`, which (2) cannot reach because it is
         anchored on the open paren.
      3. The interpolated families, which no grep can see. `Strings.technique`
         builds `"technique.\\(t.rawValue).name"`, `NineTip.message` builds
         `"tip.\\(rawValue)"`; the keys exist only at runtime, one per enum
         case. `INTERPOLATED_FAMILIES` names each one and its enum, so
         *appending* a case makes it a used key — and, since the catalog is
         generated from `EnglishPhrases.table`, a case with no row shows up as
         `missing` rather than sailing through.
      3b. `SCOPE_SUFFIX_FAMILIES`: `scope + ".placeVerb"`, the same trick with a
         prefix held as data instead of an enum case. 86 keys.
      3c. `KEY_ARRAYS`: two named `[String]`s indexed by a digit. 19 keys.

      4. `EnglishPhrases.table` itself — **lenient mode only, and the reason
         this argument exists.**

    Reader (4) was in the union unconditionally, and that made the dead-string
    check unfalsifiable rather than merely lenient. The catalog's `en` is
    *generated from* that table (`--build-catalog`), so `keys` and the table's
    keys are the same 394 strings read twice, and `dead = keys - used` was empty
    **by construction, for every key, forever**. Nothing else covered it:
    `CatalogTests.testEveryEnglishPhraseHasACatalogEntry` runs table→catalog
    only, `testTheAppLayerBuildsTheSameKeysAsShared` compares two spellings of a
    formula, and `PhrasebookTests` checks the table's shape rather than whether
    anything reads it. A gate that cannot fail is not a gate, and Task 9 is
    about to pay nine translators per key.

    So `strict=True` — the default, and what `--audit` runs — drops (4) and
    makes the check answer the question it claims to: *does any Swift file
    actually ask for this key?* Readers 2b, 3b and 3c are what (4) was really
    standing in for; they were written by reading the 118 keys strict mode
    reported the first time it ran, and each one is a shape, not a list of
    names. `strict=False` keeps the old behaviour so `--selftest-catalog` can
    drive both and show the difference.

    `Sources/Strings` is read here but is not in `TREES`: the offence scanner
    must not walk it (it is the one tree that is *supposed* to hold string
    keys), while the key reader must.
    """
    keys = set()
    for tree in TREES + [STRINGS_TREE]:
        root = os.path.join(nine, tree)
        if not os.path.isdir(root):
            continue
        for dirpath, _dirs, files in os.walk(root):
            for name in files:
                if not name.endswith(".swift"):
                    continue
                with open(os.path.join(dirpath, name), "r",
                          encoding="utf-8") as handle:
                    source = strip_comments(handle.read())
                keys.update(CATALOG_KEY_RE.findall(source))
                keys.update(PHRASEBOOK_KEY_RE.findall(source))
                for arms in PHRASEBOOK_TERNARY_KEY_RE.findall(source):
                    keys.update(arms)
    keys.update(interpolated_keys(nine))
    keys.update(scope_suffix_keys(nine))
    keys.update(array_keys(nine))
    if not strict:
        keys.update(key for key, _ in read_english_table(
            os.path.join(nine, "Sources", "Shared", "EnglishPhrases.swift")))
    return keys


def scope_suffix_keys(nine=REPO_NINE):
    """The `scope + ".field"` families, as the cross product of the scopes and
    the suffixes each declaring file actually spells.

    Both halves come out of the source, so neither can drift from the app; the
    only thing named here is which file to look in. A family that reads back
    empty on either half is a hard failure rather than a quietly smaller
    used-set, because "the parser stopped seeing your keys" and "you deleted
    your keys" are the same output otherwise — and the first one turns 86
    live keys into 86 reported dead ones on somebody else's PR.
    """
    keys = set()
    for name, path, prefix in SCOPE_SUFFIX_FAMILIES:
        full = os.path.join(nine, path)
        if not os.path.exists(full):
            sys.exit("cannot find %s, which declares the `%s` key family. "
                     "Did it move? Update SCOPE_SUFFIX_FAMILIES." % (path, prefix))
        with open(full, "r", encoding="utf-8") as handle:
            source = strip_comments(handle.read())
        scopes = set(re.findall(r'"(%s[A-Za-z0-9_.]+)"' % re.escape(prefix), source))
        suffixes = set(SCOPE_SUFFIX_RE.findall(source))
        if not scopes or not suffixes:
            sys.exit("%s no longer looks like a scope+suffix family: %d scope(s) "
                     "starting `%s` and %d `+ \".field\"` suffix(es). Its keys "
                     "would all read as dead. Fix the reader, not the app."
                     % (name, len(scopes), prefix, len(suffixes)))
        for scope in scopes:
            for suffix in suffixes:
                keys.add("%s.%s" % (scope, suffix))
    return keys


ARRAY_LITERAL_RE = re.compile(r'"([^"\\\n]+)"')


def array_keys(nine=REPO_NINE):
    """The keys held in the named `[String]`s of `KEY_ARRAYS`.

    Read out of the array rather than allow-listed by prefix, for the reason
    `EXEMPT` gives: a `board.digitWord.*` wildcard would keep passing a row
    nothing reads any more.
    """
    keys = set()
    for owner, path, array in KEY_ARRAYS:
        full = os.path.join(nine, path)
        if not os.path.exists(full):
            sys.exit("cannot find %s, which declares `%s.%s`. Update KEY_ARRAYS."
                     % (path, owner, array))
        with open(full, "r", encoding="utf-8") as handle:
            source = strip_comments(handle.read())
        match = re.search(r"\b%s\b\s*(?::[^=\n]+)?=\s*\[" % re.escape(array), source)
        if match is None:
            sys.exit("`%s.%s` is no longer a `[String]` literal in %s — its keys "
                     "would all read as dead. Fix the reader, not the app."
                     % (owner, array, path))
        end = source.index("]", match.end())
        found = ARRAY_LITERAL_RE.findall(source[match.end():end])
        if not found:
            sys.exit("`%s.%s` in %s holds no string literals the parser can see."
                     % (owner, array, path))
        keys.update(found)
    return keys


def interpolated_keys(nine=REPO_NINE):
    """The keys built by interpolation, one per enum case.

    `Technique` and `Difficulty` raw values are frozen inside 56 golden-corpus
    hashes, which is exactly why the key is derived from them rather than
    mapped: the ID half cannot drift.
    """
    keys = set()
    for enum, path, pattern in INTERPOLATED_FAMILIES:
        for case in swift_enum_cases(os.path.join(nine, path), enum):
            keys.add(pattern % case)
    return keys


def swift_enum_cases(path, enum):
    """The declared case names of `enum` in `path`, in declaration order.

    Reads `case a` and `case a, b, c` lines inside the enum's braces and
    nothing else. A `switch`'s `case .nakedSingle:` cannot match — it carries a
    leading dot and a trailing colon — and no case in these three enums has an
    associated value or an explicit raw value.
    """
    with open(path, "r", encoding="utf-8") as handle:
        source = strip_comments(handle.read())
    match = re.search(r"\benum\s+%s\b" % re.escape(enum), source)
    if match is None:
        sys.exit("cannot find `enum %s` in %s — did it move? The catalog's "
                 "key families are derived from its cases." % (enum, path))
    start = source.index("{", match.end())
    depth, end = 0, len(source)
    for i in range(start, len(source)):
        if source[i] == "{":
            depth += 1
        elif source[i] == "}":
            depth -= 1
            if depth == 0:
                end = i
                break
    body = source[start:end]
    cases = []
    for line in body.splitlines():
        found = ENUM_CASE_RE.match(line)
        if found:
            cases.extend(name.strip() for name in found.group(1).split(","))
    if not cases:
        sys.exit("`enum %s` in %s declares no cases the parser can see."
                 % (enum, path))
    return cases


def compile_catalog(tool, catalog):
    """Does `xcstringstool` accept this catalog? Returns None, or its stderr.

    `compile` requires `--output-directory` even under `--dry-run` — it exits
    64 with an argument-parser usage error otherwise. The first version of this
    passed `--dry-run` alone, so from the moment Task 4 created the catalog the
    lane would have gone red on every PR with "the catalog does not compile"
    wrapped around `Missing expected argument '--output-directory'`. Worse, the
    early `return` meant the missing-key and dead-string checks would never
    have run at all. A temporary directory is the price of `--dry-run` being a
    lie about what the tool needs, not about what it writes.
    """
    with tempfile.TemporaryDirectory() as out:
        result = subprocess.run(
            [tool, "compile", catalog, "--dry-run", "--output-directory", out],
            capture_output=True, text=True, check=False)
    if result.returncode == 0:
        return None
    return result.stderr.strip() or result.stdout.strip()


def audit_catalog(verbose, catalog=CATALOG, used=None, strict=True):
    """The three catalog checks. Returns a list of failure strings; an empty
    list with a printed note is what "the catalog does not exist yet" looks
    like, because Task 1 ships before Task 4 builds it.

    `catalog` and `used` are arguments so `--selftest-catalog` can drive this
    against a scratch catalog. Both of these checks shipped broken once because
    nothing could run them until Task 4; that is now no longer true.

    `strict` is the dead-string check's teeth — see `swift_referenced_keys`. It
    is on by default because the reason to have it off (Tasks 5-8 mid-flight,
    keys landing before their call sites) expired with Task 6.
    """
    if not os.path.exists(catalog):
        print("note: %s does not exist yet — skipping the catalog checks "
              "(Task 4 creates it)." % os.path.relpath(catalog, REPO_NINE))
        return []
    tool = xcstringstool()
    if tool is None:
        return ["xcstringstool not found — install Xcode, or fix "
                "`xcrun --find xcstringstool`"]

    failures = []
    error = compile_catalog(tool, catalog)
    if error is not None:
        failures.append("the catalog does not compile:\n%s" % error)
        return failures

    keys, error = catalog_keys(tool, catalog)
    if keys is None:
        failures.append("xcstringstool print failed:\n%s" % error)
        return failures

    if used is None:
        used = swift_referenced_keys(strict=strict)
    missing = sorted(used - keys)
    dead = sorted(keys - used)
    if missing:
        failures.append("used in Swift, absent from the catalog: %s"
                        % ", ".join(missing))
    if dead:
        failures.append("in the catalog, referenced by no Swift file "
                        "(dead strings, which translators are paid for): %s"
                        % ", ".join(dead))
    if verbose and not failures:
        print("catalog: %d keys, all of them reachable%s."
              % (len(keys), " (strict)" if strict else " (lenient)"))
    return failures


# --------------------------------------------------------------- the catalog

# What each key means, for the person who has to say it in Japanese.
#
# **Not optional, and not decoration.** "Sharp" is unguessable — a knife, a
# musical accidental, a difficulty band? — and `board.announce.solved`
# ("Solved.", a sentence VoiceOver speaks) versus `archive.day.solved`
# ("solved", a word appended to a date) are different parts of speech that a
# translator will get wrong exactly once per language, in a build nobody on this
# team can read. `--build-catalog` refuses to write a key with no comment, which
# is what makes this list impossible to forget rather than merely easy to fill
# in.
#
# Three things every comment tries to carry: the part of speech, where it
# appears, and what the arguments are. Length limits belong here too, when the
# surface has one.
COMMENTS = {
    # Archive grid (PRD-14). Fragments appended after a spoken date —
    # "12 July 2026, today, solved" — never sentences, never capitalised.
    "archive.day.today": "VoiceOver, archive grid. Appended to a spoken date: \"12 July 2026, today\". A fragment, not a sentence — no capital, no full stop.",
    "archive.day.solved": "VoiceOver, archive grid. Appended to a spoken date to say that day's puzzle is finished. A fragment: \"12 July 2026, solved\".",
    "archive.day.inProgress": "VoiceOver, archive grid. Appended to a spoken date to say that day's puzzle is started but unfinished.",
    "archive.day.notPlayed": "VoiceOver, archive grid. Appended to a spoken date to say that day's puzzle was never opened. Only ever said of a day that CAN still be played.",

    # Board VoiceOver (PRD-19). The most-spoken strings in the app: 81 cell
    # labels per screen read.
    "board.cell.label": "VoiceOver, the name of one square. %1$lld is the row (1-9), %2$lld the column (1-9). A translation may reorder them — German and Japanese both front the column.",
    "board.cell.placeHint": "VoiceOver hint on an empty square, spoken after the label. Describes how to enter a digit on this platform.",
    "board.cell.hintPair": "Joins the two halves of a square's VoiceOver hint — the box it sits in (\"Box 2\") and how to place a digit — into one utterance. Punctuation and order only, no words of its own: a full stop and a space in English, \"。\" and no space in Japanese.",
    "board.unit.row": "VoiceOver, the name of a row. %1$lld is 1-9.",
    "board.unit.column": "VoiceOver, the name of a column. %1$lld is 1-9.",
    "board.unit.box": "VoiceOver, the name of a 3x3 box. %1$lld is 1-9.",
    "board.value.empty": "VoiceOver value of a square with nothing in it. A word, not a sentence.",
    "board.value.given": "VoiceOver value of a square the puzzle supplied and the player cannot change. %1$lld is the digit.",
    "board.value.wrong": "VoiceOver value of a square holding a digit that contradicts the solution. %1$lld is the digit. Only ever spoken when the player has mistake-marking switched on.",
    "board.value.notes": "VoiceOver value of an empty square carrying pencil marks. %1$@ is the list of noted digits, already joined.",
    "board.value.noteSeparator": "Joins the digits in a spoken list of pencil marks. Punctuation only — use whatever this language lists with (a comma in English, an ideographic comma in Japanese).",
    "board.box.filled": "VoiceOver, group scan: this 3x3 box is complete. A word, not a sentence.",
    "board.box.empty": "VoiceOver, group scan: how many squares in this 3x3 box are still blank. %1$lld is 1-8. PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",
    "board.announce.placed": "VoiceOver announcement after a digit is entered. %1$@ is the digit as a word (\"four\"), and it arrives in its citation form — lowercase in English. If your language needs it capitalized in this position, capitalize it in board.digitWord.*; English opens with its own verb because it cannot. A sentence: it ends in a full stop.",
    "board.announce.cleared": "VoiceOver announcement after a digit is removed. %1$@ is the digit as a word, in its citation form — see board.announce.placed on where the capital comes from.",
    "board.announce.noteAdded": "VoiceOver announcement after a pencil mark is added. %1$@ is the digit as a word.",
    "board.announce.noteRemoved": "VoiceOver announcement after a pencil mark is removed. %1$@ is the digit as a word.",
    "board.announce.pair": "Joins the two sentences of a placement announcement — \"Placed four.\" and \"That leaves two fours.\" — into one utterance. Punctuation and order only, no words of its own: a space in English, nothing at all after a Japanese full stop. Reorder the two if that is how this language says it.",
    "board.announce.remaining": "VoiceOver announcement, spoken straight after board.announce.placed: how many of one digit are still missing. %1$@ is a count word (\"three\"), %2$@ the digit's plural (\"sevens\"), both in their citation form. A language that counts with numerals may write the number into the sentence and leave the words unused. Short — it is spoken on every digit placed, about fifty times a board.",
    "board.announce.allDone": "VoiceOver announcement: every instance of one digit is now placed. %1$@ is the digit's plural (\"sevens\").",
    "board.announce.solved": "VoiceOver announcement the moment the board is finished. One word, a full sentence.",
    "board.progress.filled": "VoiceOver board summary. %1$lld squares filled of %2$lld fillable. PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",
    "board.progress.wrong": "VoiceOver board summary: how many placed digits contradict the solution. %1$lld is the count. Only spoken with mistake-marking on. PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",
    "board.streak.plain": "VoiceOver label of the streak chip. %1$lld is a number of consecutive days, always 1 or more. PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",
    "board.streak.held": "VoiceOver label of the streak chip on a day already solved — the run is safe. %1$lld is a number of consecutive days. PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",

    # Voice Control names. Matched against a speech recogniser, so no
    # punctuation of any kind.
    "board.voiceName.cell": "Voice Control name for a square, spoken BY the player to select it. %1$lld is the row, %2$lld the column. No punctuation at all — a recogniser never emits a comma.",
    "board.voiceName.pair": "How the two numbers of the shortest Voice Control name for a square are separated. %1$@ is the row and %2$@ the column, both already written as numerals — this row is ONLY the separator. Spoken BY the player at a speech recogniser, so no punctuation: English uses a space.",
    "board.voiceName.rowColumn": "Alternative Voice Control name for the same square, spoken by the player. %1$lld is the row, %2$lld the column. No punctuation.",

    # Digit words. Spoken, never shown — the numerals are drawn as glyphs.
    "board.digitWord.zero": "The digit 0 as a spoken word, for VoiceOver announcements.",
    "watch.app.name": "The app's own name, shown as the watch's navigation title. DO NOT TRANSLATE: Nine is the product name and stays \"Nine\" in every locale, exactly as it does on the App Store.",
    "watch.dial.empty": "VoiceOver name for the Crown rose's resting position, before any digit is chosen.",
    "watch.dial.erase": "VoiceOver name for the erase stop at the end of the Crown rose's run.",
    "watch.nav.home": "Back button on the watch board, returning to the list of boards.",
    "watch.nav.map": "Back button inside the watch's zoomed 3x3 box, returning to the full 9x9 board.",
    "watch.rail.column": "VoiceOver name for the watch strip listing digits already placed in the selected cell's column.",
    "watch.rail.empty": "Spoken value of a watch peer strip when no digits are placed on that row or column yet.",
    "watch.rail.row": "VoiceOver name for the watch strip listing digits already placed in the selected cell's row.",
    "watch.today.waiting": "Watch status for today's puzzle when it has not arrived from the phone yet.",
    "watch.today.waitingHint": "VoiceOver hint telling the player how to get today's puzzle onto the watch.",
    "board.digitWord.one": "The digit 1 as a spoken word, for VoiceOver announcements.",
    "board.digitWord.two": "The digit 2 as a spoken word, for VoiceOver announcements.",
    "board.digitWord.three": "The digit 3 as a spoken word, for VoiceOver announcements.",
    "board.digitWord.four": "The digit 4 as a spoken word, for VoiceOver announcements.",
    "board.digitWord.five": "The digit 5 as a spoken word, for VoiceOver announcements.",
    "board.digitWord.six": "The digit 6 as a spoken word, for VoiceOver announcements.",
    "board.digitWord.seven": "The digit 7 as a spoken word, for VoiceOver announcements.",
    "board.digitWord.eight": "The digit 8 as a spoken word, for VoiceOver announcements.",
    "board.digitWord.nine": "The digit 9 as a spoken word, for VoiceOver announcements.",
    "board.digitPlural.one": "\"the 1s\" — the digit 1 as a countable plural noun: \"three ones remaining\". A language without plural nouns may repeat the singular.",
    "board.digitPlural.two": "\"the 2s\" — the digit 2 as a countable plural noun: \"three twos remaining\".",
    "board.digitPlural.three": "\"the 3s\" — the digit 3 as a countable plural noun.",
    "board.digitPlural.four": "\"the 4s\" — the digit 4 as a countable plural noun.",
    "board.digitPlural.five": "\"the 5s\" — the digit 5 as a countable plural noun.",
    "board.digitPlural.six": "\"the 6s\" — the digit 6 as a countable plural noun.",
    "board.digitPlural.seven": "\"the 7s\" — the digit 7 as a countable plural noun.",
    "board.digitPlural.eight": "\"the 8s\" — the digit 8 as a countable plural noun.",
    "board.digitPlural.nine": "\"the 9s\" — the digit 9 as a countable plural noun.",

    # The share card (PRD-12). A picture that leaves the app; nobody here can
    # correct it afterwards. Two short lines, centred, under a 9x9 grid.
    "card.daily": "Second line of the shareable solve card, marking the board as that day's puzzle. \"Nine\" is the app's name and stays untranslated; the separator is a middle dot.",
    "card.time": "First line of the shareable solve card. %1$@ is an elapsed time already formatted as m:ss (\"3:40\"). Keep it short — it is set large and centred.",
    "card.streak": "Half of the solve card's credit line, after the difficulty: \"Steady - 12 day streak\". %1$lld is a number of consecutive days, always 1 or more. PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",

    # The coach (PRD-11). One sentence, on a card, that the player could check
    # by hand. Never mentions the solution.
    #
    # Every argument here is a NUMBER — a digit, a row/column/box number — and
    # never a word this app formatted for you. There is one sentence per unit
    # kind (row, column, box) rather than one sentence with the unit's name
    # dropped in, so the preposition, the word order and any inflection are all
    # yours: "in row 4" and "in box 4" are one sentence in English and need not
    # be one in your language. Translate each of them as a whole sentence.
    "coach.solved.title": "Coach card heading when the board is finished. One word.",
    "coach.slip.title": "Coach card heading when two squares contradict each other, so no hint is possible. Gentle and blameless: the player made a slip, they did not fail.",
    "coach.slip.sentence": "Coach card body when two squares contradict each other. Says that nothing can follow, without saying which square is wrong.",
    "coach.exhausted.title": "Coach card heading when the board is consistent but no technique at its level applies. Not an error — the hint has simply run out.",
    "coach.exhausted.sentence": "Coach card body when no technique at this board's level applies.",
    "coach.nakedSingle.sentence": "Coach explanation, naked single: this square has only one candidate left. %1$lld is the row (1-9), %2$lld the column (1-9), %3$lld the digit. Sentence-initial in English; put the square wherever your language puts it.",
    "coach.hiddenSingle.sentence.row": "Coach explanation, hidden single confined to a ROW: only one square in that row can hold the digit. %1$lld is the row number (1-9), %2$lld the digit. The row/column/box variants are separate sentences on purpose — say each one naturally.",
    "coach.hiddenSingle.sentence.col": "Coach explanation, hidden single confined to a COLUMN. %1$lld is the column number (1-9), %2$lld the digit.",
    "coach.hiddenSingle.sentence.box": "Coach explanation, hidden single confined to a 3x3 BOX. %1$lld is the box number (1-9, reading order), %2$lld the digit.",
    "coach.hiddenSingle.sentence.cell": "Coach explanation, hidden single when no containing unit could be named — so this one names the square instead. %1$lld is the row, %2$lld the column, %3$lld the digit. Mentions no row, column or box.",
    "coach.nakedPair.sentence.row": "Coach explanation, naked pair clearing a ROW: two digits fill two squares between them, so neither can appear elsewhere in that row. %1$lld and %2$lld are the two digits, %3$lld the row number.",
    "coach.nakedPair.sentence.col": "Coach explanation, naked pair clearing a COLUMN. %1$lld and %2$lld are the two digits, %3$lld the column number.",
    "coach.nakedPair.sentence.box": "Coach explanation, naked pair clearing a 3x3 BOX. %1$lld and %2$lld are the two digits, %3$lld the box number.",
    "coach.hiddenPair.sentence.row": "Coach explanation, hidden pair inside a ROW: two digits fit only two squares there, so nothing else fits in those squares. %1$lld and %2$lld are the digits, %3$lld the row number.",
    "coach.hiddenPair.sentence.col": "Coach explanation, hidden pair inside a COLUMN. %1$lld and %2$lld are the digits, %3$lld the column number.",
    "coach.hiddenPair.sentence.box": "Coach explanation, hidden pair inside a 3x3 BOX. %1$lld and %2$lld are the digits, %3$lld the box number.",
    "coach.boxLine.sentence.boxToRow": "Coach explanation, box-line reduction pointing OUT of a box along a ROW: every place the digit can still go in that box lies on that row, so the rest of the row is clear of it. %1$lld is the digit, %2$lld the box number, %3$lld the row number. %1$lld and %3$lld each appear TWICE — if you reorder, move every occurrence.",
    "coach.boxLine.sentence.boxToCol": "Coach explanation, box-line reduction pointing OUT of a box along a COLUMN. %1$lld is the digit, %2$lld the box number, %3$lld the column number. %1$lld and %3$lld each appear twice.",
    "coach.boxLine.sentence.rowToBox": "Coach explanation, box-line reduction claiming a ROW's digit INTO a box: every place the digit can still go in that row lies inside one box, so the rest of the box is clear of it. %1$lld is the digit, %2$lld the row number, %3$lld the box number. %1$lld and %3$lld each appear twice.",
    "coach.boxLine.sentence.colToBox": "Coach explanation, box-line reduction claiming a COLUMN's digit INTO a box. %1$lld is the digit, %2$lld the column number, %3$lld the box number. %1$lld and %3$lld each appear twice.",
    "coach.xWing.sentence.rowBase": "Coach explanation, X-wing based on two ROWS: in two rows the digit can only sit in the same two columns, so it is cleared from the rest of those columns. %1$lld is the digit and appears TWICE — move both if you reorder. The words \"rows\" and \"columns\" are part of the sentence; write them the way your language names them.",
    "coach.xWing.sentence.colBase": "Coach explanation, X-wing based on two COLUMNS: in two columns the digit can only sit in the same two rows, so it is cleared from the rest of those rows. %1$lld is the digit and appears twice.",

    # Channels (PRD-24). The three pages of the home shelf: three rulesets, each
    # with its own daily, streak and stats. A title is one word on a page header;
    # a blurb is one short line under it saying what the ruleset is.
    "channel.classic.title": "Channel name, the first of three pages on the home shelf: ordinary sudoku with no extra rules. Shown as a page title. One word.",
    "channel.classic.blurb": "One-line subtitle under the Classic channel's title, saying that this page is plain sudoku. Calm and plain, not a sales pitch. Under about 25 characters.",
    "channel.thermo.title": "Channel name, a sudoku variant played on \"thermometers\" — shapes drawn on the grid whose digits must increase from the round bulb end to the tip. Short for \"thermometer\". Use whatever your language's sudoku players call this variant if there is one; otherwise a short word for thermometer. One word.",
    "channel.thermo.blurb": "One-line subtitle under the Thermo channel's title. \"Tubes\" are the thermometer shapes; \"only rise\" means the digits along one must strictly increase. Convey \"the numbers along each shape always go up\". Under about 25 characters.",
    "channel.killer.title": "Channel name, the sudoku variant known in English as Killer Sudoku: the grid is divided into outlined \"cages\", each printed with a total its digits must add up to. NOT the adjective \"killer\" and nothing to do with killing — this is the established name of a puzzle type. Use whatever your language's sudoku players call this variant. One word.",
    "channel.killer.blurb": "One-line subtitle under the Killer channel's title. \"Cages\" are the outlined regions; \"add up\" refers to each one's printed total. Convey \"outlined groups that sum to a number\". Under about 25 characters.",
    "board.cell.withRule": "Accessibility label for a puzzle square on a variant board: the square's position, then the rule it sits under, as ONE utterance VoiceOver reads on every focus move. %1$@ is like \"Row 3, column 5\"; %2$@ is like \"cage of 15\" or \"thermometer, 2 of 4\". Both halves are finished translated strings — the comma and space between them is the join, and where a join goes differs per language (Japanese uses \u3001 and no space). Keep it SHORT: it is spoken every time focus moves.",
    "board.cell.ruleSeparator": "Separator between two rules on one puzzle square, when a square sits on two thermometers at once. English uses a comma and a space. Punctuation only.",
    "board.rule.cage": "Spoken part of a puzzle square's label on a Killer board: the total its outlined cage must add up to. %1$lld is that total (2-45). Very short — it is spoken every time focus moves. \"Cage\" is the outlined group of squares.",
    "board.rule.thermo": "Spoken part of a puzzle square's label on a Thermo board: where this square sits along its thermometer. %1$lld is the position counting from the round bulb end (1 = the bulb) and %2$lld is the thermometer's length. Digits increase from bulb to tip, so the position is what tells the player how small or large this square can be. Very short — spoken every time focus moves.",
    "coach.cageSingle.sentence": "Coach explanation on a Killer board: only one square of a cage is still empty, so the cage's printed total forces its digit. %1$lld is how many squares the cage has and %2$lld is the digit. \"Cage\" is the outlined group with a printed total.",
    "coach.cageCombination.sentence": "Coach explanation on a Killer board: a cage's printed total admits only a few sets of digits, and none of the sets still possible puts this digit in this square. %1$lld is the cage's size and %2$lld is the digit being ruled out. \"Cage\" is the outlined group with a printed total.",
    "coach.innieOutie.sentence.row": "Coach explanation on a Killer board, the \"rule of 45\": every ROW holds 1 through 9 and so totals 45, and the cages covering this row account for all but one square, which forces that square. %1$lld is the row number and %2$lld the digit. 45 is arithmetic, not a translatable word. Three separate sentences exist for row/column/box so each can be phrased naturally.",
    "coach.innieOutie.sentence.col": "Coach explanation on a Killer board, the \"rule of 45\", for a COLUMN. %1$lld is the column number and %2$lld the digit. See coach.innieOutie.sentence.row.",
    "coach.innieOutie.sentence.box": "Coach explanation on a Killer board, the \"rule of 45\", for a 3x3 BOX. %1$lld is the box number and %2$lld the digit. See coach.innieOutie.sentence.row.",
    "coach.thermoBound.sentence": "Coach explanation on a Thermo board: digits along a thermometer increase strictly from the round bulb end to the tip, which limits how small or large each square on it can be. %1$lld is the thermometer's length in squares. \"Floor and ceiling\" means a lowest and highest possible digit — phrase it naturally rather than literally.",
    "channel.next": "Accessibility label for the button that turns the home shelf to the next channel page. A verb phrase VoiceOver reads before the word \"button\". Short.",
    "channel.previous": "Accessibility label for the button that turns the home shelf to the previous channel page. A verb phrase VoiceOver reads before the word \"button\". Short.",
    "channel.pager.label": "Accessibility label for the whole channel page indicator, read as one utterance. %1$@ is the channel name, %2$lld the current page, %3$lld the total (3 today). Match how your language says \"page N of M\".",
    "channel.stats.title": "Heading over a channel's own solve times on the home shelf. Possessive and plain — these are the player's times on THIS channel only. Two or three words.",
    "channel.stats.row": "One row of a channel's solve times: how many puzzles solved at this difficulty and the best time. %1$lld is the count, %2$@ is a time already formatted as m:ss in the reader's own numerals. Compact — it sits at the right edge of a narrow row. The separator is a middle dot.",
    "channel.stats.label": "Accessibility label for one row of a channel's solve times, spoken as ONE utterance. %1$@ is a difficulty name, %2$lld the number solved, %3$@ a time already formatted as m:ss. \"Best\" means fastest.",
    "channel.today.label": "Accessibility label for a channel's Today card, spoken as ONE utterance so VoiceOver does not read a title and then an orphaned status. %1$@ is the channel name; %2$@ is a whole sentence about its state (\"Solved\", \"Continue · Half done\"). The full stop between them is the join — place it as your language would.",
    "channel.today.oneADay": "Resting state of a channel's Today card, before that channel's daily puzzle has been started. Says there is one puzzle per day AND that each channel has its own — playing today's Thermo does not use up today's Classic. Short.",
    "channel.unavailable": "Shown on a saved variant puzzle that cannot be opened because this copy of the app does not understand one of its rules; it arrived from a newer version. Plain and brief, not an apology and not an error code. Fits on one line under a puzzle's name.",

    # Variant tiers (PRD-24). The difficulty ladder for a variant channel.
    # Deliberately its own key family rather than reusing difficulty.*.title:
    # a tier and a band are different ladders, so a rename of one must not move
    # the other, and a translator gets one string per meaning.
    "variantTier.gentle.title": "Difficulty of a variant puzzle, easiest of three. Same calm register as difficulty.gentle.title — not \"Easy\", which judges the player. May well be the same word you used there; it is a separate string because the two ladders can diverge. One or two words.",
    "variantTier.steady.title": "Difficulty of a variant puzzle, middle of three: unhurried, dependable. See variantTier.gentle.title on why this is separate from difficulty.steady.title. One or two words.",
    "variantTier.sharp.title": "Difficulty of a variant puzzle, hardest of three: keen-witted, demanding. NOT the knife and NOT the musical accidental. See variantTier.gentle.title on why this is separate from difficulty.sharp.title. One or two words.",

    "shelf.channel.daily": "Title of a saved variant puzzle in the board list. %1$@ is a channel name (Thermo, Killer), %2$@ is a date like \"Jul 26\". The separator is a middle dot; keep the channel first — it is what makes this a different puzzle rather than a harder one.",
    "shelf.channel.free": "Title of a saved variant practice puzzle in the board list. %1$@ is a channel name (Thermo, Killer), %2$@ is a difficulty (Gentle, Steady, Sharp). The separator is a middle dot; keep the channel first.",

    # Difficulty bands. Names of the four settings a player picks between, shown
    # on buttons, in menus and on the share card. Short: one or two words.
    "difficulty.gentle.title": "Difficulty band, easiest of four. Shown on buttons and menus and on the share card. An adjective in the app's calm register — not \"Easy\", which sounds like a judgement of the player. One or two words.",
    "difficulty.steady.title": "Difficulty band, second of four: unhurried, dependable. Shown on buttons and menus. One or two words.",
    "difficulty.sharp.title": "Difficulty band, third of four: keen-witted, demanding. NOT the knife and NOT the musical accidental. One or two words.",
    # Hand-edited into the artifact during Task 9 and not back into the
    # generator, so the next `--build-catalog` would have deleted the only
    # do-not-translate instruction in the catalog and told nobody. `--audit` now
    # runs the generator dry to make that class of drift a failure.
    "difficulty.nocturne.title": "Difficulty band, fourth of six. A night piece — the late, quiet, difficult one. DO NOT TRANSLATE: Nocturne is a coined name and stays \"Nocturne\" in every locale, pinned by CatalogTests.testCoinedBandNamesAreIdenticalInEveryLocale. Only gentle/steady/sharp are descriptions and do translate.",

    # Technique names. Sudoku terms of art, shown as the coach card's heading.
    # Every language's puzzle community has settled names for these; use them
    # rather than translating the English literally.
    "technique.nakedSingle.name": "Sudoku technique name, coach card heading: a square with only one candidate left. Use this language's established sudoku term if it has one.",
    "technique.hiddenSingle.name": "Sudoku technique name, coach card heading: a digit that fits only one square in a unit. Use this language's established sudoku term if it has one.",
    "technique.nakedPair.name": "Sudoku technique name, coach card heading: two squares sharing exactly two candidates. Use this language's established sudoku term if it has one.",
    "technique.hiddenPair.name": "Sudoku technique name, coach card heading: two digits confined to the same two squares. Use this language's established sudoku term if it has one.",
    "technique.boxLineReduction.name": "Sudoku technique name, coach card heading: a digit confined to one line within a box. Use this language's established sudoku term (\"pointing\"/\"claiming\" family) if it has one.",
    "technique.xWing.name": "Sudoku technique name, coach card heading. Almost always left as \"X-Wing\" — it is a term of art, not a description.",
    "technique.cageSingle.name": "Killer-sudoku technique name, coach card heading: a cage whose sum leaves one possibility. Use this language's established killer-sudoku term if it has one.",
    "technique.thermoBound.name": "Thermometer-sudoku technique name, coach card heading: digits must increase along a thermometer, which bounds each bulb.",
    "technique.innieOutie.name": "Killer-sudoku technique name, coach card heading. Known in English as the rule of 45, because a row, column or box always sums to 45. Use this language's established term.",
    "technique.cageCombination.name": "Killer-sudoku technique name, coach card heading: only some digit combinations reach a cage's sum.",
    "difficulty.tempest.title": "Difficulty band, fifth of six. A storm — the one where the patterns spread across the whole board. DO NOT TRANSLATE: like Nocturne, Tempest is a coined name and stays \"Tempest\" in every locale, pinned by CatalogTests.testCoinedBandNamesAreIdenticalInEveryLocale. Only gentle/steady/sharp are descriptions and translate.",
    "difficulty.abyss.title": "Difficulty band, hardest of six. DO NOT TRANSLATE: like Nocturne and Tempest, Abyss is a coined name and stays \"Abyss\" in every locale, pinned by CatalogTests.testCoinedBandNamesAreIdenticalInEveryLocale.",
    "difficulty.tempest.blurb": "One-line blurb under the Tempest difficulty card. \"Wings\" and \"swordfish\" are the sudoku patterns the band is defined by — match technique.xyWing.name and technique.swordfish.name. Very short.",
    "difficulty.abyss.blurb": "One-line blurb under the Abyss difficulty card. Refers to colouring one digit's candidates in two alternating colours — match technique.simpleColoring.name. Very short.",
    # PRD-26 — the debrief, a card the player pulls up after solving. Never
    # forced, never a score: every string here is a neutral statement of fact
    # about the solve that just happened.
    "debrief.title": "Heading of the post-solve debrief card. Possessive: the solve belongs to the player. Two or three words.",
    "debrief.placements": "One of the counts on the debrief card, joined by middle dots: how many digits the player committed over the whole solve, corrections included. Neutral — this is not a score and nothing is being judged. PLURAL: %1$lld is the count, 0 or more.",
    "debrief.duel.placed": "Debrief line after a two-player local game where people take turns on one device (PRD-27). %1$@ is a player's name, which is the name of the colour their digits are drawn in (\"Glacier\", \"Ember\"); %2$lld is how many correct digits they placed. Two of these are joined by debrief.duel.separator to make one line naming both players. A RECORD, NOT A SCORE — do not translate as a competitive result or add any word meaning \"won\", \"beat\" or \"points\". PLURAL on %2$lld.",
    "debrief.duel.cleared": "Debrief line after a two-player local game (PRD-27), shown only when at least one wrong digit was placed. %1$@ is a player's name (the name of their digit colour); %2$lld is how many of their digits were silently removed from the board during the game. VERB, past tense, NEUTRAL: the digits were cleared away. Avoid any word meaning \"mistake\", \"failure\" or \"wrong\" — this whole feature exists so that nobody is told off in front of the other player. PLURAL on %2$lld.",
    "debrief.duel.last": "Debrief line after a two-player local game (PRD-27). %1$@ is a player's name (the name of their digit colour). A statement of fact about who completed the puzzle, NOT a declaration that they won — nothing in this app declares a winner. Full sentence, ends with a full stop.",
    "debrief.duel.separator": "Joins the two halves of a two-player debrief line — \"Glacier placed 24\" and \"Ember placed 21\" — into one line. Punctuation and order only, no words of its own: a space, a middle dot and a space in English. Both halves are already-translated strings, so this carries separation and nothing else. Same job as board.cell.ruleSeparator.",
    "debrief.errors": "One of the counts on the debrief card: digits placed that contradicted the solution (matches board.rotor.errors' subject, not its wording — this is a count, not a VoiceOver rotor name). Unlike debrief.corrections, this word MAY imply a mistake; the neutrality rule applies to corrections, not to this one. Omitted from the card entirely at 0, so in practice this only ever renders at 1 or more — translate the PLURAL forms anyway. PLURAL: %1$lld is the count.",
    "debrief.corrections": "One of the counts on the debrief card: erasures and undos. Deliberately neutral — a solve with many corrections is a longer look, not a worse solve, so avoid any word implying error or mistake. PLURAL: %1$lld is the count, 0 or more.",
    "debrief.notes": "One of the counts on the debrief card: pencil marks written. \"Notes\" are the small candidate digits in a cell's corner — match game.autoNotes.chip. PLURAL: %1$lld is the count, 0 or more.",
    "debrief.headline": "The one congratulatory sentence in the whole app, shown only when the player resolved a cell with a technique harder than a single. %1$@ is a technique name (already translated, e.g. technique.xWing.name); %2$lld is which placement it was, counting only committed digits. Warm but quiet — this is not a trophy.",
    "debrief.fastest": "Debrief line naming the 3x3 box the player filled with the least hesitation. %1$@ is already-translated text like \"Box 4\" (board.unit.box). The separator is a middle dot. English says \"region\" because it is a different word from \"Box\"; if your language would repeat board.unit.box's noun here, drop the noun instead (\"Fastest - Block 4\") rather than saying it twice.",
    "debrief.longest": "Debrief line naming the cell the player kept coming back to before finally filling it. %1$@ is already-translated text like \"Row 3, column 5\" (board.cell.label). \"Circled\" is figurative — the player circled around it, returning again and again. The separator is a middle dot.",
    "debrief.replay": "Button that plays the comet — an animated retrace of the player's own solve — on the debrief card. A noun or a short imperative verb.",
    "debrief.empty": "Shown in place of the comet when this solve has no recorded move log to replay (an older board, or one solved on another device). A plain statement, not an apology or an error.",
    "debrief.open": "VoiceOver label for the control that pulls the debrief card up. Imperative verb plus the card's own heading — use exactly the words of debrief.title, so the control and the card it opens name the same thing.",
    "debrief.close": "VoiceOver label for the control that dismisses the debrief card. The exact opposite verb of debrief.open, with the same noun phrase from debrief.title.",
    # PRD-28 — The Parlor: several people on a FaceTime call solving the SAME
    # puzzle, each on their own device, each on their own board. Nobody sees
    # anybody else's digits and nobody's time is shown until everybody has
    # finished. NOTHING here is a score, a rank or a race: there is no winner,
    # no "beat", no "fastest", no points. The participants are deliberately
    # anonymous — the system does not tell the app who is on the call — so the
    # words for other people must never be a name, a placeholder for a name, or
    # a possessive that implies one.
    "parlor.activity.title": "Title of the SharePlay activity, shown by the system in FaceTime when someone starts a shared game. Contains the app's name, which is never translated. Two or three words.",
    "parlor.activity.subtitle": "One-line subtitle under parlor.activity.title in the system's SharePlay UI. Explains the whole feature: everyone gets the same puzzle but plays it separately on their own device. Not a slogan.",
    "parlor.start.title": "Title of the shelf card that starts a shared game. Imperative verb phrase, warm and plain. \"Together\" means alongside other people, NOT on the same board.",
    "parlor.start.caption": "One-line caption under parlor.start.title. States the condition (a FaceTime call is needed) and what happens (everyone gets this same puzzle). Plain statement, not a sales line.",
    "parlor.dot.you": "VoiceOver label for the small dot representing the player's OWN progress in a row of dots, one per person on the call. Second person, one or two words.",
    "parlor.dot.other": "VoiceOver label for the dot representing SOMEONE ELSE on the call. The app is not told who they are, so this must stay anonymous — no name, no placeholder for a name, no \"your friend\" (they may not be). Neutral and singular.",
    "parlor.dot.progress": "VoiceOver value for a progress dot. %1$lld is how many squares that person has filled; %2$lld is how many the puzzle has to fill in total. A statement of progress, NOT of speed or rank. Both numbers are needed: the first alone means nothing.",
    "parlor.dot.finished": "VoiceOver value for a progress dot once that person has completed their puzzle. One word. Deliberately says nothing about how long they took — no time is known to this device yet, and that is the point.",
    "parlor.sideBySide": "Heading of the section shown after EVERYONE has finished, holding one small animated replay per person, laid out next to each other. Describes the arrangement, not a comparison — do NOT translate as \"versus\", \"head to head\" or anything competitive.",
    "parlor.comet.you": "Caption under the player's OWN replay in the side-by-side section. %1$@ is a time already formatted as minutes and seconds (e.g. \"4:12\"). Second person, then a middle dot, then the time. A fact, not a result: nothing is ranked and there is no winner.",
    "parlor.comet.other": "Caption under SOMEONE ELSE's replay in the side-by-side section. %1$@ is a time already formatted as minutes and seconds. Must match parlor.dot.other's anonymous wording — the app is not told who they are. A fact, not a result.",
    "parlor.challenge": "Button that sends this exact puzzle to a friend through Game Center, for them to play whenever they like. \"This board\" is the puzzle itself. An imperative verb phrase; avoid any word meaning \"challenge\", \"beat\" or \"compete\".",
    "parlor.invite.accepted": "Short confirmation shown when a puzzle sent by someone else has been opened, so the player knows this is the same puzzle their friend played rather than a fresh one. A statement of fact, three to five words.",
    "difficulty.tempest.explainer": "The longer explanation of the Tempest band. Names three techniques — translate each the same way as technique.swordfish.name, technique.skyscraper.name and technique.xyWing.name. \"The X-wing family, grown up\" means these are the bigger relatives of the X-Wing. Kept to the length of its siblings so the guide still fits one screen.",
    "difficulty.abyss.explainer": "The longer explanation of the Abyss band. Describes simple colouring — match technique.simpleColoring.name. \"Forced pairs\" are the two squares a digit must occupy one of. Kept to the length of its siblings so the guide still fits one screen.",
    # PRD-25 — Technique School. A list of lessons, never a task list: no
    # counts, no percentages, nothing that reads as a score.
    "school.title": "Title of the Technique School screen — a list of lessons, one per sudoku technique. Two words if the language has them.",
    "school.subtitle": "One line under the School title. \"A way a board can be read\" means a solving technique. Calm, not instructional.",
    "school.close": "Button that leaves the School or a lesson. One word.",
    "school.action.showMe": "Button that reveals the pattern on the lesson's board, after the player has had a chance to find it themselves. Two words.",
    "school.action.gotIt": "Button acknowledging that the player has understood the revealed pattern. Casual and short — the register of \"got it\", not \"confirm\".",
    "school.lesson.look": "Instruction at the start of a lesson, before the pattern is revealed. \"Settled\" means the square's digit is now forced. Encourages looking before being told.",
    "school.lesson.done": "Closing line of a lesson. %1$@ is the technique's name — it comes from technique.*.name, already translated, so it may need an article or a case ending here. \"You will meet it again\" is reassurance, not a promise of difficulty.",
    "school.row.met": "VoiceOver label for a School list row the player has already met. %1$@ is the technique name.",
    "school.row.new": "VoiceOver label for a School list row the player has not met yet. %1$@ is the technique name. Never scolding — it is a statement, not a task.",
    "stats.techniquesMet": "One line in the stats drawer: how many of Nine's teachable techniques the player has met, out of how many exist. The ONLY place this number is ever shown. Both values are numbers.",

    # PRD-25 — the deep end's four coach sentences, and the why-chain's copy.
    # Same rule as the sentences above them: one whole entry per rendering, no
    # noun handed into a hole whose grammar is English's.
    "coach.swordfish.sentence.rowBase": "Coach sentence for a row-based Swordfish. %1$lld is the digit, and it appears TWICE — a translation that moves one occurrence must move both. \"These three rows\" refers to rows the board is already highlighting, so it need not name them.",
    "coach.swordfish.sentence.colBase": "Coach sentence for a column-based Swordfish. The mirror of coach.swordfish.sentence.rowBase, with rows and columns swapped. %1$lld appears twice.",
    "coach.skyscraper.sentence": "Coach sentence for a Skyscraper. Two lines each have only two places for the digit and share one of them, so one of the two FAR ends must hold it. \"Seeing\" is sudoku's word for sharing a row, column or box. %1$lld appears twice.",
    "coach.xyWing.sentence": "Coach sentence for an XY-Wing. \"The ringed square\" is the pivot, drawn with a ring on the board — refer to it however this language would refer to a highlighted square. %1$lld and %2$lld are the pivot's two candidates; %3$lld is the digit being eliminated and appears twice.",
    "coach.simpleColoring.sentence.wrap": "Coach sentence for simple colouring's wrap rule: two squares of the SAME colour can see each other, so that colour is impossible. \"Shaded group\" is the colour class as drawn on the board. %1$lld appears once.",
    "coach.simpleColoring.sentence.trap": "Coach sentence for simple colouring's trap rule: exactly one of the two colours is the true one, so a square seeing both cannot hold the digit. %1$lld appears twice.",

    # The why-chain (PRD-25). Short lines in a small card — the whole feature is
    # "narrate on the board, never a text wall", so length is a requirement.
    "why.heading": "Heading of the why-chain card, shown while the coach explains one square. %1$lld is the digit the square must hold. A question, because the player asked one. It carries NO article on purpose — the English was \"Why a %1$lld?\" and rendered \"Why a 8?\", and choosing a/an from a numeral is English grammar that no other language shares. If this language needs an article before a numeral, write the one that is always correct or rephrase.",
    "why.position": "Which beat of the explanation is on screen, e.g. \"2 of 4\". Both numbers; no words needed if this language would use none.",
    "why.action.next": "Button that advances to the next beat of the explanation. One word.",
    "why.effect.leaves": "Final line of a why-chain beat: every other candidate is gone and %1$lld is what remains. One short sentence.",
    "why.effect.rulesOutOne": "Line under a why-chain beat when the step removed exactly one possibility, %1$lld, from the square the player asked about.",
    "why.effect.rulesOutTwo": "The same for exactly two possibilities, %1$lld and %2$lld. A separate entry rather than a list, so this language writes its own conjunction.",
    "why.effect.rulesOutMore": "The same for three or more. Deliberately carries no number — past two the count stops being the point.",
    "why.elsewhere": "Shown when the explanation skipped steps that were about other squares. Reassurance that the chain is a summary, not the whole proof. No number.",
    "why.untold": "Shown when the chain is longer than the six beats the card will narrate. The beats nearest the answer are the ones kept.",
    "why.beyond.title": "Heading when the coach cannot explain this square inside the board's difficulty. Two or three words.",
    "why.beyond.sentence": "The sentence under why.beyond.title. \"This board's level\" is its difficulty band. Declining, never apologising.",

    "technique.swordfish.name": "Sudoku technique name, coach card heading. The three-line member of the X-Wing family. A term of art like X-Wing — usually kept, occasionally calqued (German \"Schwertfisch\"); do not describe it.",
    "technique.skyscraper.name": "Sudoku technique name, coach card heading: two lines sharing one column, with two ends of unequal height. A term of art; calque it (\"Wolkenkratzer\") only if that is the established local term.",
    "technique.xyWing.name": "Sudoku technique name, coach card heading. Almost always left as \"XY-Wing\" — a term of art, and the letters are the digit names in the pattern, not English words.",
    "technique.simpleColoring.name": "Sudoku technique name, coach card heading: colour one digit's forced pairs in two alternating colours. Use this language's established term; \"colouring\" is the English one.",

    # First-week tips (PRD-34). Three for the lifetime of the install, so each
    # one is a player's only instruction on that feature. One sentence, calm,
    # never an imperative to go and do it now.
    "tip.undo": "One of three lifetime tips, shown once in a chip. Explains that undo exists and that nothing can be ruined. Two short sentences; reassuring, never scolding.",
    "tip.pencil": "One of three lifetime tips, shown once in a chip. Explains that the pencil toggle turns entry into corner notes. \"the rose\" is Nine's circular digit picker — keep the metaphor if the language has one, describe it plainly if not.",
    "tip.highlight": "One of three lifetime tips, shown once in a chip. Explains that tapping a placed digit highlights every other copy of it on the board.",

    # --- Task 5: the App layer. Every surface a player touches, in the
    # same key scheme, so a translator meets one vocabulary rather than
    # eleven view files' worth of habits.
    "status.composing": "Status word shown while a puzzle is being generated — on the shelf cards, in place of the board, and as a chip over a board being replaced. One word plus an ellipsis; it appears next to a sparkles glyph. Keep it short.",
    "status.solved": "Status word on a shelf card and on the chip that appears after the last digit lands: this board is finished. A word, not a sentence, and capitalised — `archive.day.solved` is the lowercase fragment version and `board.announce.solved` the spoken sentence.",
    "shelf.today.title": "Title of the shelf card that opens the day's shared puzzle, and the heading of the same explanation in the tutorial's last beat. One word.",
    "shelf.today.oneADay": "Status line on the Today card before the day's puzzle has been opened: there is exactly one new board per day. Three words at most — it sits beside a sun glyph.",
    "shelf.today.continueProgress": "Status line on the Today card when the day's board is started but unfinished. %1$@ is a progress phrase already formatted (\"41%\", \"Just started\"). The separator is a middle dot.",
    "shelf.continue.title": "Title of the shelf card that resumes the free-play board in progress. A verb in the imperative — what tapping it does.",
    "shelf.continue.caption": "Caption under the Continue card. %1$@ is a difficulty name (\"Steady\"), %2$@ a progress phrase (\"41%\"). Punctuation only — reorder if this language reads the other way round.",
    "shelf.continue.captionMore": "Caption under the Continue card when other unfinished boards exist too. %1$@ is a difficulty name, %2$@ a progress phrase, %3$lld a count of OTHER boards (1 or more). PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",
    "shelf.continue.discard": "VoiceOver label of the ✕ on the Continue card. Throws the saved board away; it is not a close button.",
    "shelf.points.chip": "The points capsule in the shelf header. %1$lld is a lifetime points total. Very short — it shares a row with the title and the streak chip; abbreviate the unit the way this language does on a scoreboard. PLURAL: 'pt' at one, 'pts' otherwise.",
    "shelf.boards.seeAll": "The quiet link beside the Boards heading on the shelf; opens the full board list. Two words at most.",
    "shelf.boards.seeAllLabel": "VoiceOver label for the \"See all\" link, which is too terse to speak on its own.",
    "shelf.boards.subtitleEmpty": "Subtitle of the Apple TV shelf's Boards tile when nothing is in progress — the three things the sheet is for. A list of verbs, not a sentence.",
    "shelf.boards.subtitleCount": "Subtitle of the Apple TV shelf's Boards tile. %1$lld is how many boards are started but unfinished, always 1 or more. PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",
    "shelf.history.subtitle": "Subtitle of the Apple TV shelf's History tile — what the sheet behind it holds. A fragment, not a sentence.",
    "shelf.replays.subtitle": "Subtitle of the Apple TV shelf's Replays tile, which opens an ambient screen replaying the player's own finished boards. \"Retraced\" means drawn again, following the same path. A fragment, not a sentence.",
    "shelf.difficulty.label": "VoiceOver label of a free-play difficulty card. %1$@ is the band's name (\"Nocturne\"), %2$@ its one-line blurb. Punctuation only.",
    "shelf.daily.date": "How a past day's board is named in a list of boards. %1$@ is a date (\"12 Jul 2026\"). \"Daily\" here is a noun — the day's shared puzzle — not an adverb.",
    "shelf.archive.hint": "VoiceOver hint on the calendar glyph in the corner of the Today card: what opening the archive gets you. A fragment, as VoiceOver hints are.",
    "shelf.grace.title": "Heading of the card shown the morning after a missed day was bridged (PRD-13). Reassurance, past tense: the run survived. Never mentions a limit or a count.",
    "shelf.grace.body": "Body of the streak-held card. Says the missed day cost nothing, without framing rest as something spent — there is no allowance and no counter.",
    "shelf.grace.hint": "VoiceOver hint on the streak-held card: tapping it only makes it go away. A verb phrase in the third person, as VoiceOver hints are.",
    "shelf.grace.label": "VoiceOver label of the streak-held card, joining its heading and its body into one spoken sentence. %1$@ is `shelf.grace.title`, %2$@ `shelf.grace.body`.",
    "shelf.ambient.empty": "The ambient chip beside the board when the player has neither points nor a streak. Flat and factual, never an encouragement to go and play.",
    "game.control.home": "VoiceOver label of the chevron that saves the board and returns to the shelf, and the text of the same chip on the Mac. \"Home\" is the app's start screen, not a house.",
    "game.control.hint": "VoiceOver label of the lightbulb button, which shows one coaching card. A noun.",
    "game.control.pencil": "VoiceOver label of the pencil button, which switches digit entry to small corner notes. \"Pencil marks\" is the sudoku term for those notes.",
    "game.control.autoNotes": "VoiceOver label of the wand button, which fills every empty square's pencil marks automatically.",
    "game.control.undo": "VoiceOver label of the undo button. A verb in the imperative.",
    "game.control.settings": "VoiceOver label of the gear button, which opens this app's own settings sheet. Use the same word the system Settings app uses in this language.",
    "game.chip.pencil": "A chip beside the board saying that pencil mode is on, so digits become corner notes. One word — it is a status, not a button.",
    "game.chip.archive": "A chip beside the board saying this is a past day's puzzle rather than today's. %1$@ is a short date (\"12 Jul\"). \"Archive\" is the noun — the record of past days — and its presence is what tells the player their streak is not at stake.",
    "game.drawer.show": "VoiceOver action that opens the pull-down statistics panel over the board.",
    "game.drawer.hide": "VoiceOver action that closes the pull-down statistics panel.",
    "game.autoNotes.chip": "A chip confirming what the wand button just did. %1$lld is how many pencil marks were written, always 1 or more. \"Candidates\" is the sudoku term for the digits a square could still take. PLURAL: 'candidate' at one, 'candidates' otherwise.",
    "game.undo.placement": "A chip confirming an undo took a placed digit back. %1$lld is that digit. Past tense, and the digit is the object of the verb.",
    "game.undo.restored": "A chip confirming an undo put back a digit that had been erased. %1$lld is that digit.",
    "game.undo.note": "A chip confirming an undo took a pencil mark back. %1$lld is that digit; \"note\" is the small corner mark, not a message.",
    "game.undo.autoNotes": "A chip confirming an undo removed the whole batch of pencil marks the wand wrote. One action, however many marks it made.",
    "game.completion.streak": "The chip shown after the day's puzzle is finished. %1$lld is a number of consecutive days, always 1 or more. The separator is a middle dot. PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",
    "game.another.title": "A chip offered after a free-play solve: start a fresh board at the same difficulty. One word, and deliberately not \"Again\" — it is a new board, not a replay.",
    "game.another.label": "VoiceOver label for the \"Another\" chip, which is too terse to speak. %1$@ is a difficulty name.",
    "game.mac.homeLabel": "VoiceOver label of the Mac's Home chip. \"Home\" is the app's start screen.",
    "game.mac.exitDesk": "VoiceOver label of the glyph that restores the full Mac window from the small board-only pane. \"Desk mode\" is that pane's name.",
    "game.tv.padHint": "A chip flashed once when a game controller takes over on Apple TV. The three names are controller buttons — keep whatever this language's controller documentation calls them. Middle dots separate the three.",
    "game.tv.disconnected": "A chip shown when a game controller drops mid-game and the Siri Remote takes over. A statement of fact, not an error.",
    "game.tv.remoteHint": "A chip flashed once per launch on the Apple TV board. \"Click\" is the Siri Remote's clickpad press; ▶︎ is the play/pause key and stays as the glyph.",
    "board.rotor.empty": "Name of a VoiceOver rotor that jumps between squares with nothing in them. A plural noun phrase, as rotor names are.",
    "board.rotor.notes": "Name of a VoiceOver rotor that jumps between empty squares carrying pencil marks.",
    "board.rotor.errors": "Name of a VoiceOver rotor that jumps between placed digits that contradict the solution. Only ever offered when the player has mistake-marking switched on.",
    "board.action.place": "A VoiceOver custom action on a square, and the label of one petal of the digit ring. %1$lld is the digit 1-9. A verb in the imperative — this writes a real digit, not a note.",
    "board.action.note": "A VoiceOver custom action on a square, and the label of one petal of the pencil ring. %1$lld is the digit 1-9. \"Note\" is a verb here: write this as a small corner mark rather than a real digit.",
    "board.action.erase": "A VoiceOver custom action on a square: clear the digit in this square. A verb in the imperative. The rose itself has no erase petal of its own — see board.rose.eraseDigit for how a filled cell's own digit petal offers the same action.",
    "board.rose.digit": "VoiceOver label of the ring of nine petals that appears over a square. \"Rose\" is Nine's name for that circular picker — keep the flower metaphor if this language has one, or describe it plainly.",
    "board.rose.eraseDigit": "VoiceOver label of one petal of the digit ring — the petal whose digit is already placed in this square, or already pencilled in when the ring is writing pencil marks. %1$lld is the digit 1-9. A verb in the imperative, so it reads as a set with board.action.place and board.action.note, which label the other petals: activating this one clears the digit instead of writing it again. It says only that the digit is already there, never that it is wrong — do not translate it as a warning or an error.",
    "board.rose.note": "VoiceOver label of the same ring when it writes pencil marks rather than real digits.",
    "board.stats.digitLeft": "VoiceOver label of one digit in the statistics panel. %1$lld is the digit 1-9, %2$lld how many of it are still unplaced (1-8). PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",
    "board.stats.digitDone": "VoiceOver label of one digit in the statistics panel when all nine of it are placed. %1$lld is the digit 1-9.",
    "board.stats.time": "Caption under the elapsed-time tile in the board statistics panel. Lowercase, one word — these four captions are a row and read as a set.",
    "board.stats.pace": "Caption under the seconds-per-digit tile in the board statistics panel. Lowercase, one word.",
    "board.stats.notes": "Caption under the tile counting pencil marks on this board. Lowercase, plural.",
    "board.stats.undos": "Caption under the tile counting how many moves have been taken back on this board. Lowercase, plural.",
    "board.stats.errors": "Caption under the tile counting wrong digits placed on this board — matches debrief.errors' subject, not board.rotor.errors' wording (that one names a VoiceOver rotor, not a tile). Lowercase, plural. Only shown once at least one digit is wrong, same as board.stats.hints below.",
    "board.stats.hints": "Caption under the tile counting coaching hints spent on this board. Lowercase, plural. Only shown once at least one has been used.",
    "board.stats.paceSeconds": "The pace tile's value in seconds. %1$lld is a whole number of seconds; the trailing letter is the unit abbreviation — use whatever this language abbreviates seconds to, with no space if that is the convention. PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",
    "board.progress.untouched": "The words beside a saved board that has not been played at all. Said instead of \"0%\", which reads as failure rather than as a fresh start.",
    "board.progress.begun": "The words beside a saved board with only a digit or two in it, where a percentage would be a false precision.",
    "board.progress.full": "The words beside a board with every square filled in. An adjective, not \"Solved\" — a full board may still be wrong.",
    "coach.action.placeIt": "The coaching card's button when the hint resolves a square: writes that digit in. A verb in the imperative, two words.",
    "coach.action.markIt": "The coaching card's button when the hint only eliminates candidates: writes the pencil marks that follow. A verb in the imperative.",
    "coach.card.label": "VoiceOver label of the coaching card, joining its heading and its sentence into one utterance. %1$@ is a technique name or a card heading, %2$@ the explanation. Punctuation only, and it is yours: replace \". \" with \"。\" or with whatever ends a sentence here, and reorder the two if that is how this language says it.",
    "prefs.section.play": "Heading over the settings rows about how the board behaves. A noun.",
    "prefs.section.feel": "Heading over the settings rows about haptics — what the board does to your hands. A noun.",
    "prefs.section.appearance": "Heading over the theme, accent and icon settings. A noun.",
    "prefs.section.layout": "Heading over the settings that decide where things sit on the screen. A noun.",
    "prefs.timer.title": "Settings row: whether the elapsed-time chip is shown while playing.",
    "prefs.timer.shown": "The Timer row's value when the clock is visible. An adjective, paired with `prefs.timer.hidden`.",
    "prefs.timer.hidden": "The Timer row's value when the clock is not visible.",
    "prefs.errorHighlight.title": "Settings row: whether digits contradicting the solution are marked on the board. Sentence case, not Title Case — these rows are a list, not menu items.",
    "prefs.numberHighlight.title": "Settings row: whether tapping a placed digit lights up every other copy of it.",
    "prefs.resume.title": "Settings row: whether opening the app returns to the board in progress rather than to the shelf.",
    "prefs.haptics.title": "Settings row: whether the phone taps back as digits land.",
    "prefs.controllerHaptics.title": "Settings row: whether a game controller rumbles as digits land.",
    "prefs.controls.title": "Settings row: which edge of the screen the row of buttons sits on.",
    "prefs.controls.bottom": "The Controls row's value: the buttons sit along the bottom edge.",
    "prefs.controls.top": "The Controls row's value: the buttons sit along the top edge.",
    "prefs.boardPosition.title": "Settings row: whether the grid parks against the top or bottom edge, or sits centred.",
    "prefs.ambient.title": "Settings row: the optional dim chip parked beside the board — a clock, or points and streak. \"Ambient\" as in unobtrusive, always-on.",
    "prefs.toggle.on": "The value of a settings row that is switched on. Also the Ambient display row's value when a chip is shown.",
    "prefs.toggle.off": "The value of a settings row that is switched off. Also the Ambient display row's value when no chip is shown.",
    "prefs.accent.title": "Heading over the row of colour swatches that tints the app. \"Accent\" is the single highlight colour, not a decoration on a letter.",
    "prefs.theme.title": "Heading over the row of swatches that sets the whole app's ground and text colours.",
    "prefs.appIcon.title": "Heading over the row of swatches that changes Nine's icon on the Home Screen.",
    "prefs.newGame.title": "Heading over the four difficulty buttons at the foot of the Apple TV settings sheet — the couch's route to a fresh board.",
    "prefs.newGame.note": "Reassurance under the Apple TV settings sheet's new-game buttons: starting one destroys nothing. The \"shelf\" is the app's start screen.",
    "sheet.dismiss.remote": "Footer of every Apple TV sheet, saying how to leave it. \"Back\" is the Siri Remote's Back button — use the name printed in this language's Apple TV documentation.",
    "sheet.dismiss.touch": "Footer of every iPhone and iPad sheet, saying how to leave it: touch anywhere outside the panel.",
    "accent.glacier": "Name of an accent colour: a pale, cold blue. Colour names are shown beside the swatch and read by VoiceOver — evocative rather than literal, and one word.",
    "accent.ember": "Name of an accent colour: the orange of a dying coal. One word.",
    "accent.meadow": "Name of an accent colour: a fresh grass green. One word.",
    "accent.lilac": "Name of an accent colour: a pale purple. One word.",
    "accent.crimson": "Name of an accent colour: a deep red. One word.",
    "accent.gold": "Name of an accent colour: a warm yellow. One word.",
    "accent.teal": "Name of an accent colour: a blue-green. One word.",
    "accent.magenta": "Name of an accent colour: a vivid pink-purple. One word.",
    "accent.moss": "Name of an accent colour: a muted, darker green. Distinct from Meadow, which is brighter. One word.",
    "accent.orchid": "Name of an accent colour: a soft pink-mauve. Distinct from Lilac and Magenta. One word.",
    "theme.auto": "Name of the theme that follows the system's light or dark setting rather than pinning one. Short — it sits beside a swatch.",
    "theme.dark": "Name of the dark theme: near-black, the app's default and its identity. A noun — empty space — not the verb \"to void\".",
    "theme.light": "Name of the light theme: an off-white page. The material, not a document.",
    "theme.camel": "Name of a warm, sandy light theme — the colour, not the animal, if this language separates them.",
    "theme.blueprint": "Name of a deep blue theme, after the architectural drawing.",
    "theme.forest": "Name of a dark green theme.",
    "theme.ember": "Name of a dark rust-red theme, after a dying coal. Same word as the accent of the same name — keep them identical.",
    "theme.tide": "Name of a dark blue-green theme, after the sea.",
    "theme.mono": "Name of a neutral grey theme with no colour in it at all. Short for monochrome; keep it abbreviated if this language does.",
    "boardAnchor.top": "The Board position row's value: the grid sits against the top of the screen.",
    "boardAnchor.center": "The Board position row's value: the grid sits in the middle of the screen, with free space above and below.",
    "boardAnchor.bottom": "The Board position row's value: the grid sits against the bottom of the screen.",
    "ambientSlot.clock": "The Ambient display row's value: the dim chip beside the board shows the time of day.",
    "ambientSlot.streak": "The Ambient display row's value: the dim chip beside the board shows points and the daily streak.",
    "appIcon.original": "Name of the Home Screen icon Nine ships with. An adjective — the first one, not \"authentic\".",
    "appIcon.ember": "Name of an alternate Home Screen icon on the Ember ground. Same word as the theme and accent of that name — keep all three identical.",
    "appIcon.tide": "Name of an alternate Home Screen icon on the Tide ground. Keep identical to the theme of that name.",
    "appIcon.mono": "Name of an alternate Home Screen icon on the Mono ground. Keep identical to the theme of that name.",
    "difficulty.gentle.blurb": "One-line blurb under the Gentle difficulty card: the two sudoku techniques its boards need. Both are terms of art — use this language's puzzle vocabulary. Very short; it sits under a 64pt tile.",
    "difficulty.steady.blurb": "One-line blurb under the Steady difficulty card, naming the techniques its boards need. Terms of art. Very short.",
    "difficulty.sharp.blurb": "One-line blurb under the Sharp difficulty card. \"X-wing\" is a sudoku term of art, almost always left untranslated. Very short.",
    "difficulty.nocturne.blurb": "One-line blurb under the Nocturne difficulty card. \"Clues\" are the digits the puzzle supplies; Nocturne gives fewer of them than any other band. Very short.",
    "difficulty.gentle.explainer": "The longer explanation of the Gentle band, in the difficulty guide. \"A single\" is the sudoku term for a square with only one possibility. Two short sentences — the guide has no room to scroll.",
    "difficulty.steady.explainer": "The longer explanation of the Steady band. \"Naked pair\" and \"box-line elimination\" are sudoku terms of art. Two short sentences.",
    "difficulty.sharp.explainer": "The longer explanation of the Sharp band. \"X-wing\" is a term of art. Two short sentences.",
    "difficulty.nocturne.explainer": "The longer explanation of the Nocturne band. \"Sharp\" here is the name of the band below it — translate it the same way as `difficulty.sharp.title`. \"Givens\" are the digits the puzzle supplies. One sentence, kept to the length of its three siblings so the guide still fits one screen.",
    "difficulty.composeCaption": "Shown in place of a difficulty card's blurb while that band's board is being generated, which can take seconds. %1$@ is the band's name. An honest apology for a wait, not a progress report.",
    "tutorial.title": "Title of the tutorial, and of the two shelf cards that open it. Sentence case.",
    "tutorial.titlePad": "Title of the game-controller version of the tutorial on Apple TV. The dash separates the subject; use this language's punctuation.",
    "tutorial.close": "VoiceOver label of the ✕ that leaves the tutorial.",
    "tutorial.button.tryIt": "Button that leaves the tutorial's first beat and starts the playable part. A verb in the imperative, two words.",
    "tutorial.button.done": "Button that closes the tutorial on its last beat. Use the same word this language's system UI uses to finish a sheet.",
    "tutorial.button.skipStep": "The escape hatch under a tutorial beat: move on without doing the exercise.",
    "tutorial.nice": "A chip shown for a moment when the player completes a tutorial exercise. Warm and brief — praise, not a score. One word.",
    "tutorial.goal.title": "Heading of the tutorial's first beat, which explains what solving a sudoku means.",
    "tutorial.goal.body": "The rules of sudoku in one sentence, plus what this practice board is. \"Box\" is the 3×3 block — use this language's sudoku vocabulary. The dash is an em dash; the range is an en dash.",
    "tutorial.place.title": "Heading of the tutorial beat that teaches digit entry. A verb in the imperative.",
    "tutorial.pencil.title": "Heading of the tutorial beat that teaches corner notes. \"Pencil notes\" is the sudoku term for the small marks.",
    "tutorial.highlight.title": "Heading of the tutorial beat that teaches the same-number highlight. The numerals are examples and stay as numerals.",
    "tutorial.difficulty.title": "Heading of the tutorial's last beat, which explains the four difficulty bands. A wry idiom for \"choose how hard you want it\" — replace it with an equivalent idiom rather than translating the words.",
    "tutorial.difficulty.body": "The promise behind every board Nine composes, plus how points work. \"Provably\" is load-bearing: the app verifies it, so this is a claim of fact.",
    "tutorial.today.body": "What the daily puzzle is, in the tutorial's last beat. %1$@ is a difficulty name — the band the daily always composes at. \"Shared\" means every player gets the same board that day.",
    "tutorial.digit.placeholder": "Stands in for a numeral in the tutorial's instructions before the practice board has finished generating. Lowercase, mid-sentence.",
    "tutorial.pad.beginBody": "The tutorial's first beat on a game controller: the shared explanation followed by the button to press. %1$@ is `tutorial.goal.body`. \"Cross\" is the controller button — use the name this language's controller documentation gives it.",
    "tutorial.pad.readyBody": "The tutorial's last beat on a game controller. %1$@ is `tutorial.difficulty.body`. \"Cross\" is a controller button name.",
    "tutorial.pad.tryIt": "A chip on the controller tutorial's first beat, naming the button that starts the playable part. \"Cross\" is a controller button name.",
    "tutorial.pad.finish": "A chip on the controller tutorial's last beat: pressing this button closes the tutorial. \"Cross\" is a controller button name.",
    "tutorial.pad.skip": "A chip offering the escape hatch on Apple TV. \"Menu\" is the Siri Remote's back button — use the name printed in this language's Apple TV documentation.",
    "grammar.remote.placeVerb": "The Siri Remote's verb for entering a digit: a quick directional swipe. A verb in the bare infinitive, used mid-sentence and lowercase.",
    "grammar.remote.pencilVerb": "The Siri Remote's verb for entering a pencil note: press and hold the clickpad. Lowercase, hyphenated as one action.",
    "grammar.remote.highlightVerb": "The Siri Remote's verb for lighting up every copy of a digit: leave the selection sitting on it. Lowercase, mid-sentence.",
    "grammar.remote.advanceHint": "One-line reminder of the Siri Remote's controls, under a tutorial beat. \"Rose\" is Nine's circular digit picker; ▶︎ is the play/pause key and stays as the glyph. Middle dots separate the three.",
    "grammar.remote.placeDetail": "The Siri Remote's full instruction for placing a digit. %1$@ is the target numeral. \"Rose\" is the circular picker and \"petal\" one of its nine segments — keep the flower metaphor if this language has one.",
    "grammar.remote.pencilDetail": "The Siri Remote's full instruction for pencil notes. \"Rose\" is the circular picker.",
    "grammar.remote.highlightDetail": "The Siri Remote's full instruction for the same-number highlight.",
    "grammar.touch.placeVerb": "The touch verb for entering a digit. \"Petal\" is one of the nine segments of Nine's circular picker. Lowercase, mid-sentence.",
    "grammar.touch.pencilVerb": "The touch name for the button that switches digit entry to corner notes. A noun phrase, lowercase.",
    "grammar.touch.highlightVerb": "The touch verb for lighting up every copy of a digit. Lowercase, mid-sentence.",
    "grammar.touch.advanceHint": "One-line reminder of the touch controls, under a tutorial beat. \"Rose\" is the circular picker, \"petal\" one of its segments.",
    "grammar.touch.placeDetail": "The touch instruction for placing a digit. %1$@ is the target numeral. The parenthesis explains that the ring is laid out like a 3×3 number pad.",
    "grammar.touch.pencilDetail": "The touch instruction for pencil notes. \"Note\" is a verb in the second sentence.",
    "grammar.touch.highlightDetail": "The touch instruction for the same-number highlight.",
    "grammar.keyboard.placeVerb": "The Mac keyboard's verb for entering a digit. Lowercase, mid-sentence.",
    "grammar.keyboard.pencilVerb": "The Mac keyboard's verb for entering a pencil note: hold Shift while typing the digit. \"Shift\" is the key name and keeps its capital.",
    "grammar.keyboard.highlightVerb": "The Mac keyboard's key for lighting up every copy of a digit. A key name — use whatever this language prints on the space bar.",
    "grammar.keyboard.advanceHint": "One-line reminder of the Mac keyboard controls, under a tutorial beat. ⌘Z is a keyboard shortcut and stays as the glyphs.",
    "grammar.keyboard.placeDetail": "The Mac keyboard instruction for placing a digit. %1$@ is the target numeral. \"Rose\" is the circular picker the other platforms use; the point is that the Mac needs no picker at all.",
    "grammar.keyboard.pencilDetail": "The Mac keyboard instruction for pencil notes. \"Shift\" and \"P\" are key names; \"sticky\" means the mode stays on until switched off.",
    "grammar.keyboard.highlightDetail": "The Mac keyboard instruction for the same-number highlight. \"Space\" is a key name.",
    "grammar.pad.placeVerb": "The game controller's verb for entering a digit. Lowercase, mid-sentence.",
    "grammar.pad.pencilVerb": "The game controller's button for pencil notes. A button name — use whatever this language's controller documentation calls it.",
    "grammar.pad.highlightVerb": "The game controller's button for the same-number highlight. A button name.",
    "grammar.pad.advanceHint": "One-line reminder of the game controller's controls, under a tutorial beat. \"Circle\" is a button name.",
    "grammar.pad.placeDetail": "The game controller's full instruction for placing a digit. %1$@ is the target numeral. \"Cross\" and \"R3\" are button names; \"rose\" is the circular picker and \"petals\" its nine segments.",
    "grammar.pad.pencilDetail": "The game controller's instruction for pencil notes. \"Square\" is a button name; \"sticky\" means the mode stays on until switched off.",
    "grammar.pad.highlightDetail": "The game controller's instruction for the same-number highlight and the peek. \"Triangle\" and \"L2\" are button names.",
    "legend.remote.swipe.gesture": "Left column of the Siri Remote control legend: the gesture. A noun.",
    "legend.remote.swipe.action": "Right column of the Siri Remote control legend: what a swipe does.",
    "legend.remote.click.gesture": "Left column of the Siri Remote control legend: pressing the clickpad. A noun.",
    "legend.remote.click.action": "What a clickpad press does. \"Rose\" is Nine's circular digit picker.",
    "legend.remote.rose.gesture": "Left column of the Siri Remote control legend: two gestures in sequence, while the picker is open.",
    "legend.remote.rose.action": "What swiping and clicking inside the picker does: show the digit before committing it.",
    "legend.remote.flick.gesture": "Left column of the Siri Remote control legend. The parenthesis names the remote generation that can report diagonal directions.",
    "legend.remote.flick.action": "What a flick does: writes the digit with no confirmation step.",
    "legend.remote.playPause.gesture": "Left column of the Siri Remote control legend: the play/pause key. Stays as the glyph in every language.",
    "legend.remote.playPause.action": "What the play/pause key does. A verb in the imperative.",
    "legend.remote.holdPlayPause.gesture": "Left column of the Siri Remote control legend: press and hold the play/pause key. The glyph stays.",
    "legend.remote.holdPlayPause.action": "What holding play/pause does: opens this app's settings sheet.",
    "legend.remote.back.gesture": "Left column of the Siri Remote control legend: the Back button. Use the name printed in this language's Apple TV documentation.",
    "legend.remote.back.action": "What Back does: keeps the board and returns to the start screen. Two nouns joined by a plus sign — a fragment, not a sentence.",
    "legend.touch.tapCell.gesture": "Left column of the touch control legend. \"Cell\" is one square of the grid.",
    "legend.touch.tapCell.action": "What tapping a square does. \"Rose\" is Nine's circular digit picker.",
    "legend.touch.tapPetal.gesture": "Left column of the touch control legend. \"Petal\" is one of the picker's nine segments.",
    "legend.touch.tapPetal.action": "What tapping a petal does.",
    "legend.touch.flick.gesture": "Left column of the touch control legend: a quick directional drag inside the open picker.",
    "legend.touch.flick.action": "What a flick does: writes the digit with no confirmation step.",
    "legend.touch.highlight.gesture": "Left column of the touch control legend: touching a square that already holds a digit.",
    "legend.touch.highlight.action": "What tapping a placed digit does: every other copy of that digit on the board is highlighted.",
    "legend.touch.pencil.gesture": "Left column of the touch control legend: the button that switches digit entry to corner notes.",
    "legend.touch.pencil.action": "What the pencil toggle does. A fragment, not a sentence.",
    "legend.touch.undo.gesture": "Left column of the touch control legend.",
    "legend.touch.undo.action": "What the undo button does.",
    "legend.keyboard.arrows.gesture": "Left column of the Mac keyboard legend. A key name.",
    "legend.keyboard.arrows.action": "What the arrow keys do. The parenthesis says the selection reappears on the opposite side rather than stopping.",
    "legend.keyboard.digits.gesture": "Left column of the Mac keyboard legend: the number keys. Numerals joined by an en dash.",
    "legend.keyboard.digits.action": "What a number key does.",
    "legend.keyboard.pencil.gesture": "Left column of the Mac keyboard legend: Shift with a number, or the P key. The glyphs and letters stay.",
    "legend.keyboard.pencil.action": "What those keys do: one note, or a mode that stays on. \"Pencil\" is a verb in the first half. Middle dot separates the two.",
    "legend.keyboard.highlight.gesture": "Left column of the Mac keyboard legend: the space bar. Use whatever this language prints on that key.",
    "legend.keyboard.highlight.action": "What the space bar does: highlights every copy of the selected digit.",
    "legend.keyboard.tab.gesture": "Left column of the Mac keyboard legend: Tab, or Shift with Tab. Key names.",
    "legend.keyboard.tab.action": "What Tab does: jumps the selection to the next square with nothing in it.",
    "legend.keyboard.undo.gesture": "Left column of the Mac keyboard legend: the standard undo shortcut. Stays as the glyphs.",
    "legend.keyboard.undo.action": "What ⌘Z does. A verb in the imperative.",
    "legend.pad.move.gesture": "Left column of the game controller legend. Both are controller part names.",
    "legend.pad.move.action": "What the left stick does.",
    "legend.pad.place.gesture": "Left column of the game controller legend: a quick deflection of the right stick.",
    "legend.pad.place.action": "What a right-stick flick does. \"R3\" is the name of the right stick's click, which places a 5.",
    "legend.pad.cross.gesture": "Left column of the game controller legend: a face button. Use the name this language's controller documentation gives it.",
    "legend.pad.cross.action": "What Cross does. \"Rose\" is the circular digit picker, \"petal\" one of its segments.",
    "legend.pad.circle.gesture": "Left column of the game controller legend: a face button, pressed or held.",
    "legend.pad.circle.action": "What Circle does, pressed and held.",
    "legend.pad.square.gesture": "Left column of the game controller legend: a face button name.",
    "legend.pad.square.action": "What Square does: switches to corner notes and stays there until pressed again.",
    "legend.pad.triangle.gesture": "Left column of the game controller legend: a face button name.",
    "legend.pad.triangle.action": "What Triangle does: highlights every copy of the selected digit.",
    "legend.pad.peek.gesture": "Left column of the game controller legend: either trigger, held. Button names.",
    "legend.pad.peek.action": "What holding a trigger does: everything except one digit fades while held. \"Peek\" is a noun here.",
    "legend.pad.create.gesture": "Left column of the game controller legend: the button Sony calls Create and Microsoft calls View. Use this language's name for it.",
    "legend.pad.create.action": "What that button does: opens this app's settings sheet.",
    "legend.pad.menu.gesture": "Left column of the game controller legend: the button that leaves a game on Apple TV.",
    "legend.pad.menu.action": "What Menu does: keeps the board and returns to the start screen. A fragment.",
    "legend.pad.controller.gesture": "Left column of the first-run legend on Apple TV, shown only when a game controller is connected. A noun.",
    "legend.pad.controller.action": "The controller row of the first-run legend: nothing has to be set up, and the controller's own tutorial appears on the board.",
    "help.tv.tagline": "The tagline under Nine's name on the Apple TV first-run card. \"Couch\" means played from the sofa, on a television — the whole app's posture in one word. A fragment with a full stop.",
    "firstrun.welcome.title": "Heading of the card shown once, on the very first launch. \"Nine\" is the app's name and stays untranslated.",
    "firstrun.welcome.tagline": "Tagline under the welcome heading. \"Couch\" means played from the sofa; the second half says it is on every device the player owns.",
    "firstrun.ledger.daily": "One line of the welcome card's list of what the purchase included. A fragment, no full stop — the six lines read as a list.",
    "firstrun.ledger.proof": "One line of the welcome card's list. \"Proved\" is literal: the app verifies every board is solvable without guessing. A fragment, no full stop. It used to open with a count of difficulty bands and said \"Three\" while there were four, then six — copy that counts something the app can grow does not survive the app growing, so the count is gone rather than corrected.",
    "firstrun.ledger.stats": "One line of the welcome card's list. \"Honestly\" means nothing is inflated or gamified. A fragment, no full stop.",
    "firstrun.ledger.themes": "One line of the welcome card's list. %1$lld is how many colour themes ship, %2$lld how many accent colours — both counted from the code, so the sentence cannot go stale. \"Yours\" means unlocked, with nothing to buy. PLURAL: two independent counts, one per number — inflect 'theme' and 'accent' separately.",
    "firstrun.ledger.sync": "One line of the welcome card's list, about iCloud sync. A fragment, no full stop.",
    "firstrun.ledger.covenant": "One line of the welcome card's list, and the promise the whole app is built on. A fragment, no full stop.",
    "firstrun.onePurchase": "The line under the welcome card's list: one price covers every platform. The device names are Apple's and stay as they are printed in this language.",
    "firstrun.begin": "The welcome card's only button. A verb in the imperative, one word.",
    "firstrun.beat.title": "Heading of the playable first-launch lesson: one square, one digit.",
    "firstrun.beat.skip": "The escape hatch in the corner of the first-launch lesson. A verb in the imperative, one word.",
    "firstrun.beat.prompt": "The instruction in the first-launch lesson. %1$lld is the digit the empty square wants. \"Flick\" is a short directional drag.",
    "firstrun.beat.detail": "The longer instruction in the first-launch lesson. %1$lld and %2$lld are the SAME digit, written twice — if you reorder the sentence, move both. \"Rose\" is Nine's circular digit picker.",
    "firstrun.beat.hint": "The quiet line under the first-launch lesson, promising it is short and escapable.",
    "firstrun.beat.doneTitle": "What replaces the instruction once the player places the right digit: the lesson is over because there is nothing more to it. Light, not congratulatory.",
    "firstrun.beat.doneDetail": "The second half of the first-launch lesson's ending. \"The shelf\" is the app's start screen.",
    "history.title": "Title of the sheet, window and shelf card holding every solved board. A noun — the record, not the academic subject.",
    "history.close": "VoiceOver label of the ✕ that leaves the History sheet on Apple TV.",
    "history.empty": "What the History sheet says before there is enough history to chart. Explains what will appear, without urging the player to go and play.",
    "history.stat.bestTime": "Caption under the fastest-solve time. Lowercase — the three totals read as a row.",
    "history.stat.points": "Caption under the lifetime points total. Lowercase — the three totals read as a row.",
    "history.stat.solved": "Caption under the count of boards finished. Lowercase, and a past participle used as a noun — \"how many solved\".",
    "history.stat.bestStreak": "Caption under the longest run of consecutive daily solves ever reached. Lowercase.",
    "history.section.heat": "Heading over a grid of one square per day for the last twelve weeks, shaded by how much was solved that day.",
    "history.section.avgVsBest": "Heading over a chart comparing each difficulty's average solve time with its fastest. \"vs.\" is an abbreviation — spell it out if this language has no equivalent.",
    "history.section.trend": "Heading over a line chart of the last twenty solve times.",
    "history.section.table": "Heading over the weekly league section of the History sheet: twenty players and how their week is going. \"Table\" as in a league table / standings, NOT a piece of furniture and NOT a grid of data. Capitalised as a name — it is what this feature is called.",
    "history.trend.faster": "Shown beside the trend heading when recent solves are quicker than older ones. The triangle is a downward arrow and stays as the glyph.",
    "history.gameCenter.title": "The row that opens Apple's Game Center dashboard. A product name — use Apple's own name for it in this language.",
    "history.gameCenter.in": "Subtitle of the Game Center row when the player is signed in: what is behind it. Both are Game Center's own terms.",
    "history.gameCenter.out": "Subtitle of the Game Center row when the player is signed out. \"Settings\" is the system Settings app, not Nine's own sheet.",
    "history.recent.title": "Heading over the last fifteen solved boards. An adjective used as a heading.",
    "history.recent.daily": "How a solved daily puzzle is named in the recent list. %1$@ is a difficulty name. \"Daily\" is a noun here — the day's shared puzzle.",
    "boards.title": "Title of the sheet listing every board the app is holding, and of the shelf cards that open it. Plural noun.",
    "boards.close": "VoiceOver label of the ✕ that leaves the Boards sheet on Apple TV.",
    "boards.empty": "What the Boards sheet says when nothing has been played yet. \"Archive\" is a verb: set aside without deleting.",
    "boards.fresh.title": "Heading over the four difficulty buttons at the top of the Boards sheet — the way to start a new game from here.",
    "boards.fresh.label": "VoiceOver label of one of those buttons. %1$@ is a difficulty name.",
    "boards.fresh.note": "Reassurance under the Boards sheet's new-game buttons: starting one destroys nothing.",
    "boards.section.inProgress": "Heading over the boards that are started but unfinished.",
    "boards.section.played": "Heading over the boards that are finished or set aside.",
    "boards.row.archive": "VoiceOver label of the button that sets a board aside without deleting it. \"Archive\" is a verb.",
    "boards.row.delete": "VoiceOver label of the button that removes a board for good.",
    "boards.status.solved": "The line under a finished board in the Boards sheet. %1$@ is the date it was solved, %2$@ how long it took (m:ss). Middle dots separate the three.",
    "boards.status.archived": "The line under a board that was set aside. %1$@ is the date. \"Archived\" is a past participle.",
    "archive.title": "Title of the month grid of every past daily puzzle, and the VoiceOver label of the calendar glyph that opens it. A noun — the record of past days.",
    "archive.close": "VoiceOver label of the ✕ that leaves the archive.",
    "archive.previousMonth": "VoiceOver label of the ‹ that pages the archive grid backwards.",
    "archive.nextMonth": "VoiceOver label of the › that pages the archive grid forwards.",
    "archive.footnote": "The line under the archive grid. Says both that past boards are regenerated rather than stored, and — the part players actually want to know — that playing one cannot help or hurt the daily streak.",
    "share.button": "The chip that hands the finished board's picture to the system share sheet. A verb in the imperative, one word.",
    "share.label": "VoiceOver label of the share chip, and the share sheet's own subject line, so it reads as a phrase rather than a bare verb. \"Solve\" is a noun here: the finished board.",
    "menu.game.title": "A menu in the Mac menu bar. Title Case, as macOS menus are.",
    "menu.game.newGame": "The Mac menu item that opens a submenu of difficulties. Title Case.",
    "menu.game.today": "The Mac menu item that opens the day's shared board. Title Case.",
    "menu.game.boards": "The Mac menu item that opens the board list. The ellipsis is macOS convention for an item that opens a further window — keep it.",
    "menu.game.discard": "The Mac menu item that throws the saved board away. Title Case.",
    "menu.game.continue": "The Mac menu item that reopens whichever board the player last had in progress. One word, Title Case, and the same word as the shelf's Continue card if that language already has one.",
    "menu.board.title": "A menu in the Mac menu bar, holding the commands that act on the grid rather than on the app. Title Case. One word if the language has one; this sits between View and Window and competes for width.",
    "menu.board.why": "The Mac menu item that asks the coach to explain why one square must hold the digit it holds. Title Case. The ellipsis is deliberate — the sentence is unfinished because the digit depends on the square. Keep the question mark.",
    "menu.board.hint": "The Mac menu item that shows the next thing the coach can see. Title Case. It never places a digit, so avoid a verb that promises the move will be made.",
    "menu.board.pencil": "A checkable Mac menu item: when checked, digits go in as tentative pencil marks rather than as answers. Title Case, and a noun rather than a command, because macOS checkmarks label states.",
    "menu.board.autoNotes": "A checkable Mac menu item that keeps every square's possible digits pencilled in automatically. Title Case, a noun phrase.",
    "menu.board.erase": "The Mac menu item that clears the square under the cursor. Title Case, one word if possible.",
    "menu.board.nextEmpty": "The Mac menu item that moves the cursor to the next square with nothing in it. Title Case.",
    "menu.board.previousEmpty": "The Mac menu item that moves the cursor to the previous square with nothing in it. Title Case.",
    "menu.view.menuBar": "A checkable item in the Mac View menu that puts a small Nine glyph in the system menu bar. Title Case. \"Nine\" is the app's name and is never translated.",
    "prefs.livePresence.title": "A settings row label, sentence case. Turns on a Live Activity that shows the board you left half-finished on the iPhone Lock Screen. Use whatever this language calls the Lock Screen in system settings. It never shows a time or a countdown, so avoid words suggesting a timer.",
    "presence.header": "A short heading on the iPhone Lock Screen above a picture of today's puzzle. Sentence case, three or four words at most — the space is about 120pt wide.",
    "presence.remaining": "How many of the puzzle's 81 squares are still empty, shown once on the Lock Screen. %1$lld is the count. Describes the board, never the player: not \"you have N left\". Plural.",
    "presence.glyph.label": "Spoken by VoiceOver for the whole picture of the board — a dot per filled square, no digits. %1$lld is how many squares have something in them. One sentence. Plural.",
    "menu.edit.undo": "The Mac Edit menu's undo item, replacing the system one. Use exactly the word macOS itself uses in this language.",
    "menu.view.appearance": "The Mac View menu's theme picker label. Title Case.",
    "menu.view.showTimer": "The Mac View menu's item for the elapsed-time chip. Title Case.",
    "menu.view.errorHighlight": "The Mac View menu's item for marking digits that contradict the solution. Title Case.",
    "menu.view.numberHighlight": "The Mac View menu's item for lighting up every copy of a clicked digit. Title Case.",
    "menu.view.accent": "The Mac View menu's accent-colour picker label. Title Case.",
    "menu.view.enterDesk": "The Mac View menu's item that shrinks the window to a small board-only pane. \"Desk mode\" is that pane's name. Title Case.",
    "menu.view.exitDesk": "The Mac View menu's item that restores the full window from the small pane. Title Case.",
    "menu.view.floatDesk": "The Mac View menu's item that keeps the small pane above other windows. \"Float\" is a verb. Title Case.",
    "menu.help.howToPlay": "The Mac Help menu's item that opens the tutorial. Title Case, unlike the sentence-case `tutorial.title` used on the other platforms — macOS menu items follow the platform's own capitalisation.",

    # NineWidgets.appex (PRD-3, extracted in PRD-20 Task 6). Two things make
    # this block different from every one above it, and both belong in the
    # translator's brief:
    #
    #   • The three `*.name` / `*.description` pairs are the widget GALLERY —
    #     the only copy in Nine a player reads *before* launching the app, in a
    #     system-drawn list beside Apple's own widgets. They read as a catalogue
    #     entry, not as a sentence spoken by the app.
    #   • Everything else is drawn at Home Screen or Lock Screen size. A
    #     systemSmall widget is about 16 characters wide at body size and the
    #     Lock Screen line is one line with no wrap, so length is a constraint
    #     here in a way it is nowhere else in the app. `.minimumScaleFactor` will
    #     shrink an over-long status word rather than truncate it, which is
    #     survivable; the captions under it simply clip.
    "widget.daily.name": "Widget gallery: the name of the glanceable daily widget, shown under its preview when a player is choosing a widget to add. One word if this language has one. \"Daily\" is a noun here — the day's shared puzzle — not an adverb.",
    "widget.daily.description": "Widget gallery: the one-line description under `widget.daily.name`, saying what the widget shows. \"Streak\" is the run of consecutive days solved; \"points\" is the lifetime score. A sentence, with a full stop.",
    "widget.board.name": "Widget gallery: the name of the widget the player can actually tap digits into without opening the app.",
    "widget.board.description": "Widget gallery: the one-line description under `widget.board.name`. \"Home Screen\" is Apple's term — use the name this language's iOS uses. A sentence, with a full stop.",
    "widget.streak.name": "Widget gallery: the name of the Lock Screen accessory showing the run of consecutive days solved. A noun, one word if possible — the gallery sets it tight.",
    "widget.streak.description": "Widget gallery: the one-line description under `widget.streak.name`. \"Lock Screen\" is Apple's term — use the name this language's iOS uses. A sentence, with a full stop.",
    "widget.brand.daily": "The small header line inside three of the widgets, naming the app and the board. \"Nine\" is the app's name and stays untranslated; the separator is a middle dot; \"Daily\" is the day's shared puzzle. Very short — it sits above the status line in a systemMedium widget.",
    "widget.daily.header": "The header of the SMALLEST daily widget, where `widget.brand.daily` will not fit. The app's name is dropped and only the board is named. At most about 10 characters.",
    "widget.daily.points": "The points capsule in the medium daily widget. %1$lld is a lifetime points total. Very short — abbreviate the unit the way this language does on a scoreboard. Matches `shelf.points.chip`, which is the same capsule inside the app; keep the two the same. PLURAL: 'pt' at one, 'pts' otherwise.",
    "widget.daily.streak": "The flame line on the Lock Screen rectangular widget. %1$lld is a number of consecutive days, always 1 or more. One line, no wrap, so keep it to about 14 characters. PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",
    "widget.daily.startStreak": "What the flame chip says when the run is at zero: an invitation, not a status. A fragment, no full stop. Very short — it shares a line with a flame glyph in a systemSmall widget.",
    "widget.status.openNine": "The big status word in the daily widget on a fresh install, before the app has ever written a snapshot. An instruction: launch the app. \"Nine\" is the app's name and stays untranslated.",
    "widget.status.ready": "The big status word in the daily widget when today's board exists and has not been touched. An adjective about the BOARD, not the player. One word.",
    "widget.status.solved": "The big status word in the daily widget, and the footer of the playable widget, when today's board is finished. A word, not a sentence, and capitalised — the same word as `status.solved` inside the app; keep the two the same.",
    "widget.status.notStarted": "The Lock Screen rectangular widget's line when today's board has not been touched. Says less than `widget.status.ready` on purpose: this line replaces a whole widget rather than heading one. A fragment, no full stop.",
    "widget.status.filled": "The Lock Screen rectangular widget's line mid-solve. %1$@ is a percentage already formatted (\"64%\"). A fragment, no full stop.",
    "widget.status.solvedIn": "The daily and playable widgets' line once the board is finished. %1$@ is an elapsed time already formatted as m:ss (\"4:12\"). A fragment, no full stop — \"Solved 4:12\", not \"Solved in 4:12\", because the space is one line.",
    "widget.caption.awaits": "The quiet second line under `widget.status.openNine`. Says the board is there and waiting, without claiming the player has started it.",
    "widget.caption.waiting": "The quiet second line under `widget.status.ready`. \"New\" means today's, as opposed to yesterday's.",
    "widget.caption.inProgress": "The quiet second line under a percentage: this board is started and unfinished. A fragment, lowercase after the first word, no full stop.",
    "widget.caption.done": "The quiet second line shown when today's board is finished but no time was recorded. \"Daily\" is the day's shared puzzle. A fragment, no full stop.",
    "widget.board.cta": "The whole content of the playable widget before the app has published a board: tapping it opens Nine, which composes one. A sentence-shaped instruction with no full stop, set at headline size across a large widget.",
    "widget.streak.ready": "The Lock Screen INLINE accessory when the run is at zero and today's board is untouched. Shares one short line with the system clock, so it is the tightest string in the app — about 20 characters. \"Nine\" is the app's name and stays untranslated; the separator is a middle dot.",
    "widget.streak.inline": "The Lock Screen INLINE accessory when a run is going. %1$lld is a number of consecutive days, always 1 or more. The same one-line budget as `widget.streak.ready`. PLURAL: the two English forms are identical because English does not inflect here; give your language whatever forms it needs.",

    # --- PRD-29: the weekly table. The whole register of this block is
    # "a fact about your week", never "a position against other people":
    # nothing here may gain a word meaning rank, place, level, division,
    # promotion or relegation, in any language. There is no cohort to be
    # moved between — the twenty rows are a window on one global board — so
    # such a word would name something that does not exist.
    "table.invitation": "The one-sentence explanation of the weekly league, shown where the league would be before the player has joined it. Two facts: the size, and the ranking rule — how many of the week's daily puzzles you finished matters first, and your total time only separates people who finished the same number. NOT a pitch and NOT an urge to join; a description. The semicolon may become a full stop.",
    "table.join": "The button that puts the player on the weekly league. A verb in the imperative. \"Table\" is a league table / standings, not furniture — it is the feature's name and matches `history.section.table`.",
    "table.leave": "The button that takes the player off the weekly league. A verb in the imperative, and quiet — it sits below the standings as a plain text control, not a warning.",
    "table.leave.note": "One line under the leave control, explaining exactly what leaving does: this device stops sending new results, and results already sent cannot be recalled — they expire when the week does. Do NOT translate as a promise to delete anything.",
    "table.seat.label": "VoiceOver label for one row of the weekly standings, read as a single utterance. %1$@ is a player's Game Center display name; %2$lld is how many of the week's seven daily puzzles they finished (0-7); %3$@ is their total time already formatted as m:ss (\"12:04\"). The 7 is a constant — the week — so the noun \"days\" agrees with 7, not with %2$lld; if your language agrees with the first number instead, add the forms you need. The commas are the join; reorder the three facts if this language reads them another way. NO word for rank or position: the order of the rows is the standing and nothing says so out loud.",
    "table.seat.mine": "The same VoiceOver label as `table.seat.label` for the player's OWN row, where the name is replaced by a word meaning \"you\". %1$lld is how many of the week's seven daily puzzles they finished (0-7); %2$@ is their total time already formatted as m:ss. Keep the same shape and the same word as `table.you`.",
    "table.waiting": "Shown in place of the standings when the player is on the weekly league but there is nothing to show yet — a week nobody has played, or a league that has not answered. A statement of absence, not an error and not an apology.",
    "table.you": "How the player's own row is named in the weekly standings, in place of a display name. One word, capitalised, and the same word `table.seat.mine` opens with.",
}


def read_english_table(path=ENGLISH_PHRASES):
    """`EnglishPhrases.table` as an ordered list of (key, value).

    Reads the Swift file rather than importing anything, which is why that
    file's shape is a contract rather than a style: a plain `[String: String]`
    literal, one `"key": "value",` per line, keys sorted. Nothing in it has to
    be *executed* to know what the English is.
    """
    entries = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            found = TABLE_ENTRY_RE.match(line)
            if found:
                entries.append((found.group(1), found.group(2)))
    if not entries:
        sys.exit("read no phrases out of %s — has the table's shape changed? "
                 "It must stay one `\"key\": \"value\",` per line."
                 % os.path.relpath(path, REPO_NINE))
    keys = [key for key, _ in entries]
    if keys != sorted(keys):
        sys.exit("%s is not sorted by key. The catalog is generated by diffing "
                 "this file; an unsorted table makes every regeneration a "
                 "whole-file diff." % os.path.relpath(path, REPO_NINE))
    if len(set(keys)) != len(keys):
        duplicates = sorted({key for key in keys if keys.count(key) > 1})
        sys.exit("duplicate key(s) in %s: %s — the Swift dictionary literal "
                 "would keep the last one and the catalog the same, silently."
                 % (os.path.relpath(path, REPO_NINE), ", ".join(duplicates)))
    return entries


def read_english_plurals(path=ENGLISH_PHRASES):
    """`EnglishPhrases.plurals` as key → (count argument, `one` form).

    Same contract as `read_english_table`: one entry per line, sorted, nothing
    that has to be executed. An empty result is NOT an error here — a repo with
    no count-bearing phrase is a legal repo — but `PhrasebookTests` re-parses
    the same file from Swift and compares the parse against the compiled
    dictionary, so a shape change shows up as a red test rather than as a
    silently unpluralised catalog.
    """
    plurals = {}
    order = []
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            found = PLURAL_ENTRY_RE.match(line)
            if found:
                key, count, one = found.group(1), int(found.group(2)), found.group(3)
                plurals[key] = (count, one)
                order.append(key)
    if order != sorted(order):
        sys.exit("EnglishPhrases.plurals is not sorted by key.")
    if len(set(order)) != len(order):
        sys.exit("duplicate key(s) in EnglishPhrases.plurals — the Swift "
                 "literal keeps the last one and so would the catalog.")
    return plurals


def read_english_substitutions(path=ENGLISH_PHRASES):
    """`EnglishPhrases.substitutions` as key → [(name, count, one, other)].

    The three phrases whose plural cannot be a whole-string variation. See that
    table's doc comment for why the mechanism is CLDR substitutions rather than
    a plural on one of the numbers.
    """
    substitutions = {}
    owner = None
    with open(path, "r", encoding="utf-8") as handle:
        for line in handle:
            found = SUBSTITUTION_ENTRY_RE.match(line)
            if found:
                if owner is None:
                    sys.exit("an EnglishSubstitution with no `\"key\": [` line "
                             "above it — the parser cannot tell which phrase it "
                             "belongs to.")
                substitutions[owner].append(
                    (found.group(1), int(found.group(2)), found.group(3), found.group(4)))
                continue
            owned = SUBSTITUTION_OWNER_RE.match(line)
            if owned:
                owner = owned.group(1)
                substitutions.setdefault(owner, [])

    # An owner with no axis the parser could read is a HARD failure, not an
    # empty list quietly dropped — which is what this function used to do, and
    # what it did to a real key.
    #
    # Measured on this branch: wrapping one `EnglishSubstitution(…)` across two
    # lines — which the Swift compiler and every style rule accept —
    # made `SUBSTITUTION_ENTRY_RE` miss it, because that regex is
    # `^…$`-anchored. `board.progress.filled` then shipped as a plain
    # `stringUnit`, carrying a translator comment that promises plural forms the
    # catalog does not have. **Nothing else could see it**: the plural gate in
    # `CatalogTests` inspects entries that already carry plurals, so a key with
    # none is invisible to it by construction, and `--audit` only counts keys.
    #
    # "The declaration exists and the parser cannot read it" and "there is no
    # declaration" produce the same empty list, and only one of the two is a
    # legitimate state. So the parser has to account for every owner it saw.
    empty = sorted(key for key, axes in substitutions.items() if not axes)
    if empty:
        sys.exit(
            "EnglishPhrases.substitutions declares %s with no axis this parser "
            "could read.\nEvery `EnglishSubstitution(name:count:one:other:)` "
            "must sit on ONE line: the regex is line-anchored, and a wrapped "
            "declaration is dropped silently — which ships a key whose "
            "translator comment promises plural forms the catalog does not "
            "have." % ", ".join(empty))
    return substitutions


def english_localization(key, english, plurals, substitutions):
    """The `en` localization body for one key: plain, plural, or substituted.

    Three shapes, and which one a key gets is decided by the two Swift tables
    rather than by anything here.

    **The substitution frame is derived, never stored.** An axis's `other` form
    is the fragment it owns — `"%arg themes"` — so the frame is the `table` row
    with that fragment replaced by `%N$#@name@`. Each fragment has to appear in
    the row exactly once, and that is the check: an `other` that has drifted
    from the sentence it is a piece of stops matching, and a `table` row whose
    wording changed stops matching too. Either way this is a hard exit, because
    the alternative is a sentence with two homes that disagree — the one failure
    generating the catalog exists to make impossible.
    """
    if key in substitutions:
        frame = english
        for name, count, _one, other in substitutions[key]:
            fragment = other.replace(SUBSTITUTION_ARG, ARG_SPECIFIER % count)
            if frame.count(fragment) != 1:
                sys.exit("%s: substitution %r has `other` = %r, which spells out as "
                         "%r and appears %d time(s) in\n  %r\n"
                         "An axis's `other` is the fragment it owns, so it has to "
                         "be in the sentence, exactly once."
                         % (key, name, other, fragment, frame.count(fragment), english))
            frame = frame.replace(fragment, "%%%d$#@%s@" % (count, name))
        if SUBSTITUTION_ARG in frame:
            sys.exit("%s: %s survived into the derived frame %r"
                     % (key, SUBSTITUTION_ARG, frame))

        return {
            "stringUnit": {"state": "translated", "value": frame},
            "substitutions": {
                name: {
                    "argNum": count,
                    "formatSpecifier": "lld",
                    "variations": {"plural": {
                        "one": {"stringUnit": {"state": "translated", "value": one}},
                        "other": {"stringUnit": {"state": "translated", "value": other}},
                    }},
                }
                for name, count, one, other in substitutions[key]
            },
        }

    if key in plurals:
        count, one = plurals[key]
        slot = ARG_SPECIFIER % count
        if slot not in english:
            sys.exit("%s counts argument %d, but \"%s\" never names %s. A plural "
                     "whose count is not in the string cannot select a category."
                     % (key, count, english, slot))

        # A whole-string plural variation carries NO argument number: the
        # catalog's `variations.plural` has nowhere to put one, and
        # `xcstringstool` infers it from the string. It can only do that when
        # there is exactly one integer specifier — otherwise it emits
        # `%#@value@`, which means "the first argument", warns, and compiles.
        #
        # Measured on this machine with `board.stats.digitLeft`
        # ("%1$lld, %2$lld left", where the count is argument 2), against the
        # compiled .stringsdict with distinguishable forms planted:
        #
        #     digit 5, 1 left  ->  OTHER
        #     digit 1, 5 left  ->  ONE
        #
        # Exactly inverted, silently, in every language that inflects. So this
        # is a hard exit rather than a warning passed along: the fix is an
        # explicit substitution, which writes `argNum` down instead of guessing.
        integers = set(INTEGER_SPECIFIER_RE.findall(english))
        if integers != {str(count)}:
            sys.exit(
                "%s: a whole-string plural cannot say WHICH argument it counts, "
                "and \"%s\" names %d of them (%s) while the table counts argument "
                "%d.\n`xcstringstool` would infer argument 1, warn, and compile — "
                "and select on the wrong number in every language that inflects.\n"
                "Move this key to EnglishPhrases.substitutions, where argNum is "
                "written down."
                % (key, english, len(integers), ", ".join("%%%s$lld" % i
                                                          for i in sorted(integers)),
                   count))

        return {"variations": {"plural": {
            # `one` first in the source, `other` second; `json.dump(sort_keys)`
            # writes them alphabetically either way.
            "one": {"stringUnit": {"state": "translated", "value": one}},
            "other": {"stringUnit": {"state": "translated", "value": english}},
        }}}

    return {"stringUnit": {"state": "translated", "value": english}}


def _uses_xcode_spacing(catalog):
    """True when the catalog on disk separates keys from values Xcode's way.

    Read from the first line that can show it rather than parsed, because the
    whole question is about bytes that JSON throws away.
    """
    try:
        with open(catalog, encoding="utf-8") as handle:
            for line in handle:
                if '" : ' in line:
                    return True
                if '": ' in line:
                    return False
    except OSError:
        pass
    return True


def build_catalog(catalog=CATALOG, phrases=ENGLISH_PHRASES, dry_run=False):
    """Regenerate the catalog's `en` locale from `EnglishPhrases.table`.

    One English, two consumers: `Phrasebook.english` formats from the Swift
    table (so `swift test` and the Linux lane produce real sentences with no
    bundle), and this writes the same strings into the catalog a translator is
    handed. Generated rather than hand-kept because the alternative is two lists
    that agree only by inspection — which is the exact failure this task went
    and fixed in three other files.

    **Translations are preserved.** Every non-`en` localization of a key that
    still exists is carried across untouched; only `en` is rewritten. A key that
    has left the table loses its translations with it, which is the point — a
    dead string is one a translator was paid for.

    Returns (added, changed, removed).
    """
    entries = read_english_table(phrases)
    plurals = read_english_plurals(phrases)
    substitutions = read_english_substitutions(phrases)

    known = {key for key, _ in entries}
    orphans = sorted((set(plurals) | set(substitutions)) - known)
    if orphans:
        sys.exit("plural/substitution row(s) for key(s) that are not in "
                 "EnglishPhrases.table: %s. The `other` form IS the table row, "
                 "so a plural without one has no `other` at all — which "
                 "`xcstringstool` would compile clean and render as (null)."
                 % ", ".join(orphans))
    both = sorted(set(plurals) & set(substitutions))
    if both:
        sys.exit("key(s) in both EnglishPhrases.plurals and .substitutions: %s. "
                 "A phrase inflects on one axis or on several, not both."
                 % ", ".join(both))

    missing = [key for key, _ in entries if not COMMENTS.get(key)]
    if missing:
        sys.exit(
            "no translator comment for: %s\n"
            "Add one to COMMENTS in scripts/strings.py. This is a hard failure "
            "rather than an empty string because a comment is the only context "
            "the translator gets: \"Sharp\" is unguessable without one, and "
            "`board.announce.solved` (\"Solved.\") versus `archive.day.solved` "
            "(\"solved\") are different parts of speech that get confused "
            "exactly once per language." % ", ".join(missing))

    previous = {}
    if os.path.exists(catalog):
        with open(catalog, "r", encoding="utf-8") as handle:
            previous = json.load(handle).get("strings", {})

    strings = {}
    added, changed = [], []
    for key, english in entries:
        localizations = {}
        for locale, body in previous.get(key, {}).get("localizations", {}).items():
            if locale != "en":
                localizations[locale] = body
        localizations["en"] = english_localization(key, english, plurals, substitutions)
        strings[key] = {
            "comment": COMMENTS[key],
            # Xcode garbage-collects entries it believes its own extractor
            # produced. Nine's keys are runtime lookups — `Phrasebook.current
            # .string("board.cell.label")` — which that extractor cannot see, so
            # every one of them is `manual` and stays put.
            "extractionState": "manual",
            "localizations": localizations,
        }
        if key not in previous:
            added.append(key)
        else:
            # The whole `en` body, not just its `stringUnit`: adding a plural
            # variation changes the shape rather than the value, and comparing
            # values alone would report "0 changed" on the commit that
            # pluralised sixteen phrases.
            was = previous[key].get("localizations", {}).get("en")
            if was != localizations["en"] or previous[key].get("comment") != COMMENTS[key]:
                changed.append(key)

    removed = sorted(set(previous) - set(strings))
    document = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}

    if not dry_run:
        os.makedirs(os.path.dirname(catalog), exist_ok=True)
        # Sniffed BEFORE the file is opened for writing: `open(…, "w")`
        # truncates, so reading it inside the block reads an empty file and
        # silently takes the default.
        separator = " : " if _uses_xcode_spacing(catalog) else ": "
        with open(catalog, "w", encoding="utf-8") as handle:
            # 2-space indent, keys sorted, no ASCII escaping — and whichever
            # key/value separator the file on disk already uses.
            #
            # Xcode writes `"key" : value` and everything else on earth writes
            # `"key": value`, and PRD-20's translation passes left the committed
            # catalog in the second form. Hard-coding either one means the next
            # `--build-catalog` emits a **41,000-line whitespace diff** with the
            # four real new rows buried inside it, which is a review that does
            # not happen. Preserving what is there makes a regeneration diff as
            # its content in both directions; a brand-new catalog still gets
            # Xcode's form, because that is what Xcode would do to it anyway.
            json.dump(document, handle, indent=2, sort_keys=True,
                      separators=(",", separator), ensure_ascii=False)
            handle.write("\n")
    return added, changed, removed


def command_build_catalog(args):
    added, changed, removed = build_catalog(dry_run=args.dry_run)
    total = len(read_english_table())
    verb = "would write" if args.dry_run else "wrote"
    print("%s %s — %d key(s): %d new, %d changed, %d removed."
          % (verb, os.path.relpath(CATALOG, REPO_NINE), total,
             len(added), len(changed), len(removed)))
    for key in added:
        print("  + %s" % key)
    for key in changed:
        print("  ~ %s" % key)
    for key in removed:
        print("  - %s (its translations go with it)" % key)
    return 0


# ---------------------------------------------------------------------- main


def command_audit(args):
    offences = scan_tree()
    if args.write_baseline:
        count = write_baseline(offences)
        print("wrote %s — %d offence(s)."
              % (os.path.relpath(BASELINE, REPO_NINE), count))
        return 0

    if args.verbose or args.list:
        for relative, line, body in offences:
            print("%s:%d \"%s\"" % (relative, line, body.replace("\n", "\\n")))

    baseline = read_baseline()
    failed = False

    if baseline is None:
        print("no baseline at %s — %d bare literal(s) found. Run "
              "`--audit --write-baseline` to calibrate."
              % (os.path.relpath(BASELINE, REPO_NINE), len(offences)))
        failed = True
    else:
        new, stale = multiset_diff(sorted(baseline_key(o) for o in offences),
                                   baseline)
        if new:
            print("%d NEW bare user-facing literal(s) — every string a player "
                  "reads goes through the catalog:" % len(new))
            for key in new:
                print("  %s" % key)
            print("Fix: move it into a `Phrase` block and run "
                  "`python3 scripts/strings.py --extract`.")
            failed = True
        if stale:
            print("%d baseline entry/entries no longer fire. That is progress, "
                  "but a stale baseline stops measuring — regenerate it with "
                  "`--audit --write-baseline`:" % len(stale))
            for key in stale:
                print("  %s" % key)
            failed = True
        if not new and not stale:
            print("source: %d bare literal(s), all of them still in the "
                  "baseline (0 new)." % len(offences))

    for failure in audit_catalog(args.verbose):
        print("catalog: %s" % failure)
        failed = True

    # The catalog is a generated artifact, and a generated artifact that
    # disagrees with its generator is the "two lists that agree only by
    # inspection" failure this whole file was written against. It had already
    # happened: `difficulty.nocturne.title`'s DO-NOT-TRANSLATE comment was
    # hand-edited into the catalog and not into `COMMENTS`, so the next
    # `--build-catalog` would have silently deleted it. Nothing ran the
    # generator to find out — `--audit` reads the artifact and `--build-catalog`
    # is only run deliberately, so the drift had no observer.
    added, changed, removed = build_catalog(dry_run=True)
    drift = [("+", k) for k in added] + [("~", k) for k in changed] \
        + [("-", k) for k in removed]
    if drift:
        print("catalog: %d key(s) would change if the generator ran — the "
              "artifact and `EnglishPhrases`/`COMMENTS` have drifted apart:"
              % len(drift))
        for mark, key in drift:
            print("  %s %s" % (mark, key))
        print("Fix: correct the generator, then "
              "`python3 scripts/strings.py --build-catalog`. Do not hand-edit "
              "the catalog — it is regenerated.")
        failed = True

    return 1 if failed else 0


def scratch_catalog(directory, keys, broken=False):
    """A minimal `.xcstrings` on disk, so the catalog checks are drivable
    before Task 4 exists."""
    path = os.path.join(directory, "Localizable.xcstrings")
    body = {
        "sourceLanguage": "en",
        "version": "1.0",
        "strings": {
            key: {"localizations": {"en": {"stringUnit": {
                "state": "translated", "value": key.split(".")[-1].title(),
            }}}} for key in keys
        },
    }
    with open(path, "w", encoding="utf-8") as handle:
        if broken:
            # Truncated JSON. What a bad merge of a catalog actually looks
            # like, and the thing `xcstringstool compile` is here to catch.
            handle.write(json.dumps(body)[:-20])
        else:
            json.dump(body, handle, indent=2)
    return path


def command_selftest_catalog(_args):
    """Drive `audit_catalog` against scratch catalogs, both ways.

    This exists because the catalog half of `--audit` cannot run against the
    repo until Task 4 creates `Sources/Strings/Localizable.xcstrings`, and
    "cannot run" is how it shipped with two bugs in it: `compile` was invoked
    without the `--output-directory` it requires even under `--dry-run`, and
    the `print` parser expected quoted keys when the tool emits bare ones.
    Neither was reachable, so neither was caught. Now they are.
    """
    cases = [
        ("a clean catalog, every key used", ["home.title", "home.subtitle"],
         {"home.title", "home.subtitle"}, False, []),
        ("a key used in Swift but absent from the catalog", ["home.title"],
         {"home.title", "home.missing"}, False,
         ["used in Swift, absent from the catalog: home.missing"]),
        # The expected fragment names the key on purpose. Stopping at "no Swift
        # file names" passed while the check reported an entirely different
        # key — measured: made to report `home.WRONGKEY` and this case still
        # printed `ok` and exited 0. A shape is not a result.
        ("a key in the catalog that no Swift file names",
         ["home.title", "home.dead"], {"home.title"}, False,
         ["in the catalog, referenced by no Swift file"
          " (dead strings, which translators are paid for): home.dead"]),
        ("a catalog that does not parse", ["home.title"], {"home.title"},
         True, ["the catalog does not compile"]),
    ]

    failed = False
    with tempfile.TemporaryDirectory() as directory:
        for name, keys, used, broken, expected in cases:
            case_dir = os.path.join(directory, name.replace(" ", "_")[:32])
            os.makedirs(case_dir, exist_ok=True)
            path = scratch_catalog(case_dir, keys, broken=broken)
            failures = audit_catalog(False, catalog=path, used=set(used))
            joined = "\n".join(failures)
            ok = (len(failures) == len(expected)
                  and all(fragment in joined for fragment in expected))
            print("%s %s" % ("ok  " if ok else "FAIL", name))
            for failure in failures:
                print("       %s" % failure.replace("\n", "\n       "))
            if not ok:
                print("       expected %d failure(s) containing %r"
                      % (len(expected), expected))
                failed = True

        missing = os.path.join(directory, "nowhere", "Localizable.xcstrings")
        note = audit_catalog(False, catalog=missing, used=set())
        ok = note == []
        print("%s a catalog that does not exist yet degrades to a note"
              % ("ok  " if ok else "FAIL"))
        failed = failed or not ok

    # The one case that runs against the REAL tree, because it is about the
    # tree. `EnglishPhrases.table` used to be an unconditional member of the
    # used-set, and since the catalog's `en` is generated from that table the
    # dead-string check above was empty by construction for all 394 keys — the
    # check could not fail, in either direction, ever.
    #
    # Reader (4) is now off by default and the shapes it was covering for have
    # readers of their own (2b ternaries, 3b scope+suffix, 3c key arrays). This
    # asserts that: with those in place the two modes see the *same* keys, which
    # is what "reader (4) adds nothing" means as an assertion rather than as a
    # claim. A key here says a catalog row is reachable only by being in the
    # table — i.e. some new un-greppable shape landed and needs its own reader,
    # not that reader (4) should come back.
    strict = swift_referenced_keys(strict=True)
    lenient = swift_referenced_keys(strict=False)
    only_by_table = sorted(lenient - strict)
    ok = not only_by_table
    print("%s no catalog key is reachable only through EnglishPhrases.table"
          % ("ok  " if ok else "FAIL"))
    if not ok:
        print("       %d key(s) the strict readers cannot see: %s"
              % (len(only_by_table), ", ".join(only_by_table)))
        failed = True

    return 1 if failed else 0


def command_extract(_args):
    sys.exit("--extract is not implemented until Task 5. It will lift the "
             "baselined literals into Sources/Strings/Localizable.xcstrings "
             "and rewrite the call sites to name `Strings.*`. Until then "
             "`--audit` is the whole tool.")


def command_pseudo(_args):
    # Kept as a signpost rather than deleted, because the obvious next move on
    # reading "pseudo-loc lane" in the plan is to write this function, and the
    # point is that it should not be written.
    sys.exit("--pseudo is not implemented, and generating a pseudo-locale is "
             "NOT the plan. Foundation already does it: launching with "
             "`-NSDoubleLocalizedStrings YES` was hand-verified to fire against "
             "this app, so the catalog needs no synthetic `qps-Ploc` entries and "
             "no extra 425 keys to keep in step. The pseudo-loc + RTL lane is "
             "PRD-20 Task 10 and drives the real app with that argument; see "
             "DEVIATIONS.md. Beware: double-localization is what exposed the "
             "bare-specifier bug, rendering `lld 4` for every board digit, so a "
             "unit whose whole content is one specifier must be formatted in "
             "Swift rather than translated.")


def main(argv=None):
    parser = argparse.ArgumentParser(
        description=__doc__.split("\n")[0],
        formatter_class=argparse.RawDescriptionHelpFormatter)
    mode = parser.add_mutually_exclusive_group(required=True)
    mode.add_argument("--audit", action="store_true",
                      help="fail on bare user-facing literals and catalog drift")
    mode.add_argument("--build-catalog", action="store_true",
                      help="regenerate Localizable.xcstrings' `en` from "
                           "EnglishPhrases.table, preserving translations")
    mode.add_argument("--extract", action="store_true",
                      help="(Task 5) lift literals into the catalog")
    mode.add_argument("--pseudo", action="store_true",
                      help="not implemented; use -NSDoubleLocalizedStrings YES")
    mode.add_argument("--selftest-catalog", action="store_true",
                      help="drive the catalog checks against scratch catalogs")
    parser.add_argument("--verbose", "-v", action="store_true",
                        help="print every offence, not just the new ones")
    parser.add_argument("--list", action="store_true",
                        help="alias for --verbose")
    parser.add_argument("--write-baseline", action="store_true",
                        help="recalibrate Tests/StringBaselines/offences.txt")
    parser.add_argument("--dry-run", action="store_true",
                        help="with --build-catalog: report, write nothing")
    args = parser.parse_args(argv)

    if args.build_catalog:
        return command_build_catalog(args)
    if args.extract:
        return command_extract(args)
    if args.pseudo:
        return command_pseudo(args)
    if args.selftest_catalog:
        return command_selftest_catalog(args)
    return command_audit(args)


if __name__ == "__main__":
    sys.exit(main())
