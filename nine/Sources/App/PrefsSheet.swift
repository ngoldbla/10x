// PrefsSheet.swift — the one allowed secondary surface (suite rule): timer
// on/off (off is the default and the statement), error-highlight on/off,
// same-number highlight, haptics, the theme and accent swatches, and on iOS
// control placement and launch resume. Lives inside CouchKit's GlassSheet.
//
// PRD-34 changed two things here. The rows are grouped into four named
// sections — Play / Feel / Appearance / Layout — because the flat list had
// drifted into an order
// nobody could hold in their head (theme at row six, accent at row ten). And
// "New game" left entirely: a live sim audit found it buried at the bottom of
// Settings, which is the last place anyone looks for the next board. Its
// three new homes are the shelf's difficulty cards, the "Fresh board" row at
// the top of the Boards sheet, and an "Another" chip after the Afterglow
// settles.
//
// W4A rebuilt what is *inside* the sheet, after wave 1 made the sheet itself a
// real one. Five things were wrong and all five were structural:
//
//  1. **Nothing was a control.** Six boolean prefs rendered as `Text("On")` and
//     three enumerated prefs silently *cycled* to the next case on tap with
//     nothing on screen saying so. They are now `Toggle`s and menus — a switch
//     says "two states, tap me", a chevron says "a list, tap me", and neither
//     needs a legend. The app ships ten accent hues and this sheet had no
//     coloured pixel on it; the row symbols and the switches now carry the
//     player's own accent.
//  2. **Two thirds of every row missed the 44pt floor.** The vertical padding
//     lived *inside* the button label, and SwiftUI derives a button's frame
//     from its drawn content, so `Tests/AXBaselines/prefs.txt` recorded
//     `Button "Haptics, On" (45,634 304x22)` — 22pt tall on a 63pt pitch. Rows
//     now carry `Hit.min` explicitly.
//  3. **The pitch jittered.** Row tops ran 351/414/475/536/634/699 — 63, 61,
//     61, 65 — because the height came from glyph metrics rather than from a
//     row metric. `Metrics.rowHeight` is that metric.
//  4. **The sections did not visually exist.** The header sat 28pt below the
//     block above it and 30pt above the block it labelled, a 1:1 ratio where
//     iOS runs about 4:1, so proximity read every header as a *footer* for the
//     block above. Headers now sit `Metrics.headerGap` above their own group
//     and `Metrics.sectionTop` below the previous one, and the group is a real
//     container with hairline separators.
//  5. **Four left edges.** The wordmark, the legend, the headings and the row
//     icons each invented their own inset, and the row icons were ragged among
//     themselves because `lock.iphone` is narrower than `hand.tap.fill`. There
//     is one `Metrics.gutter` and one `Metrics.iconColumn` now, so icons sit on
//     one vertical and labels on a second.
//
// The manual moved to the foot of the sheet in the same pass. It stays here —
// the suite rule is that the prefs sheet doubles as the help page — but a
// settings surface that opens on four rows of instructions pushes every actual
// setting below the fold, and the fold is where this sheet's whole Appearance
// section was living.
//
// **Round 2. Four findings, four structural answers.** Fourteen critics read
// the shipped frame blind; this sheet drew two blockers and two majors, and
// every one of them is about the same thing — the surface had shape but no
// light and no colour.
//
//  1. *"Zero Liquid Glass — the sheet is a flat opaque gray, not a material."*
//     The group card was `couchInset` and a tint, which is a region of a
//     surface and correct as far as it goes; what it lacked is an **edge**.
//     Every card now carries `couchRim` on top of the wash: one point of
//     gradient, bright at `.topLeading`, through nothing, to genuinely dark at
//     `.bottomTrailing`, with a second highlight one point inside along the top
//     arc. That is what makes a slab read as a pane, and it is the difference
//     ten of fourteen critics named in the same words on ten different screens.
//  2. *"Six identical full-blue switches… all system default"* and *"an icon set
//     that mixes filled circles and outline glyphs at inconsistent optical
//     weight."* Both are one fault: the symbol was carrying two jobs it is bad
//     at — signalling on/off (which the switch beside it already does, better)
//     and identifying the row (which it could not do consistently, because
//     `lock.iphone` and `hand.tap.fill` are not the same drawing at the same
//     size). Symbols are now **always filled, always in an equal rounded
//     container**, exactly as Settings does it, and their *colour* carries
//     meaning instead: coral for the error-highlight row, a neutral ink for the
//     timer, the player's accent for everything they chose.
//  3. *"Large title indented ~14pt past the group card's leading edge."*
//     Measured in `Tests/AXBaselines/prefs.txt` before this change: the cards
//     began at x=29 and "Nine" and every section header at x=44. `Metrics.margin`
//     is the one left edge all three now share, and it is 0 rather than a new
//     number because the card's radius is only concentric with the sheet's at
//     that inset (see `cardShape`).
//  4. *"The frame ends on an orphaned APPEARANCE header over ~150px of empty
//     sheet."* Half of that was the edge fade eating the last visible row: at
//     24pt it was wider than the 22pt content margin holding it off the
//     content, so the bottom row dissolved while the empty margin below it did
//     not. `fade` is now smaller than `scrollMargin`, which is the invariant
//     that was missing. The other half is the compact detent itself, which
//     lives in `couchkit/GlassComponents.swift` and is filed as a cross-file
//     need rather than fixed from here.
//
// **Round 3. The material was inverted and the fade was cutting.** A second
// blind panel read this sheet on both leanings and filed four things; three of
// them are one sentence that recurred on every sheet in the app, and it became
// the round's third acceptance rule.
//
//  1. *"Material is inverted and inert — cards are darker than the sheet,
//     nothing refracts."* The group card was a 4.5% **black** wash on light
//     grounds. A card that is darker than the surface it sits in is a well, not
//     a card, and a list of them reads as disabled. `cardTint` is white on both
//     leanings now, and `cardLift` buys back the separation that not-darkening
//     costs with the ambient shadow the panel asked for in place of a stroke.
//  2. *"A wall of eight identical blue toggles, all on, with zero hierarchy"*
//     and *"the Timer tile is gray while every other tile is blue — gray reads
//     'disabled' next to an ON toggle."* One fault: grey had been spent on one
//     row's *identity* (round 2's `neutralTint`), so the column could never use
//     it for the thing every reader takes it to mean. The tile follows the
//     switch now — see `toggleRow` and `offTint`. The other half of that
//     finding, a line of detail copy per row, needs ten catalog rows and is
//     filed as a cross-file need.
//  3. *"The bottom fade whites out the next section instead of clipping it…
//     the frame ends on a mushy gradient."* The dissolve was drawn at full
//     height whether or not there was anything beyond it. `edgeFade` scales
//     each end by the scroll's own remaining travel, so at rest the wordmark is
//     whole and at the foot of the scroll the last row is.
//  4. *"Section headers sit 2px off the card edge."* Already fixed —
//     `Metrics.margin` is the single left rule and the panel was reading a
//     frame recorded before it landed. Left as it is, and recorded here so the
//     next reader does not re-fix it.
import SwiftUI
import CouchKit

