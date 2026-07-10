// Sudoku.swift — core grid representation and the static geometry tables
// every other engine file leans on. Pure Swift: Foundation + CouchCore only.
import Foundation
import CouchCore

/// A 9×9 sudoku grid. `cells` is row-major, 81 entries, `0` = empty,
/// `1...9` = digit. Value type, Sendable, Codable — safe to ship across
/// actors and to persist via `CouchJSON`.
public struct SudokuGrid: Sendable, Equatable, Hashable, Codable {
    public var cells: [Int]

    public init(cells: [Int]) {
        precondition(cells.count == 81, "SudokuGrid needs exactly 81 cells")
        self.cells = cells
    }

    /// An empty grid.
    public init() {
        self.cells = Array(repeating: 0, count: 81)
    }

    /// Parse an 81-character string; `0` or `.` mean empty. Whitespace and
    /// newlines are ignored. Returns nil for malformed input.
    public init?(string: String) {
        var parsed: [Int] = []
        parsed.reserveCapacity(81)
        for ch in string {
            if ch.isWhitespace { continue }
            if ch == "." || ch == "0" {
                parsed.append(0)
            } else if let d = ch.wholeNumberValue, (1...9).contains(d) {
                parsed.append(d)
            } else {
                return nil
            }
        }
        guard parsed.count == 81 else { return nil }
        self.cells = parsed
    }

    public subscript(_ index: Int) -> Int {
        get { cells[index] }
        set { cells[index] = newValue }
    }

    public subscript(row: Int, col: Int) -> Int {
        get { cells[row * 9 + col] }
        set { cells[row * 9 + col] = newValue }
    }

    public var isFull: Bool { !cells.contains(0) }

    public var emptyCount: Int { cells.count(where: { $0 == 0 }) }

    public var givenCount: Int { 81 - emptyCount }

    /// True when every row, column and box contains exactly the digits 1–9.
    public var isValidComplete: Bool {
        guard isFull else { return false }
        for unit in Sudoku.units {
            var seen: UInt16 = 0
            for cell in unit { seen |= UInt16(1) << UInt16(cells[cell]) }
            if seen != Sudoku.allDigitsMask { return false }
        }
        return true
    }

    /// True when no filled cell conflicts with a peer (empties allowed).
    public var isConsistent: Bool {
        for unit in Sudoku.units {
            var seen: UInt16 = 0
            for cell in unit where cells[cell] != 0 {
                let bit = UInt16(1) << UInt16(cells[cell])
                if seen & bit != 0 { return false }
                seen |= bit
            }
        }
        return true
    }

    /// 81-character serialization (`.` for empty) — handy for fixtures.
    public var asString: String {
        String(cells.map { $0 == 0 ? "." : Character(String($0)) })
    }
}

/// Static sudoku geometry: units (rows, columns, boxes) and peer tables.
public enum Sudoku {
    /// Bitmask with bits 1…9 set (bit 0 unused).
    public static let allDigitsMask: UInt16 = 0b11_1111_1110

    @inlinable public static func row(of cell: Int) -> Int { cell / 9 }
    @inlinable public static func col(of cell: Int) -> Int { cell % 9 }
    @inlinable public static func box(of cell: Int) -> Int { (cell / 27) * 3 + (cell % 9) / 3 }

    @inlinable public static func bit(_ digit: Int) -> UInt16 { UInt16(1) << UInt16(digit) }

    /// 27 units: indices 0–8 rows, 9–17 columns, 18–26 boxes. Each unit is
    /// 9 cell indices in reading order.
    public static let units: [[Int]] = {
        var result: [[Int]] = []
        for r in 0..<9 { result.append((0..<9).map { r * 9 + $0 }) }
        for c in 0..<9 { result.append((0..<9).map { $0 * 9 + c }) }
        for b in 0..<9 {
            let baseRow = (b / 3) * 3, baseCol = (b % 3) * 3
            var unit: [Int] = []
            for r in 0..<3 {
                for c in 0..<3 { unit.append((baseRow + r) * 9 + baseCol + c) }
            }
            result.append(unit)
        }
        return result
    }()

    /// For each cell, the indices (into `units`) of its row, column and box.
    public static let unitsOfCell: [[Int]] = (0..<81).map { cell in
        [row(of: cell), 9 + col(of: cell), 18 + box(of: cell)]
    }

    /// For each cell, its 20 distinct peers (same row/column/box, minus self).
    public static let peers: [[Int]] = (0..<81).map { cell in
        var set = Set<Int>()
        for u in unitsOfCell[cell] { set.formUnion(units[u]) }
        set.remove(cell)
        return set.sorted()
    }

    /// Digits present in a candidate bitmask, ascending.
    public static func digits(in mask: UInt16) -> [Int] {
        var result: [Int] = []
        var m = mask
        while m != 0 {
            result.append(m.trailingZeroBitCount)
            m &= m - 1
        }
        return result
    }
}
