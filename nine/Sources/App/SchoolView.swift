// SchoolView.swift — Technique School (PRD-25 §2.3).
//
// One lesson per technique, each a **real position from a real board**. The
// list ships as ten `(seed, difficulty, stepIndex)` triples; the device
// regenerates the puzzle, replays its trace, proves the step is the technique
// the lesson claims, and hands the position to the same `BoardView` everything
// else in Nine is drawn on. `TechniqueSchool` is where all of that lives — this
// file is only the screen.
//
// Three rules the design is holding, all of them PRD-7's:
//
//   • **Nothing locks.** Every lesson is open from the first launch, and the
//     list never re-sorts itself under someone reading it. `CoachProgress`
//     still computes the first technique you have not met — it just *marks*
//     that row now instead of floating it to the top, because a curriculum
//     whose order is the argument (gentle → abyss) cannot also be a queue.
//   • **No score.** A met technique gets a tick and an accessibility label. No
//     count on this screen, no percentage, no badge. The one place a number
//     appears is the stats drawer, once, in a sentence.
//
//     A round-2 critic asked for "completed checkmark, attempts, best time" in
//     the space the band capsule was wasting, and two of those three are a
//     score. The tick landed; the counters did not, and this is where that
//     decision is recorded rather than argued again — `CoachProgress.Met` does
//     hold an `explained` count, and its own comment says it is "never shown as
//     a number, and never compared against a threshold".
//   • **The coach still does not place a digit.** A lesson ends by handing the
//     board back: you make the move.
//
// Resolution composes a puzzle — Tempest is ~0.02 s and Sharp ~0.7 s in
// Release — so it happens off the main actor and the row shows a spinner in its
// own status slot until it lands, exactly as the difficulty cards do while
// composing.
//
// **What wave 4 rebuilt, and why.** The shipped list was ten 334×48 lozenges
// each holding an 8pt dot and one word — 66% empty ink — and the ladder the
// curriculum *is* (`TechniqueSchool.lessons`: gentle, gentle, steady×3, sharp,
// tempest×3, abyss) reached the screen nowhere. Four defects, all measured off
// the shipped frames:
//
//   1. The backdrop was a colour multiply, not a material, so the shelf read
//      straight through it — 'Continue', 'Steady', the difficulty labels under
//      the card and a board fingerprint above it. A multiply cannot blur. It is
//      `.ultraThinMaterial` plus a theme tint now.
//   2. `.regular` glass on `.regular` glass: card 1.09:1 against its rows on
//      dark, 1.07:1 on light. The card keeps the one material; the rows are
//      wave 1's L4 rung (`couchInset` + a half-point seam) through
//      `historyInset`, whose two opacities are *solved* rather than picked.
//   3. The row carried nothing but a name. It carries the technique's own
//      figure now — drawn on `BoardArt`, the same geometry `MiniBoard` and
//      `BoardFingerprint` use — plus a line of copy, under a band header.
//   4. The progress dot was `Color.secondary.opacity(0.25)`: 1.3:1 on dark and
//      1.2:1 on light against WCAG 1.4.11's 3:1, and it was the School's entire
//      progress model. Met versus unmet is a *shape* now — a tick, a target or
//      a chevron — which survives a greyscale copy of the screenshot.
//
// **What round 2 rebuilt on top of that.** Wave 4 gave every row a name, a
// figure, a line of copy *and* a capsule naming its band — under a header
// naming the same band. Four of a critic's findings on this screen come out of
// that one decision and its consequences:
//
//   • the capsule said what the header above it had just said, ten times;
//   • three of the four bands drew an indistinguishable blue, so the one axis
//     the capsule existed to encode encoded nothing (see `bandTint`, and
//     `rankLadder`, which draws the same order as a shape);
//   • the figure was 40pt of 81 sub-pixel dots — decoration nobody can decode
//     (see `SchoolMetrics.preview` and `TechniquePattern`);
//   • and with the capsule gone the row's trailing edge is free for the one
//     thing a lesson list is for (see `indicator`).
//
// The screen also had no edges: no scroll-edge treatment under the title, no
// bottom fade, no primary action, and rows sliced through their baseline by the
// card's clip. `startAction`, `learnScrollFades` and the header's condense are
// those four.
//
// The one thing this file wants and cannot have is ten `technique.<case>.lesson`
// rows in the catalog (see `lessonLine`). Adding catalog rows is separately
// gated, so the row's second line reads the key it will one day find and falls
// back to the band's own blurb until then; nothing else has to change on the
// day those rows land.
#if os(iOS) || os(macOS)
import SwiftUI
import CouchKit

/// Every number this screen invents, in one block — the audit that produced
/// `DesignTokens` counted nine off-grid spacings in this file alone (2, 8, 10,
/// 12, 14, 16, 18, 20, 22, four of them different vertical alignments inside one
/// 370pt card). Each of these is either a token or derived from one.
private enum SchoolMetrics {
    /// The card's own radius. Not `Radius.sheet` (28): this card is the
    /// shipped silhouette and every number below is concentric *with it*.
    static let card: CGFloat = 32
    /// One gutter for the header and the list both. They shipped at 20 and 18,
    /// so every row capsule overhung the title by 2pt on both sides — a visible
    /// jog at 3×.
    static let gutter: CGFloat = Space.xl
    /// Concentric, by the rule `Radius.inner` exists to state: a row inset one
    /// gutter inside a 32pt card is 12, which is also `Radius.tile`. The 18 it
    /// shipped with read as too round at every size.
    static let row: CGFloat = Radius.inner(SchoolMetrics.card, inset: SchoolMetrics.gutter)
    /// The technique's figure.
    ///
    /// **It was 40, and a round-2 critic measured what 40 bought**: "the dotted
    /// 9×9 glyphs are sub-pixel dots at ~1px with almost no contrast against
    /// the card; the X-Wing thumbnail and the Naked Pair thumbnail read
    /// identically at a glance… a thumbnail nobody can decode is decoration."
    /// Both halves of that are true and only one of them is a size problem:
    /// the figure also drew all 81 cells, so the three or four marks that *are*
    /// the technique were competing with 77 that are not.
    ///
    /// 56 is what the arithmetic asks for. `BoardArt` puts the cell at
    /// `(side − 2 × 0.035 × side) / 9`, so a 40pt square gave a 4.1pt cell and a
    /// 2.4pt mark — under three pixels at 2×, which is a dot rather than a
    /// shape. 56 gives a 5.8pt cell and a 3.8pt mark, and the field of 77
    /// distractors is gone.
    static let preview: CGFloat = 56
    /// The trailing status slot — one square, held open on every row whether or
    /// not there is a tick in it, so ten chevrons sit on one vertical.
    /// (The target ring that used to share it is gone; see `indicator`.)
    static let status: CGFloat = 24
    /// The close disc's glass, inside a `Hit.min` target.
    static let disc: CGFloat = 30
    /// How far the card has to be pulled before the drag is a dismissal.
    static let dismissDrag: CGFloat = 80
    /// The widest the card ever gets. Unchanged.
    static let maxWidth: CGFloat = 560
}

