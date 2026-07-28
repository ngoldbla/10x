// WatchLink.swift — the wire between the iPhone and the wrist (PRD-6).
//
// # What crosses, and what deliberately does not
//
// `SharedDailyBoard` — the app↔widget file this borrows its discipline from —
// carries the whole `NineGame`, and its safety argument is written into its own
// header: "both sides only ever append moves to the same day's board, so a lost
// race costs a move, never corruption." That argument does **not** survive the
// move to a watch. The wrist has undo and erase, so a device can legitimately
// hold *fewer* filled cells than the one it is syncing with, and last-writer-
// wins would then quietly delete a player's phone progress rather than lose a
// move. PRD-6 §2.5 already ruled that in-progress boards do not hand off in v1;
// this file is why that ruling is right rather than merely convenient.
//
// So the link is deliberately asymmetric, and both halves are immutable facts:
//
//   • **down** — `WatchDailyHandoff`, today's composed `GeneratedPuzzle`. The
//     puzzle is a pure function of the day, so two devices can never disagree
//     about it and a lost or reordered handoff costs nothing.
//   • **up** — `WatchSolveReport`, the fact that a day was solved and how long
//     it took. Reusing `PendingSolve` verbatim, because the phone already knows
//     how to ingest exactly one of those idempotently
//     (`AppModel.ingestSharedDailyBoard`).
//
// What survives from the `SharedDailyBoard` pattern is the *discipline*: a
// monotone revision, a day guard, "strictly newer wins", and a persisted
// high-water mark on the reader (an in-memory one reset every launch and
// clobbered partials — see `SharedDailyBoardStore.knownRevision`).
//
// # Why the link exists at all
//
// The daily composes at `.steady` and the watch may not compose above
// `.gentle` (PROGRAM-2.0 "watch never generates above catalog-easy"), so this
// is not an optimisation — it is the only route today's board has to the wrist.
// `WatchComposePolicy` holds both halves of that sentence so the two can never
// drift apart silently; `theDailyIsAboveTheCeilingSoTheLinkIsLoadBearing` fails
// the moment they do.
//
// Pure Foundation + Engine, so the whole adoption rule and the whole wire are
// unit-tested in `NineShared` with no simulator, no pairing and no
// WatchConnectivity. The two `#if os(...)` session classes hold nothing but
// transport.
import Foundation
#if canImport(NineEngine)
import NineEngine
#endif

// MARK: - Down: today's daily

/// Today's daily, couriered to a watch that is not allowed to compose it.
public struct WatchDailyHandoff: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Which daily this is. Anything ≠ today is stale and never adopted.
    public var dayOrdinal: Int
    /// The composed board. Immutable and seed-derived, which is the whole
    /// reason last-writer-wins is safe here.
    public var puzzle: GeneratedPuzzle
    /// Monotonic; the higher revision wins on read.
    public var revision: Int
    public var updatedAt: Date

    public init(
        schemaVersion: Int = WatchDailyHandoff.currentSchemaVersion,
        dayOrdinal: Int,
        puzzle: GeneratedPuzzle,
        revision: Int,
        updatedAt: Date
    ) {
        self.schemaVersion = schemaVersion
        self.dayOrdinal = dayOrdinal
        self.puzzle = puzzle
        self.revision = revision
        self.updatedAt = updatedAt
    }

    /// The stale-day guard, same shape as `SharedDailyBoard.isCurrent(today:)`.
    public func isCurrent(today: Int) -> Bool { dayOrdinal == today }

    /// The whole adoption rule, in one place so the watch cannot spell it
    /// differently from the test: today's, and strictly newer than what we
    /// already took.
    public func supersedes(known: Int, today: Int) -> Bool {
        isCurrent(today: today) && revision > known
    }

    /// Does this payload's board actually belong to the day it claims?
    ///
    /// **A stamp check, not a proof, and that is on purpose.** Re-deriving the
    /// board would mean composing `.steady` on the watch, which is precisely
    /// what the compose ceiling forbids — the check would break the rule it
    /// exists to protect. `GeneratedPuzzle` already carries the seed and band
    /// it was generated from, so provenance costs nothing; the givens/solution
    /// agreement then catches a payload that was garbled rather than forged.
    public var matchesTheDayItClaims: Bool {
        guard puzzle.seed == DailySeed.seed(forDayOrdinal: dayOrdinal),
              puzzle.difficulty == WatchComposePolicy.dailyBand,
              puzzle.solution.isValidComplete
        else { return false }
        // Every given must be the solution's digit in that cell.
        return zip(puzzle.puzzle.cells, puzzle.solution.cells)
            .allSatisfy { given, solved in given == 0 || given == solved }
    }
}

