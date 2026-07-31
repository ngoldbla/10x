// DraftingTable.swift — which composition the game screen wears, as a pure
// function of the window (PRD-31).
//
// Nine has never had an iPad layout. `Sources/` contains zero `sizeClass`, zero
// `UIDevice`, zero `userInterfaceIdiom`; the whole adaptation story was one
// `.frame(maxWidth: 560)` on the home shelf and a board clamp in `TouchUI`
// whose height term subtracts a control-bar reserve and whose width term does
// not — portrait-shaped reasoning, shipped to a device that runs landscape.
//
// **The input is a size, never a device, and that is the Stage Manager
// answer.** A size class would actively break here: a 1000×700 Stage Manager
// tile on an iPad Pro reports `.regular` horizontally while having less usable
// width than an iPhone 17 Pro Max has height, and an external display can hand
// us 1920×1080 from the same idiom that hands us 834×1194. Ask the window.
//
// Linux-clean on purpose, exactly like `RoseLens`: no SwiftUI, no CoreGraphics,
// no CGSize. Lane 1 tests the whole decision table on Linux without booting a
// simulator, which is the only way a claim like "the rail never costs you
// board" can be checked against thirty window sizes instead of the two someone
// happened to open.
import Foundation

/// How the game screen is laid out right now.
public enum BoardComposition: Equatable, Sendable {
    /// Today's phone stack: bands, board, a horizontal control bar, and a
    /// stats drawer you pull down. The associated value is the board's side.
    case column(boardSide: Double)
    /// PRD-31's drafting table: controls float in a column beside the board,
    /// the board is centre stage, and the stats drawer is a rail that is
    /// simply *there* — discoverability solved by geometry rather than by a
    /// hairline grabber that has to teach itself and then get out of the way.
    case table(DraftingTable)

    /// The board's side in either arm, for the callers that only want that.
    public var boardSide: Double {
        switch self {
        case .column(let side): return side
        case .table(let table): return table.boardSide
        }
    }

    public var table: DraftingTable? {
        if case .table(let table) = self { return table }
        return nil
    }
}

/// How the *shelf* composes, which is a different question from how the game
/// screen does — and answering both with one function is the defect two critics
/// independently reported as "the iPad canvas is a phone layout stretched".
///
/// The game screen asks *can a 360pt stats rail and a 60pt control column sit
/// beside a board that is still at least 520pt and no smaller than the phone
/// would have drawn it*. On an 834×1194 iPad in portrait the honest answer is
/// no, and `resolve` says so. The shelf's question is completely different —
/// *can two columns of cards stand side by side* — and a card column is happy at
/// 340pt. Portrait iPads answer yes to the second and no to the first, so a
/// shelf that asked `resolve` shipped one 560pt ribbon down the middle of an
/// 834pt canvas with 137pt of dead ground on each side.
///
/// The two decisions are still *related* — nothing may ever be a table without
/// also being a pair, and `theTableIsAlwaysAlsoAShelfPair` pins that — but they
/// are no longer the same decision.
public enum ShelfComposition: Equatable, Sendable {
    /// One centred column, clamped so a line of body copy never runs the width
    /// of an iPad. The associated value is that clamp.
    case column(maxWidth: Double)
    /// Two columns of cards, side by side.
    case pair(ShelfPair)

    public var pair: ShelfPair? {
        if case .pair(let pair) = self { return pair }
        return nil
    }

    /// The width the whole shelf occupies, column or pair — which is also the
    /// width the persistent top bar must clamp itself to, so the wordmark and
    /// the first card share one leading margin instead of the three competing
    /// alignment origins the audit measured in the top 300pt.
    /// Both arms measure edge to edge — the column's own gutters are *inside*
    /// its clamp, exactly as `TouchUI`'s shipped `.padding(20).frame(maxWidth:
    /// 560)` always was.
    public var contentWidth: Double {
        switch self {
        case .column(let maxWidth): return maxWidth
        case .pair(let pair): return pair.totalWidth
        }
    }
}

/// The measured two-column shelf. Points in the window's own space.
public struct ShelfPair: Equatable, Sendable {
    public let columnWidth: Double
    public let gutter: Double
    public let outerPadding: Double

    public init(columnWidth: Double, gutter: Double, outerPadding: Double) {
        self.columnWidth = columnWidth
        self.gutter = gutter
        self.outerPadding = outerPadding
    }

    public var totalWidth: Double { 2 * columnWidth + gutter + 2 * outerPadding }
}

/// The measured drafting table. Every number is points in the window's own
/// space; the App layer converts to `CGFloat` at the boundary.
public struct DraftingTable: Equatable, Sendable {
    public let boardSide: Double
    public let railWidth: Double
    public let controlColumnWidth: Double
    public let gutter: Double
    public let outerPadding: Double

