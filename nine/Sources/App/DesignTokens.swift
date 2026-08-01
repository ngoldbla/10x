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

    /// **The area rule, round 4.** `maxDeadBand` is a *linear* ceiling and the
    /// iPad frames slipped past it sideways: no single band exceeded 40pt, and
    /// the panel still measured **37–50% of the canvas as untouched ground** by
    /// area, because the composition was one phone-width column centred in a
    /// 1024pt-wide screen. A rule stated in points cannot see that.
    ///
    /// > **No more than `maxEmptyFraction` of a screen's area may be bare
    /// > ground.** Ground *behind* something (a board under a floating bar, a
    /// > card's own backdrop) does not count as bare — it is being refracted,
    /// > which is the whole point of lighting it.
    ///
    /// 0.28 rather than a rounder number because that is roughly where the
    /// reference frames sit: Apple's Fitness and Journal iPad layouts measure
    /// 24–30% ground, and they are the two the panel kept naming.
    ///
    /// The cure for a screen over budget is almost never "add chrome". It is
    /// `NineLayout.columns(for:)` — a second column of real content — or spending
    /// the slack on the board, which is the one object on this screen worth
    /// making bigger.
    static let maxEmptyFraction: Double = 0.28
}

/// **Where the rails are.** The rung above `Space`: `Space` says how far apart
/// two things sit, `NineLayout` says where the screen's own edges are and how many
/// columns fit between them.
///
/// It exists because round 4 measured two stacked slabs of the same material —
/// the board container and the keypad container on the iPad game screen —
/// starting at x=32px and x=40px: a 4pt jog between two things that are
/// obviously one object. Neither number was wrong on its own; there was simply
/// nowhere to ask what the rail was. This is that place, and the rule is that a
/// screen resolves `gutter(for:)` **once** and every full-width element on it
/// uses that value.
// Named `NineLayout`, not `Layout`: SwiftUI ships a `Layout` protocol, and a
// same-module type of that name shadows it — `PrefsSheet`'s `SwatchFlow: Layout`
// stopped compiling with "inheritance from non-protocol type" the moment this
// enum was called `Layout`. Do not shorten it back.
enum NineLayout {
    /// The screen's horizontal rail, resolved from the *container's* width
    /// (never from the device: an iPad in a 320pt Slide Over is a phone).
    ///
    /// Three rungs, all off `Space`, because a rail that is not on the spacing
    /// scale makes every gap measured from it off-scale too.
    static func gutter(for width: CGFloat) -> CGFloat {
        switch width {
        case ..<420: return Space.l      // 16 — a phone, or a narrow pane
        case ..<760: return Space.xl     // 20 — a large phone, a split pane
        default: return Space.xxl        // 28 — an iPad, a Mac window
        }
    }

    /// 560 — the widest a **single column of chrome** may grow.
    ///
    /// Not a text measure (that is ~65 characters and narrower); this is the
    /// width past which a stack of cards stops reading as a list and starts
    /// reading as a stretched phone layout. Every iPad finding about "one
    /// phone-width column floating in a sea of grey" is the *absence* of this
    /// constant: the fix is never to let the column grow to 1024, it is to put
    /// a second column beside it.
    static let readable: CGFloat = 560

    /// How many columns of `readable` content fit between the rails.
    ///
    /// Returns 1 on every phone and 2–3 on an iPad, and it is deliberately
    /// conservative — a column needs `readable * 0.62` at minimum before it is
    /// worth splitting, because two cramped columns are worse than one calm
    /// one.
    static func columns(for width: CGFloat) -> Int {
        let usable = width - 2 * gutter(for: width)
        let minimum = readable * 0.62
        guard usable > 0 else { return 1 }
        return max(1, min(3, Int((usable + Space.xxl) / (minimum + Space.xxl))))
    }

