// TipCoach.swift — the whole of Nine's in-game hinting, as a pure function
// (PRD-34 "The First Five Minutes").
//
// The PRD's requirement is a *budget*, not a mechanism: three tips for the
// lifetime of the app, at most one per session, each one shown once and then
// never again. A budget that lives in view code is a budget nobody can prove,
// so it lives here instead — no SwiftUI, no clocks, no globals, testable on
// Linux CI beside `BoardSpeech`.
//
// Three rules earned the shape below:
//
//   • **The ledger stores strings, not cases.** A tip minted by a later build
//     decodes into an older one as an unrecognised id — and still counts
//     against the cap, so a downgraded player is not suddenly re-taught. The
//     same reasoning as the library's element quarantine, three orders of
//     magnitude smaller.
//   • **Nothing here may leak the solution.** The undo tip is triggered by a
//     wrong digit standing on the board, which `NineGame` knows only because it
//     holds the proven solution. `visibleMistake` is therefore the caller's
//     assertion that the screen is *already* showing the mistake — with
//     `errorHighlight` off it is false, exactly like the error haptic and the
//     spoken "wrong" (PRD-19).
//   • **A tip is never the last word on a solved board.** The Afterglow owns
//     that moment; nothing else speaks over it.
import Foundation

/// The three things a first-week player misses, in the order they matter.
public enum NineTip: String, CaseIterable, Sendable {
    /// A wrong digit is on the board and undo has never been used.
    case undo
    /// Digits are going down and not one corner note has been made.
    case pencil
    /// The board is filling and the same-number highlight is undiscovered.
    case highlight

    /// The sentence, once, in the app's voice: what it does, not how clever
    /// the feature is. Never an instruction to go do it now.
    public var message: String {
        switch self {
        case .undo: return Phrase.undo
        case .pencil: return Phrase.pencil
        case .highlight: return Phrase.highlight
        }
    }

    /// The SF Symbol shown beside the sentence — the same glyph as the control
    /// the tip is about, so the eye can find the button from the chip.
    public var symbol: String {
        switch self {
        case .undo: return "arrow.uturn.backward"
        case .pencil: return "pencil"
        case .highlight: return "9.square"
        }
    }
}

/// Which tips have already been spent, for good. Persisted as its own
/// `CouchStored` blob (`nine.tips`) — never as a field on a library entry.
public struct TipLedger: Codable, Equatable, Sendable {
    /// The hard cap, for the lifetime of the install.
    public static let capacity = 3

    /// Raw ids rather than `NineTip`s: see the file header.
    public private(set) var shown: [String]

    public init(shown: [String] = []) {
        self.shown = shown
    }

    /// No budget left, whatever the ids happen to say.
    public var isSpent: Bool { shown.count >= Self.capacity }

    public func hasShown(_ tip: NineTip) -> Bool { shown.contains(tip.rawValue) }

    /// Idempotent: showing the same tip twice can never cost two of the three.
    public mutating func record(_ tip: NineTip) {
        guard !hasShown(tip) else { return }
        shown.append(tip.rawValue)
    }

    // `CouchStored` discards the entire blob when a decode throws, so this one
    // cannot: a malformed or future-shaped payload reads as "no tips shown yet"
    // rather than taking the file down with it.
    public init(from decoder: any Decoder) throws {
        guard let container = try? decoder.container(keyedBy: CodingKeys.self),
              let ids = try? container.decodeIfPresent([String].self, forKey: .shown) else {
            shown = []
            return
        }
        shown = ids
    }
}

/// Everything about the current board a tip decision may read. A snapshot,
/// passed in — so the decision is a function of its arguments and nothing else.
public struct TipMoment: Equatable, Sendable {
    /// Digits committed this board, corrections included (`placementCount`).
    public var placements: Int
    /// Undos taken on this board, ever (`undoCount`).
    public var undosTaken: Int
    /// Corner notes standing on the board (`pencilMarkCount`).
    public var pencilMarks: Int
    /// The pencil toggle has been used this session.
    public var pencilUsed: Bool
    /// The same-number highlight has been lit this session.
    public var highlightUsed: Bool
    /// …and it is switched on in prefs at all. Nine never advertises a
    /// feature the player has turned off.
    public var highlightAvailable: Bool
    /// A wrong digit is standing on the board **and the screen is showing it**.
    /// False whenever `errorHighlight` is off — see the file header.
    public var visibleMistake: Bool
    /// The board is finished; the Afterglow owns the screen.
    public var solved: Bool

    public init(
        placements: Int = 0,
        undosTaken: Int = 0,
        pencilMarks: Int = 0,
        pencilUsed: Bool = false,
        highlightUsed: Bool = false,
        highlightAvailable: Bool = true,
        visibleMistake: Bool = false,
        solved: Bool = false
    ) {
        self.placements = placements
        self.undosTaken = undosTaken
        self.pencilMarks = pencilMarks
        self.pencilUsed = pencilUsed
        self.highlightUsed = highlightUsed
        self.highlightAvailable = highlightAvailable
        self.visibleMistake = visibleMistake
        self.solved = solved
    }
}

/// The decision: which tip, if any, may be shown right now.
public enum TipCoach {
    /// Placements before the pencil is worth mentioning — long enough that a
    /// player who already pencils has done it, short enough to still help.
    public static let pencilAfter = 8
    /// Placements before the highlight is worth mentioning. Later than the
    /// pencil: hunting one digit across the grid is a mid-board move.
    public static let highlightAfter = 12

    /// Nil unless the ledger has room, the session is unspent, the tip has
    /// never been shown and its signal is live. `NineTip.allCases` order is the
    /// priority order — a standing mistake outranks a technique the player
    /// simply hasn't met yet.
    public static func next(
        for moment: TipMoment,
        ledger: TipLedger,
        shownThisSession: Bool
    ) -> NineTip? {
        guard !shownThisSession, !ledger.isSpent, !moment.solved else { return nil }
        return NineTip.allCases.first { tip in
            !ledger.hasShown(tip) && qualifies(tip, moment)
        }
    }

    private static func qualifies(_ tip: NineTip, _ moment: TipMoment) -> Bool {
        switch tip {
        case .undo:
            return moment.visibleMistake && moment.undosTaken == 0
        case .pencil:
            return !moment.pencilUsed && moment.pencilMarks == 0
                && moment.placements >= pencilAfter
        case .highlight:
            return moment.highlightAvailable && !moment.highlightUsed
                && moment.placements >= highlightAfter
        }
    }
}

/// Every user-facing string in this file, in one block (PRD-20's seam).
private enum Phrase {
    static let undo = "Undo takes the last digit back. Nothing here is ever stuck."
    static let pencil = "Tap the pencil, then flick — the rose leaves corner notes instead."
    static let highlight = "Tap any placed digit to light up every one of its kind."
}
