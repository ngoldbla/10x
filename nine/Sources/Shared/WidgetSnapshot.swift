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
    /// The single missed day the streak's bridge is spent on, mirrored from
    /// `StreakState.lastGraceDay` (PRD-13). Never rendered — the widget shows
    /// no shield — but `displayedStreak` cannot be honest without it.
    ///
    /// Additive and optional on purpose: `schemaVersion` stays at 1, because
    /// `load` rejects a snapshot newer than the reader and a bump would blank
    /// the widget rather than degrade it. A pre-grace file decodes this as nil,
    /// which reads as "a bridge is there" — the same answer a fresh install
    /// gives.
    public var lastGraceDay: Int?
    public var totalPoints: Int
    public var generatedAt: Date

    /// `ThemeChoice.rawValue` and `AccentChoice.rawValue`, mirrored from
    /// `SharedAppearance` (PRD-30). nil = written by a build before this field.
    ///
    /// The appearance already crossed one process boundary — the watch has read
    /// it out of KVS since PRD-6 — but never *this* one: `nine.appearance` goes
    /// to `CouchStored` + KVS and the widget extension reads neither, so
    /// `WidgetPalette` has been a hardcoded glacier-on-paper since PRD-3.
    /// Additive and optional, `schemaVersion` stays 1, for the reason
    /// `lastGraceDay` gives above. Resolved by `SharedPalette`.
    public var themeRaw: String?
    public var accentRaw: String?

    /// The active Focus filter, mirrored so the Home Screen goes quiet too
    /// (PRD-33). nil is the same answer as false: no filter.
    ///
    /// A filter that calmed the app while a widget two inches away kept showing
    /// the streak and the percentage would not be a filter; it would be a
    /// setting with a bug.
    public var focusHidesDaily: Bool?
    public var focusHidesStreak: Bool?

    public init(
        schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
        dailyDayOrdinal: Int? = nil,
        dailyFillFraction: Double? = nil,
        dailySolvedSeconds: TimeInterval? = nil,
        streakCurrent: Int = 0,
        streakBest: Int = 0,
        lastCompletedDay: Int? = nil,
        lastGraceDay: Int? = nil,
        totalPoints: Int = 0,
        generatedAt: Date = Date(),
        themeRaw: String? = nil,
        accentRaw: String? = nil,
        focusHidesDaily: Bool? = nil,
        focusHidesStreak: Bool? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.dailyDayOrdinal = dailyDayOrdinal
        self.dailyFillFraction = dailyFillFraction
        self.dailySolvedSeconds = dailySolvedSeconds
        self.streakCurrent = streakCurrent
        self.streakBest = streakBest
        self.lastCompletedDay = lastCompletedDay
        self.lastGraceDay = lastGraceDay
        self.totalPoints = totalPoints
        self.generatedAt = generatedAt
        self.themeRaw = themeRaw
        self.accentRaw = accentRaw
        self.focusHidesDaily = focusHidesDaily
        self.focusHidesStreak = focusHidesStreak
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

    /// Mirrors `StreakState.graceAvailable` (cross-checked by unit test).
    public var graceAvailable: Bool {
        guard let bridged = lastGraceDay, let last = lastCompletedDay else { return true }
        return last > bridged + 1
    }

    /// The streak a widget shows at `today`: yesterday's chain is still alive,
    /// one silent missed day is bridged while a bridge remains (PRD-13 §2), and
    /// anything older has lapsed to 0. Mirrors `StreakState.displayedStreak`
    /// (cross-checked by unit test).
    ///
    /// The mirror has to move with the original or the widget shows a lapsed
    /// flame the app still shows lit — on the one surface a player glances at
    /// without opening anything.
    public func displayedStreak(today: Int) -> Int {
        guard let last = lastCompletedDay else { return 0 }
        if last >= today - 1 { return streakCurrent }
        if last == today - 2, graceAvailable { return streakCurrent }
        return 0
    }

    /// Optimistically fold a solve made **entirely inside the widget** into the
    /// streak fields, so the glanceable widgets are honest before the app next
    /// activates and records the real thing (PRD-3 §2).
    ///
    /// Mirrors `StreakState.recordCompletion(day:)`, bridge included, and lives
    /// here rather than in `BoardIntents` because it used to live there — as a
    /// third hand-rolled copy of the rule, which PRD-13 promptly made wrong.
    /// Finish a daily in the widget after one missed day and the old code took
    /// the `else` branch and reset the streak to 1, while the app's next ingest
    /// bridged it back to 12. The widget would have been the app's one
    /// streak-shaming surface, on the screen a player is least likely to look
    /// twice at. Cross-checked against the Engine by unit test.
    public mutating func recordOptimisticSolve(day: Int) {
        if let last = lastCompletedDay {
            guard day > last else { return }
            if day == last + 1 {
                streakCurrent += 1
            } else if day == last + 2, graceAvailable {
                streakCurrent += 1
                lastGraceDay = day - 1
            } else {
                streakCurrent = 1
            }
        } else {
            streakCurrent = 1
        }
        lastCompletedDay = day
        streakBest = max(streakBest, streakCurrent)
    }

    /// Theme and accent as the widget's palette wants them (PRD-30). An older
    /// file, or a phone that has never opened prefs, yields the pair every
    /// reader already treats as "use your default".
    public var appearance: SharedAppearance {
        SharedAppearance(theme: themeRaw ?? "", accent: accentRaw ?? "")
    }

    /// The Focus filter, with nil read as "none" (PRD-33).
    public var focus: QuietFocus {
        QuietFocus(
            hidesDaily: focusHidesDaily ?? false,
            hidesStreak: focusHidesStreak ?? false
        )
    }

    /// Coarse digest gating `WidgetCenter` reloads: state bucket
    /// (notStarted / solved / fill decile), displayed streak, points — plus the
    /// exact daily board revision. `place()` publishes on every move, and the
    /// decile bucket used to lag the playable BoardWidget (a move within a
    /// decile didn't change the digest, so no reload). Appending the revision
    /// makes every *daily* move reload the widget (foreground reloads are
    /// WidgetKit-budget-exempt); free-play moves don't bump the revision, so
    /// there's no waste. Pass 0 to reproduce the pre-fix, glanceable-only digest.
    ///
    /// Appearance and Focus join the digest for the same reason the revision did:
    /// they change what the widget draws, so a change that is not in here is a
    /// change the Home Screen does not show. Switching theme, or turning on a
    /// Focus, would otherwise leave three widgets in the old look until some
    /// unrelated move happened to move the bucket.
    public func reloadDigest(today: Int, boardRevision: Int = 0) -> String {
        let state: String
        if isSolved(today: today) {
            state = "solved"
        } else if isInProgress(today: today), let fill = dailyFillFraction {
            state = "fill\(Int((fill * 10).rounded(.down)))"
        } else {
            state = "notStarted"
        }
        let look = "\(themeRaw ?? "-")/\(accentRaw ?? "-")"
        let quiet = "\(focusHidesDaily == true ? "d" : "-")\(focusHidesStreak == true ? "s" : "-")"
        return "\(state)|\(displayedStreak(today: today))|\(totalPoints)"
            + "|r\(boardRevision)|\(look)|\(quiet)"
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
