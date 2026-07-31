// DesignTokens.swift — the scale layer Nine has never had.
//
// `Theme.swift`'s own header says what it is: "the board's palette, and nothing
// else". That is accurate and it is the whole problem — colour is the only
// token layer in the app, and it is excellent (measured against the composited
// glass, pinned by `AppearancePaletteTests`), while every other dimension is
// invented at the call site. The audit that produced this file counted 22
// distinct `spacing:` values, 12 `.padding(n)` values and 20 card radii across
// `Sources/App`, with the two most common spacings — 10 and 14 — both off a
// 4pt grid.
//
// A view that wants "the card radius" has nowhere to ask, so it picks 24 and
// the next view picks 22. This file is where it asks.
//
// **These are unscaled point values, not `CouchScale.chrome` multiplicands.**
// `CouchScale` exists so one *shared component* can be authored once at couch
// distance and shrink to the hand; a token consumed by `#if os(iOS)` view code
// has already chosen its platform and multiplying it again is how a 44pt hit
// target became 24.2pt (see `Hit.min`). Multiply a token by `CouchScale.chrome`
// only inside `couchkit/`, never here.
//
// **This file is on the app target *and* on the watch target.** (The paragraph
// that used to stand here said the watch list "stops before this one". It does
// not, and has not since `BoardType` landed: `nine/project.yml` names
// `Sources/App/DesignTokens.swift` in the watch app's sources, right after
// `BoardView.swift`, with a comment explaining that the board draws its digits
// from `BoardType` and a hand-copy of a scale is a scale that drifts. Corrected
// here rather than in the project file, which this order does not own.)
//
// Two consequences, and they are the constraints on everything below:
//
//   • It must compile for watchOS. SwiftUI only, and no dependency outside the
//     watch target's own source list (`BoardView.swift`, `BoardAccessibility.swift`,
//     `Theme.swift`, `Sources/Engine`, `Sources/Shared`, `Sources/Strings`) plus
//     CouchKit, which the watch target links.
//   • The widget extension compiles no App sources at all, so nothing here may
//     become load-bearing for *that* process.
//
// The material and specular constants deliberately do **not** live here — they
// are `CouchSpecular` in `couchkit/Sources/CouchKit/CouchGlass.swift`, because
// four other apps need them too and a token with two homes has none. This file
// is the scale layer: space, corners, hit targets, scrims, board type.
import SwiftUI

/// The spacing scale. A 4pt grid with two deliberate off-grid rungs at the
/// extremes (`hair` for optical separators, `xxl`/`couch` for the big breathing
/// room a full-bleed game screen needs).
///
/// Naming is by *rank*, not by use, so a view never has to decide whether its
/// gap is "card spacing" or "row spacing" — it decides how far apart two things
/// should feel and picks the rung.
enum Space {
    /// 2 — an optical separator: the gap that reads as "touching, but not one
    /// thing". Notes inside a cell, a rule under a label.
    static let hair: CGFloat = 2
    /// 4 — glyph-to-glyph inside a single composed element.
    static let xs: CGFloat = 4
    /// 8 — icon-to-label, chip internals.
    static let s: CGFloat = 8
    /// 12 — sibling controls in one cluster.
    static let m: CGFloat = 12
    /// 16 — the default. Rows in a list, cards in a stack, sheet gutters.
    static let l: CGFloat = 16
    /// 20 — a card's internal padding when it holds more than one line.
    static let xl: CGFloat = 20
    /// 28 — section-to-section inside a screen.
    static let xxl: CGFloat = 28
    /// 40 — screen-level margins, the gap above a primary action.
    static let hero: CGFloat = 40
    /// 56 — the full-bleed rung: chrome-to-content on a screen that is mostly
    /// one object. Named for the couch because tvOS is where it started.
    static let couch: CGFloat = 56
}

/// The corner scale. Every radius in the app is one of these, so a card and the
/// tile inside it can never accidentally agree (which reads as one flat shape)
/// or disagree by 2pt (which reads as a mistake).
enum Radius {
    /// 8 — a chip, a swatch, a keycap.
    static let chip: CGFloat = 8
    /// 12 — a tile inside a card.
    static let tile: CGFloat = 12
    /// 16 — a control: a segmented row, a button, a stepper.
    static let control: CGFloat = 16
    /// 22 — a card. The shelf's boards, the stat cards, the board's own frame.
    static let card: CGFloat = 22
    /// 28 — a sheet or a panel.
    static let sheet: CGFloat = 28
    /// 40 — a hero surface: the board card on a large screen, the share card.
    static let hero: CGFloat = 40

    /// Apple's icon superellipse ratio — radius as a **fraction of the side**,
    /// not a point value. Multiply by the square's edge before use:
    /// `RoundedRectangle(cornerRadius: side * Radius.iconSquircle)`.
    static let iconSquircle: CGFloat = 0.2237

