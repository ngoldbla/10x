// HistorySheet.swift — the record of every solved board: totals, best times
// per difficulty, the recent log, and the door into Game Center. Lives in
// the same GlassSheet shell as prefs (the suite's one secondary surface —
// only ever one open at a time). On macOS the same content fills the History
// window opened from the Game menu (⌘Y, PRD-4 §2.6); on tvOS it opens from a
// shelf History card, reachable by remote and pad alike (PRD-5 §2.3).
//
// **Everything drawn here is INSIDE a pane of glass, and that is the fact this
// file kept forgetting.** `GlassSheet` already wraps the panel in
// `.couchGlass(in: RoundedRectangle(cornerRadius: 28))`, and the stat cards, the
// Game Center row, the tvOS close disc and `TableView`'s pills each asked for
// `.regular` glass again inside it. Two lenses stacked do not read as two
// surfaces; they read as one slightly murkier one. Measured on the shipped
// build, the card edge went 221 → 221 → 221 in light mode — a one-level step,
// **1.005:1** — which is a card that does not exist. Every child now uses wave
// 1's `couchInset` (L4: shape and tint, never a second material), through the
// one `historyInset` helper below, so there is a single place to change it and
// a single place for the contrast harness to aim at.
//
// **Round 2 — what fourteen blind critics saw and this file answers.** Two of
// their three blockers on this surface were here:
//
//  1. *"The 84-cell heatmap reads as a loading skeleton, not an empty state."*
//     It was 84 identical opaque squares at one tone with no axis on it, and a
//     grid with no axis is a shimmer placeholder. `HeatFigure` gives it the
//     semantics it was already pretending to have — weekday initials down the
//     left rail, month caps across the top, a less→more tonal legend beside the
//     section label — and drops the *unfilled* tone from 10% to 5%, so ink
//     recedes into ground instead of competing with it. All four are locale
//     data, not copy: the letters come from `ArchiveCalendar.weekdayInitials`
//     (the one live locale bug PRD-20 found and fixed) and the caps from a
//     UTC-pinned `DateFormatter`, because a day ordinal *is* a UTC midnight and
//     reading one back locally puts every player west of Greenwich a day out.
//  2. *"Zero semantic colour and zero material in the sheet."* Every inset now
//     carries `couchRim` on top of its themed hairline. The hairline is the
//     *boundary* — it is what the contrast harness measures and it works on any
//     ground; the specular rim is the *light*, bright along the top arc and
//     genuinely dark along the bottom lip, which is the difference between a
//     card and a rectangle of fill. Both, in that order, and neither replaces
//     the other.
//
// Three smaller ones, all recorded at their site: the three em-dashes across
// points / solved / best streak read as a data-fetch failure and are now real
// zeros; the empty-state paragraph was centre-set inside a flush-left sheet and
// is now on the same rule as everything else; and the scroll had no edge
// treatment, so a sheet with four sections below the fold looked like the whole
// story.
//
// **Round 3 — and one of its two blockers here is a number round 2 set.**
//
//  1. *"Empty heat grid has almost no contrast — the chart is invisible.
//     Empty cells sit ~2% above the sheet fill, so the 12×7 figure reads as
//     noise."* Round 2 dropped `heatEmpty` from 10% to 5% on a critic's
//     prescription and overshot: 0.05 of the theme's ink measures 1.11:1 on
//     paper. The two readings are reconcilable and the constant's own note
//     works through it — what round 2 actually diagnosed was a grid with no
//     axis, and the axis is what `HeatFigure` added. It is 0.15 now.
//  2. *"Material is inverted — cards are darker than the sheet"*, the round's
//     third acceptance rule, filed against four surfaces. `HistoryMetrics.fill`
//     is white on light grounds now instead of the theme's near-black ink, its
//     hairline drops to a 0.5pt separator, and `historyLift` puts the ambient
//     shadow under a light card that the tone step no longer buys. Because
//     every child of this sheet — the stat tiles, the Game Center row, the
//     recent log, `TableView`'s seats and `SchoolView`'s ten lesson rows — goes
//     through `historyInset`, that is one edit for five surfaces.
//  3. *"Corner radii are not concentric — the tile radius should be sheet
//     radius minus its inset."* `childRadius` is derived from the compact
//     sheet's actual 38pt corner and 22pt padding now, which is 16, which is
//     what `PrefsSheet` had already derived for the same object.
//  4. *"The sheet detent slices the Game Center row through its label."* The
//     detent is `couchkit/GlassComponents.swift`'s and is filed as a cross-file
//     need. What is fixed from here is the *fade*: `edgeFade` is scaled by the
//     scroll's own remaining travel, so neither end dissolves a row that has
//     nothing beyond it.
#if os(iOS) || os(macOS) || os(tvOS)
import Foundation
import SwiftUI
import CouchKit

// MARK: - The sheet's own scale

/// The numbers this surface and `TableView` share.
///
/// Two files draw one sheet, and before this they disagreed about every
/// dimension in it: three container heights measured 67.7 / 63.7 / 44.0pt, three
/// corner radii 16 / 16 / 14, and the body copy came in at 13pt in one file and
/// 12pt in the other. None of those differences meant anything — they are what
/// happens when two authors each pick a plausible number — and all of them are
/// visible as a surface that does not quite line up with itself.
enum HistoryMetrics {

    // MARK: Shape

    /// The radius of anything drawn inside the sheet's panel.
    ///
    /// **Concentric, not merely "rounded".** `Radius.inner(_:inset:)` is the
    /// rule: a child inset `N` points inside a panel of radius `R` must use
    /// `R − N` or its corner reads as too round.
    ///
    /// **Sixteen, and it is measured against the presentation this sheet
    /// actually gets.** The old derivation aimed at the trailing panel
    /// (`Radius.sheet` 28, 22pt padding) and landed on a compromise; the compact
    /// sheet a phone sees is `presentationCornerRadius(38)` with `.padding(22)`,
    /// and `Radius.inner(38, inset: 22)` is **16** exactly — `Radius.control`.
    /// A blind panel measured the drift and filed it: *"sheet corner ~38pt, stat
    /// tiles ~12pt, Game Center row ~14pt… the tile radius should be sheet
    /// radius minus its inset (roughly 20–22pt) for concentricity. Derive child
    /// radii from the parent radius and padding instead of hard-coding them."*
    /// This is that derivation, and it is the same one `PrefsSheet.cardShape`
    /// already ran — so the app's two secondary surfaces stop disagreeing about
    /// the corner of the same object.
    static let childRadius: CGFloat = Radius.control

    /// A card or a full-width row: the stat blocks and the Game Center row.
    /// 64 rather than 67.7 and 63.7, which were two paddings that happened to
    /// land 4pt apart around different content.
    static let row: CGFloat = 64