// MARK: - Up: a solve made on the wrist

/// A daily finished on the watch. The watch has its own KVS streak, but
/// `nine.history` and Game Center are last-writer-wins blobs the phone owns,
/// so the fact travels and the phone records it — exactly once, guarded by
/// `StreakState.hasCompleted(day:)`, exactly as a widget solve is.
public struct WatchSolveReport: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    public var dayOrdinal: Int
    public var solve: PendingSolve

    public init(
        schemaVersion: Int = WatchSolveReport.currentSchemaVersion,
        dayOrdinal: Int,
        solve: PendingSolve
    ) {
        self.schemaVersion = schemaVersion
        self.dayOrdinal = dayOrdinal
        self.solve = solve
    }
}

// MARK: - What the watch may compose for itself

/// The one place the "never above catalog-easy" rule lives.
///
/// There is no fast-seed catalog in the repo yet (PRD-23 shipped its engine
/// with "catalogs/pantry" explicitly not done), so "catalog-easy" can only mean
/// the easiest band. Holding `dailyBand` here too is what makes the rule
/// checkable: the link is load-bearing precisely because these two constants
/// disagree, and a test says so.
public enum WatchComposePolicy {
    /// The hardest band the watch composes on its own.
    public static let ceiling: Difficulty = .gentle
    /// The band `AppModel.openToday()` composes the daily at.
    public static let dailyBand: Difficulty = .steady

    public static func mayComposeLocally(_ difficulty: Difficulty) -> Bool {
        difficulty == ceiling
    }
}

// MARK: - The transport format

/// Codable ⇄ the property-list dictionaries WatchConnectivity takes.
///
/// One `Data` under one key, and the two directions never share a key: a
/// delegate callback that receives one can then never decode it as the other.
/// WCSession *throws* on a non-plist value rather than warning, and it does so
/// only on a real paired device, so `theWireIsPlistSafe` is the only place that
/// contract can be checked at all.
public enum WatchLinkWire {
    public static let handoffKey = "nine.watch.handoff"
    public static let reportKey = "nine.watch.solve"
    /// The phone's acknowledgement, carrying the day ordinal it ingested.
    ///
    /// Without it the watch could only *hope* its solve landed. With it the
    /// watch keeps the report in its ledger — across being out of range, being
    /// killed, and being relaunched — and re-sends until the phone says it has
    /// the fact. Re-sending is free: the phone's ingest is guarded by
    /// `StreakState.hasCompleted(day:)`, which is idempotent per day.
    public static let acknowledgedSolveKey = "nine.watch.solveAck"

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    public static func encode(_ handoff: WatchDailyHandoff) -> [String: Any] {
        (try? encoder.encode(handoff)).map { [handoffKey: $0] } ?? [:]
    }

    public static func encode(_ report: WatchSolveReport) -> [String: Any] {
        (try? encoder.encode(report)).map { [reportKey: $0] } ?? [:]
    }

    public static func decodeHandoff(_ payload: [String: Any]) -> WatchDailyHandoff? {
        decode(WatchDailyHandoff.self, from: payload, key: handoffKey) {
            $0.schemaVersion <= WatchDailyHandoff.currentSchemaVersion
        }
    }

    public static func decodeReport(_ payload: [String: Any]) -> WatchSolveReport? {
        decode(WatchSolveReport.self, from: payload, key: reportKey) {
            $0.schemaVersion <= WatchSolveReport.currentSchemaVersion
        }
    }

    /// Never throws, and refuses a payload from a build that knows more than
    /// this one — `WidgetSnapshotStore.load`'s reject-newer rule, for the same
    /// reason: a half-understood board is worse than no board.
    private static func decode<T: Decodable>(
        _ type: T.Type,
        from payload: [String: Any],
        key: String,
        isReadable: (T) -> Bool
    ) -> T? {
        guard let data = payload[key] as? Data,
              let value = try? JSONDecoder().decode(type, from: data),
              isReadable(value)
        else { return nil }
        return value
    }
}