struct PrefsSheetContent: View {
    let model: AppModel
    /// tvOS only, and only in-game. The TV has no in-game route to the Boards
    /// sheet — it is reachable from the shelf alone — so the couch keeps its
    /// escape hatch here until the TV gets an IA pass of its own. iOS and
    /// macOS pass nil: they have Home in the control bar and the menu bar.
    var onNewGame: (@MainActor (Difficulty) -> Void)? = nil

    @Environment(\.colorScheme) private var colorScheme

    /// How far the sheet's scroll still has to travel at each end — the input to
    /// the edge fade, so a fade is only ever drawn where there is genuinely
    /// content beyond it. See `edgeFade`.
    #if !os(tvOS)
    @State private var edges = LearnScrollEdges()
    #endif

    /// The theme's own inks. Resolved once and read by `isLight`, the card
    /// wash and the semantic row tints, so the sheet cannot end up with two
    /// answers to "what colour is a mistake in this theme".
    private var tones: ThemeTones { model.prefs.theme.tones(for: colorScheme) }

    private var isLight: Bool { tones.isLight }

    /// The live accent, deepened for a light ground the same way every mark on
    /// the board is (`AccentChoice.color(isLight:)`).
    private var accent: Color { model.prefs.accent.color(isLight: isLight) }

    /// **The one row tint that is not the accent.**
    ///
    /// Error highlight is the only preference on this sheet that names a colour
    /// the player will see on the board, and `ThemeTones.coral` is that exact
    /// colour — already deepened for light grounds (`coralOnLight`, because the
    /// vivid one measures 1.92:1 on Camel). Round-2 finding: *"tint the switches
    /// to the app accent and vary icon color semantically (error highlight red,
    /// timer neutral) so the column isn't one undifferentiated blue stripe."*
    /// This is the "red" half.
    private var errorTint: Color { tones.coral }

    /// **The tint of a row whose switch is OFF, and it is the only thing in the
    /// icon column that means anything now.**
    ///
    /// Round 2 gave the timer a permanent neutral ink on the argument that the
    /// row "is genuinely about nothing but itself". Round 3 measured what a
    /// reader sees instead: *"the Timer tile is a black glyph on gray while
    /// every other tile is a blue glyph on blue tint — gray reads 'disabled'
    /// next to an ON toggle. Give Timer the same accent tint (reserve gray for
    /// genuinely off/neutral)."* That is the whole correction: grey is not a
    /// category of setting, it is a *state*, and spending it on one row's
    /// identity meant the column could never use it for the thing it reads as.
    ///
    /// So every tile now takes the row's own colour while the row is on, and
    /// this quiet ink while it is off — which is also the first hierarchy this
    /// sheet has ever had beyond "eight identical pills", and it costs no copy
    /// (the other prescription, a line of detail text per row, needs ten catalog
    /// rows and is filed as a cross-file need).
    private var offTint: Color { Color.primary.opacity(0.38) }

    /// The wash under a group of rows. `couchInset` is L4 of the material
    /// ladder — shape and tint, never a second pane — because this sheet is
    /// already glass and a `.regular` card inside `.regular` glass measured
    /// 1.005:1 against it.
    ///
    /// **White on both leanings now, and on paper that is a reversal.** The card
    /// was a 4.5% *black* wash on light grounds, which is a card darker than the
    /// sheet it sits in — the finding two panels filed against every sheet in
    /// the app and the round's third acceptance rule: *"flip the stack to
    /// Apple's grouped model: sheet on secondarySystemGroupedBackground, rows on
    /// white with a 0.5pt specular edge and a soft ambient shadow so the groups
    /// read as elevated."* Elevation is brightness on every ground; a darker
    /// inset region is a well, not a card. `HistoryMetrics.fill` carries the
    /// same correction for the other sheet and the same 0.75, so the two agree
    /// about what a card is.
    private var cardTint: Color {
        isLight ? Color.white.opacity(0.75) : Color.white.opacity(0.07)
    }