    /// A pill you press. `Hit.min`, and it stays the floor it is — the join and
    /// leave controls were measured at 36pt before a `minHeight` was on them.
    static let control: CGFloat = Hit.min

    /// Section-to-section inside the scroll.
    static let section: CGFloat = Space.xxl

    /// The hairline that gives an inset child an edge. Half a point: this is a
    /// seam between two regions of one surface, not a border around an object.
    static let hairlineWidth: CGFloat = 0.5

    // MARK: Ink

    /// The fill that separates an inset child from the panel it sits in.
    ///
    /// **This is `gridTone`, not `plane`, and the difference is the whole fix.**
    /// The obvious prescription — wash the child in the theme's own ground —
    /// fails twice, and both failures are in `Theme.swift`'s own numbers:
    ///
    /// * On light themes `plane` is built at `planeOpacity 0`, deliberately
    ///   (restoring a light ground costs contrast on every mark the board
    ///   draws). `Color.opacity` *multiplies*, so `plane.opacity(0.55)` on Paper
    ///   or Camel is `0 × 0.55` — perfectly transparent, i.e. exactly the
    ///   1.005:1 step this file exists to end.
    /// * On dark themes it is arithmetically impossible. Against a panel that
    ///   composites to ~20/255 (L ≈ 0.007), *every* darker fill down to pure
    ///   black tops out at (0.007 + 0.05) / 0.05 = **1.14:1**. A dark card
    ///   cannot be separated from a dark panel by darkening it; the +0.05 in the
    ///   WCAG ratio eats the whole range.
    ///
    /// `gridTone` is the theme's ink, and a theme's ink always opposes its
    /// ground — near-white on the six dark themes, near-black on Paper and
    /// Camel. So one expression darkens on light grounds and lightens on dark
    /// ones, which is what "an inset region of this surface" means in both.
    ///
    /// **And on a light ground that is exactly backwards, which is round 3's
    /// single most repeated finding across every sheet in the app.** Two blind
    /// panels wrote it four times, in four places, in the same words: *"material
    /// is inverted and inert — cards are darker than the sheet, nothing
    /// refracts"*, *"rows are opaque gray slabs, darker than the sheet — the
    /// list reads as disabled"*. It became an acceptance rule for the round: **a
    /// card inside a sheet is LIGHTER than the sheet, never darker.**
    ///
    /// The old reasoning was not wrong about the arithmetic, it was wrong about
    /// what a card is. Darkening does buy the biggest luminance step available
    /// on paper — and a darker inset region is what a *well* looks like.
    /// Elevation is brightness: a surface nearer the light is lighter than the
    /// one it floats on, in a dark room and in a bright one alike. Apple's own
    /// grouped model says the same thing in system colours (sheet on
    /// `secondarySystemGroupedBackground`, rows on `systemBackground`), and the
    /// panel prescribed it directly: *"flip the stack to Apple's grouped model…
    /// rows on white with a 0.5pt specular edge and a soft ambient shadow so
    /// the groups read as elevated."*
    ///
    /// So the fill is white on light and the theme's ink on dark — which is the
    /// *same* physical claim twice, because the theme's ink on a dark ground is
    /// near-white. And the separation a light card loses by not darkening is
    /// bought back by the shadow `historyInset` now puts under it, which is the
    /// second half of the same prescription: *"drop the outline strokes on the
    /// tiles in favour of a lighter fill + soft shadow, so elevation comes from
    /// material rather than from borders."*
    ///
    /// 0.75 rather than opaque, so a quarter of the board still bleeds through
    /// and the card is a region of glass rather than a sheet of paper stuck to
    /// it. Dark keeps its solved 0.11 (a 20 panel needs a child at ≥46 for
    /// 1.36:1) untouched — it was already the right direction.
    static func fill(_ tones: ThemeTones) -> Color {
        tones.isLight ? Color.white.opacity(0.75) : tones.gridTone.opacity(0.11)
    }

    /// The seam around an inset child. Same ink, one step up, so the edge is
    /// visible even where a wallpaper happens to sit behind the glass at the
    /// same luminance as the fill.
    ///
    /// **Much lighter on paper now, and that is deliberate rather than a
    /// weakening.** A near-black hairline drawn all the way round a white card
    /// is the "1px stroke is the only depth cue in the frame" a panel named on
    /// three surfaces. With the card lighter than the sheet and a soft shadow
    /// under it, the boundary is already stated twice; this drops to the 0.5pt
    /// separator the panel asked for rather than a border.
    static func rim(_ tones: ThemeTones) -> Color {
        tones.isLight ? Color.black.opacity(0.06) : tones.gridTone.opacity(0.14)
    }

    /// The one surface here that outranks the others: the table's join pill,
    /// which is this sheet's primary action and shipped as bare text on bare
    /// glass (220 interior against a 221 exterior).
    ///
    /// Still `couchInset` rather than `couchGlassTinted` — L3 is a second
    /// `.regular` material and would put the pill straight back into the
    /// nesting it is being rescued from. The accent carries the primacy on its
    /// own. Dark grounds need the heavier wash for the same reason the fill
    /// above does: 0.16 of a mid-luminance accent over a 20 panel only reaches
    /// 1.27:1, and 0.22 reaches 1.42:1.
    ///
    /// **Light grounds tint white rather than washing the panel**, for `fill`'s
    /// reason and by the same rule: 0.16 of a *deepened* accent (Nine darkens
    /// every hue for paper) over a 221 panel is a card darker than the sheet it
    /// sits in, which is the inversion this round exists to end. Mixing 12% of
    /// the accent into white keeps the hue unmistakable and keeps the surface on
    /// the right side of its ground; the accent rim carries the rest.
    static func accentFill(_ accent: Color, _ tones: ThemeTones) -> Color {
        tones.isLight
            ? Color.white.mix(with: accent, by: 0.12).opacity(0.92)
            : accent.opacity(0.22)
    }

    static func accentRim(_ accent: Color) -> Color { accent.opacity(0.45) }

    /// The track behind a *measured* mark: a `TwinBar`'s capsule, a week glyph's
    /// seven pips. Ten percent of the theme's ink — enough that the unfilled
    /// remainder of a bar is legible as "the rest of the scale", because in
    /// those two figures the empty part carries meaning.
    static func track(_ tones: ThemeTones) -> Color { tones.gridTone.opacity(0.10) }