    /// 12 — the floor on the gap between two *stroked* siblings.
    ///
    /// Round 4 measured the iPad home toolbar's calendar and gear buttons as
    /// two 43pt circles spanning 718→810pt with **zero** gap: their 1pt rims
    /// intersect, and two tangent circles read as a Venn diagram rather than as
    /// two controls. A rim is a lighting artifact of one object; two of them
    /// touching describes an object that does not exist.
    ///
    /// Either separate by this much, or commit to a **single** glass container
    /// with one continuous rim and an interior divider — never two rims
    /// kissing.
    static let controlGap: CGFloat = Space.m
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
///
/// **Round 4 took every rung down, and that is a refraction fix rather than a
/// taste change.** A scrim is applied *behind* a pane of glass, and a scrim
/// heavy enough to flatten the backdrop leaves the glass with nothing to
/// sample: the panel measured the iPhone Preferences sheet at RGB (41,42,43) at
/// three points 1300pt apart — a constant fill over a board carrying
/// full-brightness blue digits — and wrote "the sheet could be composited over
/// anything and look identical". It could, because at 0.62 the board was gone
/// before the material ever saw it.
///
/// The old numbers were set when the ground was flat and the scrim was the only
/// thing separating a panel from the page. `VoidBackground` now carries a
/// ~3× wider luminance field and the material ladder (`Elevation`) carries the
/// separation, so the scrim's remaining job is smaller: keep the backdrop from
/// competing, and let it through otherwise.
///
///  | rung    | dark        | light       |
///  |---------|-------------|-------------|
///  | overlay | 0.62 → 0.46 | 0.42 → 0.26 |
///  | modal   | 0.74 → 0.60 | 0.55 → 0.38 |
///  | hud     | 0.44 → 0.36 | 0.24 → 0.18 |
enum Scrim {
    // MARK: Overlay — a panel floating over live content

    /// The default: a sheet, a drawer, a coach card. Content behind stays
    /// legible on purpose (the suite's rule is that glass floats over live
    /// content, never over a blanked screen).
    static func overlay(isLight: Bool) -> Color {
        .black.opacity(isLight ? 0.26 : 0.46)
    }

    /// Theme-aware overlay — prefer this wherever a `ThemeTones` is in hand.
    static func overlay(for tones: ThemeTones) -> Color {
        tones.isLight ? .black.opacity(0.26) : tones.background.opacity(0.46)
    }

    /// The dark-ground default, for the handful of call sites with no tones to
    /// hand (`Scrim.overlay` with no argument list).
    static var overlay: Color { overlay(isLight: false) }

    // MARK: Modal — a takeover the player must answer

    /// First Run and the tutorial: the screen behind is context, not content.
    ///
    /// Taken down hardest of the three. The tutorial finding is the argument in
    /// one line: *"lower the 0.62 scrim so the field survives"* — the coach card
    /// is a pane of glass over a practice board, and at 0.74 the board behind it
    /// was a whisper the card could not bend.
    static func modal(isLight: Bool) -> Color {
        .black.opacity(isLight ? 0.38 : 0.60)
    }

    static func modal(for tones: ThemeTones) -> Color {
        tones.isLight ? .black.opacity(0.38) : tones.background.opacity(0.60)
    }

    static var modal: Color { modal(isLight: false) }

    // MARK: HUD — a transient badge that must not blank the board

    /// The lightest rung: a toast, a probe, a status pill's own backdrop. Never
    /// theme-tinted — a HUD is chrome, and chrome stays neutral (CouchUI's art
    /// direction line).
    static func hud(isLight: Bool) -> Color {
        .black.opacity(isLight ? 0.18 : 0.36)
    }