    /// The card's corner. Concentric with the sheet by construction: the
    /// compact presentation is a 38pt sheet with 22pt of content padding, and
    /// `Radius.inner(38, inset: 22)` is 16 — `Radius.control` exactly.
    private var cardShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: Radius.control, style: .continuous)
    }

    var body: some View {
        #if os(tvOS)
        content
        #else
        // `showsIndicators: false` used to stand here, on a sheet whose last
        // visible line was the *label* of the theme row — every swatch, all ten
        // accents, the icon picker and the whole Layout section sat below an
        // invisible fold with nothing on screen admitting they existed. The
        // indicator and the edge fade are both evidence.
        ScrollView { content }
            .contentMargins(.vertical, Metrics.scrollMargin, for: .scrollContent)
            .learnScrollEdges(into: $edges)
            .mask { edgeFade }
        #endif
    }

    #if !os(tvOS)
    /// A dissolve at both ends, so content passing the edge of the sheet reads
    /// as continuing rather than as being cut.
    ///
    /// **It has to be shorter than the content margin holding it off the
    /// content**, and at 24 against a 22pt margin it was not — so at rest the
    /// gradient reached two points *into* the first and last real rows and
    /// ghosted them. That is half of a round-2 blocker (*"the frame ends on an
    /// orphaned APPEARANCE header over ~150px of empty sheet"*): the header was
    /// legible, the Theme row under it was not, and a faded row reads as absent.
    /// See `Metrics.fade`.
    ///
    /// **Round 3 tied each end's height to the scroll's own travel**, which is
    /// the same fix `HistorySheet.edgeFade` records and the same finding: *"the
    /// fade over the APPEARANCE card is so strong the partial row is nearly
    /// invisible, so the affordance is lost and the frame ends on a mushy
    /// gradient — either drop the fade and let content clip hard under the
    /// sheet edge, or shorten it to ~24pt and make the detent land mid-row."*
    /// A dissolve that is present when there is nothing beyond it is not a
    /// scroll edge, it is a vignette, and it is what the round's fourth
    /// acceptance rule forbids: no fade may cut a glyph or a row in half. At
    /// rest the top gradient is zero points tall and the wordmark is whole; at
    /// the foot of the scroll the bottom one is, and so is the last row.
    private var edgeFade: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom)
                .frame(height: Metrics.fade * CGFloat(edges.strength(top: true)))
            Color.black
            LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: Metrics.fade * CGFloat(edges.strength(top: false)))
        }
    }
    #endif

    private var content: some View {
        let stack = VStack(alignment: .leading, spacing: 0) {
            // The wordmark, not a word — see `ShareCardMetrics.wordmark`.
            //
            // `margin`, not `gutter`. This line sat 15pt right of the card edge
            // below it (x=44 against x=29 in the shipped AX baseline), which is
            // three left rules in one 349pt panel — the title's, the card's and
            // the row content's. There are two now and both mean something.
            Text(verbatim: Phrase.wordmark)
                .couchText(CouchTypography.title)
                .padding(.horizontal, Metrics.margin)

            // PRD-34: five named groups — Play, Feel, Appearance, Layout,
            // About — replacing the flat list the live audit walked, where
            // theme and accent sat four rows apart with resume, haptics and
            // the whole Layout block wedged between them.
            playSection
            feelSection
            appearanceSection
            layoutSection
            newGameSection
            legendSection
            dismissHint
        }
        // `headerGap`, not `sectionTop`. `contentMargins` already holds 22pt of
        // empty scroll below the last row; stacking a second 24pt block on top
        // of it left ~46pt of untouched ground at the foot of the sheet, which
        // is over round 2's `Rhythm.maxDeadBand` ceiling and is doing no
        // compositional work at all. On tvOS there is no scroll and no content
        // margin, but there is also `maxHeight: .infinity` below, so the stack
        // is top-aligned in a full-height panel and this padding never shows.
        .padding(.bottom, Metrics.headerGap)

        #if os(tvOS)
        return stack.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        #else
        return stack.frame(maxWidth: .infinity, alignment: .topLeading)
        #endif
    }

    // MARK: - Sections

    /// **Every symbol here is unconditionally filled, and that is a deliberate
    /// loss of information.**
    ///
    /// Each of these four used to flip between an outline and a filled variant
    /// with the pref — `clock`/`clock.fill`, `circle`/`checkmark.circle.fill` —
    /// which meant the icon column was a second, quieter on/off readout beside a
    /// switch that already says it louder and unambiguously. It cost more than
    /// it paid: half the states put an *outline* glyph next to a filled one in
    /// the neighbouring row, so the column's optical weight changed with the
    /// player's settings rather than staying a column. A round-2 critic caught
    /// exactly that — *"mixes filled circles and outline glyphs at inconsistent
    /// optical weight"*. Filled always; the switch carries the state; the
    /// container and the tint carry the identity.
    private var playSection: some View {
        prefsSection(Strings.string("prefs.section.play")) {
            toggleRow(
                title: Strings.string("prefs.timer.title"),
                symbol: "clock.fill",
                isOn: bind(\.showTimer))
            separator
            toggleRow(
                title: Strings.string("prefs.errorHighlight.title"),
                // The mark this row governs is the board's error marker, so the
                // glyph is a warning in the theme's own coral rather than a
                // checkmark in the accent. A checkmark said "correct"; the pref
                // is about being shown when you are not.
                symbol: "exclamationmark.triangle.fill",
                tint: errorTint,
                isOn: bind(\.errorHighlight))
            separator
            // `square.grid.3x3.fill`, not `9.square.fill`. Round 3: *"normalise
            // glyph cap-height inside the tile — the clock nearly full-bleeds
            // while the '9' sits tiny in its box."* Both halves of that are one
            // fact about the catalog: an *enclosed* glyph spends most of its
            // box on the enclosure and draws its meaning at about half the cap
            // height of a free-standing one, so no point size can make the two
            // weigh the same. The tile is already the enclosure. A filled 3×3
            // grid is the board this pref lights up, at the same ink mass as the
            // clock beside it.
            toggleRow(
                title: Strings.string("prefs.numberHighlight.title"),
                symbol: "square.grid.3x3.fill",
                isOn: bind(\.numberHighlight))
            // Resume-on-launch ships on iOS, macOS and tvOS (PRD-4 §2.6,
            // PRD-5 §2.3 parity) — which is every platform this file compiles
            // for, and the fence is kept so it stays true if a fifth arrives.
            #if os(iOS) || os(macOS) || os(tvOS)
            separator
            // `play.fill` for the same reason as the row above: the triangle
            // inside `play.circle.fill` is a third of its own box.
            toggleRow(
                title: Strings.string("prefs.resume.title"),
                symbol: "play.fill",
                isOn: bind(\.resumeOnLaunch))
            #endif
        }
    }

    /// Feel — everything the board does to your hands. One row on iOS
    /// (PRD-21 haptics) and one on the TV, none on the Mac. (The Live Activity
    /// row left with the daily system, 2026-08-02.)
    @ViewBuilder
    private var feelSection: some View {
        #if os(iOS)
        prefsSection(Strings.string("prefs.section.feel")) {
            toggleRow(
                title: Strings.string("prefs.haptics.title"),
                symbol: "hand.tap.fill",
                isOn: bind(\.touchHaptics))
        }
        #elseif os(tvOS)
        prefsSection(Strings.string("prefs.section.feel")) {
            // Controller haptics — the Afterglow score in hand, and the ticks
            // during play (PRD-5 §2.2). Silences all of it in a pad session.
            toggleRow(
                title: Strings.string("prefs.controllerHaptics.title"),
                symbol: "gamecontroller.fill",
                isOn: bind(\.controllerHaptics))
        }
        #endif
    }

    /// Appearance — the two colour controls, finally adjacent, and on iOS the
    /// Home Screen icon beside them.
    private var appearanceSection: some View {
        prefsSection(Strings.string("prefs.section.appearance")) {
            themeRow
            separator
            accentRow
            #if os(iOS)
            // PRD-16. iOS only — a tvOS icon is a layered brand asset and macOS
            // has no alternate-icon API.
            separator
            AppIconRow(accent: accent)
            #endif
        }
    }

    @ViewBuilder
    private var layoutSection: some View {
        #if os(iOS)
        // PRD-2: board anchor + ambient slot, grouped with the existing
        // control-placement pref — all three decide where things sit. All
        // three used to *cycle* on tap: one silent step per press through a
        // list the player could not see, with no way back but going round.
        prefsSection(Strings.string("prefs.section.layout")) {
            pickRow(
                title: Strings.string("prefs.controls.title"),
                symbol: model.prefs.controlsAtBottom
                    ? "inset.filled.bottomthird.square"
                    : "inset.filled.topthird.square",
                selection: bind(\.controlsAtBottom),
                options: [true, false],
                label: {
                    Strings.string($0 ? "prefs.controls.bottom" : "prefs.controls.top")
                })
            separator
            pickRow(
                title: Strings.string("prefs.boardPosition.title"),
                symbol: boardAnchorSymbol,
                selection: bind(\.boardAnchor),
                options: BoardAnchor.allCases,
                label: { $0.title })
            separator
            pickRow(
                title: Strings.string("prefs.ambient.title"),
                symbol: ambientSlotSymbol,
                selection: bind(\.ambientSlot),
                options: AmbientSlot.allCases,
                label: { $0.title })
        }
        #endif
    }

    /// The manual, at the foot of the sheet rather than the head of it.
    private var legendSection: some View {
        prefsSection(Strings.string("menu.help.howToPlay")) {
            ControlLegend(rows: legendRows, arrangement: .grid)
                .padding(.horizontal, Metrics.gutter)
                .padding(.vertical, Metrics.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var legendRows: [LegendRow] {
        #if os(tvOS)
        // Keyed on padSession, not padConnected: the sim's phantom pad
        // reports connected but never adopts, so remote players (and the
        // sim) keep the remote legend.
        return model.padSession ? NineLegend.padCompact : NineLegend.compact
        #elseif os(macOS)
        return NineLegend.keyboardCompact
        #else
        return NineLegend.touchCompact
        #endif
    }

    @ViewBuilder
    private var dismissHint: some View {
        #if os(tvOS)
        Text(Strings.string("sheet.dismiss.remote"))
            .couchText(CouchTypography.caption, Color.primary.opacity(Metrics.hintTone))
            .padding(.horizontal, Metrics.margin)
            .padding(.top, Metrics.sectionTop)
        #elseif os(macOS)
        // The Settings window has its own chrome — no dismissal hint.
        EmptyView()
        #else
        Text(Strings.string("sheet.dismiss.touch"))
            .couchText(CouchTypography.caption, Color.primary.opacity(Metrics.hintTone))
            .padding(.horizontal, Metrics.margin)
            .padding(.top, Metrics.sectionTop)
        #endif
    }

    #if os(iOS)
    // PRD-2 suggested inset.filled.tophalf.square — that name doesn't exist
    // in the SF catalog; the square.*half.filled family does.
    private var boardAnchorSymbol: String {
        switch model.prefs.boardAnchor {
        case .top: return "square.tophalf.filled"
        case .center: return "square.inset.filled"
        case .bottom: return "square.bottomhalf.filled"
        }
    }

    /// Filled, like every other symbol on this sheet. `circle.slash` is the one
    /// exception the catalog forces — there is no filled "off" glyph that reads
    /// as absence rather than as a different feature — and it is also the only
    /// state of the three where the row is turned off, so it is allowed to be
    /// the lightest mark in the column.
    private var ambientSlotSymbol: String {
        switch model.prefs.ambientSlot {
        case .none: return "circle.slash"
        case .clock: return "clock.fill"
        }
    }
    #endif

    // MARK: - New game (tvOS only — see `onNewGame`)

    @ViewBuilder
    private var newGameSection: some View {
        #if os(tvOS)
        if let onNewGame {
            VStack(alignment: .leading, spacing: 14) {
                sectionLabel(Strings.string("prefs.newGame.title"))
                // One row of the three offered bands (2026-08-02). The twin of
                // this row is `BoardsSheet.freshPill` — duplicated on purpose,
                // so change one and go look at the other. Only the shape is
                // shared: here the affordance is the focus ring, so
                // `couchGlassInteractive` stays and there is no filter-chip
                // reading to fix.
                HStack(spacing: 10) {
                    ForEach(Difficulty.rowBands, id: \.self) { newGamePill($0, onNewGame) }
                }
                .padding(.horizontal, Metrics.margin)
                // Corrected in PRD-34: `startFree` calls `library.create`, which
                // mints a *new* entry — the board you are on stays a partial and
                // is resumable from the shelf. The old copy said it was abandoned,
                // which scared people off a non-destructive action.
                Text(Strings.string("prefs.newGame.note"))
                    .couchText(CouchTypography.caption,
                               Color.primary.opacity(Metrics.hintTone))
                    .padding(.horizontal, Metrics.margin)
            }
            .padding(.top, Metrics.sectionTop)
        }
        #endif
    }

    #if os(tvOS)
    private func newGamePill(
        _ difficulty: Difficulty,
        _ start: @escaping @MainActor (Difficulty) -> Void
    ) -> some View {
        Button {
            start(difficulty)
        } label: {
            Text(Strings.difficulty(difficulty))
                .font(CouchTypography.caption)
                // Cap the line and let a tight locale shrink by a hair rather
                // than grow a second line and break the row's height.
                .lineLimit(1)
                .minimumScaleFactor(0.9)
                // Inset before the stretch, so 12pt is a floor the label keeps
                // while the capsule still fills its column.
                .padding(.horizontal, 12)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .couchGlassInteractive(in: Capsule())
                // The unfocused state needs an edge too — see the same note on
                // `HistorySheet`'s close disc. Six pills in two rows with no rim
                // on any of them is six grey lozenges until the remote arrives.
                .couchRim(in: Capsule(), isLight: isLight)
        }
        .buttonStyle(.plain)
    }
    #endif

    // MARK: - Grouping

    /// A named group: its header, then its rows inside one container.
    ///
    /// The two paddings are the whole point. `sectionTop` separates this group
    /// from the one above it and `headerGap` binds the header to the rows
    /// below it, at roughly the 4:1 ratio iOS uses — the shipped sheet spent
    /// the same 28-30pt on both sides of every header, so gestalt proximity
    /// read each one as a footer for the block it followed.
    ///
    /// **The card has an edge now, and that is round 2's whole thesis on this
    /// surface.** `couchInset` + `cardTint` is a *region* — a tone step, which
    /// tells you where the card ends and nothing else. Ten of fourteen blind
    /// critics wrote a version of the same sentence about frames drawn this way:
    /// *"flat opaque fill plus a hairline, not a material"*. `couchRim` adds the
    /// missing half: a one-point gradient running bright at `.topLeading`,
    /// through explicit zero-alpha stops in the middle, to genuinely dark at
    /// `.bottomTrailing`, plus a second highlight one point inside along the top
    /// arc only. Bright top, dark bottom lip, thickness between them — that is a
    /// pane of glass rather than a rectangle of paint, and it is a *lighting*
    /// artefact, so it stays one point at every scale and never becomes a frame.
    ///
    /// `couchRim` and not `couchElevated`: these cards are flush against the
    /// sheet, not floating above it, and giving five stacked groups a drop
    /// shadow each is how a settings surface starts looking like a pile of
    /// stickers. The rim, never the lift.
    ///
    /// **On paper that argument loses to arithmetic, and `cardLift` is the
    /// split.** With the card now *lighter* than the sheet rather than darker
    /// (see `cardTint`) the tone step on a light ground is about 1.27:1, where
    /// darkening reached 1.44 — and a rim alone cannot carry a boundary that
    /// faint. Round 3's prescription names the replacement: *"drop the outline
    /// strokes in favour of a lighter fill + a soft ambient shadow, so elevation
    /// comes from material rather than from borders."* Dark grounds keep the
    /// rim alone, where a 7% white lift is a full perceptual step and the pile
    /// of stickers is still the risk.
    private func prefsSection<Rows: View>(
        _ title: String, @ViewBuilder rows: () -> Rows
    ) -> some View {
        VStack(alignment: .leading, spacing: Metrics.headerGap) {
            sectionLabel(title)
            cardLift(
                VStack(spacing: 0) { rows() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .couchInset(in: cardShape, tint: cardTint)
            )
            .padding(.horizontal, Metrics.margin)
        }
        .padding(.top, Metrics.sectionTop)
    }

    /// The edge under a group card: the specular rim on dark, the rim and a
    /// two-layer ambient shadow on light. See `prefsSection`.
    @ViewBuilder
    private func cardLift<V: View>(_ view: V) -> some View {
        if isLight {
            view.couchElevated(in: cardShape, isLight: true)
        } else {
            view.couchRim(in: cardShape, isLight: false)
        }
    }

    /// A group heading. Uppercase and tracked rather than merely small: the
    /// shipped sheet typeset the header, the row's value and the legend's
    /// action column in *one* style — `CouchTypography.caption` at
    /// `.secondary`, all three measuring (161,161,161) on dark and (98,98,97)
    /// on light — so three semantic roles had one voice and the only hierarchy
    /// left was indentation.
    ///
    /// The tone is `.primary` at 62% rather than `.tertiary`. A header is meant
    /// to sit *under* its rows in weight, and `.tertiary` gets there by giving
    /// up contrast — on Paper it lands near 3:1, below AA for 13pt. Uppercase
    /// and a half-point of tracking buy the same recession typographically and
    /// this measures about 5.5:1 on the same ground.
    ///
    /// `margin`, not `gutter`: a header labels the card, so it sits on the
    /// card's own leading edge rather than 15pt to the right of it.
    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .tracking(Metrics.headerTracking)
            .couchText(CouchTypography.label, Color.primary.opacity(Metrics.headerTone))
            .textCase(.uppercase)
            .padding(.horizontal, Metrics.margin)
            .accessibilityAddTraits(.isHeader)
    }

    /// The seam between two rows, inset to the label column so the icon column
    /// reads as one continuous strip — **and fading out at its trailing end
    /// rather than stopping dead on the card's edge.**
    ///
    /// Round 2's second acceptance rule is that no bar in the app may end on a
    /// line. A rule that runs to the card's boundary and terminates there is
    /// exactly that: the corner curves away and the line does not follow it, so
    /// what the eye reads is a scratch across the glass rather than a division
    /// inside it. The leading end needs no ramp — it already begins in open
    /// space at `labelColumn`, which is a beginning and not a cut — so the
    /// gradient is asymmetric on purpose: full strength from the start, easing
    /// to nothing over the last eighth.
    private var separator: some View {
        Rectangle()
            .fill(
                LinearGradient(
                    stops: [
                        .init(color: Color.primary.opacity(Metrics.separatorTone), location: 0),
                        .init(color: Color.primary.opacity(Metrics.separatorTone), location: 0.86),
                        .init(color: Color.primary.opacity(0), location: 1),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing))
            .frame(height: Metrics.separator)
            .padding(.leading, Metrics.labelColumn)
            .accessibilityHidden(true)
    }

    // MARK: - Rows

    /// A binding into `model.prefs` — assigning the field mutates the struct
    /// in place, tripping its `didSet` and persisting.
    private func bind<V>(_ keyPath: WritableKeyPath<NinePrefs, V>) -> Binding<V> {
        Binding(
            get: { model.prefs[keyPath: keyPath] },
            set: { model.prefs[keyPath: keyPath] = $0 }
        )
    }

    /// The left half of every row in the sheet, and the reason there are two
    /// vertical edges here instead of six: the symbol is given a fixed column
    /// (`hand.tap.fill` is 3pt wider than `lock.iphone`, which is what made the
    /// shipped labels ragged from x=77.3 to x=80.3) and the title always starts
    /// at `Metrics.labelColumn`.
    ///
    /// A type rather than a method so `AppIcons.swift` — which draws a row in
    /// the same card and has no model of its own — cannot land on a second set
    /// of numbers.
    ///
    /// **The symbol sits in a container now, and the container is the fix.**
    /// A bare glyph in a fixed-width column lines up its *box* and nothing else:
    /// `lock.iphone` is a thin outline, `hand.tap.fill` is a solid mass, and
    /// `9.square.fill` is a filled square, so the column read as three different
    /// weights stacked — the round-2 note about glyphs "visibly lighter and
    /// off-metric next to the filled clock". Settings solves this by never
    /// showing a naked glyph: every row icon is the same rounded square, and the
    /// *tile* is what the eye aligns and weighs, with the glyph inside free to
    /// be whatever shape the meaning needs.
    ///
    /// A **washed** tile rather than Settings' saturated one, because Nine's is
    /// drawn on glass and not on an opaque list: a column of five fully
    /// saturated chips over a translucent card is a stripe of paint, and a
    /// critic already called the shipped switches "one undifferentiated blue
    /// stripe". Low-alpha tile, hairline of the same hue, glyph at full
    /// strength — the tint is legible, the value is not shouted.
    struct RowLabel: View {
        let title: String
        let symbol: String
        let accent: Color
        /// What this row *means*, when that is not simply "the player's accent":
        /// coral for the error marker, a neutral ink for the timer. Defaulted so
        /// `AppIcons.swift` and every accent-coloured row say nothing.
        var tint: Color? = nil

        private var ink: Color { tint ?? accent }

        var body: some View {
            HStack(spacing: Metrics.iconGap) {
                Image(systemName: symbol)
                    .font(.system(size: Metrics.iconSize, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(ink)
                    .frame(width: Metrics.iconTile, height: Metrics.iconTile)
                    .background {
                        let tile = RoundedRectangle(
                            cornerRadius: Metrics.iconTile * Radius.iconSquircle,
                            style: .continuous)
                        tile
                            .fill(ink.opacity(Metrics.iconTileTone))
                            .overlay(tile.strokeBorder(
                                ink.opacity(Metrics.iconTileRimTone),
                                lineWidth: Metrics.iconTileRim))
                    }
                    .frame(width: Metrics.iconColumn, alignment: .center)
                Text(title)
                    .couchText(CouchTypography.body)
                    .lineLimit(2)
                    .minimumScaleFactor(0.85)
                Spacer(minLength: Space.s)
            }
            // The row metric lives on the *label*, not on the control wrapping
            // it, and that is the whole 44pt fix. An accessibility element
            // belongs to the view that generated it, so a `Toggle` padded from
            // the outside still reports the height of its own switch —
            // `Button "Haptics, On" (45,634 304x22)` is that mistake in the
            // shipped baseline. Give the *content* the height and the control
            // is that tall.
            .frame(minHeight: Metrics.rowHeight)
        }
    }

    /// The header line of a swatch row: the same symbol column, the same title
    /// treatment and the same height as a `toggleRow`, with the current choice
    /// spelled out on the right.
    ///
    /// Before this, "Theme" was set in the *section header's* style — so a
    /// sub-row impersonated a heading, at the precise point the shipped sheet's
    /// fold fell, with "Appearance" sitting directly above it in the same type.
    struct SwatchHeader: View {
        let title: String
        let symbol: String
        let value: String
        let accent: Color
        /// See `RowLabel.tint`. Trailing and defaulted so `AppIcons.swift`'s
        /// call site keeps compiling untouched.
        var tint: Color? = nil

        var body: some View {
            HStack(spacing: Metrics.iconGap) {
                RowLabel(title: title, symbol: symbol, accent: accent, tint: tint)
                Text(value)
                    .couchText(CouchTypography.body, Color.primary.opacity(Metrics.valueTone))
                    .lineLimit(1)
            }
            .padding(.horizontal, Metrics.gutter)
            .frame(minHeight: Metrics.rowHeight)
            .accessibilityElement(children: .combine)
        }
    }

    /// A boolean pref as a real switch.
    ///
    /// The label lives *inside* the `Toggle` rather than beside a
    /// `.labelsHidden()` one on purpose: a hidden-label toggle is an
    /// accessibility element the size of the switch — 51×31 — and this row has
    /// a 44pt floor to clear. With the label inside, the element is the row.
    ///
    /// **The switch keeps the accent even where the icon does not.** A `Toggle`'s
    /// tint is a system control colour with a system meaning — "on" — and Nine's
    /// accent is the app's answer to what "on" looks like. Tinting the error
    /// row's switch coral would be saying the setting is *dangerous* rather than
    /// that it concerns errors, which is not what it does. So the row's
    /// semantics live in the icon tile and the switch stays the one colour the
    /// player picked, on every row.
    ///
    /// **The tile follows the switch now.** Eight tiles all lit in the accent
    /// beside eight switches all lit in the accent was the wall a panel opened
    /// with — *"a wall of eight identical blue toggles, all on, with zero
    /// hierarchy"* — and the column had no way to say anything else, because
    /// grey had been spent on one row's identity (see `offTint`). Lit while the
    /// pref is on, quiet while it is off: the icon column becomes a second,
    /// glanceable readout of the whole sheet instead of eight copies of one
    /// decoration, and a frame with a mixed state finally has something in it
    /// to look at.
    private func toggleRow(
        title: String, symbol: String, tint: Color? = nil, isOn: Binding<Bool>
    ) -> some View {
        let ink = isOn.wrappedValue ? (tint ?? accent) : offTint
        let toggle = Toggle(isOn: isOn) {
            RowLabel(title: title, symbol: symbol, accent: accent, tint: ink)
        }
        .tint(accent)

        #if os(tvOS)
        // `SwitchToggleStyle` is not available on tvOS; the platform's own
        // toggle presentation is the focusable one there.
        let styled = toggle
        #else
        let styled = toggle.toggleStyle(.switch)
        #endif

        return hapticized(
            styled
                .padding(.horizontal, Metrics.gutter)
                .frame(minHeight: Metrics.rowHeight)
                .contentShape(Rectangle()),
            on: isOn.wrappedValue)
    }

    #if os(iOS)
    /// An enumerated pref as a menu: the current value, a chevron, and the
    /// whole list one tap away with the current one ticked.
    ///
    /// A `Menu` wrapping a `Picker` rather than `.pickerStyle(.menu)` directly,
    /// because outside a `Form` a menu-styled picker drops its own label and
    /// renders as a bare value button — this row needs the symbol, the title
    /// and the value on one line.
    private func pickRow<Value: Hashable>(
        title: String,
        symbol: String,
        selection: Binding<Value>,
        options: [Value],
        label: @escaping (Value) -> String
    ) -> some View {
        let menu = Menu {
            Picker(selection: selection) {
                ForEach(options, id: \.self) { option in
                    Text(label(option)).tag(option)
                }
            } label: {
                EmptyView()
            }
        } label: {
            HStack(spacing: Metrics.iconGap) {
                RowLabel(title: title, symbol: symbol, accent: accent)
                Text(label(selection.wrappedValue))
                    .couchText(CouchTypography.body,
                               Color.primary.opacity(Metrics.valueTone))
                    .lineLimit(1)
                // The affordance the cycling rows never had: a value plus the
                // mark that says the value is one of several.
                Image(systemName: "chevron.up.chevron.down")
                    .font(CouchTypography.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, Metrics.gutter)
            .frame(minHeight: Metrics.rowHeight)
            .contentShape(Rectangle())
        }
        // The list is a fixed order the player can learn, not one that
        // reshuffles itself around wherever the finger last was.
        .menuOrder(.fixed)

        return hapticized(menu, on: selection.wrappedValue)
    }
    #endif

    /// Selection feedback for a row, gated on the player's own haptics pref —
    /// toggling "Haptics" itself used to be the one switch in the app that
    /// produced no haptic.
    ///
    /// The flag is read here and captured as a `Bool` rather than read inside
    /// the closure: the condition closure is not main-actor isolated and
    /// `AppModel` is.
    @ViewBuilder
    private func hapticized<V: View, T: Equatable>(_ view: V, on trigger: T) -> some View {
        #if os(iOS)
        let enabled = model.prefs.touchHaptics
        view.sensoryFeedback(.selection, trigger: trigger) { _, _ in enabled }
        #else
        view
        #endif
    }

    // MARK: - Swatch rows

    private var accentRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            SwatchHeader(
                title: Strings.string("prefs.accent.title"),
                symbol: "paintpalette.fill",
                value: model.prefs.accent.title,
                accent: accent)
            SwatchFlow(spacing: Swatch.gap) {
                ForEach(AccentChoice.allCases, id: \.self) { choice in
                    Button {
                        model.prefs.accent = choice
                    } label: {
                        accentSwatch(choice, isSelected: choice == model.prefs.accent)
                    }
                    .buttonStyle(.plain)
                    // The touch target was always meant to be the padded
                    // square, and the accessibility shape used to be the only
                    // thing that knew it: the drawn circle was 36pt (24.2pt on
                    // iOS, because it was multiplied by `CouchScale.chrome`)
                    // while `Tests/AXBaselines/prefs.txt` recorded a compliant
                    // 44. The swatch is a real `Hit.min` square now and this
                    // line only makes the two agree.
                    .contentShape(.accessibility, Circle().size(width: Hit.min, height: Hit.min))
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(choice == model.prefs.accent ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, Metrics.cardPadding)
        }
    }

    private var themeRow: some View {
        VStack(alignment: .leading, spacing: 0) {
            SwatchHeader(
                title: Strings.string("prefs.theme.title"),
                symbol: "circle.lefthalf.filled",
                value: model.prefs.theme.title,
                accent: accent)
            SwatchFlow(spacing: Swatch.gap) {
                ForEach(ThemeChoice.allCases, id: \.self) { choice in
                    Button {
                        model.prefs.theme = choice
                    } label: {
                        themeSwatch(choice, isSelected: choice == model.prefs.theme)
                    }
                    .buttonStyle(.plain)
                    .contentShape(
                        .accessibility,
                        RoundedRectangle(cornerRadius: Swatch.ringRadius, style: .continuous)
                            .size(width: Hit.min, height: Hit.min))
                    .accessibilityLabel(choice.title)
                    .accessibilityAddTraits(choice == model.prefs.theme ? [.isSelected] : [])
                }
            }
            .padding(.horizontal, Metrics.gutter)
            .padding(.bottom, Metrics.cardPadding)
        }
    }

    /// An accent at swatch size: the colour it will actually paint on this
    /// ground, ringed when it is the one in force.
    private func accentSwatch(_ choice: AccentChoice, isSelected: Bool) -> some View {
        ZStack {
            Circle()
                .fill(choice.color(isLight: isLight))
                .frame(width: Swatch.art, height: Swatch.art)
                .overlay {
                    // Every swatch keeps an edge — a pale accent on Paper would
                    // otherwise have none.
                    Circle().strokeBorder(
                        Color.primary.opacity(Swatch.hairlineTone),
                        lineWidth: Swatch.hairline)
                }
            if isSelected {
                Circle()
                    .strokeBorder(Color.primary, lineWidth: Swatch.selected)
                    .frame(width: Hit.min, height: Hit.min)
            }
        }
        .frame(width: Hit.min, height: Hit.min)
    }

    /// A theme at swatch size: its backdrop with a "9" in its digit tone —
    /// auto splits Void/Paper diagonally since it could resolve to either.
    private func themeSwatch(_ choice: ThemeChoice, isSelected: Bool) -> some View {
        let dark = choice.tones(for: .dark)
        let light = choice.tones(for: .light)
        let art = RoundedRectangle(cornerRadius: Swatch.artRadius, style: .continuous)
        return ZStack {
            ZStack {
                Rectangle().fill(dark.background)
                if choice == .auto {
                    DiagonalHalf().fill(light.background)
                }
                // A numeral drawn as a swatch, not a word.
                Text(verbatim: "9")
                    .font(.system(size: Swatch.art * 0.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(choice == .auto ? .gray : dark.digitTone)
            }
            .frame(width: Swatch.art, height: Swatch.art)
            .clipShape(art)
            .overlay {
                art.strokeBorder(
                    Color.primary.opacity(Swatch.hairlineTone), lineWidth: Swatch.hairline)
            }
            if isSelected {
                RoundedRectangle(cornerRadius: Swatch.ringRadius, style: .continuous)
                    .strokeBorder(Color.primary, lineWidth: Swatch.selected)
                    .frame(width: Hit.min, height: Hit.min)
            }
        }
        .frame(width: Hit.min, height: Hit.min)
    }

    /// A left-aligned flow that wraps onto as many lines as it needs. PRD-16
    /// took the theme row from six swatches to nine and the accent row from
    /// eight to ten; a plain `HStack` still fits an iPhone by about 30 pt,
    /// which is the kind of margin that turns into a clipped swatch on the
    /// release that adds a tenth theme.
    ///
    /// A `Layout` rather than a `LazyVGrid` because each row is a wrapped
    /// sentence, not a table; tvOS focus is derived from geometry, so wrapping
    /// needs no focus work of its own.
    struct SwatchFlow: Layout {
        var spacing: CGFloat

        func sizeThatFits(
            proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
        ) -> CGSize {
            let width = proposal.width ?? .infinity
            let rows = rows(subviews: subviews, width: width)
            return CGSize(
                width: proposal.width ?? rows.map(\.width).max() ?? 0,
                height: rows.last.map { $0.y + $0.height } ?? 0)
        }

        func placeSubviews(
            in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
        ) {
            for row in rows(subviews: subviews, width: bounds.width) {
                var x = bounds.minX
                for index in row.range {
                    let size = subviews[index].sizeThatFits(.unspecified)
                    subviews[index].place(
                        at: CGPoint(x: x, y: bounds.minY + row.y),
                        anchor: .topLeading,
                        proposal: ProposedViewSize(size))
                    x += size.width + spacing
                }
            }
        }

        private struct Row {
            var range: Range<Int>
            var y: CGFloat
            var width: CGFloat
            var height: CGFloat
        }

        private func rows(subviews: Subviews, width: CGFloat) -> [Row] {
            var rows: [Row] = []
            var start = 0
            var x: CGFloat = 0
            var y: CGFloat = 0
            var lineHeight: CGFloat = 0

            for index in subviews.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                if index > start, x + size.width > width {
                    rows.append(
                        Row(range: start..<index, y: y, width: x - spacing, height: lineHeight))
                    y += lineHeight + spacing
                    start = index
                    x = 0
                    lineHeight = 0
                }
                x += size.width + spacing
                lineHeight = max(lineHeight, size.height)
            }
            if start < subviews.count {
                rows.append(
                    Row(
                        range: start..<subviews.count, y: y, width: x - spacing,
                        height: lineHeight))
            }
            return rows
        }
    }

    /// The lower-right triangle — the light half of the Auto theme swatch.
    private struct DiagonalHalf: Shape {
        func path(in rect: CGRect) -> Path {
            var path = Path()
            path.move(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
            path.closeSubpath()
            return path
        }
    }

    /// Every user-facing literal in this file that is not already an enum's
    /// own `title`, in one block (PRD-20's seam).
    private enum Phrase {
        /// Nine's name, never translated — see `ShareCardMetrics.wordmark`.
        static let wordmark = "Nine"

        /// The value of a plain on/off row. Unused since the boolean rows
        /// became switches — a switch *is* the on/off vocabulary, and a switch
        /// with the word "On" printed beside it says the same thing twice —
        /// and kept because `AmbientSlot.none` still spells its off state with
        /// the same key, which is the agreement this pair exists to hold.
        static func onOff(_ isOn: Bool) -> String {
            Strings.string(isOn ? "prefs.toggle.on" : "prefs.toggle.off")
        }
    }

    // MARK: - Metrics

    /// One left edge, one row height, one icon column.
    ///
    /// **Unscaled point values below the tvOS fence.** `CouchScale.chrome` is
    /// 0.55 on iOS, so `44 * CouchScale.chrome` is a 24.2pt hit target and
    /// `52 * CouchScale.chrome` is a 28.6pt row — a floor that scales is not a
    /// floor (see `Hit.min`). The couch gets its own numbers instead.
    enum Metrics {
        #if os(tvOS)
        static let gutter: CGFloat = 28
        static let iconColumn: CGFloat = 56
        static let iconTile: CGFloat = 52
        static let iconGap: CGFloat = 24
        static let iconSize: CGFloat = 30
        static let rowHeight: CGFloat = 84
        static let sectionTop: CGFloat = 44
        static let headerGap: CGFloat = 10
        static let cardPadding: CGFloat = 20
        #elseif os(macOS)
        static let gutter: CGFloat = Space.l
        static let iconColumn: CGFloat = Space.xxl
        static let iconTile: CGFloat = Space.xxl
        static let iconGap: CGFloat = Space.m
        static let iconSize: CGFloat = 15
        static let rowHeight: CGFloat = 52
        static let sectionTop: CGFloat = 26
        static let headerGap: CGFloat = 6
        static let cardPadding: CGFloat = Space.m
        #else
        /// 16 — the padding *inside* the group card: where a row's icon tile
        /// starts, where the legend's symbol column starts. Distinct from
        /// `margin`, which is the card's own edge — the two were one number and
        /// the sheet had three competing left rules because of it.
        static let gutter: CGFloat = Space.l
        /// 28 — the icon column. Unchanged, because `labelColumn` is derived
        /// from it and every row title in the sheet sits on that vertical.
        static let iconColumn: CGFloat = Space.xxl
        /// 28 — the icon *tile*, filling its column exactly. Equal for every
        /// row, which is the entire point: the tile is what the eye aligns and
        /// weighs, so a thin outline glyph and a solid filled one stop reading
        /// as two different weights.
        static let iconTile: CGFloat = Space.xxl
        static let iconGap: CGFloat = Space.m
        /// 16, down from 18. The glyph is inside a 28pt tile now rather than
        /// standing alone in a 28pt column, and at 18 it filled the tile corner
        /// to corner — a symbol in a container needs a margin or the container
        /// reads as a box drawn around it rather than as the thing it sits on.
        static let iconSize: CGFloat = 16
        /// 52 — above the 44pt floor with room for a two-line title at large
        /// Dynamic Type, and the same for every row so the pitch stops
        /// jittering with the glyphs.
        static let rowHeight: CGFloat = 52
        /// 24, down from 30. Five groups plus a legend plus a hint is a tall
        /// stack for a 0.72 detent, and the shipped frame ended on a section
        /// header with the rows it labelled below the fold. Six points per
        /// boundary is 30pt of content pulled up, and the ratio to `headerGap`
        /// is still 4:1 — the number this pair was chosen for.
        static let sectionTop: CGFloat = 24
        /// 6 — deliberately off the 4pt grid. This is the optical gap that
        /// binds a header to the rows it labels; at 8 the ratio to
        /// `sectionTop` stops reading as 1:4.
        static let headerGap: CGFloat = 6
        static let cardPadding: CGFloat = Space.m
        #endif

        /// **The one left edge the title, the headers and the cards share.**
        ///
        /// Zero, and it is a measured zero rather than a shrug: `cardShape` is
        /// `Radius.control` because `Radius.inner(38, inset: 22)` is 16, and
        /// that arithmetic only holds while the card sits exactly 22pt inside
        /// the 38pt sheet — which is `GlassSheet`'s own content padding and
        /// nothing more. Insetting the cards by a further margin would make
        /// their corners non-concentric with the sheet's; moving the title in to
        /// meet them costs nothing and fixes the finding. Named rather than
        /// omitted so tvOS and the Mac can differ, and so the next reader can
        /// see that all three call sites are answering one question.
        static let margin: CGFloat = 0

        /// The second hard vertical: where every row title starts. Measured from
        /// the **card's** leading edge, not the sheet's — its one consumer is
        /// `separator`, which is drawn inside the card and therefore already
        /// past `margin`.
        static var labelColumn: CGFloat { gutter + iconColumn + iconGap }

        /// The icon tile's wash and its edge. Low on purpose — see `RowLabel`:
        /// this is glass, not an opaque list, and a column of saturated chips
        /// over a translucent card is a stripe of paint.
        static let iconTileTone: Double = 0.18
        static let iconTileRimTone: Double = 0.34
        static let iconTileRim: CGFloat = 0.5

        /// One device pixel at 3x. A 1pt rule between two 52pt rows is a line;
        /// this is a seam.
        static let separator: CGFloat = 1.0 / 3.0
        static let separatorTone: Double = 0.12

        /// Values sit just under the title's weight without leaving AA:
        /// `.primary` at 82% measures about 7:1 on Paper, where the shipped
        /// `.secondary` caption measured 4.35.
        static let valueTone: Double = 0.82
        /// Headers sit under the values, and still measure about 5.5:1.
        static let headerTone: Double = 0.62
        static let headerTracking: CGFloat = 0.5
        /// The dismissal hint is the only genuinely incidental line here.
        static let hintTone: Double = 0.55

        /// **`fade` must stay below `scrollMargin`.** The margin is empty scroll
        /// held at each end; the fade is the dissolve drawn over it. At 24
        /// against 22 the gradient reached two points past the slack and into
        /// the first and last real rows, so at rest the sheet ghosted its own
        /// content — half of the round-2 blocker about a header stranded over
        /// dead sheet. Twenty leaves two points of margin the fade never
        /// touches.
        static let scrollMargin: CGFloat = 22
        static let fade: CGFloat = 20
    }

    /// One selection grammar for all three swatch rows — themes, accents and
    /// (in `AppIcons.swift`) Home Screen icons.
    ///
    /// The shipped rule was `lineWidth: choice == selected ? 3 * CouchScale.chrome : 1`,
    /// which drew the *selected* ring at 1.65pt and the unselected hairline at
    /// a raw 1pt: three device pixels for "not chosen" against five for
    /// "chosen", so selection was barely heavier than its absence. The ring is
    /// now five times the hairline, and it is drawn on an outer circle so it
    /// never crops the colour it is pointing at.
    enum Swatch {
        /// The coloured part. `Hit.min` minus a 5pt ring gap on each side.
        static let art: CGFloat = Hit.min - 10
        /// The corner of the art tile — a swatch is a chip.
        static let artRadius: CGFloat = Radius.chip
        /// Concentric with the art: the ring sits 5pt outside it, so its radius
        /// is 5pt larger (`Radius.inner` run in the other direction).
        static let ringRadius: CGFloat = Radius.chip + 5
        static let hairline: CGFloat = 0.5
        static let hairlineTone: Double = 0.18
        static let selected: CGFloat = 2.5
        #if os(tvOS)
        static let gap: CGFloat = 14
        #else
        static let gap: CGFloat = 10
        #endif
    }
}