    /// The radius a shape nested `inset` points inside a shape of radius
    /// `outer` must use for the two curves to stay concentric.
    ///
    /// Two rounded rectangles with the *same* radius, one inset inside the
    /// other, do not look nested — the inner corner is visibly too round. The
    /// correct inner radius is `outer − inset`, floored at 4 so a deeply inset
    /// tile degrades to a soft corner rather than to a hard one.
    static func inner(_ outer: CGFloat, inset: CGFloat) -> CGFloat {
        max(4, outer - inset)
    }
}

/// **Vertical rhythm — the rule round 2 added, and the only token in this file
/// that is a ceiling rather than a value.**
///
/// Nine's own tokens fixed the *small* spacings and left the big ones to the
/// call site, which is how a phone game screen ended up with three unequal
/// voids in it: measured off the shipped frames, ~110pt between the header and
/// the board, ~150pt between the keypad and the action row, and ~60pt below
/// that. Every critic who looked at the screen described it the same way —
/// "three unrelated islands", "no anchor", "the screen has no bottom edge".
///
/// The diagnosis is not that the gaps are large. It is that they are large
/// *and unexplained*: a 200pt gap that separates two sections is composition,
/// and a 150pt gap between two halves of one control cluster is a mistake. So
/// the rule is stated as a ceiling with an escape hatch rather than as a
/// spacing value:
///
/// > **No band of untouched background may exceed `maxDeadBand` unless it is a
/// > flexible spacer doing deliberate compositional work** — centring the board
/// > in the space between two docked clusters, for instance. A fixed
/// > `Spacer(minLength:)` or a `.padding` above that number is the bug.
///
/// Where slack exists, spend it on the board: a sudoku screen has exactly one
/// object worth making bigger.
enum Rhythm {
    /// 40 — the largest fixed run of empty ground allowed between two elements.
    /// Deliberately `Space.hero` and not a new number: the screen-margin rung
    /// *is* the biggest gap that still reads as one composition.
    static let maxDeadBand: CGFloat = Space.hero

    /// 16 — the single internal gap inside a docked cluster. When two control
    /// groups (a digit pad and a tool row, a header and its pager) belong to
    /// one object, exactly one gap of this size separates them and nothing
    /// else does.
    static let cluster: CGFloat = Space.l

    /// 8 — a docked cluster's gap to the safe area. Small on purpose: the
    /// home indicator already reserves its own room, and adding a second
    /// margin on top of it is what floats a toolbar 60pt off the bottom of
    /// the screen.
    static let dock: CGFloat = Space.s
}

/// Touch-target floors.
enum Hit {
    /// The platform floor for a touch target — 44pt, from the HIG.
    ///
    /// **Never multiplied by `CouchScale.chrome`, and that is the bug this
    /// constant exists to end.** `CouchScale.chrome` is 0.55 on iOS, so a
    /// shared component that wrote `44 * CouchScale.chrome` shipped a **24.2pt**
    /// target — which is what the Preferences accent swatches actually are today
    /// while `Tests/AXBaselines/prefs.txt` records 44. A floor that scales is
    /// not a floor. A finger is the same size on every screen.
    static let min: CGFloat = 44
}

/// The three scrims, so the app stops having four recipes for "dim what is
/// behind this".
///
/// Shipped today: `0.45` (CouchKit's `GlassSheet`), `0.45 * progress` (TouchUI's
/// hand-rolled twin), `0.55` (First Run, School) and `0.34` (the tutorial) —
/// four numbers for three jobs, all of them flat black on every theme.
///
/// Two axes, both deliberate:
///
/// * **Weight follows the ground's leaning, and the light value is *lower*.**
///   A 0.62 black over Paper is a bruise; a 0.42 black over Void barely
///   registers. The dark grounds need more scrim, not less, because there is
///   less luminance to take away.
/// * **On dark themes the scrim is the theme's own ground, not black.** A flat
///   black scrim over Blueprint or Ember greys the app out — it desaturates the
///   one thing that made the theme a theme. Scrimming with the ground dims the
///   card *and* pushes it toward the backdrop, which is what "recede" means.
///   Light themes keep black, because scrimming a bright ground with itself
///   would brighten rather than dim.
enum Scrim {
    // MARK: Overlay — a panel floating over live content

    /// The default: a sheet, a drawer, a coach card. Content behind stays
    /// legible on purpose (the suite's rule is that glass floats over live
    /// content, never over a blanked screen).
    static func overlay(isLight: Bool) -> Color {
        .black.opacity(isLight ? 0.42 : 0.62)
    }