    /// The tone of an **unfilled heat cell**, and the one number in this file
    /// that a critic set.
    ///
    /// It was `track` — the same 10% — which is right for a bar and wrong for
    /// 84 cells: at twelve weeks of nothing, an empty cell repeated 84 times
    /// stops being a track and becomes the subject. Blind round-2 review: *"as
    /// drawn — 84 identical opaque squares at one tone — it is indistinguishable
    /// from a shimmer placeholder"*, and the prescription was 4-6%. Five is the
    /// middle of that, and it is deliberately a **fill and not a stroke**: an
    /// 84-cell hairline grid is a table, and this is a tally.
    ///
    /// **Round 3 put it back up, and the two panels are not actually in
    /// conflict.** Five percent measured out as *"empty cells sit ~2% above the
    /// sheet fill, so the 12×7 figure reads as noise and the 12pt legend
    /// swatches next to it are the only saturated pixels on screen"* — a
    /// blocker, and the reading is right: 0.05 of the theme's ink is 1.11:1 on
    /// paper and 1.13:1 on Void, which is not a mark, it is an absence. What
    /// round 2 actually diagnosed was *"84 identical squares with no axis"*, and
    /// the axis is what `HeatFigure` added; the tone was collateral. At 0.15 the
    /// figure reads as a grid at 1.5:1 on both leanings while every inked cell —
    /// the accent from 0.4 to full — still stands clear of it by a mile.
    static func heatEmpty(_ tones: ThemeTones) -> Color { tones.gridTone.opacity(0.15) }

    // MARK: Type

    /// Body copy: an invitation, a note, an empty state. 15pt regular.
    ///
    /// A scaled literal rather than a ramp token, for the reason `TwinBar`'s own
    /// comment gives — every dimension in this sheet is multiplied by `s` for
    /// couch distance, and a semantic font cannot be multiplied. The *sizes* are
    /// the ramp's all the same: 15 is `body`, 12 is the section rung, 11 is
    /// `caption`.
    static func bodyFont(_ s: CGFloat) -> Font {
        .system(size: 15 * s, weight: .regular, design: .rounded)
    }

    /// A section head. 12pt semibold, and it is set uppercase and tracked by
    /// `HistorySectionHeader` — because before that a header and the sentence
    /// under it both sampled rgb(98,98,98) one point apart, so the header read
    /// as the first line of the paragraph rather than as a label on it.
    static func sectionFont(_ s: CGFloat) -> Font {
        .system(size: 12 * s, weight: .semibold, design: .rounded)
    }

    /// The label under a headline figure, and a row's secondary line.
    static func labelFont(_ s: CGFloat) -> Font {
        .system(size: 11 * s, weight: .medium, design: .rounded)
    }

    /// The heat figure's axis: one weekday letter, one month cap. 9pt, which is
    /// a rung *below* `caption` on purpose — an axis is not content, it is the
    /// thing that lets content be read, and at 11pt the rail competed with the
    /// section label two lines above it.
    static func axisFont(_ s: CGFloat) -> Font {
        .system(size: 9 * s, weight: .medium, design: .rounded)
    }

    // MARK: Scroll

    /// The dissolve at each end of the sheet's scroll, and the margin that
    /// keeps it off the content.
    ///
    /// **Both numbers, or neither.** A mask alone ghosts the first line of the
    /// sheet at rest, which is how you end up fading your own title; the
    /// content margin holds `fade` points of empty scroll at each end so the
    /// gradient only ever eats slack. `margin > fade` by two points so the
    /// first row is fully opaque rather than exactly opaque.
    ///
    /// It exists at all because of a round-2 finding: *"Game Center status and
    /// The Table section are gone from this detent and nothing peeks above the
    /// sheet's bottom edge to say there is more."* A hard clip says the sheet
    /// ended; a dissolve says it continues.
    static let fade: CGFloat = 20
    static let scrollMargin: CGFloat = 22

    // MARK: Prose

    /// Body ink. `.primary` at 0.82 rather than `.secondary`: the shipped sheet
    /// typeset its prose at `.secondary` and its *headers* at `.secondary` too,
    /// so nothing on screen was the thing you were meant to read.
    static let bodyInk = Color.primary.opacity(0.82)
}

extension View {
    /// The one card treatment inside the sheet's glass: L4 inset, a themed fill,
    /// a half-point seam, and the specular rim on top of it. Never a second
    /// material.
    ///
    /// **Two edges, and they are not redundant.** The themed hairline is the
    /// *boundary*: `HistoryMetrics.rim` is the theme's own ink, so it exists on
    /// Paper and on Void alike, and it is what `scripts/contrast-harness.py`
    /// measures. `couchRim` is the *light*: a one-point gradient that runs
    /// bright at `.topLeading`, through nothing, to genuinely dark at
    /// `.bottomTrailing`, plus a second highlight one point inside along the top
    /// arc only. Round 1 shipped the boundary alone and ten of fourteen blind
    /// critics wrote the same sentence about it — *"flat opaque fill plus a
    /// hairline, not a material"*. A tone step tells you where a card ends; only
    /// the specular tells you it has a top surface and a bottom lip.
    ///
    /// Order matters: the specular goes on *last* so it reads as light falling
    /// on the seam rather than as a second border beside it. Where the specular
    /// ramp passes through zero alpha (its middle 20%) the themed hairline shows
    /// through, which is exactly the region a lighting gradient has nothing to
    /// say about.
    ///
    /// - Parameter interactive: whether this child is something the tvOS focus
    ///   engine can land on. See `historyMaterial` for why that is a question a
    ///   material rung has to answer.
    func historyInset(
        _ tones: ThemeTones,
        radius: CGFloat,
        fill: Color? = nil,
        rim: Color? = nil,
        hairline: CGFloat = HistoryMetrics.hairlineWidth,
        interactive: Bool = false
    ) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        return self
            .historyMaterial(in: shape,
                             tint: fill ?? HistoryMetrics.fill(tones),
                             interactive: interactive)
            .overlay(shape.strokeBorder(rim ?? HistoryMetrics.rim(tones), lineWidth: hairline))
            .historyLift(in: shape, tones: tones)
    }

    /// The rim on dark, the rim **and a shadow** on light.
    ///
    /// A light card is now lighter than the panel it sits in
    /// (`HistoryMetrics.fill`), which is the right direction and a much smaller
    /// step than darkening bought: white at 0.75 over a 221 panel is about
    /// 1.27:1 where the old black wash reached 1.44:1. That difference is
    /// exactly what a shadow is for. Round 3's prescription was explicit —
    /// *"drop the outline strokes on the tiles in favour of a lighter fill + a
    /// soft ambient shadow, so elevation comes from material rather than from
    /// borders"* — and `couchElevated` is the suite's existing two-layer
    /// answer: a wide faint ambient plus a tight contact band, drawn as a
    /// blurred fill of the caller's own shape rather than as a `.shadow`
    /// modifier, which would have silhouetted the card's *type* as well.
    ///
    /// Dark grounds get the rim alone, unchanged. There the 0.11 lift is a full
    /// perceptual step (20 → 46) and five stacked groups each casting a shadow
    /// is how a settings surface starts looking like a pile of stickers —
    /// `PrefsSheet.prefsSection`'s recorded reason, which still holds on the
    /// leaning it was written for.
    @ViewBuilder
    func historyLift(in shape: some InsettableShape, tones: ThemeTones) -> some View {
        if tones.isLight {
            self.couchElevated(in: shape, isLight: true)
        } else {
            self.couchRim(in: shape, isLight: false)
        }
    }

    /// `historyInset`'s circular twin, for a disc rather than a card.
    ///
    /// A circle rather than `historyInset(radius: side / 2)`: at a continuous
    /// corner radius of half the side SwiftUI draws a squircle, not a circle,
    /// and a 34pt close-button squircle sitting beside a real `Circle()` focus
    /// ring reads as a rendering bug. The rung — `.identity` glass plus one
    /// hairline rim, never a second material — is the same one, which is the
    /// point of putting it here beside its sibling instead of letting each
    /// caller improvise a disc.
    func historyInsetCircle(
        _ tones: ThemeTones,
        fill: Color? = nil,
        rim: Color? = nil,
        hairline: CGFloat = HistoryMetrics.hairlineWidth,
        interactive: Bool = false
    ) -> some View {
        self
            .historyMaterial(in: Circle(),
                             tint: fill ?? HistoryMetrics.fill(tones),
                             interactive: interactive)
            .overlay(Circle().strokeBorder(rim ?? HistoryMetrics.rim(tones), lineWidth: hairline))
            .historyLift(in: Circle(), tones: tones)
    }

    /// L4 everywhere, with exactly one platform exception.
    ///
    /// `.identity` glass is by definition nothing to put a specular highlight on
    /// — that is what makes it the right rung for a card inside a panel, and it
    /// is also what makes it the wrong rung for a control a Siri Remote has to
    /// be able to see itself land on. A focusable pill on a television that does
    /// not light up is broken in a way no contrast ratio expresses, so tvOS
    /// keeps the interactive rung for the two controls that take focus. The
    /// nesting that costs is against a 44pt-radius panel seen from three metres;
    /// the 1.005:1 card measured in this sheet was on a phone, in the hand.
    @ViewBuilder
    func historyMaterial(in shape: some Shape, tint: Color, interactive: Bool) -> some View {
        #if os(tvOS)
        if interactive {
            self.couchGlassInteractive(in: shape)
        } else {
            self.couchInset(in: shape, tint: tint)
        }
        #else
        self.couchInset(in: shape, tint: tint)
        #endif
    }
}

