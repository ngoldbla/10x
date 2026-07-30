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

    // MARK: The column's own arithmetic (unchanged from `TouchUI`)

    /// Glass plane padding around the Canvas.
    public static let boardInset = 12.0
    /// Vertical reserve for the horizontal control bar in column mode.
    public static let controlBarReserve = 76.0
    /// `TouchUI`'s `.padding(.horizontal, 8)`, both sides.
    public static let columnHorizontalPadding = 16.0
    /// The floor `TouchUI` has always clamped to.
    public static let minimumBoardSide = 200.0

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
    /// current device is an iPad Pro 12.9" in portrait at **984pt**, and the
    /// largest table board is a 13" in landscape at **850pt**. The cap exists
    /// for the external display, where the column clamp would otherwise draw a
    /// 1324pt grid on a 1440p panel — a board you read by moving your head.
    /// `theCapIsInertOnEveryShippingDevice` pins the claim that this constant
    /// changes nothing anyone currently owns.
    public static let maximumBoardSide = 1000.0

    /// The board's side in column mode, for a window of this size.
    ///
    /// Byte-for-byte `TouchUI`'s clamp, moved rather than rewritten, so that
    /// adopting this function cannot silently reshape the phone.
    public static func columnBoardSide(width: Double, height: Double) -> Double {
        let side = min(width - 2 * boardInset - columnHorizontalPadding,
                       height - controlBarReserve - 2 * boardInset - columnHorizontalPadding)
        return max(minimumBoardSide, side)
    }

    /// The board's side if the table were adopted — before any of the tests
    /// that decide whether it should be.
    public static func tableBoardSide(width: Double, height: Double) -> Double {
        let chrome = 2 * outerPadding + controlColumnWidth + railWidth
            + 2 * gutter + 2 * boardInset
        return min(width - chrome, height - 2 * outerPadding - 2 * boardInset)
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
