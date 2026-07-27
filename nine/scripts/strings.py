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


CATALOG_KEY_RE = re.compile(r"Strings\.([A-Za-z_][A-Za-z0-9_]*"
                            r"(?:\.[A-Za-z_][A-Za-z0-9_]*)*)")


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
    """Every `Strings.foo.bar` named anywhere in the app trees."""
    keys = set()
    for tree in TREES:
        root = os.path.join(nine, tree)
        for dirpath, _dirs, files in os.walk(root):
            for name in files:
                if not name.endswith(".swift"):
                    continue
                with open(os.path.join(dirpath, name), "r",
                          encoding="utf-8") as handle:
                    source = strip_comments(handle.read())
                keys.update(CATALOG_KEY_RE.findall(source))
    return keys


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
    args = parser.parse_args(argv)

    if args.extract:
        return command_extract(args)
    if args.pseudo:
        return command_pseudo(args)
    if args.selftest_catalog:
        return command_selftest_catalog(args)
    return command_audit(args)


if __name__ == "__main__":
    sys.exit(main())
