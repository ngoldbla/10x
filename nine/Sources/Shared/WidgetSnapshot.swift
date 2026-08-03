// WidgetSnapshot.swift — the one-way bridge from the app to the widget
// extension (PRD-3 §2). The app writes this small versioned JSON into the
// app-group container; the widget only ever reads it. Raw facts, not display
// values, so the timeline provider can re-derive state at any entry date.
//
// This file compiles into BOTH the app target and the widget extension (and
// as the `NineShared` SwiftPM module for tests). It must stay pure
// Foundation: no CouchKit, no Engine. The ~10 lines of day math are
// deliberately duplicated from `DailySeed.dayOrdinal` — a unit test
// cross-checks them against the original.
//
// The daily/streak fields were removed on 2026-08-02 with the daily system
// itself; the snapshot now carries the in-progress board's facts, the points
// total, and the appearance the widget draws with.
import Foundation

/// Everything a glanceable widget needs to render Nine's state.
public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public static let currentSchemaVersion = 1

    public var schemaVersion: Int
    /// Fill fraction of the shared board; nil = no board in progress.
    public var boardFillFraction: Double?
    /// Solve time for the shared board once solved, when known.
    public var boardSolvedSeconds: TimeInterval?
    public var totalPoints: Int
    public var generatedAt: Date

    /// `ThemeChoice.rawValue` and `AccentChoice.rawValue`, mirrored from
    /// `SharedAppearance` (PRD-30). nil = written by a build before this field.
    public var themeRaw: String?
    public var accentRaw: String?

    public init(
        schemaVersion: Int = WidgetSnapshot.currentSchemaVersion,
        boardFillFraction: Double? = nil,
        boardSolvedSeconds: TimeInterval? = nil,
        totalPoints: Int = 0,
        generatedAt: Date = Date(),
        themeRaw: String? = nil,
        accentRaw: String? = nil
    ) {
        self.schemaVersion = schemaVersion
        self.boardFillFraction = boardFillFraction
        self.boardSolvedSeconds = boardSolvedSeconds
        self.totalPoints = totalPoints
        self.generatedAt = generatedAt
        self.themeRaw = themeRaw
        self.accentRaw = accentRaw
    }

    /// Tolerant decode: every field falls back rather than throwing, so a file
    /// written by an older build (which carried daily/streak fields under
    /// other keys) still yields a drawable snapshot.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        schemaVersion = ((try? c.decodeIfPresent(Int.self, forKey: .schemaVersion)) ?? nil)
            ?? Self.currentSchemaVersion
        boardFillFraction =
            ((try? c.decodeIfPresent(Double.self, forKey: .boardFillFraction)) ?? nil) ?? nil
        boardSolvedSeconds =
            ((try? c.decodeIfPresent(TimeInterval.self, forKey: .boardSolvedSeconds)) ?? nil) ?? nil
        totalPoints = ((try? c.decodeIfPresent(Int.self, forKey: .totalPoints)) ?? nil) ?? 0
        generatedAt = ((try? c.decodeIfPresent(Date.self, forKey: .generatedAt)) ?? nil) ?? Date()
        themeRaw = ((try? c.decodeIfPresent(String.self, forKey: .themeRaw)) ?? nil) ?? nil
        accentRaw = ((try? c.decodeIfPresent(String.self, forKey: .accentRaw)) ?? nil) ?? nil
    }

    enum CodingKeys: String, CodingKey {
        case schemaVersion, boardFillFraction, boardSolvedSeconds
        case totalPoints, generatedAt, themeRaw, accentRaw
    }
}

// MARK: - Derivation

extension WidgetSnapshot {
    /// Theme and accent as the widget's palette wants them (PRD-30). An older
    /// file, or a phone that has never opened prefs, yields the pair every
    /// reader already treats as "use your default".
    public var appearance: SharedAppearance {
        SharedAppearance(theme: themeRaw ?? "", accent: accentRaw ?? "")
    }

    /// Coarse digest gating `WidgetCenter` reloads: fill decile, points, the
    /// exact board revision, and the appearance. `place()` publishes on every
    /// move, and the system reload budget is finite; the revision makes every
    /// board move reload the playable widget (foreground reloads are
    /// budget-exempt) while an unchanged snapshot costs nothing.
    public func reloadDigest(boardRevision: Int = 0) -> String {
        let state: String
        if boardSolvedSeconds != nil {
            state = "solved"
        } else if let fill = boardFillFraction {
            state = "fill\(Int((fill * 10).rounded(.down)))"
        } else {
            state = "empty"
        }
        let look = "\(themeRaw ?? "-")/\(accentRaw ?? "-")"
        return "\(state)|\(totalPoints)|r\(boardRevision)|\(look)"
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
    /// Mirrors `DailySeed.dayOrdinal`. Still used: the widget's ephemeral
    /// cell selection is keyed to the day so a leftover selection cannot
    /// point into a board adopted later.
    public static func dayOrdinal(for date: Date, calendar: Calendar = .current) -> Int {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        let midnight = utc.date(from: components)!
        return Int((midnight.timeIntervalSinceReferenceDate / 86_400).rounded(.down))
    }
}
