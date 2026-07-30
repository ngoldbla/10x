// The composition decision, pinned against real window sizes (PRD-31).
//
// The point of testing this on Linux rather than by opening the app is
// coverage: "the rail never costs you board" is a claim about every window the
// app can be handed, and the two an engineer happens to open are exactly the
// two where it is easiest to be accidentally right. Every size below is a real
// one — a shipping iPad in both orientations, an iPhone on its side, the Stage
// Manager tiles a player can actually drag to, and a 1080p external display.
import XCTest
@testable import NineShared

final class DraftingTableTests: XCTestCase {

    // MARK: Devices, in points, portrait-first

    private static let iPhone17Pro = (w: 402.0, h: 874.0)
    private static let iPhoneSE = (w: 375.0, h: 667.0)
    private static let iPadMini = (w: 744.0, h: 1133.0)
    private static let iPad11 = (w: 834.0, h: 1194.0)
    private static let iPad109 = (w: 820.0, h: 1180.0)
    private static let iPadPro13 = (w: 1024.0, h: 1366.0)

    private func isTable(_ size: (w: Double, h: Double)) -> Bool {
        BoardCompositionRules.resolve(width: size.w, height: size.h).table != nil
    }

    private func flipped(_ size: (w: Double, h: Double)) -> (w: Double, h: Double) {
        (w: size.h, h: size.w)
    }

    // MARK: The two ends of the decision

    /// No phone is ever a drafting table, in either orientation. An iPhone on
    /// its side is the size most likely to be mistaken for "wide enough" by a
    /// rule that only reads width — 874pt of it — and it is exactly the case
    /// where a 360pt rail would leave a board smaller than the phone draws
    /// upright.
    func testNoPhoneIsEverADraftingTable() {
        for phone in [Self.iPhone17Pro, Self.iPhoneSE] {
            XCTAssertFalse(isTable(phone), "portrait \(phone)")
            XCTAssertFalse(isTable(flipped(phone)), "landscape \(phone)")
        }
    }

    /// Every shipping iPad in landscape is a drafting table, and no iPad in
    /// portrait is. Portrait is the case the governing rule has to get right on
    /// its own: an iPad Pro is 1024pt wide upright, which any width threshold
    /// generous enough to admit an 11" in landscape would also admit — and the
    /// board would fall from 984pt to 568pt to make room for a rail.
    func testEveryIPadIsATableInLandscapeAndNeverInPortrait() {
        for pad in [Self.iPadMini, Self.iPad109, Self.iPad11, Self.iPadPro13] {
            XCTAssertTrue(isTable(flipped(pad)), "landscape \(pad)")
            XCTAssertFalse(isTable(pad), "portrait \(pad)")
        }
    }

    // MARK: The governing rule

    /// The rule the whole decision exists to enforce, checked against a swept
    /// grid rather than against the handful of sizes above: wherever the table
    /// is adopted, the board it draws is within the named 8% skirt of what the
    /// column would have drawn. There is no window where accepting the rail
    /// quietly costs a third of the grid.
    func testTheRailNeverMeaningfullyCostsBoard() {
        for width in stride(from: 320.0, through: 2000.0, by: 10.0) {
            for height in stride(from: 320.0, through: 1440.0, by: 10.0) {
                let resolved = BoardCompositionRules.resolve(width: width, height: height)
                guard let table = resolved.table else { continue }
                let column = min(BoardCompositionRules.columnBoardSide(width: width, height: height),
                                 BoardCompositionRules.maximumBoardSide)
                XCTAssertGreaterThanOrEqual(
                    table.boardSide,
                    column * BoardCompositionRules.boardConcession - 0.001,
                    "table board \(table.boardSide) vs column \(column) at \(width)×\(height)"
                )
                XCTAssertGreaterThanOrEqual(table.boardSide, BoardCompositionRules.tableBoardFloor)
            }
        }
    }

