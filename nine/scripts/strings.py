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
    python3 scripts/strings.py --pseudo            # Task 9+
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
TREES = ["Sources/App", "Sources/Widgets", "Sources/Shared"]

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

# PRD-20's ten launch locales, in the order `project.yml` declares them.
# `CatalogTests.testDeclaredLocalizationsAreExactlyTheNineLaunchLocales` is what
# keeps the two lists equal.
LOCALES = ["en", "ja", "de", "fr", "es", "it", "pt-BR", "ko", "zh-Hans", "nl"]

# `"key": "value",` — the one shape `EnglishPhrases.table` is allowed to take.
# `PhrasebookTests.testTableIsOneSortedEntryPerLineSoAScriptCanReadIt` is the
# other half of this contract: it re-parses the same file from Swift and checks
# the parse against the compiled dictionary, so this reader cannot drift from
# what the app actually says.
TABLE_ENTRY_RE = re.compile(r'^\s*"([^"]+)"\s*:\s*"(.*)",\s*$')

# A key handed to the Phrasebook as a literal: `Phrasebook.current.string("…")`,
# `Strings.string("…")`. Shared cannot name `Strings`, so this — not a
# `Strings.foo.bar` path — is how most of Nine's keys are actually written.
PHRASEBOOK_KEY_RE = re.compile(r'\.string\(\s*"([^"\\\n]+)"')

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
]

BASELINE_HEADER = """\
# Nine — bare user-facing literals, as of the start of PRD-20.
#
# This file is a COUNTDOWN, not a permit. Each line is one string that still
# reaches a player without passing through the catalog. `StringSealTests` fails
# on any offence NOT in this list, so the rot cannot grow while Tasks 5-8
# extract; those tasks shrink this file, and it is empty when they are done.
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
    #   AppIcon-Ember  AppIcon-Mono  AppIcon-Tide  UTF-8        <- CamelCase segment
    #   pad-probe  cloud-sync  widget-bridge  d-pad  hold-click <- all lowercase
    #
    # while hyphenated English never has an uppercase letter *inside* a word and
    # is not uniformly lowercase, because at least one segment starts a phrase:
    #
    #   Sign-in  Re-solve  Auto-save  Multi-line  Best-of-3  Auto-Save  X-Ray
    #
    # "All segments share a case class" was the first thing tried and is not
    # enough: it drops `Auto-Save` and `Well-Being`, and Title Case is exactly
    # what the Mac menu bar uses ("New Game", "Float Desk on Top"), so that is a
    # shape this app will really produce.
    #
    # Residual false negative, and it is a real string in this tree rather than
    # a hypothetical: `TutorialGrammar.pencilVerb` is `"hold-click"` on one
    # platform and `"Shift-type"` on another. `Shift-type` flags, `hold-click`
    # does not — nothing distinguishes it from `pad-probe`. Neither reaches the
    # rule today (they are struct fields, not sink arguments), but whoever does
    # Tasks 5-8 should extract that pair by hand.
    segments = trimmed.split("-")
    if len(segments) >= 2 and all(s.isalnum() for s in segments):
        uniformly_lower = all(not any(c.isupper() for c in s) for s in segments)
        has_camel_segment = any(any(c.isupper() for c in s[1:]) for s in segments)
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


def swift_referenced_keys(nine=REPO_NINE):
    """Every catalog key this app actually asks for.

    A `Strings.foo.bar` grep is only one of the three ways a key is named here,
    and on its own it is wrong in the loudest possible direction: from the
    moment the catalog exists it reports **every one of the Shared keys as a
    dead string** and turns the cheap lane red. That is not a nuisance to
    suppress, it is the check disagreeing with the design — `Sources/Shared`
    cannot name `Strings` (it is Linux-clean and compiles into two bundles), so
    it reaches its words through `Phrasebook.current.string("…")` instead, with
    the key as a literal.

    So the used-set is a union of four readers:

      1. `Strings.foo.bar` — the App-layer accessor paths Task 5 generates.
      2. `.string("board.cell.label")` — the literal handed to `Phrasebook`, in
         `Sources/Shared` and in `Sources/Strings`.
      3. The interpolated families, which no grep can see. `Strings.technique`
         builds `"technique.\\(t.rawValue).name"`, `NineTip.message` builds
         `"tip.\\(rawValue)"`; the keys exist only at runtime, one per enum
         case. `INTERPOLATED_FAMILIES` names each one and its enum, so
         *appending* a case makes it a used key — and, since the catalog is
         generated from `EnglishPhrases.table`, a case with no row shows up as
         `missing` rather than sailing through.
      4. `EnglishPhrases.table` itself. Not a rubber stamp: the catalog's `en`
         is *generated from* that table (`--build-catalog`), so the two are one
         list read twice, and a row there is a key this app ships by
         construction. It is also the only reader that survives the shapes (2)
         cannot see — `BoardSpeech.Phrase.digitWordKeys` is a `[String]` of ten
         literals indexed by the digit, which is a perfectly good way to write
         that and hopeless to grep for. Dead rows are caught on the *table*
         side instead, by `PhrasebookTests` and by review, where the whole
         list is in one file.

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
    keys.update(interpolated_keys(nine))
    keys.update(key for key, _ in read_english_table(
        os.path.join(nine, "Sources", "Shared", "EnglishPhrases.swift")))
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