// MARK: - Section header

/// A label on a group, drawn so it cannot be mistaken for the group's first
/// sentence: uppercase, tracked, a rung smaller than the body copy beneath it
/// and a step back in ink.
///
/// **It speaks in its own case.** `.textCase(.uppercase)` changes the rendered
/// glyphs and VoiceOver reads what is rendered, so "The Table" would have become
/// "THE TABLE" in the accessibility tree — which some voices spell out letter by
/// letter. The explicit `.accessibilityLabel` puts the sentence case back for
/// the three harnesses and for anyone listening.
struct HistorySectionHeader: View {
    let text: String
    let s: CGFloat
    var trailing: String? = nil
    var trailingTint: Color? = nil

    var body: some View {
        HStack {
            label(text, tint: nil)
            Spacer()
            if let trailing {
                label(trailing, tint: trailingTint)
            }
        }
    }

    /// `tracking` is a `Text` method and `textCase` is a `View` one, so the
    /// order of these four is load-bearing rather than stylistic.
    private func label(_ string: String, tint: Color?) -> some View {
        Text(string)
            .font(HistoryMetrics.sectionFont(s))
            .tracking(0.9 * s)
            .textCase(.uppercase)
            .foregroundStyle(tint ?? Color.secondary)
            .accessibilityLabel(string)
    }
}

// MARK: - The seam between two rows of one card

/// A hairline that **fades out at both ends instead of ending on a line.**
///
/// Round 2's second acceptance rule, verbatim: *no hard full-bleed horizontal
/// seam anywhere; bars fade rather than ending on a line.* A rule that runs the
/// full width of a card and stops dead at its rounded corner is the single most
/// reliable tell that a surface was drawn rather than lit — the corner curves
/// away and the line does not follow it, so the eye reads a scratch on the
/// glass. Ramping the alpha to zero over the outer eighth means there is no
/// terminus to notice: it simply runs out.
///
/// One device pixel at 3x, not one point. Between two 56pt rows a 1pt rule is a
/// divider; this is a seam in one surface.
struct HistorySeam: View {
    let tones: ThemeTones
    var leading: CGFloat = 0

    static let thickness: CGFloat = 1.0 / 3.0

    var body: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: tones.gridTone.opacity(0), location: 0),
                        .init(color: tones.gridTone.opacity(0.16), location: 0.14),
                        .init(color: tones.gridTone.opacity(0.16), location: 0.86),
                        .init(color: tones.gridTone.opacity(0), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing))
            .frame(height: Self.thickness)
            .padding(.leading, leading)
            .accessibilityHidden(true)
    }
}

// MARK: - The heat figure

/// The twelve-week tally, **with the axis it always implied.**
///
/// `HeatGrid` (in `StatsViews.swift`) draws the cells and nothing else, which is
/// correct — it is a mark, not a chart. What was missing is everything that
/// turns a field of marks into a reading: which row is which day, where one
/// month ends and the next begins, and what a darker cell means. Without those,
/// 84 squares at one tone is a shimmer placeholder, and that is exactly what a
/// blind round-2 panel called it.
///
/// **Three alignment facts hold this together, and all three are arithmetic
/// rather than eyeballing:**
///
///  * *Every column's row `r` is the same weekday.* Columns step by exactly
///    seven ordinals, so `(start + r) mod 7` is invariant in the column index.
///    That is what makes a single left rail honest rather than a decoration.
///  * *Day ordinal 0 is 2001-01-01, a Monday* — `weekdayIndex` below derives
///    the weekday from that fact. No `Calendar`, no branch.
///  * *The caps row and the grid row share a width.* Both are an `HStack` at the
///    grid's own `4 * s` spacing, both open with the same fixed rail column, and
///    the twelve caps each take `maxWidth: .infinity`. So a cap's column is
///    `(W − rail − 12·gap) / 12` and a cell's is
///    `((W − rail − gap) − 11·gap) / 12` — the same number, which is why the
///    caps sit over their weeks and not near them.
///
/// The whole figure is `accessibilityHidden`. It was already silent — `HeatGrid`
/// emits unlabelled shapes — and the rail would otherwise add nineteen
/// single-character elements to a sheet whose tree three harnesses pin.
struct HeatFigure: View {
    /// Seven — the one calendar constant this figure leans on. It lived in
    /// `DailyTable` until the weekly table was removed (2026-08-02).
    static let daysInWeek = 7

    let columns: [[HeatCell]]
    /// The ordinal of the top-left cell. The rail and the caps are both read off
    /// this, so the figure cannot disagree with the cells it is labelling.
    let startOrdinal: Int
    let accent: Color
    let tones: ThemeTones
    let s: CGFloat