struct SchoolView: View {
    let model: AppModel
    let accent: Color
    let onDismiss: @MainActor () -> Void

    @State private var open: TechniqueLesson?
    @State private var loading: Technique?
    /// How far the lesson list still has to scroll at each end — the input to
    /// the header's condense, its divider and the two edge fades.
    @State private var listEdges = LearnScrollEdges()
    /// The measured height of the lesson list, so the card can hug it. Without
    /// this a `ScrollView` takes every point it is offered and the card is full
    /// height on every device — ~700pt of empty glass on a 13" iPad.
    @State private var listHeight: CGFloat = 0
    /// The measured height of the action bar. See `listCap`: the bar is a
    /// content inset on the scroll, not a slice out of it, so the card has to
    /// grow by exactly this much for a list that fits to still fit.
    @State private var barHeight: CGFloat = 0
    @GestureState private var dragOffset: CGFloat = 0
    @Environment(\.nineTheme) private var theme
    @Environment(\.colorScheme) private var colorScheme

    private var tones: ThemeTones { theme.tones(for: colorScheme) }

    /// Touch platforms get the sheet grammar — a grabber, a drag that
    /// dismisses, a backdrop that answers a tap. macOS presents this as its own
    /// window (`MacSchoolWindow`), where a click on the backdrop closing the
    /// window would be a surprise and there is nothing to pull.
    private var isTouch: Bool {
        #if os(iOS)
        true
        #else
        false
        #endif
    }

    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: SchoolMetrics.card, style: .continuous)
    }

    /// The curriculum, grouped into the bands it already climbs. Consecutive
    /// runs rather than a sort: `TechniqueSchool.lessons` is mined in rank
    /// order and the bands come out monotone, so grouping *in place* is the
    /// only form of this that cannot silently reorder a lesson.
    private var bands: [BandSection] {
        var sections: [BandSection] = []
        for exemplar in TechniqueSchool.lessons {
            if let last = sections.last, last.difficulty == exemplar.difficulty {
                sections[sections.count - 1] = BandSection(
                    difficulty: last.difficulty,
                    techniques: last.techniques + [exemplar.technique])
            } else {
                sections.append(BandSection(difficulty: exemplar.difficulty,
                                            techniques: [exemplar.technique]))
            }
        }
        return sections
    }

    /// The first technique you have not met, or nil once they are all met.
    ///
    /// Still `CoachProgress.suggestedOrder`, which is the only thing that knows
    /// this — it just answers the question instead of rearranging the list to
    /// imply it. `suggestedOrder` returns its input unchanged when the first
    /// unmet lesson is already first, so the `hasMet` check is what keeps a
    /// fully-met School from marking Naked Single.
    private var suggested: Technique? {
        let curriculum = TechniqueSchool.lessons.map(\.technique)
        guard let next = model.coachProgress.suggestedOrder(curriculum).first,
              !model.coachProgress.hasMet(next) else { return nil }
        return next
    }

    var body: some View {
        ZStack {
            scrim

            Group {
                if let open {
                    SchoolLessonView(lesson: open, accent: accent, tones: tones) { finished in
                        if finished { model.noteLessonFinished(open.exemplar.technique) }
                        withAnimation(.couchFast) { self.open = nil }
                    }
                } else {
                    list
                }
            }
            .frame(maxWidth: SchoolMetrics.maxWidth)
            // One material for the whole card, plus round 2's two corrections:
            // a white lift under the glass so the card is *above* the page it
            // floats on rather than a shade below it, and a specular rim that
            // runs bright at the top edge and dark at the bottom. Wave 1's rim
            // and shadow were the right idea drawn only half way — a diagonal
            // white-to-less-white gradient is a bevel, and a bevel with no dark
            // side is a drawn outline. See `LearnSurface`.
            .learnCard(in: cardShape, tones: tones)
            .offset(y: dragOffset)
            .padding(Space.l)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // The shelf underneath stays on screen and, without this, stays in the
        // accessibility tree: `describe-ui` read the difficulty cards *through*
        // the School. An overlay is a sibling, not a presentation, so nothing
        // makes it modal for us.
        .accessibilityAddTraits(.isModal)
    }

    /// **A material, not a wash.** The first version dimmed with
    /// `tones.plane` and the home shelf read straight through it; the second
    /// swapped in `tones.background` at 0.42/0.62, which only *darkened* the
    /// same multiply — 'Continue', 'Steady' and the shelf's own circular ✕ were
    /// all still legible in the light frame, with the status-bar clock landing
    /// on top of 'Continue'. A colour multiply does not blur, desaturate or
    /// defocus; only a material does.
    ///
    /// **Round 2 found the tint was too light, and that a blur is not a
    /// backdrop.** `.ultraThinMaterial` over a near-black ground composites
    /// *up* while `.glassEffect(.regular)` over that composites *down*, so a
    /// scrim built from the one and a card built from the other invert their
    /// elevation as a matter of arithmetic — the finding a critic filed against
    /// the tutorial word for word ("the sheet is a hole, not glass") and which
    /// this screen shares by construction. The wash is heavier now, and light
    /// grounds scrim with black rather than with themselves for `Scrim`'s own
    /// reason: washing a bright page with its own ground brightens it.
    ///
    /// It also has something in it. A lens over a constant draws a constant, so
    /// the curriculum's next figure is drawn behind the card — enormous, out of
    /// focus, in the player's accent — which hands the glass a real luminance
    /// field to bend and makes the backdrop this screen's own rather than
    /// anyone's grey.
    private var scrim: some View {
        GeometryReader { geo in
            ZStack {
                Rectangle().fill(.ultraThinMaterial)
                if let next = startTarget {
                    TechniquePattern(
                        technique: next,
                        // The band's tint, not the bare accent: the figure
                        // behind the card and the figure in its row are the
                        // same picture and should be the same colour.
                        tint: bandTint(band(of: next)),
                        ground: tones.gridTone,
                        second: tones.coral,
                        side: max(geo.size.width, geo.size.height) * 0.96
                    )
                    // Round 3 more than halved the blur, for the reason the
                    // tutorial's `PracticeBackdrop` records at length: a lens
                    // over a monotonic ramp draws the same ramp, and at 0.028
                    // of the long edge the figure had been smoothed past every
                    // inflection it had. What the card's glass needs from the
                    // field behind it is *structure*, not brightness.
                    .blur(radius: max(geo.size.width, geo.size.height) * 0.013)
                    .opacity(tones.isLight ? 0.34 : 0.55)
                    .position(x: geo.size.width * 0.5, y: geo.size.height * 0.38)
                }
                (tones.isLight ? Color.black : tones.background)
                    .opacity(tones.isLight ? 0.28 : 0.60)
                // The room's one light. `GroundLight` is private to
                // `NineApp.swift` and the material above has flattened the
                // ground's own gradient anyway, so the anchor and the falloff
                // are restated here rather than reached for.
                RadialGradient(
                    stops: [
                        .init(color: Color.white.opacity(tones.isLight ? 0.10 : 0.07),
                              location: 0),
                        .init(color: Color.white.opacity(0), location: 1),
                    ],
                    center: UnitPoint(x: 0.88, y: 0.08),
                    startRadius: 0,
                    endRadius: max(max(geo.size.width, geo.size.height) * 0.92, 1)
                )
            }
        }
        .ignoresSafeArea()
        .contentShape(Rectangle())
        // The shipped scrim swallowed its tap on purpose — "the way out is
        // Close" — while the shelf's own ✕ sat visible through it 40pt away, so
        // one corner of one screenshot carried two dismiss vocabularies and
        // neither worked. The backdrop answers now.
        .onTapGesture { if isTouch { dismissTop() } }
        .accessibilityHidden(true)
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            handle
            // The scroll-edge divider a critic filed as missing: "title,
            // subtitle and the first section header sit on flat sheet fill with
            // no separator, no blur, no progressive-blur scroll edge. On scroll
            // the 'Naked Single' card will slide up and collide with the 34pt
            // title." It fades in with the scroll and fades out at both ends,
            // so it is never the hard full-bleed hairline of a table view.
            Rectangle()
                .fill(LearnSurface.seam(tones))
                .frame(height: 1)
                .opacity(listEdges.strength(top: true))
                .padding(.horizontal, SchoolMetrics.gutter)
                .accessibilityHidden(true)
            ScrollView {
                // Ten sibling glass shapes used to sample the backdrop ten
                // times independently. They are `.identity` glass now, which is
                // what a container is for.
                CouchGlassContainer(spacing: Space.s) {
                    VStack(alignment: .leading, spacing: Space.l) {
                        ForEach(bands) { section in
                            VStack(alignment: .leading, spacing: Space.s) {
                                bandHeader(section.difficulty)
                                    .padding(.horizontal, Space.xs)
                                ForEach(section.techniques, id: \.self) { technique in
                                    row(technique, band: section.difficulty)
                                }
                            }
                        }
                    }
                    .padding(.top, Space.s)
                    .padding(.horizontal, SchoolMetrics.gutter)
                    // A row must never end flush with the clip. The critic's
                    // frame sliced "Skyscraper" through its baseline; one
                    // gutter of trailing air plus the bottom fade means the
                    // last thing a reader sees is a row dissolving, which is
                    // also the signal that there is more of it.
                    .padding(.bottom, SchoolMetrics.gutter)
                    .onGeometryChange(for: CGFloat.self) { proxy in
                        proxy.size.height
                    } action: { height in
                        listHeight = height
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .learnScrollEdges(into: $listEdges)
            // **Only the top end fades now.** The bottom boundary is a real bar
            // of glass, and a bar plus a gradient underneath it is two
            // treatments on one edge — which is precisely what a panel filed
            // twice: *"the scroll-edge fade is a hard white band that
            // guillotines the first SHARP card"*, *"the gradient above the CTA
            // dims the X-Wing row but does not blur it, and it has a visible
            // hard band where it starts"*. One edge, one treatment.
            .learnScrollFades(listEdges, tones: tones, bottom: false)
            // **The bar floats over the list rather than sitting beside it**,
            // and both halves of that matter. A `safeAreaInset` reserves the
            // bar's height as *content inset* instead of as layout, so the last
            // row can scroll clear of it — the missing bottom inset the light
            // panel named — and the rows genuinely pass underneath, which is the
            // only reason a clear material has anything to refract. Chrome over
            // content, never a parking space beside it.
            .safeAreaInset(edge: .bottom, spacing: 0) { startBar }
            // A maximum, not a size: on a phone the proposal is smaller than
            // the content and the list scrolls exactly as before; on an iPad it
            // is larger, and the card stops at its last row.
            .frame(maxHeight: listCap)
        }
    }

    /// Nil until the list has been measured once, so the first layout pass
    /// proposes the full height rather than collapsing the card to nothing.
    ///
    /// **Plus the bar**, because the bar's height is a content inset rather than
    /// a slice out of the viewport: with the list capped at its own height the
    /// scroll would be permanently short by exactly one bar and an iPad would
    /// show a scrollbar on a list that fits.
    private var listCap: CGFloat? {
        guard listHeight > 0 else { return nil }
        return listHeight + barHeight
    }

    /// True once the list has been scrolled far enough that the subtitle is
    /// buying nothing.
    ///
    /// A threshold rather than the continuous value, deliberately: a header
    /// whose height is a function of `contentOffset` re-lays-out on every frame
    /// of a bouncing scroll, and the ScrollView it is measuring is the thing
    /// that would be re-measured. One boolean is one transition.
    private var condensed: Bool { listEdges.top > 10 }

    /// The lesson the screen would start if you asked it to — the first one you
    /// have not met, or the first one there is.
    private var startTarget: Technique? {
        suggested ?? TechniqueSchool.lessons.first?.technique
    }

    /// The band a technique first becomes necessary in. The curriculum already
    /// knows; nothing else does.
    private func band(of technique: Technique) -> Difficulty {
        TechniqueSchool.lessons.first { $0.technique == technique }?.difficulty ?? .gentle
    }

    /// The way out of a dead end.
    ///
    /// **The list had no primary action at all**, which a critic named as the
    /// thing that makes the frame unshippable: "a selected lesson with no
    /// visible Start Lesson button makes this a dead-end frame". Every row is
    /// its own button, so this is not a second way to do anything — it is the
    /// screen stating which one of the ten it thinks you want, which is the
    /// question `CoachProgress.suggestedOrder` has always been able to answer
    /// and has never been allowed to say out loud.
    ///
    /// Solid accent rather than tinted glass, for the reason the tutorial's own
    /// CTA records: `.regular.tint(accent × 0.22)` over a dark backdrop is 22%
    /// of a colour over 78% of a dark lens, and it cannot be the accent and
    /// cannot be bright. A primary action is the one surface on a screen that
    /// is *not* translucent.
    ///
    /// **Round 3 kept the rung and rebuilt everything else about it**, from
    /// three findings that are one object drawn wrong:
    ///
    ///  * *"a fully saturated system-blue capsule with black text spanning the
    ///    full width — the highest-contrast object on a screen whose subject is
    ///    a lesson list, and it flattens the whole hierarchy."*
    ///    `LearnSurface.prominentFill` deepens the accent toward the theme's own
    ///    ground until white clears AA on all ten hues, so the label is
    ///    white-on-accent like every prominent button on the platform and the
    ///    list stays the brightest content on the card.
    ///  * *"'Show me' is bold ~22pt and 'Naked Single' is regular ~17pt, jammed
    ///    side by side with a single space… as drawn it looks like two labels
    ///    collided."* Stacked, which is the panel's own second option and the
    ///    only one available without a catalog row: a title, and the lesson's
    ///    name under it at `caption`.
    ///  * *"the bottom bar is a linear dark scrim, not a scroll-edge material."*
    ///    See `startBar`.
    private func startAction(_ next: Technique) -> some View {
        Button { openLesson(next) } label: {
            VStack(spacing: 1) {
                Text(Phrase.showMe)
                    .font(CouchTypography.heading)
                    .foregroundStyle(LearnSurface.prominentInk)
                Text(Strings.technique(next))
                    .font(CouchTypography.caption)
                    .foregroundStyle(LearnSurface.prominentInk.opacity(0.78))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            // A `VStack` handed a wider proposal centres its children, which is
            // why the two `Spacer`s the side-by-side version needed are gone
            // with it: the leading-edge bug they existed to defeat is an
            // `HStack` property.
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, minHeight: Hit.min + Space.s)
            .background(LearnSurface.prominentFill(accent, tones), in: Capsule())
            .couchElevated(in: Capsule(), isLight: tones.isLight)
            .learnRim(in: Capsule(), tones: tones, strength: 0.8)
            .contentShape(Capsule())
            .contentShape(.accessibility, Capsule())
        }
        .buttonStyle(LearnPressStyle())
        .disabled(loading != nil)
        .opacity(loading != nil ? 0.5 : 1)
    }

    /// **A bar of glass, not a gradient painted over the list.**
    ///
    /// The action used to be a sibling in the card's `VStack` with a linear
    /// scrim above it, and a panel measured exactly what that is: *"the gradient
    /// above the CTA dims the X-Wing row but does not blur it, and it has a
    /// visible hard band where it starts. Use a real bar material so content
    /// genuinely defocuses under it, and give the bar a defined top hairline
    /// instead of a fade that dies mid-row."*
    ///
    /// `couchGlassBar` is that rung and it is the one the suite already has:
    /// clear-leaning glass (a bar sits over what the player is reading, and
    /// `.regular` fogs it), an interior sheen for thickness, and a specular top
    /// rim **masked to zero at both ends** — so the bar has an edge instead of a
    /// seam. Its own note is emphatic that a caller must not then paint a
    /// hairline as well, and this one does not.
    ///
    /// The shape is uneven on purpose: the bar reaches the card's own bottom
    /// corners, so those two corners carry the card's 32pt radius and the top
    /// two are square. A capsule floating inside the card would have been a
    /// second object where the finding asked for an edge.
    @ViewBuilder
    private var startBar: some View {
        if let next = startTarget {
            startAction(next)
                .padding(.horizontal, SchoolMetrics.gutter)
                .padding(.top, Space.m)
                .padding(.bottom, SchoolMetrics.gutter)
                .frame(maxWidth: .infinity)
                .couchGlassBar(in: barShape, isLight: tones.isLight)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.size.height
                } action: { height in
                    barHeight = height
                }
        }
    }

    /// The bar's silhouette: square at the top where the list passes under it,
    /// concentric with the card at the bottom where it *is* the card's edge.
    private var barShape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(
            topLeadingRadius: 0,
            bottomLeadingRadius: SchoolMetrics.card,
            bottomTrailingRadius: SchoolMetrics.card,
            topTrailingRadius: 0,
            style: .continuous)
    }

    /// The grabber and the title, which are one unit because the grabber is
    /// only honest if the region under it is what answers the drag.
    @ViewBuilder
    private var handle: some View {
        if isTouch {
            // `.simultaneousGesture`, for the reason TouchUI's page-turn
            // records: a `DragGesture` that claims the stroke exclusively takes
            // everything under it with it — here that would be the close disc
            // sitting inside this same header.
            header.simultaneousGesture(dismissDrag)
        } else {
            header
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: Space.xs) {
            if isTouch {
                Capsule()
                    .fill(tones.gridTone.opacity(0.35))
                    .frame(width: 36, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, Space.s)
                    .accessibilityHidden(true)
            }
            // The title row is exactly one `Hit.min` tall so the close disc
            // overlaid on it cannot reach the subtitle — which is how the
            // subtitle gets its ~76pt of measure back and stops breaking with
            // a two-word orphan. The scale factor is for German and Russian.
            Text(Phrase.title)
                .font(CouchTypography.title)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(minHeight: Hit.min, alignment: .leading)
                .padding(.trailing, Hit.min + Space.s)
            // The condense. Fitness and Journal both give the subtitle back to
            // the list the moment it starts moving, and the reason is the one
            // the critic wrote down: this card is short, and a standing
            // two-line header is two lines of lessons.
            if !condensed {
                Text(Phrase.subtitle)
                    .couchText(CouchTypography.label, .secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .transition(.opacity)
            }
        }
        .animation(.couchFast, value: condensed)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) {
            CloseDisc(tones: tones, label: Phrase.close) { dismissTop() }
                .padding(.top, isTouch ? Space.m : 0)
        }
        .padding(.horizontal, SchoolMetrics.gutter)
        .padding(.top, isTouch ? Space.m : SchoolMetrics.gutter)
        .padding(.bottom, Space.m)
        .contentShape(Rectangle())
    }

    /// One band of the curriculum, labelled in its own place on the ramp.
    ///
    /// **The band used to be said twice per row and ranked nowhere.** Every row
    /// under GENTLE carried a capsule reading "Gentle"; every row under STEADY
    /// carried one reading "Steady" — the blocker a critic opened with. Killing
    /// the capsule and letting the header carry the tier is one of the two
    /// answers they offered, and it is the right one here: the header is
    /// already a grouping, and the trailing space the capsule was occupying is
    /// where a list like this puts progress.
    ///
    /// The ladder beside the name is the second half of the same finding —
    /// "the semantic colour ramp doesn't ramp". A colour ramp that must survive
    /// ten player-chosen accents cannot carry an ordinal on hue alone, so the
    /// order is *drawn*: six bars, rising, filled to this band's rank. It reads
    /// in greyscale, it reads for a player who cannot see the hue difference at
    /// all, and it says the one thing the capsule never did — where this band
    /// sits among the six.
    ///
    /// The rule runs out of the ladder and fades to nothing at the trailing
    /// edge rather than ruling across the card and stopping on a line.
    private func bandHeader(_ band: Difficulty) -> some View {
        let tint = bandTint(band)
        let name = Strings.difficulty(band)
        return HStack(alignment: .center, spacing: Space.s) {
            Text(name)
                .font(HistoryMetrics.sectionFont(1))
                .tracking(0.9)
                .textCase(.uppercase)
                .foregroundStyle(tint)
                // `.textCase(.uppercase)` changes the rendered glyphs and
                // VoiceOver reads what is rendered — `HistorySectionHeader`'s
                // recorded reason for putting the sentence case back by hand.
                .accessibilityLabel(name)
            rankLadder(band, tint: tint)
            LinearGradient(
                stops: [
                    .init(color: tones.gridTone.opacity(tones.isLight ? 0.22 : 0.18),
                          location: 0),
                    .init(color: tones.gridTone.opacity(0), location: 1),
                ],
                startPoint: .leading,
                endPoint: .trailing
            )
            .frame(height: 1)
            .accessibilityHidden(true)
        }
    }

    /// Where this band sits among the six, as a shape.
    ///
    /// Six slots for six bands, and Nocturne's slot stays empty in every header
    /// because the curriculum has no Nocturne lesson (`TechniqueSchool.lessons`
    /// runs gentle, gentle, steady×3, sharp, tempest×3, abyss). That gap is
    /// information rather than an omission: there is a band between Sharp and
    /// Tempest, and nothing here teaches it.
    private func rankLadder(_ band: Difficulty, tint: Color) -> some View {
        let rank = Difficulty.allCases.firstIndex(of: band) ?? 0
        return HStack(alignment: .bottom, spacing: 2) {
            ForEach(0..<Difficulty.allCases.count, id: \.self) { index in
                Capsule()
                    .fill(index <= rank ? tint : tones.gridTone.opacity(0.20))
                    .frame(width: 2.5, height: 3 + CGFloat(index) * 1.6)
            }
        }
        .accessibilityHidden(true)
    }

    private var dismissDrag: some Gesture {
        // 10pt so a tap that lands on the title never twitches the card. The
        // gesture is on the header alone: a `DragGesture` wrapping the list
        // would fight the ScrollView's own pan for every vertical stroke.
        DragGesture(minimumDistance: 10)
            .updating($dragOffset) { value, offset, _ in
                offset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > SchoolMetrics.dismissDrag { dismissTop() }
            }
    }

    /// One lesson. Four parts, and every one of them is data the app already
    /// had: the figure the technique draws, its name, a line about it, and the
    /// band it first becomes *necessary* in.
    private func row(_ technique: Technique, band: Difficulty) -> some View {
        let met = model.coachProgress.hasMet(technique)
        let isSuggested = suggested == technique
        let composing = loading == technique
        // Narrowed from `loading != nil`: the row you pressed stays lit and
        // shows its spinner, and only the other nine go to sleep — which the
        // dimming now *states* rather than merely enforcing.
        let asleep = loading != nil && !composing
        let shape = RoundedRectangle(cornerRadius: SchoolMetrics.row, style: .continuous)
        let tint = bandTint(band)
        // The one row that is *next* is tinted rather than labelled: a word
        // there would need a catalog key this screen is not allowed to add,
        // and a target reads in every language.
        let fill: Color? = isSuggested ? HistoryMetrics.accentFill(accent, tones) : nil
        let rim: Color? = isSuggested ? HistoryMetrics.accentRim(accent) : nil

        return Button {
            openLesson(technique)
        } label: {
            HStack(spacing: Space.m) {
                // **The figure sits in a container now**, which is the light
                // panel's prescription verbatim — *"put the glyph in a 44×44
                // rounded container"* — arrived at from the dark panel's
                // complaint that the figures were floating marks with no object
                // around them. A thumbnail with an edge reads as a picture of a
                // board; the same marks with no edge read as debris on the row.
                // 56 rather than 44 because round 2's arithmetic still holds
                // (`SchoolMetrics.preview`): below that the cell is under 5pt
                // and the marks stop being shapes.
                TechniquePattern(technique: technique, tint: tint,
                                 ground: tones.gridTone, second: tones.coral)
                    .background {
                        thumbShape.fill(tones.gridTone.opacity(tones.isLight ? 0.05 : 0.07))
                    }
                    .couchRim(in: thumbShape, isLight: tones.isLight)
                VStack(alignment: .leading, spacing: Space.hair) {
                    Text(Strings.technique(technique))
                        .couchText(CouchTypography.body.weight(.semibold), .primary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                    Text(lessonLine(technique, band: band))
                        .couchText(CouchTypography.caption, .secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: Space.s)
                // The space the duplicated band capsule was occupying, spent on
                // the one thing a lesson list is *for*: whether you have done
                // this one.
                indicator(met: met, composing: composing)
            }
            .padding(.horizontal, Space.l)
            // `Space.s`, down from `Space.m`. Two panels measured this row at
            // 100pt and 128pt and both drew the same conclusion — *"dead
            // horizontal space and 128pt row height buy only 5.5 visible
            // rows… techniques past Box-Line Reduction, the reason to open this
            // sheet, currently start below the fold"*. Eight points off each
            // end is 16pt a row and roughly one extra lesson on screen, without
            // touching the figure's own legibility.
            .padding(.vertical, Space.s)
            .frame(maxWidth: .infinity, alignment: .leading)
            // **Both content shapes, and they fix two different bugs.**
            //
            // A `Button`'s hit region is its label's *content*, and this label
            // ends in a `Spacer` — a `Spacer` has no content, so the tappable
            // area ended at the end of the word. A row 334 pt wide responded to
            // taps only in its leftmost ~120: every tap at the row centre,
            // which is where a finger goes, landed on nothing. It looks exactly
            // like a button that does not work, and it took a scrim that
            // dismissed on tap to prove the touch was reaching the card and
            // being swallowed rather than never arriving.
            //
            // The accessibility shape is the same defect one layer over:
            // `describe-ui` measured the row at 104×16 against a drawn 334×48.
            // PRD-19 hit that on the chrome's SF Symbols and fixed it the same
            // way. Neither is visible in a screenshot.
            .contentShape(shape)
            // L4, not a second `.regular` material. `HistoryMetrics.fill`'s two
            // opacities are solved against the composited panel — 0.16 of the
            // theme's ink on light, 0.11 on dark — because a dark card cannot
            // be separated from a dark panel by *darkening* it: the +0.05 in
            // the WCAG ratio eats the whole range below it.
            .historyInset(tones, radius: SchoolMetrics.row, fill: fill, rim: rim,
                          hairline: isSuggested ? 1 : HistoryMetrics.hairlineWidth)
            // Round 2's edge, over `historyInset`'s seam rather than instead of
            // it: the seam says where the region ends, and this says which way
            // the light is coming from. A boundary that is one flat hairline is
            // the "flat opaque fill plus a hairline, not a material" ten critics
            // wrote down.
            .learnRim(in: shape, tones: tones, strength: 0.55, width: 0.75)
        }
        .buttonStyle(LearnPressStyle())
        .disabled(asleep)
        .opacity(asleep ? 0.45 : 1)
        .contentShape(.accessibility, shape)
        .accessibilityLabel(Phrase.rowLabel(Strings.technique(technique), met: met))
    }

    /// The row's silhouette for its figure: concentric with the row by
    /// `Radius.inner`'s rule — a 56pt tile sitting `Space.s` inside a 12pt row
    /// is a 4pt corner. Nearly square, and that is correct rather than a
    /// degenerate case: the thing inside it is a board.
    private var thumbShape: RoundedRectangle {
        RoundedRectangle(
            cornerRadius: Radius.inner(SchoolMetrics.row, inset: Space.s),
            style: .continuous)
    }

    /// Met, next, unmet or composing — one slot, four states, and the three
    /// visible ones differ in **shape** rather than in opacity.
    ///
    /// The shipped dot filled at `Color.secondary.opacity(0.25)` when unmet:
    /// #3b3b3d on #1c1c1c ≈ 1.3:1 dark, #d4d2cf on #efeee8 ≈ 1.2:1 light,
    /// against WCAG 1.4.11's 3:1 — and this is the School's entire progress
    /// model. A shape survives greyscale; 25% opacity does not.
    ///
    /// It is also where the compose lands. The spinner used to be an 11pt word
    /// pinned ~300pt away at the far end of a `Spacer`, which is not where
    /// anyone is looking when they press a row.
    ///
    /// **Round 2 moved it to the trailing edge and gave it a tick.** The dot
    /// sat at the leading edge in front of the figure, which put two marks and
    /// a picture in the first 70pt of every row and left the last 90pt to a
    /// capsule repeating the section header. A list of lessons reads
    /// name-first, so the state belongs where the eye finishes — and that is
    /// also the space the capsule vacated.
    ///
    /// Wave 4's "filled disc versus outline ring" was a distinction a reader
    /// had to have been told; a tick is not.
    ///
    /// **Round 3 made the chevron unconditional and dropped the target ring,
    /// and it is the same finding on both leanings**: *"the selected row ends in
    /// a filled radio glyph while all unselected rows end in a disclosure
    /// chevron, so the control switches from 'choose' to 'navigate' depending on
    /// state… mixing 'navigates' and 'is chosen' in the same slot makes the tap
    /// outcome unguessable."* Every one of these ten rows does exactly one
    /// thing — it opens a lesson — so every one of them ends in the mark for
    /// that, on every state.
    ///
    /// The tick did not go with it, because a tick is not an affordance: it is
    /// the row's own history, sitting *before* the chevron the way a value sits
    /// before a chevron in Settings. And the suggestion the ring used to carry
    /// is carried by the row's fill and its brighter rim instead — the panel's
    /// own prescription, "the selection carried by the row fill and stroke".
    private func indicator(met: Bool, composing: Bool) -> some View {
        HStack(spacing: Space.xs) {
            ZStack {
                if composing {
                    ProgressView().controlSize(.mini)
                } else if met {
                    Circle()
                        .fill(accent)
                        .frame(width: 20, height: 20)
                        .overlay {
                            Image(systemName: "checkmark")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(LearnSurface.accentInk(tones))
                        }
                        .shadow(color: accent.opacity(0.45), radius: 4)
                }
            }
            .frame(width: SchoolMetrics.status, height: SchoolMetrics.status)
            Image(systemName: "chevron.forward")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(tones.digitTone.opacity(0.38))
        }
        .accessibilityHidden(true)
    }

    /// Where a band sits on one signed ramp: negative desaturates the accent
    /// toward the theme's digit tone, positive warms it toward the coral, and
    /// Sharp is the pivot and is the player's accent unchanged. The shape of
    /// the rule is `MiniBoard.warmth`'s, duplicated as a *number* rather than as
    /// a colour because `MiniBoard.tint` is private to a view that draws a
    /// board.
    ///
    /// **The stops are wider than `MiniBoard`'s, and that is the round-2 fix.**
    /// A critic filed "three of four difficulty tiers use an indistinguishable
    /// system-blue capsule; only Tempest breaks to mauve", and the arithmetic
    /// agrees: −0.42 / −0.20 / 0 are three points inside the *cool* half of one
    /// hue, and the shipped chip then rendered them as 11pt text on a 16%
    /// accent wash, which flattens what little separation they had. Six evenly
    /// spaced stops across the theme's whole temperature axis — the ink at one
    /// end, the coral at the other — is a ramp that steps.
    ///
    /// Abyss stops at 0.80 rather than reaching the coral outright: the coral
    /// is Nine's error mark on every other surface in the app, and a band that
    /// is literally the colour of a mistake is a claim nobody meant to make.
    ///
    /// Colour is never the only encoding — see `rankLadder`, which draws the
    /// same order as a shape.
    private func bandTint(_ band: Difficulty) -> Color {
        let warmth: Double
        switch band {
        case .gentle: warmth = -0.55
        case .steady: warmth = -0.28
        case .sharp: warmth = 0
        case .nocturne: warmth = 0.28
        case .tempest: warmth = 0.55
        case .abyss: warmth = 0.80
        }
        if warmth < 0 { return accent.mix(with: tones.digitTone, by: -warmth) }
        if warmth > 0 { return accent.mix(with: tones.coral, by: warmth) }
        return accent
    }

    /// The row's second line.
    ///
    /// **The key it wants does not exist yet, and that is deliberate.** Ten
    /// `technique.<case>.lesson` rows belong beside the ten `.name` rows this
    /// file already reads (the seam `Phrase` documents at the foot of the file),
    /// but adding catalog rows is gated separately from this screen, and
    /// inventing the copy here would ship a bare literal past `StringSealTests`
    /// or — worse — print `technique.xWing.lesson` on a player's phone, because
    /// `Phrasebook` deliberately resolves a missing key *to the key*.
    ///
    /// So it asks for the key, recognises the key-as-value answer, and falls
    /// back to the band's blurb, which is true of every technique in the band
    /// ("Pairs & box lines" covers all three of Steady's). The day the ten rows
    /// land, nothing in this file changes.
    private func lessonLine(_ technique: Technique, band: Difficulty) -> String {
        let key = "technique.\(technique.rawValue).lesson"
        let value = Strings.string(key)
        return value == key ? band.blurb : value
    }

    /// One way out, wherever it is asked for: a lesson closes back to the list,
    /// the list closes the School.
    private func dismissTop() {
        if open != nil {
            withAnimation(.couchFast) { open = nil }
        } else {
            onDismiss()
        }
    }

    /// Compose off the main actor. A lesson that fails to resolve simply does
    /// not open — CI is where a rotted exemplar should be loud, not a player's
    /// phone (`TechniqueSchoolTests`).
    private func openLesson(_ technique: Technique) {
        guard loading == nil,
              let exemplar = TechniqueSchool.lessons.first(where: { $0.technique == technique })
        else { return }
        loading = technique
        Task {
            let lesson = await Task.detached { TechniqueSchool.resolve(exemplar) }.value
            loading = nil
            guard let lesson else { return }
            withAnimation(.couchFast) { open = lesson }
        }
    }
}

/// One band of the curriculum and the techniques that first become necessary
/// in it. A named type rather than a tuple so `ForEach` has an `id` it cannot
/// get wrong.
private struct BandSection: Identifiable {
    let difficulty: Difficulty
    let techniques: [Technique]
    var id: Difficulty { difficulty }
}

// MARK: - The figure

/// The technique's own shape, drawn on the board it happens on.
///
/// Ten rows that differ only in their words are ten rows a reader has to
/// *parse*; ten rows that differ in their picture are a curriculum you can see
/// the shape of before you read one. The geometry is `BoardArt` — the same cell
/// origins, the same 3.5% box seam and the same two interior rules `MiniBoard`
/// and `BoardFingerprint` draw — so a technique diagram and a board thumbnail
/// are recognisably the same object at the same size.
///
/// Nothing here is generated from a solve: resolving a lesson costs ~0.7s at
/// Sharp, and ten of those on a list appearing is not a trade anyone would
/// take. These are the *canonical* forms — the picture in the textbook, not a
/// screenshot of one board — which is also the picture a player needs before
/// they have seen the position.
private struct TechniquePattern: View {
    let technique: Technique
    /// The figure's ink: the band's tint, so a row's picture and its chip agree.
    let tint: Color
    /// The board under the figure — the theme's own grid tone, which always
    /// opposes its ground (near-white on the six dark themes, near-black on
    /// Paper and Camel).
    let ground: Color
    /// The second colour, for the one technique that is *about* two colours.
    let second: Color
    var side: CGFloat = SchoolMetrics.preview

    /// What a technique looks like: the cells it is about, the units it happens
    /// inside, and what links to what.
    struct Figure {
        /// Cells drawn in the band tint.
        var lit: [Int] = []
        /// Cells drawn in the second colour, or as rings when `altIsRing`.
        var alt: [Int] = []
        /// Cell pairs joined by a line — a rectangle, a chain, a pair of legs.
        var links: [(Int, Int)] = []
        /// Units washed under the figure: this is what the deduction happens
        /// *in*, and half the techniques here are only distinguishable by it.
        var rows: [Int] = []
        var columns: [Int] = []
        var boxes: [Int] = []
        /// XY-Wing's pivot is a ring, not a second colour: it is the same digit
        /// pair seen from a different square, not a different mark.
        var altIsRing = false
    }

    /// Every case spelled out rather than a `default`, so appending a
    /// `Technique` fails the build here instead of silently drawing nothing.
    /// PRD-23's four variant techniques have no lesson (they are behind a
    /// channel seal) and therefore no figure.
    static func figure(for technique: Technique) -> Figure {
        switch technique {
        // One square, squeezed by all three of its units at once.
        case .nakedSingle:
            return Figure(lit: [40], rows: [4], columns: [4], boxes: [4])
        // One unit, and only one square in it can take the digit.
        case .hiddenSingle:
            return Figure(lit: [40], rows: [4])
        // Two squares that fill each other, side by side in one line.
        case .nakedPair:
            return Figure(lit: [30, 31], rows: [3])
        // The same claim from the other side: two digits, two squares, but the
        // squares are apart and the line is what ties them. The link is drawn:
        // without it this and `nakedPair` were two dots on a washed row at two
        // spacings, which is the pair a critic reported reading identically.
        case .hiddenPair:
            return Figure(lit: [28, 34], links: [(28, 34)], rows: [3])
        // A line crossing a box, and the intersection is the whole argument.
        case .boxLineReduction:
            return Figure(lit: [9, 10, 11], rows: [1], boxes: [0])
        // Four corners of a rectangle, two lines, and the rectangle drawn.
        case .xWing:
            return Figure(lit: [19, 25, 55, 61],
                          links: [(19, 25), (55, 61), (19, 55), (25, 61)],
                          rows: [2, 6])
        // The X-wing grown up: three lines, three columns, nine corners.
        case .swordfish:
            return Figure(lit: [9, 13, 17, 36, 40, 44, 63, 67, 71], rows: [1, 4, 7])
        // Two towers on one floor, at different heights — which is the name.
        case .skyscraper:
            return Figure(lit: [10, 55, 33, 60],
                          links: [(10, 55), (33, 60), (55, 60)],
                          columns: [1, 6])
        // A pivot that sees two wings, and either way one of them lands.
        case .xyWing:
            return Figure(lit: [43, 67], alt: [40],
                          links: [(40, 43), (40, 67)],
                          rows: [4], columns: [4], altIsRing: true)
        // One digit, two colours, alternating down a chain.
        case .simpleColoring:
            return Figure(lit: [10, 50], alt: [14, 53],
                          links: [(10, 14), (14, 50), (50, 53)])
        // PRD-23's variant four: no lesson, no figure.
        case .cageSingle, .thermoBound, .innieOutie, .cageCombination:
            return Figure()
        }
    }

    var body: some View {
        Canvas { context, size in
            let gutter = size.width * BoardArt.thumbGutter
            let cell = BoardArt.cell(side: size.width, gutter: gutter)
            let figure = Self.figure(for: self.technique)

            /// The dot for one cell, `scale` of the cell across, centred in it.
            /// A function returning a rect rather than one that draws, so
            /// nothing captures the Canvas's `inout` context.
            func dot(_ index: Int, _ scale: CGFloat) -> CGRect {
                let centre = BoardArt.centre(of: index, cell: cell, gutter: gutter)
                let d = cell * scale
                return CGRect(x: centre.x - d / 2, y: centre.y - d / 2, width: d, height: d)
            }

            // 1. The units the deduction lives in. Nearly twice the wash it
            //    shipped with: with the 77-dot field gone (step 3, deleted),
            //    the unit is the only thing between the marks and bare glass,
            //    and at 0.16 of a mid-luminance tint it was under 2% coverage.
            var wash = Path()
            for index in 0..<81 {
                let column = index % 9
                let row = index / 9
                let inUnit = figure.rows.contains(row)
                    || figure.columns.contains(column)
                    || figure.boxes.contains((row / 3) * 3 + column / 3)
                guard inUnit else { continue }
                wash.addRect(BoardArt.cellRect(column: column, row: row,
                                               cell: cell, gutter: gutter))
            }
            context.fill(wash, with: .color(self.tint.opacity(0.28)))

            // 2. The two box seams. At this size the gutter alone nearly
            //    carries the 3×3 structure; the rule is what turns "unevenly
            //    spaced dots" into "that is a sudoku" (`BoardArt`'s own note).
            BoardArt.strokeBoxRules(
                in: context, side: size.width, cell: cell, gutter: gutter,
                color: self.ground.opacity(0.34), lineWidth: 0.75)

            // 3. **The 77-cell field is gone**, and that is the round-2 fix
            //    rather than a saving. It drew every unmarked cell as a dot at
            //    0.26 of a 4.1pt cell — 1.07pt, under three pixels at 2× — so
            //    every figure was three or four marks inside seventy-seven
            //    competing ones, and a critic reported the X-Wing and the Naked
            //    Pair as indistinguishable at a glance. What a figure needs to
            //    be "somewhere in" is the board's *structure*, which the seams
            //    and the unit wash above already draw; the dots were noise
            //    wearing the costume of context.

            // 4. What the pattern joins. Heavier and more opaque: this line is
            //    half of what separates a skyscraper from an X-wing.
            if !figure.links.isEmpty {
                var chain = Path()
                for link in figure.links {
                    chain.move(to: BoardArt.centre(of: link.0, cell: cell, gutter: gutter))
                    chain.addLine(to: BoardArt.centre(of: link.1, cell: cell, gutter: gutter))
                }
                // Round caps and joins, so a rectangle's four corners and a
                // chain's two bends are curves rather than the spikes a miter
                // puts on a 4pt line. `StrokeStyle` rather than the `lineWidth:`
                // overload, which is the only one that takes them.
                context.stroke(chain, with: .color(self.tint.opacity(0.70)),
                               style: StrokeStyle(lineWidth: max(0.75, cell * 0.16),
                                                  lineCap: .round, lineJoin: .round))
            }

            // 5. The cells the technique is about, at full chroma and a size
            //    that survives the 2× grid. 0.58 → 0.72 of the cell is 3.8pt
            //    against 3.1, and nothing is competing with it now.
            var marks = Path()
            for index in figure.lit { marks.addEllipse(in: dot(index, 0.72)) }
            context.fill(marks, with: .color(self.tint))

            var others = Path()
            for index in figure.alt { others.addEllipse(in: dot(index, 0.72)) }
            if figure.altIsRing {
                context.stroke(others, with: .color(self.tint),
                               lineWidth: max(0.75, cell * 0.18))
            } else {
                context.fill(others, with: .color(self.second))
            }
        }
        .frame(width: side, height: side)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

// MARK: - Shared chrome

/// The app's circular ✕, at the L4 rung because it sits *inside* the card's
/// glass. The word 'Close' it replaces drew a 13pt target in the corner while
/// the shelf's own disc was visible through the scrim 40pt away.
private struct CloseDisc: View {
    let tones: ThemeTones
    let label: String
    let action: @MainActor () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "xmark")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: SchoolMetrics.disc, height: SchoolMetrics.disc)
                .historyInsetCircle(tones, hairline: HistoryMetrics.hairlineWidth)
                // The disc gets the same edge every other surface here got:
                // a hairline says where the shape ends, a specular rim says
                // which way the light is coming from.
                .learnRim(in: Circle(), tones: tones, strength: 0.55, width: 0.75)
                .frame(width: Hit.min, height: Hit.min)
                // SwiftUI derives an image button's hit and AX frames from the
                // symbol's tight glyph bounds, not from the frame around it
                // (PRD-19). Without these the target measures ~15pt.
                .contentShape(Circle())
                .contentShape(.accessibility, Circle())
        }
        .buttonStyle(LearnPressStyle())
        .accessibilityLabel(label)
    }
}

