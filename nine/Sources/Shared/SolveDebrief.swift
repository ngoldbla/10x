// SolveDebrief.swift — everything the debrief says, with nothing that knows how
// to draw it (PRD-26 §2.2).
//
// `SolveCardFacts`'s header made the argument and this is the second instance
// of it: the words a player reads are provable on Linux CI beside `BoardSpeech`,
// and the view that shows them becomes layout with no branching left to get
// wrong. The two types are siblings on purpose — the still card and the debrief
// caption the same solve, and splitting the sentences out is what stops them
// drifting apart.
//
// **The honesty rule this type exists to enforce.** Fastest region and longest
// circled are functions of `LoggedMove.at` and nothing else. On an untimed log —
// every board solved before PRD-26, and every board that reached this device
// over CloudKit with its log stripped by `SyncedEntry` — they are not
// computable, so they are `nil` and the card is simply shorter. It does not
// apologise for them or explain them. A comet replayed at a uniform cadence is
// still a true drawing of the path; "fastest region: box 4" derived from that
// same uniform cadence is a fabricated fact on a card the player will believe.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

public struct SolveDebrief: Equatable, Sendable {

    /// Digits committed over the whole solve, corrections included — the same
    /// count `NineGame.placementCount` reports, and not the same as filled
    /// cells.
    public let placements: Int
    /// Erasures and undos. Named for what they are and never scored: a solve
    /// with forty corrections is not a worse solve, it is a longer look.
    public let corrections: Int
    public let notes: Int

    /// "You found the X-Wing at move 31." Nil on a board solved entirely by
    /// singles, and **nothing takes its place** — an empty line saying "no
    /// techniques found" would be the app inventing a way to disappoint.
    public let headline: String?

    /// "Fastest region · Box 4", or nil on an untimed log.
    public let fastestRegion: String?
    /// "Longest circled · Row 3, column 5", or nil on an untimed log.
    public let longestCircled: String?

    /// Whether the two lines above could have existed at all. The UI does not
    /// need it — nil renders nothing either way — but a test does, so that
    /// "the lines are missing" and "the lines are missing *because* the log is
    /// untimed" cannot be confused for one another.
    public let isTimed: Bool

    /// Every line, in order, skipping the ones that are not there. The one
    /// place the card's order is decided.
    public var lines: [String] {
        [headline, fastestRegion, longestCircled].compactMap { $0 }
    }

    /// The counts, as one line. Always present: they are true for every log.
    public var countsLine: String {
        [Phrase.placements(placements), Phrase.corrections(corrections), Phrase.notes(notes)]
            .joined(separator: " · ")
    }

    public init(replay: SolveReplay, analysis: ReplayAnalysis) {
        let moves = replay.moves
        let timed = replay.isTimed
        isTimed = timed
        placements = moves.count(where: { $0.kind == .place })
        corrections = moves.count(where: { $0.kind == .erase || $0.kind == .undo })
        notes = moves.count(where: { $0.kind == .pencil })

        // "At move 31" counts *placements*, not log entries. A player who
        // pencilled forty candidates first did not make forty moves in the
        // sense they would count them, and a number they cannot recognise is
        // worse than no number.
        if let found = analysis.headline, let technique = found.technique {
            let ordinal = moves.prefix(found.moveIndex + 1).count(where: { $0.kind == .place })
            headline = Phrase.headline(technique: technique, move: ordinal)
        } else {
            headline = nil
        }

        guard timed else {
            fastestRegion = nil
            longestCircled = nil
            return
        }
        fastestRegion = SolveDebrief.fastestBox(in: moves).map(Phrase.fastest)
        longestCircled = SolveDebrief.longestCircledCell(in: moves).map(Phrase.longest)
    }

    // MARK: - The two timed facts

    /// The box the player placed digits in with the least deliberation.
    ///
    /// Measured as mean seconds *before* each placement — the gap from the
    /// previous move, which is the pause the player actually took — rather than
    /// the span from a box's first digit to its last. The span is the wrong
    /// measure and it is worth saying why: a box whose first digit fell in the
    /// opening minute and whose last fell at the end scores terribly under it
    /// while having taken almost no thought, because the clock kept running
    /// through eight other boxes.
    ///
    /// Needs three placements before it will name a box, so a box with one
    /// lucky digit cannot win.
    static let regionMinimumPlacements = 3

    static func fastestBox(in moves: [LoggedMove]) -> Int? {
        var total = [Double](repeating: 0, count: 9)
        var counts = [Int](repeating: 0, count: 9)
        var previous: TimeInterval = 0
        for move in moves {
            guard let at = move.at else { continue }
            defer { previous = at }
            guard move.kind == .place, (0..<81).contains(move.cell) else { continue }
            let box = Sudoku.box(of: move.cell)
            guard (0..<9).contains(box) else { continue }
            total[box] += max(0, at - previous)
            counts[box] += 1
        }
        return (0..<9)
            .filter { counts[$0] >= regionMinimumPlacements }
            .min { total[$0] / Double(counts[$0]) < total[$1] / Double(counts[$1]) }
    }

    /// The cell the player came back to for longest: the gap between first
    /// touching it — a note, an erasure, a digit that did not stick — and the
    /// placement that finally resolved it.
    ///
    /// A cell filled the first time it was touched has a gap of zero and can
    /// never win, which is the behaviour that makes this a *circled* cell
    /// rather than just a late one.
    static func longestCircledCell(in moves: [LoggedMove]) -> Int? {
        var firstTouch: [Int: TimeInterval] = [:]
        var best: (cell: Int, gap: TimeInterval)?
        for move in moves {
            guard let at = move.at, (0..<81).contains(move.cell) else { continue }
            let first = firstTouch[move.cell] ?? at
            if firstTouch[move.cell] == nil { firstTouch[move.cell] = at }
            guard move.kind == .place else { continue }
            let gap = at - first
            if gap > (best?.gap ?? 0) { best = (move.cell, gap) }
        }
        return best?.cell
    }

    /// The debrief's words, through the one seam (PRD-20). Nothing above holds
    /// an English literal, so the nine languages get this for free the same way
    /// the share card did.
    private enum Phrase {
        static func placements(_ count: Int) -> String {
            Phrasebook.current.string("debrief.placements", .int(count))
        }
        static func corrections(_ count: Int) -> String {
            Phrasebook.current.string("debrief.corrections", .int(count))
        }
        static func notes(_ count: Int) -> String {
            Phrasebook.current.string("debrief.notes", .int(count))
        }
        /// Keyed off the frozen raw value, for `BoardSpeech.Phrase.techniqueName`'s
        /// reason: the Engine stopped naming things, and a `switch` here would
        /// be a second list.
        static func headline(technique: Technique, move: Int) -> String {
            Phrasebook.current.string(
                "debrief.headline",
                .text(Phrasebook.current.string("technique.\(technique.rawValue).name")),
                .int(move)
            )
        }
        static func fastest(_ box: Int) -> String {
            Phrasebook.current.string("debrief.fastest", .text(BoardSpeech.boxGroupLabel(box)))
        }
        static func longest(_ cell: Int) -> String {
            Phrasebook.current.string("debrief.longest", .text(BoardSpeech.cellLabel(cell)))
        }
    }
}