    public init(
        boardSide: Double,
        railWidth: Double,
        controlColumnWidth: Double,
        gutter: Double,
        outerPadding: Double
    ) {
        self.boardSide = boardSide
        self.railWidth = railWidth
        self.controlColumnWidth = controlColumnWidth
        self.gutter = gutter
        self.outerPadding = outerPadding
    }
}

/// The decision, and the constants it is made of.
public enum BoardCompositionRules {

    // MARK: The column's own arithmetic

    /// Glass plane padding around the Canvas.
    ///
    /// **8 in round 3, and it was 12.** Two panels reported the board card as
    /// "a bezel": *"there is a ~16pt padding ring between the card's stroke and
    /// the grid's corner, which reads as a picture frame rather than one
    /// object"*. The ring is this constant, and every point of it is a point the
    /// grid does not get. Taking it to 8 widens the grid by 8pt on every window
    /// and — because the header capsule and the bottom cluster now reach 12pt
    /// *onto* the plane (`columnChromeOverlap`) — leaves exactly enough ring for
    /// a floating bar to cross the card's edge without ever touching a digit.
    public static let boardInset = 8.0
    /// `TouchUI`'s `.padding(.horizontal, 8)`, both sides. The plane is
    /// therefore the full safe-area width less 16, which is the brief's
    /// "full safe-area width minus 16pt" stated as arithmetic.
    public static let columnHorizontalPadding = 16.0
    /// The floor `TouchUI` has always clamped to.
    public static let minimumBoardSide = 200.0

    // MARK: The floating chrome (round 3)
    //
    // **The reserve was 200 and it was the wrong shape of number.** It bought
    // the board's height term a parking space for the header, the pad and the
    // toolbar — as if those three sat *beside* the board — and on every phone in
    // portrait the width term binds anyway, so the whole 200 was pure
    // subtraction from a dimension that never decided anything. Worse, it
    // enshrined the composition two blind panels rejected twice: chrome in
    // reserved bands, a board floating between them, and 120pt of dead ground
    // above and ~200 below.
    //
    // Round 3 docks the chrome to the two safe-area edges and lets it *overlap*
    // the board. So the reserve is no longer "everything outside the board", it
    // is only what the column still owes once the overlap is paid back, and the
    // digit pad is the surface that spends whatever is left over. That is why
    // the reserve below assumes the pad's **one-row minimum**: the pad is
    // elastic, so reserving for its largest form would shrink the board to buy
    // space the pad is going to give back.

    /// The docked header: `Rhythm.dock` (8) to the safe area plus a 44pt
    /// capsule.
    public static let columnHeaderBlock = 52.0
    /// The tool capsule: a 44pt row, `Space.s` above and below it inside the
    /// bar, and `Rhythm.dock` to the safe area.
    public static let columnToolbarBlock = 68.0
    /// The one gap inside the bottom cluster (`Rhythm.cluster`). The pad and the
    /// toolbar are one object and exactly one rung separates them.
    public static let columnClusterGap = 16.0
    /// How far the header capsule and the bottom cluster reach *onto* the
    /// board's glass plane.
    ///
    /// **12, and every point of it is measured.** The plane's own ring is
    /// `boardInset` = 8, so the first 8 points of overlap cross nothing but
    /// glass; the remaining 4 land on the first (or last) row's dead margin. A
    /// board digit is `BoardType.entry` — 0.66 of a cell — centred, so at the
    /// phone's ≈41pt cell the glyph box starts ~7pt below the cell's edge and
    /// its cap height a point or two below that. Nothing legible is ever under
    /// the bar, and the bar has the card's rim, the grid's outer rule and two
    /// cell fills behind it to bend. That is the whole point: a lens over a void
    /// draws nothing, which is the sentence both panels kept writing.
    public static let columnChromeOverlap = 12.0

    /// Everything the column spends outside the board and outside the pad —
    /// 52 + 68 + 16 − 2·12 = 112.
    public static let columnChromeFixed =
        columnHeaderBlock + columnToolbarBlock + columnClusterGap
        - 2 * columnChromeOverlap

    /// The height term's reserve: the fixed chrome plus the pad at its smallest.
    public static let columnChromeReserve = columnChromeFixed + padMinimumHeight(rows: 1)

    // MARK: The digit pad, which is where the surplus goes