    /// Theme-aware overlay — prefer this wherever a `ThemeTones` is in hand.
    static func overlay(for tones: ThemeTones) -> Color {
        tones.isLight ? .black.opacity(0.42) : tones.background.opacity(0.62)
    }

    /// The dark-ground default, for the handful of call sites with no tones to
    /// hand (`Scrim.overlay` with no argument list).
    static var overlay: Color { overlay(isLight: false) }

    // MARK: Modal — a takeover the player must answer

    /// First Run and the tutorial: the screen behind is context, not content.
    static func modal(isLight: Bool) -> Color {
        .black.opacity(isLight ? 0.55 : 0.74)
    }

    static func modal(for tones: ThemeTones) -> Color {
        tones.isLight ? .black.opacity(0.55) : tones.background.opacity(0.74)
    }

    static var modal: Color { modal(isLight: false) }

    // MARK: HUD — a transient badge that must not blank the board

    /// The lightest rung: a toast, a probe, a status pill's own backdrop. Never
    /// theme-tinted — a HUD is chrome, and chrome stays neutral (CouchUI's art
    /// direction line).
    static func hud(isLight: Bool) -> Color {
        .black.opacity(isLight ? 0.24 : 0.44)
    }

    static var hud: Color { hud(isLight: false) }
}

/// One grammar for every digit Nine draws, **expressed as a fraction of one
/// cell's side** rather than as a point size.
///
/// The board is drawn at five different scales — the game board, the shelf's
/// mini-boards, the fingerprint, the share card and the widget — and each of
/// them re-derived its own type sizes from its own cell size, which is why the
/// same puzzle reads as a different object in each. A fraction is the only form
/// of this constant that survives the scale change.
///
/// **The reference is cap height to cell side, and the em is not the cap.** A
/// newspaper sudoku sets its entries at 50–55% of the cell *measured at the cap*.
/// SF's cap height is ~0.72 em, so a `Font.system(size: 0.56 * cell)` lands the
/// cap at 0.56 × 0.72 ≈ **40%** of the cell — which is exactly the number the
/// audit called undersized, not a fix for it.
///
/// **0.56 was therefore a no-op and this is the correction.** `BoardView` derives
/// `scale = size.width / 900` and `cell = size.width / 9`, so `cell == 100 *
/// scale` exactly and the shipped `56 * scale` *was already* `0.56 * cell`.
/// Adopting the token at 0.56 changed nothing on the board and quietly shrank
/// every other surface that adopted it. 0.66 puts the cap at ≈47.5%, inside the
/// reference band, and is the size `BoardView` now draws.
///
/// Kept in sync with `BoardInk` in `BoardView.swift`, which is a deliberate
/// second copy: this file is on the **app** target only, and `BoardView.swift` is
/// also on the **watch** target's hand-written source list, so the board cannot
/// import these tokens. Two copies with a comment beats a board that will not
/// compile for the wrist.
enum BoardType {
    /// A committed digit — the player's own entry. 0.66 × cell.
    static let entry: CGFloat = 0.66
    /// A clue printed with the puzzle. Same size as an entry by design: a given
    /// and an entry are the same *kind* of mark and differ by weight and tone,
    /// never by size. Two sizes in one grid is what makes a board look ransom-
    /// noted.
    static let given: CGFloat = 0.66
    /// The live-flick preview drawn before commit. Identical to `entry` so the
    /// digit does not resize the instant it lands — the board used to shrink a
    /// committed digit by 10% and a committed note by 18%.
    static let ghost: CGFloat = 0.66
    /// A pencil mark. 0.22 × cell — three of them across a cell with air.
    static let note: CGFloat = 0.22
    /// A pencil-mark preview. Same as `note`, same reason as `ghost`.
    static let noteGhost: CGFloat = 0.22
    /// A killer-cage sum in the corner of a cell.
    static let cageSum: CGFloat = 0.22
    /// The pitch of the 3×3 mini-keypad pencil marks sit on, as a fraction of the
    /// cell. Not derivable from `note`: the glyph size and the grid it is placed
    /// on are separate decisions, and at 0.28 (the old inline value) three notes
    /// crowded the cell's centre instead of reading as a keypad.
    static let notePitch: CGFloat = 0.33

    /// A given is one weight *step and a half* above an entry, not one: at 0.66
    /// of a cell, `.semibold` against `.regular` is the smallest difference that
    /// still reads at a glance without making the givens look bold.
    static let givenWeight: Font.Weight = .semibold
    /// The player's own marks. Regular, so the grid the puzzle came with stays
    /// visibly the skeleton and the player's work stays visibly additions.
    static let entryWeight: Font.Weight = .regular
    /// Pencil marks. Medium rather than regular because at 0.22 of a cell a
    /// regular stroke disappears into the hairlines.
    static let noteWeight: Font.Weight = .medium
}