    static var hud: Color { hud(isLight: false) }
}

/// **The elevation ladder — what is above what, and by how much.**
///
/// The one thing round 4 proved the app has never had. Colour is tokenised,
/// space is tokenised, the *material* is tokenised in CouchKit — and the
/// question every one of those answers is "what does this surface look like",
/// never "where does it sit in the stack". So each view answered it locally, and
/// the local answers do not compose:
///
/// * On the History sheet an **empty** heat cell measured (56,57,57) while the
///   stat tiles and the Game Center row measured (45,46,46). The one square on
///   the screen with no data in it was the brightest object in the sheet.
/// * On the iPhone home shelf every card — Today, Continue, three difficulty
///   tiles, two channels — was the same ~4% white fill with the same 1pt
///   hairline. Seven ranks of importance, one elevation.
/// * On the iPad game screen the nav capsule sampled a constant lift over the
///   canvas with a uniform hairline: chrome and content at the same altitude.
///
/// The ladder is five rungs, and the ordering is a **law**, not a suggestion:
///
/// ```
/// ground  <  panel  <  track  <  card  <  data
/// ```
///
/// Read it as the History sheet reads: the sheet is a `panel`, an empty heat
/// cell is a `track` cut into it, a stat tile is a `card` sitting on it, and a
/// *filled* heat cell is `data` and outranks all of them. That sentence is
/// exactly the fix the panel asked for — "sheet < empty cell < container <
/// data" — generalised so no surface has to re-derive it.
///
/// **What each rung is made of**, so this stays a system rather than a table of
/// numbers. The material rungs are CouchKit's (`CouchGlass.swift`); the fill is
/// this file's; the rim and the lift are `couchRim` / `couchElevated`:
///
/// | rung     | material                    | fill                        | rim | lift |
/// |----------|-----------------------------|-----------------------------|-----|------|
/// | `ground` | none — `VoidBackground`     | none                        | no  | no   |
/// | `panel`  | `couchGlass` / `couchGlassBar` | `Elevation.fill(.panel,…)` | yes | no   |
/// | `track`  | `couchInset(in:tint:)`      | `Elevation.fill(.track,…)`  | no  | no   |
/// | `card`   | `couchInset` on a panel, `couchGlassElevated` on the ground | `.card` | yes | on the ground only |
/// | `data`   | none — it is ink or accent  | `.data` only when it needs a plate | no | no |
///
/// **Two rules that are not obvious and are load-bearing:**
///
/// 1. **Never two materials in a stack.** A `card` inside a `panel` uses
///    `couchInset` (CouchKit's L4, `.identity` glass — shape and tint, no second
///    lens). Glass inside glass reads as one murkier pane, which is how twelve
///    sites in this app measured 1.03:1 against their own background.
/// 2. **On paper you may lift until you hit white, and then you must recess.**
///    A light-leaning `card` is pure white on a near-white `panel`; a second
///    tier inside *that* has nowhere left to go and takes `track` instead. This
///    is why `fill` is not a signed multiplier: the direction of "up" changes.
enum Elevation: Int, Comparable, CaseIterable, Sendable {
    /// The lit ground. `VoidBackground` draws it and nothing else may claim it —
    /// a view that paints its own opaque page has deleted the field every pane
    /// of glass above it was going to refract.
    case ground = 0
    /// The big surface: a sheet, a drawer, a bar, the board's own card.
    case panel = 1
    /// A region *marked out inside* a panel rather than an object on it: an
    /// empty heat cell, a segmented control's groove, an unfilled progress bar,
    /// the dish under a keycap. Above the panel because it is a deliberate mark;
    /// below a card because there is nothing in it.
    case track = 2
    /// An object sitting on a panel — a stat tile, a shelf row, a tier card, a
    /// key in a pad. The rung that carries a rim.
    case card = 3
    /// The mark that must outrank its own container: a filled heat cell, a
    /// committed digit, the number in a stat tile. Usually ink or the accent
    /// rather than a fill — ask for the fill only when data needs a plate.
    case data = 4

    static func < (lhs: Elevation, rhs: Elevation) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// The wash this rung composites over **the surface immediately behind it**,
    /// not over the ground. Pass it to `couchInset(in:tint:)`, or `.background`
    /// it under a shape.
    ///
    /// The dark values are white-ish washes over a composited glass ground that
    /// measures ~19 on Void, and they were solved from the panel's own targets:
    /// a `track` lands at **42.6** (the finding asked for 40–44), a `card` at
    /// **55.6** (it asked for the containers to sit above the empty track,
    /// which shipped at 56 with the tiles at 45 — exactly inverted), and `data`
    /// at **75.6**. The hue is the theme's, never pure white — see
    /// `ThemeTones.surfaceHue` — so a Blueprint tile is a *blue* tile and Ember's
    /// is warm, which is most of what makes a theme survive a screenshot.
    static func fill(_ level: Elevation, on tones: ThemeTones) -> Color {
        tones.isLight ? lightFill(level, tones) : darkFill(level, tones)
    }