    /// The shipped key height, and the floor a key may never go under.
    public static let padKeyFloor = 58.0
    /// Past this a key stops reading as a key. Round 2's number, kept.
    public static let padKeyCeiling = 92.0
    /// …and the same claim in the other axis. A 230pt-wide key on an iPad is
    /// not a keypad, it is a banner, so a row count that produces one is
    /// rejected in favour of a shallower one.
    public static let padKeyMaxWidth = 140.0
    /// `Space.m`, the tray's own padding, both sides.
    public static let padTrayPadding = 12.0
    /// `Space.xs`, between keys.
    public static let padKeyGap = 4.0
    /// The tray is narrower than the board plane by this much on each side, so
    /// the board's edges show past it and the overlap reads as one surface
    /// lying on another rather than as two slabs butted together.
    public static let padTrayInset = 8.0

    /// Nine keys in this many rows. 1 → nine across (the iPad's shape, and the
    /// one round 2 measured at 85×84); 2 → 5 + 4; 3 → the 3×3 block, which is
    /// also the rose's flick mapping and the board's own box, so the phone's
    /// keypad and its fast path finally teach the same geometry.
    public static func padColumns(rows: Int) -> Int {
        switch rows {
        case 1: return 9
        case 2: return 5
        default: return 3
        }
    }

    public static func padKeyWidth(planeWidth: Double, rows: Int) -> Double {
        let columns = Double(padColumns(rows: rows))
        let content = planeWidth - 2 * padTrayInset - 2 * padTrayPadding
        return (content - (columns - 1) * padKeyGap) / columns
    }

    /// The tray at this row count with every key on the floor.
    public static func padMinimumHeight(rows: Int) -> Double {
        Double(rows) * padKeyFloor + Double(rows - 1) * padKeyGap + 2 * padTrayPadding
    }

    /// How many rows the pad takes: the deepest one that both fits the budget
    /// and keeps its keys under `padKeyMaxWidth`.
    ///
    /// Deepest rather than shallowest, and that is the whole mechanism by which
    /// the dead band disappears. A phone hands the pad ~283pt because a square
    /// board cannot use the height a 9:19.5 canvas has spare; one row of keys
    /// would take 116 of it and leave 167 of background, which is four times
    /// `Rhythm.maxDeadBand`. Three rows take all 283 and leave nothing.
    public static func padRows(planeWidth: Double, budget: Double) -> Int {
        for rows in [3, 2] {
            guard budget >= padMinimumHeight(rows: rows) else { continue }
            guard padKeyWidth(planeWidth: planeWidth, rows: rows) <= padKeyMaxWidth else {
                continue
            }
            return rows
        }
        return 1
    }

    public static func padKeyHeight(planeWidth: Double, budget: Double) -> Double {
        let rows = Double(padRows(planeWidth: planeWidth, budget: budget))
        let raw = (budget - 2 * padTrayPadding - (rows - 1) * padKeyGap) / rows
        return min(padKeyCeiling, max(padKeyFloor, raw))
    }

    /// The tray's resolved height — what the column actually gives up.
    public static func padHeight(planeWidth: Double, budget: Double) -> Double {
        let rows = Double(padRows(planeWidth: planeWidth, budget: budget))
        return rows * padKeyHeight(planeWidth: planeWidth, budget: budget)
            + (rows - 1) * padKeyGap + 2 * padTrayPadding
    }

    /// What is left for the pad once the board and the docked chrome have taken
    /// theirs. Never less than a one-row tray: on a window too short for even
    /// that the column overflows, exactly as it always has, rather than drawing
    /// a keypad with no keys in it.
    public static func columnPadBudget(height: Double, plane: Double) -> Double {
        max(padMinimumHeight(rows: 1), height - plane - columnChromeFixed)
    }

    // MARK: The table's constants

    /// Wide enough for `DigitRingRow`'s nine 30pt rings and their eight 6pt
    /// gaps — 318pt of content — plus the panel's own padding. The rail is the
    /// stats drawer's content at its natural width, not a squeezed copy of it:
    /// a ring row that has to compress stops being nine countable things,
    /// which is the entire reason `SegmentedRing` draws nine arcs and not one.
    public static let railWidth = 360.0
    /// One 44pt control button plus 8pt each side.
    public static let controlColumnWidth = 60.0
    /// Between the three columns.
    public static let gutter = 20.0
    /// Outside all three.
    public static let outerPadding = 16.0

    /// A board smaller than this is not a drafting table, it is a phone layout
    /// with furniture bolted to it. Below the floor the column always wins,
    /// whatever the width says.
    public static let tableBoardFloor = 520.0

    /// How much board the rail is allowed to cost.
    ///
    /// The governing rule is *the rail never costs you board* — adopt the table
    /// only when the board is at least as big as the column would have drawn
    /// it. Held literally, that rule is correct and unusable: on an 11" iPad in
    /// landscape the two sides land within single-digit points of each other,
    /// so a 2pt change of chrome anywhere would flip the entire composition.
    /// The 8% skirt is the width of that knife edge, named rather than
    /// implied — and it is the *only* softening; the floor above and the
    /// comparison itself are absolute.
    public static let boardConcession = 0.92

