// WidgetSnapshot.swift — the one-way bridge from the app to the widget
// extension (PRD-3 §2). The app writes this small versioned JSON into the
// app-group container; the widget only ever reads it. Raw facts, not display
// values, so the timeline provider can re-derive state at any entry date —
// a midnight rollover renders correctly without an app launch.
//
// This file compiles into BOTH the app target and the widget extension (and
// as the `NineShared` SwiftPM module for tests). It must stay pure
// Foundation: no CouchKit, no Engine. The ~10 lines of day math are
// deliberately duplicated from `DailySeed.dayOrdinal` / `StreakState.
// displayedStreak` — a unit test cross-checks them against the originals.
import Foundation

/// Everything a glanceable widget needs to render Nine's daily state.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Day ordinal of the in-progress or solved daily; nil = never played.
    public var dailyDayOrdinal: Int?
    /// Fill fraction of that daily; nil = not started.
    public var dailyFillFraction: Double?
    /// Solve time for the last completed daily, when known.
    public var dailySolvedSeconds: TimeInterval?
    public var streakCurrent: Int
    public var streakBest: Int
    /// Day ordinal of the last completed daily (streak bookkeeping).
    public var lastCompletedDay: Int?
    public var totalPoints: Int
    public var generatedAt: Date

    public init(
        schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
        dailyDayOrdinal: Int? = nil,
        dailyFillFraction: Double? = nil,
        dailySolvedSeconds: TimeInterval? = nil,
        streakCurrent: Int = 0,
        streakBest: Int = 0,
        lastCompletedDay: Int? = nil,
        totalPoints: Int = 0,
        generatedAt: Date = Date()
    ) {
        self.schemaVersion = schemaVersion
        self.dailyDayOrdinal = dailyDayOrdinal
        self.dailyFillFraction = dailyFillFraction
        self.dailySolvedSeconds = dailySolvedSeconds
        self.streakCurrent = streakCurrent
        self.streakBest = streakBest
        self.lastCompletedDay = lastCompletedDay
        self.totalPoints = totalPoints
        self.generatedAt = generatedAt
    }
}

// MARK: - Per-entry-date derivation (PRD-3 §2)

extension WidgetSnapshot {
    /// Today's daily is done.
    public func isSolved(today: Int) -> Bool { lastCompletedDay == today }

    /// Today's daily has moves on the board but isn't done.
    public func isInProgress(today: Int) -> Bool {
        !isSolved(today: today) && dailyDayOrdinal == today && dailyFillFraction != nil
    }

    /// The streak a widget shows at `today`: yesterday's chain is still
    /// alive, anything older has lapsed to 0. Mirrors
    /// `StreakState.displayedStreak` (cross-checked by unit test).
    public func displayedStreak(today: Int) -> Int {
        guard let last = lastCompletedDay, last >= today - 1 else { return 0 }
        return streakCurrent
    }

    /// Coarse digest gating `WidgetCenter` reloads: state bucket
    /// (notStarted / solved / fill decile), displayed streak, points. `place()`
    /// publishes on every move, so reloading only when this string changes
    /// keeps the widget reload budget intact.
    public func reloadDigest(today: Int) -> String {
        let state: String
        if isSolved(today: today) {
            state = "solved"
        } else if isInProgress(today: today), let fill = dailyFillFraction {
            state = "fill\(Int((fill * 10).rounded(.down)))"
        } else {
            state = "notStarted"
        }
        return "\(state)|\(displayedStreak(today: today))|\(totalPoints)"
    }
}

// MARK: - App-group persistence

/// Reads and writes the snapshot in the app-group container. Plain
/// sorted-keys JSON — CouchStored is never involved (PRD-3 §2).
public enum WidgetSnapshotStore {
    /// Per-app group id, matching the bundle-id convention.
    public static let appGroupID = "group.com.couchsuite.nine"
    public static let snapshotFileName = "widget-snapshot.json"

    /// nil when the app group isn't provisioned (e.g. tvOS, tests).
    public static var snapshotURL: URL? {
        FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupID)?
            .appendingPathComponent(snapshotFileName)
    }

    public static func load(from url: URL? = snapshotURL) -> WidgetSnapshot? {
        guard let url,
              let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(WidgetSnapshot.self, from: data),
              snapshot.schemaVersion <= WidgetSnapshot.currentSchemaVersion
        else { return nil }
        return snapshot
    }

    public static func save(_ snapshot: WidgetSnapshot, to url: URL? = snapshotURL) throws {
        guard let url else { throw CocoaError(.fileWriteUnknown) }
        try encoder.encode(snapshot).write(to: url, options: .atomic)
    }

    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }()

    static let decoder = JSONDecoder()

    // MARK: Day math (duplicated from the Engine, unit-test cross-checked)

    /// Days since the reference epoch in the given calendar's reckoning of
    /// `date`'s local day. Consecutive calendar days differ by exactly 1.
    /// Mirrors `DailySeed.dayOrdinal`.
    public static func dayOrdinal(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: components)!
        return Int((midnight.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }

    /// The next local midnight after `date` — the widget timeline's second
    /// entry, where the same snapshot re-renders as "new puzzle waiting".
    public static func nextLocalMidnight(after date: Date, calendar: Calendar = .current) -> Date {
        calendar.nextDate(
            after: date,
            matching: DateComponents(hour: 0, minute: 0, second: 0),
            matchingPolicy: .nextTime
        ) ?? date.addingTimeInterval(86_400)
    }
}
