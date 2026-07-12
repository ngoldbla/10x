// Darkroom engine — core puzzle types.
//
// Pure Swift: Foundation + CouchCore only. Everything here is Sendable and
// Codable so puzzles can cross actors and land in @CouchStored JSON as-is.
import Foundation
import CouchCore

/// Board side lengths offered by the daily roll.
public enum GridSize: Int, CaseIterable, Sendable, Codable, Hashable, Identifiable {
    case small = 10
    case medium = 15
    case large = 20

    public var id: Int { rawValue }

    public var label: String {
        switch self {
        case .small: return "Small"
        case .medium: return "Medium"
        case .large: return "Large"
        }
    }

    /// The difficulty the daily roll aims for in this slot (PRD §5.4).
    public var targetBand: DifficultyBand {
        switch self {
        case .small: return .easy
        case .medium: return .medium
        case .large: return .hard
        }
    }
}

/// Coarse difficulty derived from the verifier's pass count.
public enum DifficultyBand: Int, Sendable, Codable, CaseIterable, Comparable, Hashable {
    case easy = 0
    case medium = 1
    case hard = 2

    public static func < (lhs: DifficultyBand, rhs: DifficultyBand) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    /// Band for a solver pass count on an N×N board. Bigger boards naturally
    /// need more sweeps, so the ceilings scale with the side length.
    public static func band(passes: Int, size: Int) -> DifficultyBand {
        let easyCeiling = max(2, size / 5)         // 10→2, 15→3, 20→4
        if passes <= easyCeiling { return .easy }
        if passes <= easyCeiling * 2 { return .medium }
        return .hard
    }
}

/// A compiled, verified nonogram. Invariant by construction: `solution` is
/// provably reachable by single-line logic (the compiler rejects anything
/// else), so a `Puzzle` value is always human-solvable.
public struct Puzzle: Sendable, Codable, Equatable, Identifiable {
    /// Stable identity: `photoID|size|dateSeed`.
    public let id: String
    public let photoID: String
    /// Side length N of the square board.
    public let size: Int
    /// The daily seed this puzzle was compiled under (yyyymmdd).
    public let dateSeed: UInt64
    /// Row-major N×N binary solution. `true` = filled.
    public let solution: [Bool]
    /// Row-major N×N developed colors — the actual photo cell colors the
    /// board paints as the player fills (PRD §4.2).
    public let colors: [RGB]
    /// Clue runs per row, top to bottom. Empty array = blank row.
    public let rowClues: [[Int]]
    /// Clue runs per column, left to right. Empty array = blank column.
    public let colClues: [[Int]]
    /// Verifier pass count — the difficulty score (PRD §5.4).
    public let difficulty: Int

    public init(
        photoID: String,
        size: Int,
        dateSeed: UInt64,
        solution: [Bool],
        colors: [RGB],
        difficulty: Int
    ) {
        precondition(size > 0 && solution.count == size * size, "solution must be size²")
        precondition(colors.count == size * size, "colors must be size²")
        self.id = "\(photoID)|\(size)|\(dateSeed)"
        self.photoID = photoID
        self.size = size
        self.dateSeed = dateSeed
        self.solution = solution
        self.colors = colors
        var rows = [[Int]]()
        var cols = [[Int]]()
        rows.reserveCapacity(size)
        cols.reserveCapacity(size)
        for y in 0..<size {
            rows.append(Puzzle.clues(for: (0..<size).map { solution[y * size + $0] }))
        }
        for x in 0..<size {
            cols.append(Puzzle.clues(for: (0..<size).map { solution[$0 * size + x] }))
        }
        self.rowClues = rows
        self.colClues = cols
        self.difficulty = difficulty
    }

    /// Run-length clue extraction for one line. Blank line ⇒ `[]`.
    public static func clues(for line: [Bool]) -> [Int] {
        var out = [Int]()
        var run = 0
        for filled in line {
            if filled {
                run += 1
            } else if run > 0 {
                out.append(run)
                run = 0
            }
        }
        if run > 0 { out.append(run) }
        return out
    }

    @inlinable
    public func isFilled(x: Int, y: Int) -> Bool { solution[y * size + x] }

    @inlinable
    public func color(x: Int, y: Int) -> RGB { colors[y * size + x] }

    public var filledCount: Int { solution.lazy.filter { $0 }.count }

    public var band: DifficultyBand { DifficultyBand.band(passes: difficulty, size: size) }
}