    /// Both compositions stop growing the board here.
    ///
    /// Nothing that ships today reaches it: the largest column board on any
    /// current device is an iPad Pro 12.9" in portrait at **992pt** (984 before
    /// round 3 thinned the board's padding ring), and the largest table board is
    /// a 13" in landscape at **858pt**. The cap exists
    /// for the external display, where the column clamp would otherwise draw a
    /// 1324pt grid on a 1440p panel — a board you read by moving your head.
    /// `theCapIsInertOnEveryShippingDevice` pins the claim that this constant
    /// changes nothing anyone currently owns.
    public static let maximumBoardSide = 1000.0

    /// The board's side in column mode, for a window of this size.
    ///
    /// **The height term no longer subtracts `columnHorizontalPadding`**, and
    /// that was not a rounding error, it was a category one: the column's
    /// left-and-right gutters were being charged against its *height*. Every
    /// board in the app was 16pt smaller than it needed to be, on both arms, for
    /// as long as this function has existed.
    public static func columnBoardSide(width: Double, height: Double) -> Double {
        let side = min(width - columnHorizontalPadding - 2 * boardInset,
                       height - columnChromeReserve - 2 * boardInset)
        return max(minimumBoardSide, side)
    }

    /// The board's side if the table were adopted — before any of the tests
    /// that decide whether it should be.
    public static func tableBoardSide(width: Double, height: Double) -> Double {
        let chrome = 2 * outerPadding + controlColumnWidth + railWidth
            + 2 * gutter + 2 * boardInset
        return min(width - chrome, height - 2 * outerPadding - 2 * boardInset)
    }

    // MARK: The shelf's own constants

    /// The single column's clamp — `TouchUI`'s shipped `.frame(maxWidth: 560)`,
    /// moved rather than retuned so adopting this function cannot reshape the
    /// phone.
    public static let shelfColumnWidth = 560.0
    /// Between the two columns.
    public static let shelfGutter = 20.0
    /// Outside them. Also the single column's own gutter, so a window that
    /// crosses the threshold does not shift its content sideways by 4pt.
    public static let shelfOuterPadding = 24.0
    /// Narrower than this and a card column stops holding a title, a 64pt
    /// mini-board and a two-line blurb without truncating — which is the same
    /// arithmetic that keeps the free-play row at three across on a phone and
    /// not four.
    public static let shelfMinimumColumn = 340.0
    /// A pair also needs somewhere to *scroll*. Without this term an iPhone
    /// 17 Pro Max on its side (956×440) reads as wide enough for two columns
    /// and gets a shelf two cards tall and eleven screens long.
    ///
    /// **560, not 600, and the difference is an invariant.** A drafting table
    /// needs `tableBoardFloor + 2·outerPadding + 2·boardInset` = 568pt of
    /// height (576 until round 3 took `boardInset` to 8), so at 600 there is a
    /// 568…600 band where the game screen is a
    /// table and the shelf is a single column — the two screens disagreeing
    /// about the same window, which is the one thing splitting the decision
    /// must not buy. `theTableIsAlwaysAlsoAShelfPair` pins it.
    public static let shelfMinimumHeight = 560.0
    /// Both columns stop growing here. Two 506pt columns is already wider than
    /// the 560pt a single column was ever allowed, and past that the cards stop
    /// being cards and become bands.
    public static let shelfMaximumWidth = 1080.0

    /// How the shelf composes for a window of this size.
    public static func resolveShelf(width: Double, height: Double) -> ShelfComposition {
        let usable = min(width, shelfMaximumWidth) - 2 * shelfOuterPadding - shelfGutter
        let column = min(shelfColumnWidth, usable / 2)
        guard height >= shelfMinimumHeight, column >= shelfMinimumColumn else {
            return .column(maxWidth: shelfColumnWidth)
        }
        return .pair(ShelfPair(columnWidth: column,
                               gutter: shelfGutter,
                               outerPadding: shelfOuterPadding))
    }

    /// The composition for a window of this size.
    public static func resolve(width: Double, height: Double) -> BoardComposition {
        let column = columnBoardSide(width: width, height: height)
        let table = tableBoardSide(width: width, height: height)
        guard table >= tableBoardFloor, table >= column * boardConcession else {
            return .column(boardSide: min(column, maximumBoardSide))
        }
        return .table(DraftingTable(
            boardSide: min(table, maximumBoardSide),
            railWidth: railWidth,
            controlColumnWidth: controlColumnWidth,
            gutter: gutter,
            outerPadding: outerPadding
        ))
    }
}