    /// `HeatGrid`'s own inter-cell spacing, mirrored rather than shared: that
    /// view is not this order's to edit, and a rail that guesses the gap is a
    /// rail that drifts by a point per row. If `StatsViews.swift` ever changes
    /// it, this is the line that has to change with it.
    private var gap: CGFloat { 4 * s }

    /// Two letters' worth at `axisFont`, which is what a very-short weekday
    /// symbol needs in the widest locales (Japanese and Korean spend a full
    /// ideograph on it).
    private var railWidth: CGFloat { 13 * s }

    var body: some View {
        VStack(alignment: .leading, spacing: Space.xs * s) {
            caps
            HStack(alignment: .center, spacing: gap) {
                rail
                HeatGrid(columns: columns,
                         accent: accent,
                         emptyTrack: HistoryMetrics.heatEmpty(tones),
                         s: s)
            }
        }
        .accessibilityHidden(true)
    }

    // MARK: The two axes

    private var caps: some View {
        let labels = monthCaps
        return HStack(spacing: gap) {
            // The rail's column, held open with nothing in it. `height: 1` so
            // the row's height comes from the type and not from this spacer.
            Color.clear.frame(width: railWidth, height: 1)
            ForEach(labels.indices, id: \.self) { column in
                Text(labels[column])
                    .font(HistoryMetrics.axisFont(s))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private var rail: some View {
        // Sunday-first, which is the order `veryShortWeekdaySymbols` comes in
        // and the order `weekdayIndex` counts in. The grid's rows are ordinal
        // order, not the locale's week order, so rotating by `firstWeekday`
        // here would be rotating the wrong array.
        let symbols = ArchiveCalendar.weekdayInitials(firstWeekday: 1)
        return VStack(spacing: gap) {
            ForEach(0..<Self.daysInWeek, id: \.self) { row in
                Text(initial(row, symbols))
                    .font(HistoryMetrics.axisFont(s))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .trailing)
            }
        }
        .frame(width: railWidth)
    }

    private func initial(_ row: Int, _ symbols: [String]) -> String {
        // `weekdayInitials` returns seven or nothing — an empty header row is
        // visibly wrong, where a padded one would restore PRD-20's locale bug
        // quietly. Honour that contract rather than second-guessing it.
        guard symbols.count == Self.daysInWeek else { return "" }
        return symbols[Self.weekdayIndex(startOrdinal + row) - 1]
    }

    /// `Calendar`'s convention: 1 = Sunday … 7 = Saturday.
    ///
    /// Ordinal 0 is a Monday, so `ordinal mod 7` is 0 for Monday, and Monday is
    /// 2 in that convention. The double floor-mod is a defence against Swift's
    /// `%` keeping the sign of the dividend — ordinals before 2001 are negative.
    static func weekdayIndex(_ ordinal: Int) -> Int {
        let mondayBased = ((ordinal % 7) + 7) % 7
        return (mondayBased + 1) % 7 + 1
    }

    /// One cap per column, blank where the month has not turned.
    ///
    /// **UTC, and this is the one line in the figure that would be silently
    /// wrong without it.** `ArchiveCalendar`'s file header states the rule: a
    /// day ordinal *is* a UTC midnight, so reading one back through the device's
    /// own timezone puts every player west of Greenwich on the previous day —
    /// which at a month boundary prints "Jun" over the week of 1 July. The
    /// formatter is built per call rather than cached in a `static`: the app is
    /// Swift 6, a `DateFormatter` is not `Sendable`, and one construction per
    /// render of one sheet section is not a cost worth an `nonisolated(unsafe)`.
    private var monthCaps: [String] {
        let formatter = DateFormatter()
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        formatter.calendar = utc
        formatter.timeZone = utc.timeZone
        formatter.locale = .current
        formatter.setLocalizedDateFormatFromTemplate("MMM")

        var out: [String] = []
        var previous: ArchiveMonth?
        for column in columns.indices {
            let ordinal = startOrdinal + column * HeatFigure.daysInWeek
            let month = ArchiveCalendar.month(ofDayOrdinal: ordinal)
            if month == previous {
                // A blank string rather than a conditional view: the caps row
                // takes its height from the type, and an empty `Text` still
                // occupies a line where a `Color.clear` would collapse it.
                out.append("")
            } else {
                out.append(formatter.string(from: ArchiveCalendar.date(forDayOrdinal: ordinal)))
                previous = month
            }
        }
        return out
    }
}

/// The less→more key for `HeatFigure`, drawn as the ramp itself.
///
/// **Five chips and no words**, and the omission is deliberate rather than a
/// gap: `HeatGrid.fill` has exactly five states (empty, one solve, two, three
/// or more, and a daily at full strength) and showing them in order *is* the
/// sentence "darker means more". A legend that needs two words to be read is a
/// legend that needs translating, and PRD-20's rule is that copy comes from the
/// catalog or not at all. The tones below are `HeatGrid.fill`'s own ladder,
/// mirrored for the same reason `HeatFigure.gap` is.
struct HeatLegend: View {
    let accent: Color
    let tones: ThemeTones
    let s: CGFloat

    private var side: CGFloat { 8 * s }

    var body: some View {
        HStack(spacing: 3 * s) {
            ForEach(tonesLadder.indices, id: \.self) { step in
                RoundedRectangle(cornerRadius: 2 * s, style: .continuous)
                    .fill(tonesLadder[step])
                    .frame(width: side, height: side)
            }
        }
        .accessibilityHidden(true)
    }

    private var tonesLadder: [Color] {
        [HistoryMetrics.heatEmpty(tones),
         accent.opacity(0.4),
         accent.opacity(0.65),
         accent.opacity(0.9),
         accent]
    }
}

// MARK: - The sheet

struct HistorySheetContent: View {
    let model: AppModel
    /// tvOS only: a focusable dismiss control so the remote/pad can always leave
    /// the sheet. It used to be load-bearing for a second reason — the Game
    /// Center row was `.disabled` when signed out, so a signed-out TV could have
    /// had nothing for the focus engine to land on. That row is a live control
    /// in both states now, but the close disc stays: a sheet on a television
    /// wants a visible way out, not an inferred one.
    var onClose: (@MainActor () -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    /// The accent resolved for the theme's leaning (themes pin the scheme).
    private var accent: Color { model.prefs.accent.color(isLight: colorScheme == .light) }

    /// Theme tones for re-theming the stat views (muted tracks, empty cells)
    /// so they read on Paper and the tinted themes, not just Void.
    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }

    /// How far the sheet's scroll still has to travel at each end — the input to
    /// the edge fade, so a fade is only ever drawn where there is genuinely
    /// content beyond it. See `edgeFade`.
    #if !os(tvOS)
    @State private var edges = LearnScrollEdges()
    #endif

    /// The new stat sections need a real history to be worth drawing; below
    /// this they collapse (PRD-9 §2 — never an empty chart).
    private static let richStatsThreshold = 5

    /// **Three states, because there were three all along and only two branches.**
    ///
    /// `hasRichStats` gated the charts at five records while `recentSolves`
    /// rendered at one, so a player with three solves read "Solve a board and it
    /// lands here" sitting directly above the three boards that already landed.
    /// A `switch` over a named decision is the shape that cannot produce that:
    /// the seam between 1 and 5 has to be answered here, in the open, rather
    /// than falling out of two conditions that were written apart.
    ///
    /// **The heat grid crosses the seam and the other two do not**, and the
    /// line is drawn by what each mark needs rather than by one threshold
    /// applied to all three. Average-vs-best needs a distribution and the
    /// sparkline needs a run — with three solves both are noise wearing a
    /// chart's clothes, which is what PRD-9 §2 forbids. The grid is a *tally*:
    /// twelve weeks with three days inked is exactly as true as twelve weeks
    /// with sixty, and it is the same drawing the zero state uses to say "this
    /// is the shape of the thing you are filling". Sending a player from a
    /// ghosted grid at zero solves to no grid at all at one would be the
    /// surface taking something away for making progress.
    private enum Face {
        case blank       // nothing solved — the designed zero state
        case seam        // 1…4 solves: totals, the tally, the log — no charts
        case full        // 5+ — the two charts have something to say
    }

    private var face: Face {
        let solved = model.history.records.count
        if solved == 0 { return .blank }
        return solved < Self.richStatsThreshold ? .seam : .full
    }

    /// TV read distance wants everything larger; iOS/macOS keep their exact
    /// pixel sizes (`1.0`), so this widening is byte-identical off the couch.
    private var s: CGFloat {
        #if os(tvOS)
        1.7
        #else
        1.0
        #endif
    }

    /// **The footer is not scroll content.** `Spacer(minLength: 12)` used to sit
    /// inside this `ScrollView`, where a `Spacer` has no height to claim — so it
    /// did nothing, the footer hugged the last row, and the sheet ended with
    /// 242pt of bare glass (32% of its interior) below everything, with the
    /// whole surface crammed into the top 40%.
    ///
    /// The touch caption that lived down there is gone entirely: wave 1 gives
    /// the compact sheet a real grabber and an interactive dismiss, and "Tap
    /// outside to return" measured 2.06:1 in light mode — the sentence
    /// explaining how to leave was the hardest thing on the screen to read. The
    /// remote has no discoverable equivalent, so tvOS keeps its line, pinned to
    /// the bottom edge rather than floating after the content.
    ///
    /// **The indicator came back and an edge fade came with it.** `showsIndicators:
    /// false` stood on a scroll whose last visible row at the compact detent is
    /// the Game Center button — Table and Recent are both below the fold with
    /// nothing on screen admitting they exist. A blind round-2 reader called it:
    /// *"nothing peeks above the sheet's bottom edge to say there is more"*. The
    /// bar is one piece of evidence; the dissolve at both ends is the other, and
    /// it is the same treatment `PrefsSheet` already uses, deliberately, so the
    /// suite's one secondary surface behaves one way in both of its modes.
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: HistoryMetrics.section * s) {
                titleRow

                switch face {
                case .blank:
                    zeroState
                case .seam:
                    totalsRow
                    heatSection
                case .full:
                    totalsRow
                    heatSection
                    avgVsBestSection
                    trendSection
                }

                gameCenterRow

                if !model.history.records.isEmpty {
                    recentSolves
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        #if !os(tvOS)
        .contentMargins(.vertical, HistoryMetrics.scrollMargin, for: .scrollContent)
        .learnScrollEdges(into: $edges)
        .mask { edgeFade }
        #endif
        #if os(tvOS)
        .safeAreaInset(edge: .bottom) {
            Text(Strings.string("sheet.dismiss.remote"))
                .font(HistoryMetrics.labelFont(s))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, Space.m * s)
        }
        #endif
    }

    #if !os(tvOS)
    /// A 20pt dissolve at each end — **but only at an end that has something
    /// beyond it.** See `HistoryMetrics.fade` for why it comes with a content
    /// margin two points larger than itself.
    ///
    /// **The height is scaled by the scroll's own travel now, and that is round
    /// 3's fix.** A fixed dissolve is drawn whether or not it is telling the
    /// truth, so at rest the sheet ghosted its own first line and at the foot of
    /// the scroll it ghosted its last — which is the shape of two blockers:
    /// *"the fade over the APPEARANCE card is so strong the partial row is
    /// nearly invisible, so the affordance is lost and the frame ends on a
    /// mushy gradient"*, and the round's fourth acceptance rule, *no fade,
    /// detent or scrim cuts a glyph or a row in half*. At either extreme of the
    /// scroll the corresponding gradient is exactly zero points tall and the
    /// row at that edge is rendered whole; in between, it is the dissolve that
    /// says the content continues.
    private var edgeFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: HistoryMetrics.fade * CGFloat(edges.strength(top: true)))
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: HistoryMetrics.fade * CGFloat(edges.strength(top: false)))
        }
    }
    #endif

    // MARK: - Title

    private var titleRow: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(Strings.string("history.title"))
                .couchText(CouchTypography.title)
            #if os(tvOS)
            if let onClose {
                Spacer()
                Button(action: onClose) {
                    // Interactive glass, and deliberately not the inset rung:
                    // this disc exists to take focus, and the focus engine's
                    // specular response is the only feedback a remote gets.
                    Image(systemName: "xmark")
                        .font(.system(size: 22 * s, weight: .semibold))
                        .padding(18 * s)
                        .couchGlassInteractive(in: Circle())
                        // Interactive glass still needs an edge when it is not
                        // focused, and the focus engine's own specular only
                        // arrives once the remote lands on it. Round 2's rule is
                        // that every glass surface in the app has a visible top
                        // rim, unfocused included.
                        .couchRim(in: Circle(), isLight: tones.isLight)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Strings.string("history.close"))
            }
            #endif
        }
        .padding(.bottom, Space.xs)
    }

    // MARK: - Zero state

    /// The surface's own mark, ghosted — **and the sentence first.**
    ///
    /// `ContentUnavailableView` appears nowhere in this app and this is not the
    /// place it starts: the heat grid is already the drawing this sheet uses to
    /// mean "days you solved", so twelve weeks of it is the honest picture of a
    /// history with nothing in it — the shape of the thing you are about to
    /// fill. It is also most of the dead band the old footer left behind.
    ///
    /// Round 2 changed three things about it, all from one finding — *"the
    /// 84-cell heatmap reads as a loading skeleton"*:
    ///
    ///  * **The copy leads.** A grid arriving before any explanation of it is
    ///    what a skeleton looks like; a sentence arriving first makes the grid
    ///    an illustration of the sentence.
    ///  * **It is the real grid, not a ghost.** `ghostColumns` built twelve
    ///    weeks of positional indices so no day was being claimed — but with no
    ///    records, `heatColumns` produces exactly the same 84 empty cells while
    ///    carrying the *true* start ordinal, which is what lets the rail print
    ///    real weekdays and the caps print real months. A zero state that shows
    ///    you which twelve weeks they were is a better zero state than one that
    ///    shows you an abstraction of them, and it means the drawing does not
    ///    change shape when the first solve lands.
    ///  * **One left rule.** The paragraph was centre-set two lines under a
    ///    flush-left title with a full-bleed tile row beneath it — three
    ///    competing axes in one sheet. It is flush left with everything else now.
    private var zeroState: some View {
        VStack(alignment: .leading, spacing: Space.l * s) {
            Text(Strings.string("history.empty"))
                .font(HistoryMetrics.bodyFont(s))
                .foregroundStyle(HistoryMetrics.bodyInk)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)

            heatSection
            totalsRow
        }
    }

    // MARK: - Totals

    /// **Zeros, not em-dashes, and the previous comment here was wrong.**
    ///
    /// It argued that three `0`s in a row read as a data-load failure and that
    /// a dash was the honest "nothing has been counted". Fourteen critics looked
    /// at the shipped frame and read it the other way round, in the same words:
    /// *"rendering '—' three times across points / solved / best streak reads as
    /// a data-fetch failure"*. They are right and the old reasoning was also
    /// factually shaky — with no records, points, solves and best streak are all
    /// genuinely **zero**, not unknown, so the dash was substituting a mystery
    /// for a fact the app holds.
    ///
    /// So the value is always the real figure and only its *ink* changes: a
    /// dimmed zero says "counted, and it came to nothing", which is both true
    /// and quiet. `blank` therefore no longer picks the string, only the tone.
    ///
    /// `formatted(.number)` rather than string interpolation, for the reason
    /// `recentSolves` gives about its `+`: a figure belongs to the reader's
    /// locale, in the reader's digits.
    private var totalsRow: some View {
        let blank = model.history.records.isEmpty
        // Best time replaced best streak when the streak left (2026-08-02): a
        // third column that is a *time* keeps the row three facts wide without
        // resurrecting a count the covenant no longer keeps.
        let best = model.history.records.map(\.seconds).min()
        return HStack(spacing: Space.s * s) {
            statBlock(value: model.totalPoints.formatted(.number),
                      label: Strings.string("history.stat.points"),
                      blank: blank)
            statBlock(value: model.history.records.count.formatted(.number),
                      label: Strings.string("history.stat.solved"),
                      blank: blank)
            statBlock(value: SolveCardFacts.elapsedText(best ?? 0),
                      label: Strings.string("history.stat.bestTime"),
                      blank: best == nil)
        }
    }

    /// One headline figure.
    ///
    /// **Tabular, like every other figure in the sheet.** This was the only
    /// headline number here without `.monospacedDigit()` — `recentSolves`,
    /// `TwinBar` and the table's own times all have it — which is why three
    /// proportional figures in three equal columns never quite lined up with
    /// each other. `.numericText()` then rolls the digit that changed instead of
    /// crossfading the whole number.
    private func statBlock(value: String, label: String, blank: Bool) -> some View {
        VStack(spacing: Space.xs * s) {
            Text(value)
                .font(.system(size: 22 * s, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())
                // A figure nobody has earned yet is still a figure — it is just
                // not the thing to read first. `.tertiary`'s weight, written as
                // an opacity so the ternary has one type on both arms. Lifted
                // from 0.32 to 0.42 now that it carries a digit rather than a
                // dash: a dimmed glyph that is *also* meaningless can go very
                // quiet, a dimmed zero has to stay readable.
                .foregroundStyle(blank ? Color.primary.opacity(0.42) : Color.primary)
            Text(label)
                .font(HistoryMetrics.labelFont(s))
                .foregroundStyle(.secondary)
        }
        .multilineTextAlignment(.center)
        .padding(.vertical, Space.s * s)
        .frame(maxWidth: .infinity, minHeight: HistoryMetrics.row * s)
        .historyInset(tones,
                      radius: HistoryMetrics.childRadius * s,
                      hairline: HistoryMetrics.hairlineWidth * s)
    }

    // MARK: - Heat grid (last 12 weeks)

    /// Twelve weeks of seven days, oldest column first, today in the bottom
    /// right. Named rather than inlined because `HeatFigure` needs the same
    /// number to label the rows and the columns, and a rail computed off a
    /// second copy of `today - 83` is a rail that goes wrong the first time
    /// somebody edits one of them.
    private var heatStart: Int { model.todayOrdinal - (12 * HeatFigure.daysInWeek - 1) }

    private var heatColumns: [[HeatCell]] {
        let today = model.todayOrdinal
        let start = heatStart                       // 84 days incl. today
        let buckets = model.history.solvesByDay(ordinalRange: start...today)
        return (0..<12).map { col in
            (0..<HeatFigure.daysInWeek).map { row in
                let ord = start + col * HeatFigure.daysInWeek + row
                let day = buckets[ord]
                return HeatCell(id: ord, count: day?.count ?? 0, hasDaily: day?.hasDaily ?? false)
            }
        }
    }

    /// The label row carries the legend, because the legend *is* part of the
    /// label: "Last 12 weeks" says what is being counted and the ramp says how
    /// the counting is drawn. `HistorySectionHeader` already ends in a `Spacer`,
    /// so it takes the width it needs and the key sits hard against the trailing
    /// edge without either of them needing to know the other's size.
    private var heatSection: some View {
        VStack(alignment: .leading, spacing: Space.m * s) {
            HStack(alignment: .center, spacing: Space.s * s) {
                HistorySectionHeader(text: Strings.string("history.section.heat"), s: s)
                HeatLegend(accent: accent, tones: tones, s: s)
            }
            HeatFigure(columns: heatColumns,
                       startOrdinal: heatStart,
                       accent: accent,
                       tones: tones,
                       s: s)
        }
    }

    // MARK: - Average vs. best

    private var avgVsBestRows: [(Difficulty, TimeInterval, TimeInterval)] {
        Difficulty.allCases.compactMap { d in
            guard let avg = model.history.averageSeconds(for: d),
                  let best = model.history.bestSeconds(for: d) else { return nil }
            return (d, avg, best)
        }
    }

    @ViewBuilder
    private var avgVsBestSection: some View {
        let rows = avgVsBestRows
        if !rows.isEmpty {
            let maxAvg = rows.map(\.1).max() ?? 1
            VStack(alignment: .leading, spacing: Space.m * s) {
                HistorySectionHeader(text: Strings.string("history.section.avgVsBest"), s: s)
                ForEach(rows, id: \.0) { difficulty, avg, best in
                    TwinBar(title: Strings.difficulty(difficulty),
                            avg: avg / maxAvg,
                            best: best / maxAvg,
                            bestLabel: SolveCardFacts.elapsedText(best),
                            avgLabel: SolveCardFacts.elapsedText(avg),
                            accent: accent,
                            track: HistoryMetrics.track(tones),
                            s: s)
                }
            }
        }
    }

    // MARK: - Solve-time trend

    @ViewBuilder
    private var trendSection: some View {
        let raw = model.history.trend(window: 20)
        if raw.count >= 2 {
            let lo = raw.min() ?? 0, hi = raw.max() ?? 0
            let span = hi - lo
            let points = raw.map { span > 0 ? ($0 - lo) / span : 0.5 }
            let faster = raw.last! < raw.first!
            VStack(alignment: .leading, spacing: Space.m * s) {
                HistorySectionHeader(
                    text: Strings.string("history.section.trend"),
                    s: s,
                    trailing: faster ? Strings.string("history.trend.faster") : nil,
                    trailingTint: accent)
                Sparkline(points: points, accent: accent)
                    .frame(height: 56 * s)
            }
        }
    }

    // MARK: - Game Center

    /// A live row in both states.
    ///
    /// **The `.disabled` came off, and it was the least readable pixel on the
    /// screen.** It sat on the whole `Button`, so SwiftUI's dimming multiplied
    /// on top of the subtitle's own `.secondary`: "Sign in via Settings to
    /// compete" measured rgb(159,159,157) on rgb(221,220,218) — **1.93:1**,
    /// under even the 3:1 floor for a non-text component. It was also a
    /// cul-de-sac: interactive glass that could not be tapped, telling the
    /// player to go somewhere else. `GameCenter.authenticate()` re-installs
    /// `GKLocalPlayer`'s handler and presents the system sign-in sheet, so the
    /// row now *is* the route it was describing.
    private var gameCenterRow: some View {
        let signedIn = GameCenter.shared.isAuthenticated
        return Button {
            if signedIn {
                GameCenter.shared.showDashboard()
            } else {
                GameCenter.shared.authenticate()
            }
        } label: {
            HStack(spacing: Space.m * s) {
                // Accent, not `.primary`. A round-2 blocker on this sheet was
                // that it had no chroma in it at all — *"the only colour in the
                // frame is the blue page dot in the dimmed background behind
                // it"* — and this is the one glyph on the surface that stands
                // for a door out of the app, which is exactly what an accent is
                // for. `.hierarchical` so the controller's buttons stay legible
                // at a single hue.
                Image(systemName: "gamecontroller.fill")
                    .font(.system(size: 19 * s, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(accent)
                VStack(alignment: .leading, spacing: Space.hair * s) {
                    Text(Strings.string("history.gameCenter.title"))
                        .couchText(CouchTypography.body)
                    Text(Strings.string(signedIn
                                        ? "history.gameCenter.in"
                                        : "history.gameCenter.out"))
                        .font(HistoryMetrics.labelFont(s))
                        // The theme's own ink rather than `.secondary`: this
                        // line is the one that explains the row, and it read at
                        // 1.93:1 while the title above it read at 4.89:1.
                        .foregroundStyle(tones.digitTone.opacity(0.72))
                }
                Spacer()
                // In BOTH states. A chevron is the promise that pressing this
                // goes somewhere, and the state where the player has not been
                // anywhere yet is exactly the one that needed the promise.
                Image(systemName: "chevron.right")
                    .font(.system(size: 13 * s, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, Space.l * s)
            .padding(.vertical, Space.m * s)
            .frame(minHeight: HistoryMetrics.row * s)
            .historyInset(tones,
                          radius: HistoryMetrics.childRadius * s,
                          hairline: HistoryMetrics.hairlineWidth * s,
                          interactive: true)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Recent solves

    /// The log, **inside one card instead of loose on the glass.**
    ///
    /// Fifteen rows of unbacked text under a section label is the shape a list
    /// takes when nobody decided it was a list: the stat tiles, the Game Center
    /// row and the join pill were all cards, and the one place in the sheet
    /// actually holding *records* was the one place with no surface under it.
    /// It is now the same `historyInset` as its siblings — one material rung,
    /// one radius, one specular rim — with rows separated by `HistorySeam`
    /// rather than by air.
    ///
    /// The seam starts at the icon column's trailing edge so the symbols read as
    /// one continuous strip, which is the same rule `PrefsSheet.separator`
    /// follows, and it fades out at both ends so the card's rounded corner is
    /// never crossed by a line that does not curve with it.
    private var recentSolves: some View {
        let records = Array(model.history.records.prefix(15))
        return VStack(alignment: .leading, spacing: Space.m * s) {
            HistorySectionHeader(text: Strings.string("history.recent.title"), s: s)
            VStack(spacing: 0) {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    if index > 0 {
                        HistorySeam(tones: tones, leading: recentSeamInset)
                    }
                    recentRow(record)
                }
            }
            .historyInset(tones,
                          radius: HistoryMetrics.childRadius * s,
                          hairline: HistoryMetrics.hairlineWidth * s)
        }
    }

    /// Where the seam starts: past the card's own padding and the icon column,
    /// so the run of symbols is unbroken down the leading edge.
    private var recentSeamInset: CGFloat { (Space.l + 22 + Space.s) * s }

    private func recentRow(_ record: SolveRecord) -> some View {
        HStack(spacing: Space.s * s) {
            Image(systemName: "square.grid.3x3.fill")
                .font(.system(size: 14 * s, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.secondary)
                .frame(width: 22 * s)
            VStack(alignment: .leading, spacing: 1 * s) {
                // One label per row since the daily left (2026-08-02): the
                // band's name, whatever a legacy record's `isDaily` flag says.
                Text(Strings.difficulty(record.difficulty))
                    .font(CouchTypography.label)
                Text(record.date.formatted(date: .abbreviated, time: .omitted))
                    .font(HistoryMetrics.labelFont(s))
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Text(SolveCardFacts.elapsedText(record.seconds))
                .font(CouchTypography.label)
                .monospacedDigit()
                .foregroundStyle(.secondary)
            // The `+` is a sign, not a word. `history.recent.points`
            // was `"+%1$lld"` — a translation unit whose entire content
            // is a specifier and an ASCII plus, which is the shape a
            // pseudolocalizer or a translator who does not read printf
            // destroys. `.sign(strategy: .always())` gives the locale's
            // own plus, in its own digits, in its own position; Arabic
            // even puts an invisible mark in front of it (PRD-20 Task 8).
            Text(record.points.formatted(.number.sign(strategy: .always())))
                .font(CouchTypography.label)
                .monospacedDigit()
                .foregroundStyle(accent)
        }
        .padding(.horizontal, Space.l * s)
        .padding(.vertical, Space.m * s)
    }
}
#endif