    private static func darkFill(_ level: Elevation, _ tones: ThemeTones) -> Color {
        switch level {
        case .ground: return tones.surfaceHue.opacity(0)
        case .panel: return tones.surfaceHue.opacity(0.045)
        case .track: return tones.surfaceHue.opacity(0.10)
        case .card: return tones.surfaceHue.opacity(0.155)
        case .data: return tones.surfaceHue.opacity(0.24)
        }
    }

    /// Paper's ladder, and it is not the dark one inverted. Rule 2 above: a
    /// `panel` takes the page to near-white, a `card` goes the last step to
    /// white, and everything below a panel is cut *into* it with `wellHue` —
    /// the theme's own deep tone, so Camel's grooves are warm rather than grey.
    private static func lightFill(_ level: Elevation, _ tones: ThemeTones) -> Color {
        switch level {
        case .ground: return tones.surfaceHue.opacity(0)
        case .panel: return tones.surfaceHue.opacity(0.60)
        case .track: return tones.wellHue.opacity(0.05)
        case .card: return tones.surfaceHue.opacity(1.0)
        case .data: return tones.wellHue.opacity(0.13)
        }
    }

    /// Whether this rung carries `couchRim`. Stated as a token so a view does
    /// not have to remember: a `track` with a rim reads as an empty *object*,
    /// which is exactly the History defect.
    var wantsRim: Bool { self == .panel || self == .card }

    /// Whether this rung carries `couchElevated`'s shadow. Only a card standing
    /// on the **ground** does; a card on a panel is flush and takes `couchRim`
    /// alone, because a control panel where every tile has a drop shadow is a
    /// pile of stickers (CouchKit's own note on `couchRim`).
    func wantsLift(over parent: Elevation) -> Bool {
        self == .card && parent == .ground
    }
}

/// **Foreground weights, and the floor under them.**
///
/// The panel sampled the iPad channel toolbar and got a glyph at L=146 on a
/// capsule fill at L=91: **2.15:1**, under WCAG 1.4.11's 3:1 for a graphical
/// object, and two adjacent buttons that merge into one grey blob at arm's
/// length. The cause is a habit, not an oversight — a symbol inside a container
/// gets `.secondary` because that is what a symbol in a *list row* gets. Inside
/// glass it is wrong twice: the container has already dimmed, and the symbol is
/// the control's entire content.
///
/// So the rule this enum exists to state:
///
/// > **A glyph that is a control's only content is `Ink.glyph`. Never
/// > `.secondary`, never an opacity.** Dim the *container* if the control needs
/// > to recede — `Elevation.fill(.track,…)` instead of `.card` — and leave the
/// > symbol alone. A control you cannot see is not a quiet control.
enum Ink {
    /// WCAG 1.4.11: a graphical object, and the boundary of any control, needs
    /// 3:1 against what is immediately behind it. Text needs 4.5:1. Neither is
    /// negotiable and both are routinely missed on glass, because the designer
    /// measures against the *page* and the pixel lands on the *capsule*.
    static let graphicalFloor: Double = 3.0
    static let textFloor: Double = 4.5

    /// A symbol that is a control's only content. Full strength, always.
    static func glyph(on tones: ThemeTones) -> Color { tones.digitTone }

    /// A title, a value, a row's primary label.
    static func label(on tones: ThemeTones) -> Color { tones.digitTone }

    /// A caption, a unit, a row's second line. The lowest rung that still
    /// carries meaning.
    static func secondary(on tones: ThemeTones) -> Color {
        tones.digitTone.opacity(tones.isLight ? 0.68 : 0.72)
    }

    /// Decoration: a separator's label, a placeholder, a disabled row. Below
    /// this the text is no longer required to clear `textFloor` because it is no
    /// longer required to be read — which is also the test for whether a string
    /// belongs here at all.
    static func tertiary(on tones: ThemeTones) -> Color {
        tones.digitTone.opacity(tones.isLight ? 0.50 : 0.52)
    }
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