    /// The three columns and their gutters always fit inside the window with
    /// the padding they asked for. A composition that overflows its own window
    /// clips the rail off the trailing edge, which looks like a rendering bug
    /// and is arithmetic.
    func testTheTableAlwaysFitsTheWindowItWasMeasuredFor() {
        for width in stride(from: 600.0, through: 2000.0, by: 7.0) {
            for height in stride(from: 400.0, through: 1440.0, by: 7.0) {
                guard let table = BoardCompositionRules
                    .resolve(width: width, height: height).table else { continue }
                let used = 2 * table.outerPadding + table.controlColumnWidth
                    + 2 * table.gutter + table.railWidth
                    + table.boardSide + 2 * BoardCompositionRules.boardInset
                XCTAssertLessThanOrEqual(used, width + 0.001, "at \(width)×\(height)")
                let usedVertically = table.boardSide + 2 * BoardCompositionRules.boardInset
                    + 2 * table.outerPadding
                XCTAssertLessThanOrEqual(usedVertically, height + 0.001, "at \(width)×\(height)")
            }
        }
    }

    // MARK: Stage Manager

    /// Stage Manager tiles, which are the sizes a size class gets wrong. All
    /// four report `.regular` horizontally on an iPad Pro; only the two that
    /// can actually seat a rail beside a real board get one.
    func testStageManagerTilesAreDecidedByRoomAndNotByIdiom() {
        XCTAssertFalse(isTable((w: 800.0, h: 600.0)))
        XCTAssertFalse(isTable((w: 1000.0, h: 700.0)))
        XCTAssertTrue(isTable((w: 1180.0, h: 800.0)))
        XCTAssertTrue(isTable((w: 1366.0, h: 900.0)))
    }

    /// Dragging a window narrower crosses back into the column exactly once,
    /// and never oscillates. A composition that flickered between two layouts
    /// as the grabber moved would be the worst possible Stage Manager bug, and
    /// it is the one a rule built from two independent thresholds invites.
    func testShrinkingAWindowCrossesOnceAndStaysCrossed() {
        var sawTable = false
        var sawColumnAfterTable = false
        for width in stride(from: 1600.0, through: 600.0, by: -1.0) {
            let table = isTable((w: width, h: 900.0))
            if table {
                XCTAssertFalse(sawColumnAfterTable,
                               "composition came back at width \(width)")
                sawTable = true
            } else if sawTable {
                sawColumnAfterTable = true
            }
        }
        XCTAssertTrue(sawTable)
        XCTAssertTrue(sawColumnAfterTable)
    }

    // MARK: The cap

    /// The board cap is for the external display and nothing else. If this
    /// fails, the cap has started reshaping a device someone owns — which is a
    /// change to the phone and the iPad, not to the projector.
    func testTheCapIsInertOnEveryShippingDevice() {
        let devices = [Self.iPhone17Pro, Self.iPhoneSE, Self.iPadMini,
                       Self.iPad109, Self.iPad11, Self.iPadPro13]
        for device in devices {
            for size in [device, flipped(device)] {
                let uncapped = max(
                    BoardCompositionRules.columnBoardSide(width: size.w, height: size.h),
                    BoardCompositionRules.tableBoardSide(width: size.w, height: size.h)
                )
                XCTAssertLessThan(uncapped, BoardCompositionRules.maximumBoardSide,
                                  "cap would bite at \(size)")
            }
        }
    }

    /// …and it does bite on a 1080p external display, which is the case it was
    /// added for. Without it the column clamp draws a 964pt board and the table
    /// a 1024pt one; the numbers grow without limit as the panel does.
    func testTheCapBitesOnAnExternalDisplay() {
        let resolved = BoardCompositionRules.resolve(width: 2560, height: 1440)
        XCTAssertEqual(resolved.boardSide, BoardCompositionRules.maximumBoardSide)
    }

    // MARK: The column is untouched

    /// The column arithmetic moved out of `TouchUI` verbatim, so the phone
    /// cannot have been reshaped by this PRD. These are the numbers the shipped
    /// build draws, restated: `max(200, min(W − 40, H − 116))`.
    func testTheColumnClampIsTheOneTouchUIAlreadyShipped() {
        XCTAssertEqual(BoardCompositionRules.columnBoardSide(width: 402, height: 874),
                       362, accuracy: 0.001)
        XCTAssertEqual(BoardCompositionRules.columnBoardSide(width: 375, height: 667),
                       335, accuracy: 0.001)
        // The 200pt floor, from a window far too small for any board.
        XCTAssertEqual(BoardCompositionRules.columnBoardSide(width: 200, height: 200),
                       200, accuracy: 0.001)
    }
}