def audit_catalog(verbose, catalog=CATALOG, used=None):
    """The three catalog checks. Returns a list of failure strings; an empty
    list with a printed note is what "the catalog does not exist yet" looks
    like, because Task 1 ships before Task 4 builds it.

    `catalog` and `used` are arguments so `--selftest-catalog` can drive this
    against a scratch catalog. Both of these checks shipped broken once because
    nothing could run them until Task 4; that is now no longer true.
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
        used = swift_referenced_keys()
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
        print("catalog: %d keys, all of them reachable." % len(keys))
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
    "board.unit.row": "VoiceOver, the name of a row. %1$lld is 1-9.",
    "board.unit.column": "VoiceOver, the name of a column. %1$lld is 1-9.",
    "board.unit.box": "VoiceOver, the name of a 3x3 box. %1$lld is 1-9.",
    "board.value.empty": "VoiceOver value of a square with nothing in it. A word, not a sentence.",
    "board.value.plain": "VoiceOver value of a square the player filled in. %1$lld is the digit.",
    "board.value.given": "VoiceOver value of a square the puzzle supplied and the player cannot change. %1$lld is the digit.",
    "board.value.wrong": "VoiceOver value of a square holding a digit that contradicts the solution. %1$lld is the digit. Only ever spoken when the player has mistake-marking switched on.",
    "board.value.notes": "VoiceOver value of an empty square carrying pencil marks. %1$@ is the list of noted digits, already joined.",
    "board.value.noteSeparator": "Joins the digits in a spoken list of pencil marks. Punctuation only — use whatever this language lists with (a comma in English, an ideographic comma in Japanese).",
    "board.box.filled": "VoiceOver, group scan: this 3x3 box is complete. A word, not a sentence.",
    "board.box.empty": "VoiceOver, group scan: how many squares in this 3x3 box are still blank. %1$lld is 1-8.",
    "board.announce.placed": "VoiceOver announcement after a digit is entered. %1$@ is the digit as a word (\"four\"). A sentence: it ends in a full stop.",
    "board.announce.cleared": "VoiceOver announcement after a digit is removed. %1$@ is the digit as a word.",
    "board.announce.noteAdded": "VoiceOver announcement after a pencil mark is added. %1$@ is the digit as a word.",
    "board.announce.noteRemoved": "VoiceOver announcement after a pencil mark is removed. %1$@ is the digit as a word.",
    "board.announce.remaining": "VoiceOver announcement: how many of one digit are still missing. %1$@ is a count word (\"three\"), %2$@ the digit's plural (\"sevens\").",
    "board.announce.allDone": "VoiceOver announcement: every instance of one digit is now placed. %1$@ is the digit's plural (\"sevens\").",
    "board.announce.solved": "VoiceOver announcement the moment the board is finished. One word, a full sentence.",
    "board.progress.filled": "VoiceOver board summary. %1$lld squares filled of %2$lld fillable.",
    "board.progress.wrong": "VoiceOver board summary: how many placed digits contradict the solution. %1$lld is the count. Only spoken with mistake-marking on.",
    "board.streak.plain": "VoiceOver label of the streak chip. %1$lld is a number of consecutive days, always 1 or more.",
    "board.streak.held": "VoiceOver label of the streak chip on a day already solved — the run is safe. %1$lld is a number of consecutive days.",

    # Voice Control names. Matched against a speech recogniser, so no
    # punctuation of any kind.
    "board.voiceName.cell": "Voice Control name for a square, spoken BY the player to select it. %1$lld is the row, %2$lld the column. No punctuation at all — a recogniser never emits a comma.",
    "board.voiceName.rowColumn": "Alternative Voice Control name for the same square, spoken by the player. %1$lld is the row, %2$lld the column. No punctuation.",
    "board.voiceName.bare": "Shortest Voice Control name for a square: the two numbers alone. %1$lld is the row, %2$lld the column. No punctuation.",

    # Digit words. Spoken, never shown — the numerals are drawn as glyphs.
    "board.digitWord.zero": "The digit 0 as a spoken word, for VoiceOver announcements.",
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
    "card.streak": "Half of the solve card's credit line, after the difficulty: \"Steady - 12 day streak\". %1$lld is a number of consecutive days, always 1 or more.",

    # The coach (PRD-11). One sentence, on a card, that the player could check
    # by hand. Never mentions the solution.
    "coach.solved.title": "Coach card heading when the board is finished. One word.",
    "coach.slip.title": "Coach card heading when two squares contradict each other, so no hint is possible. Gentle and blameless: the player made a slip, they did not fail.",
    "coach.slip.body": "Coach card body when two squares contradict each other. Says that nothing can follow, without saying which square is wrong.",
    "coach.exhausted.title": "Coach card heading when the board is consistent but no technique at its level applies. Not an error — the hint has simply run out.",
    "coach.exhausted.body": "Coach card body when no technique at this board's level applies.",
    "coach.axis.rows": "The word \"rows\" as used inside a coach sentence about an X-wing. Lowercase, plural, mid-sentence.",
    "coach.axis.columns": "The word \"columns\" as used inside a coach sentence about an X-wing. Lowercase, plural, mid-sentence.",
    "coach.nakedSingle.body": "Coach explanation, naked single. %1$@ is a square's name (\"Row 4, column 2\"), %2$@ a digit as a word (\"seven\").",
    "coach.hiddenSingle.body": "Coach explanation, hidden single. %1$@ is a unit's name (\"Box 3\"), %2$@ a digit as a word.",
    "coach.hiddenSingle.fallback": "Coach explanation, hidden single, when no containing unit was derived. %1$@ is a square's name, %2$@ a digit as a word.",
    "coach.nakedPair.body": "Coach explanation, naked pair. %1$@ and %2$@ are digits as words, %3$@ a unit's name (\"Row 7\").",
    "coach.hiddenPair.body": "Coach explanation, hidden pair. %1$@ and %2$@ are digits as words, %3$@ a unit's name.",
    "coach.boxLine.body": "Coach explanation, box-line reduction. %1$@ is a digit as a word, %2$@ and %3$@ are unit names. Note %1$@ and %3$@ each appear TWICE — if you reorder the sentence, move every occurrence.",
    "coach.xWing.body": "Coach explanation, X-wing. %1$@ and %4$@ are the same digit as a word, %2$@ and %3$@ are the words \"rows\"/\"columns\". %3$@ appears twice — if you reorder, move both.",

    # Difficulty bands. Names of the four settings a player picks between, shown
    # on buttons, in menus and on the share card. Short: one or two words.
    "difficulty.gentle.title": "Difficulty band, easiest of four. Shown on buttons and menus and on the share card. An adjective in the app's calm register — not \"Easy\", which sounds like a judgement of the player. One or two words.",
    "difficulty.steady.title": "Difficulty band, second of four: unhurried, dependable. Shown on buttons and menus. One or two words.",
    "difficulty.sharp.title": "Difficulty band, third of four: keen-witted, demanding. NOT the knife and NOT the musical accidental. One or two words.",
    "difficulty.nocturne.title": "Difficulty band, hardest of four. A night piece — the late, quiet, difficult one. Borrowing the musical term untranslated is fine where that word exists. One or two words.",

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

    # First-week tips (PRD-34). Three for the lifetime of the install, so each
    # one is a player's only instruction on that feature. One sentence, calm,
    # never an imperative to go and do it now.
    "tip.undo": "One of three lifetime tips, shown once in a chip. Explains that undo exists and that nothing can be ruined. Two short sentences; reassuring, never scolding.",
    "tip.pencil": "One of three lifetime tips, shown once in a chip. Explains that the pencil toggle turns entry into corner notes. \"the rose\" is Nine's circular digit picker — keep the metaphor if the language has one, describe it plainly if not.",
    "tip.highlight": "One of three lifetime tips, shown once in a chip. Explains that tapping a placed digit highlights every other copy of it on the board.",
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
        localizations["en"] = {
            "stringUnit": {"state": "translated", "value": english}
        }
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
            was = (previous[key].get("localizations", {}).get("en", {})
                   .get("stringUnit", {}).get("value"))
            if was != english or previous[key].get("comment") != COMMENTS[key]:
                changed.append(key)

    removed = sorted(set(previous) - set(strings))
    document = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    if not dry_run:
        os.makedirs(os.path.dirname(catalog), exist_ok=True)
        with open(catalog, "w", encoding="utf-8") as handle:
            # Xcode's own formatting: 2-space indent, `" : "` between key and
            # value, keys sorted, no ASCII escaping. Matching it means Xcode
            # opening the catalog does not rewrite the whole file.
            json.dump(document, handle, indent=2, sort_keys=True,
                      separators=(",", " : "), ensure_ascii=False)
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
        ("a key in the catalog that no Swift file names",
         ["home.title", "home.dead"], {"home.title"}, False,
         ["in the catalog, referenced by no Swift file"]),
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

    return 1 if failed else 0


def command_extract(_args):
    sys.exit("--extract is not implemented until Task 5. It will lift the "
             "baselined literals into Sources/Strings/Localizable.xcstrings "
             "and rewrite the call sites to name `Strings.*`. Until then "
             "`--audit` is the whole tool.")


def command_pseudo(_args):
    sys.exit("--pseudo is not implemented until Task 9. It will render a "
             "pseudo-locale (accented, +40% length) from the catalog so "
             "clipped layouts show up before a translator is paid. Until then "
             "`--audit` is the whole tool.")


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
                      help="(Task 9) render the pseudo-locale")
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