// MARK: - One lesson

/// One lesson: the position, then the pattern, then the board handed back.
private struct SchoolLessonView: View {
    let lesson: TechniqueLesson
    let accent: Color
    let tones: ThemeTones
    /// `true` when the player reached the end rather than backing out.
    let onDismiss: @MainActor (Bool) -> Void

    /// Three beats, and the middle one is the whole lesson: **look before you
    /// are shown.** Revealing the pattern immediately would make this a
    /// diagram; making the player look first is what makes it practice.
    private enum Beat { case look, shown, done }
    @State private var beat: Beat = .look
    @State private var game: NineGame?

    private var technique: Technique { lesson.exemplar.technique }

    var body: some View {
        VStack(spacing: Space.l) {
            VStack(alignment: .leading, spacing: Space.xs) {
                Text(Strings.technique(technique))
                    .font(CouchTypography.title)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
                    .frame(minHeight: Hit.min, alignment: .leading)
                    .padding(.trailing, Hit.min + Space.s)
                // The lesson's one sentence, and it is the point of the screen —
                // it was typeset at `caption`, the smallest rung in the ramp.
                Text(detail)
                    .couchText(CouchTypography.body, .secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .topTrailing) {
                CloseDisc(tones: tones, label: Phrase.close) { onDismiss(beat == .done) }
            }

            if let game {
                GeometryReader { proxy in
                    // 24 = two `Space.m` gutters, unchanged: this is the board's
                    // own geometry and nothing in this pass is moving it.
                    let side = min(proxy.size.width, proxy.size.height) - Space.m * 2
                    BoardView(
                        game: game,
                        cursor: lesson.coach.step.cells.first ?? 40,
                        accent: accent,
                        showErrors: false,
                        solvedAt: nil,
                        roseOpen: false,
                        previewDigit: nil,
                        previewPencil: false,
                        // Lit only once the player has asked to be shown.
                        coachFocus: beat == .look ? nil : CoachFocus(.step(lesson.coach)),
                        side: max(120, side),
                        inset: Space.m
                    )
                    .frame(width: proxy.size.width, height: proxy.size.height)
                }
                .aspectRatio(1, contentMode: .fit)
            } else {
                ProgressView().controlSize(.small)
            }

            // The lesson's own primary action, now the same object as the
            // list's. It was a 16–22% accent wash inside the card's glass,
            // which is the L4 rung and correct for a *row*; a beat's one button
            // is not a row. Solid accent, a specular rim, an ambient shadow and
            // a pressed state — see `LearnSurface` and the tutorial's CTA,
            // which this deliberately matches so the two learning surfaces
            // press the same way.
            Button(action: advance) {
                Text(actionTitle)
                    .font(CouchTypography.heading)
                    .foregroundStyle(LearnSurface.accentInk(tones))
                    .frame(maxWidth: .infinity, minHeight: Hit.min + Space.xs)
                    .background(accent, in: Capsule())
                    .couchElevated(in: Capsule(), isLight: tones.isLight)
                    .learnRim(in: Capsule(), tones: tones, strength: 0.8)
                    .contentShape(Capsule())
                    .contentShape(.accessibility, Capsule())
            }
            .buttonStyle(LearnPressStyle())
        }
        .padding(SchoolMetrics.gutter)
        .frame(maxWidth: SchoolMetrics.maxWidth)
        .task { game = buildGame() }
    }

    private var detail: String {
        switch beat {
        case .look:  return Phrase.lessonLook
        case .shown: return BoardSpeech.coachSentence(.step(lesson.coach))
        case .done:  return Phrase.lessonDone(Strings.technique(technique))
        }
    }

    private var actionTitle: String {
        switch beat {
        case .look:  return Phrase.showMe
        case .shown: return Phrase.gotIt
        case .done:  return Phrase.close
        }
    }

    private func advance() {
        switch beat {
        case .look:  withAnimation(.couchFast) { beat = .shown }
        case .shown: withAnimation(.couchFast) { beat = .done }
        case .done:  onDismiss(true)
        }
    }

    /// The lesson's position as a real `NineGame`: the replayed placements go
    /// in as moves, and the candidate masks go in as pencil marks. The player
    /// is handed the notes because **a technique you cannot see the notes for
    /// is a technique you cannot learn** — every pattern here is a claim about
    /// where a digit can still go.
    private func buildGame() -> NineGame {
        var game = NineGame(puzzle: lesson.puzzle)
        for cell in 0..<81 where lesson.values[cell] != 0 && !lesson.givens[cell] {
            _ = game.place(lesson.values[cell], at: cell)
        }
        for cell in 0..<81 where lesson.values[cell] == 0 {
            for digit in 1...9 where lesson.candidates[cell] & Sudoku.bit(digit) != 0 {
                _ = game.togglePencil(digit, at: cell)
            }
        }
        return game
    }
}

/// Every user-facing literal in this file, in one block (PRD-20's seam).
///
/// The ten rows this file would like next are `technique.<case>.lesson`,
/// alongside the `technique.<case>.name` rows `Strings.technique` already
/// reads — one line each, saying what the pattern *is*. See `lessonLine`.
private enum Phrase {
    static let title = Strings.string("school.title")
    static let subtitle = Strings.string("school.subtitle")
    static let close = Strings.string("school.close")
    static let showMe = Strings.string("school.action.showMe")
    static let gotIt = Strings.string("school.action.gotIt")
    static let lessonLook = Strings.string("school.lesson.look")
    static func lessonDone(_ technique: String) -> String {
        Strings.string("school.lesson.done", .text(technique))
    }
    static func rowLabel(_ technique: String, met: Bool) -> String {
        Strings.string(met ? "school.row.met" : "school.row.new", .text(technique))
    }
}
#endif
