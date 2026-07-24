// LibrarySync.swift — the cloud merge core (PRD-8). Pure, Sendable, no
// CloudKit and no UI, so it lives in the Engine and is fully SwiftPM-testable
// on Linux. `SyncedEntry` is the CloudKit projection of a `LibraryEntry`
// (drops the undo stack and move log — device-local UX state, ~1-2 KB once
// gone); `LibrarySync` holds the merge rules that reconcile a remote entry
// into the local library without ever losing progress silently.
import Foundation

/// A `LibraryEntry` as it travels through CloudKit: the board and its
/// lifecycle, minus device-local history. One `SyncedEntry` ⇔ one `CKRecord`.
public struct SyncedEntry: Codable, Sendable, Equatable {
    public let id: UUID
    public var kind: GameKind
    public var status: BoardStatus
    public var game: NineGame
    public let createdAt: Date
    public var updatedAt: Date
    public var solvedAt: Date?

    /// Project a library entry for the cloud: strip undo/move log.
    public init(_ entry: LibraryEntry) {
        var g = entry.game
        g.clearLocalHistory()
        self.id = entry.id
        self.kind = entry.kind
        self.status = entry.status
        self.game = g
        self.createdAt = entry.createdAt
        self.updatedAt = entry.updatedAt
        self.solvedAt = entry.solvedAt
    }

    /// Rebuild a library entry (undo/move log start empty on the new device).
    public func hydrated() -> LibraryEntry {
        LibraryEntry(
            id: id, kind: kind, game: game, status: status,
            createdAt: createdAt, updatedAt: updatedAt, solvedAt: solvedAt
        )
    }

    enum CodingKeys: String, CodingKey {
        case id, kind, status, game, createdAt, updatedAt, solvedAt
    }

    /// Tolerant decoding: any field added after this ships must fall back to a
    /// default rather than throwing (a thrown decode drops the whole record).
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        kind = try c.decode(GameKind.self, forKey: .kind)
        status = (try? c.decode(BoardStatus.self, forKey: .status)) ?? .inProgress
        game = try c.decode(NineGame.self, forKey: .game)
        createdAt = try c.decode(Date.self, forKey: .createdAt)
        updatedAt = try c.decode(Date.self, forKey: .updatedAt)
        solvedAt = try c.decodeIfPresent(Date.self, forKey: .solvedAt)
    }
}
