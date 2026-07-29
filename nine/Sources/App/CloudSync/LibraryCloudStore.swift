// LibraryCloudStore.swift — the CloudKit boundary (PRD-8 §2). Owns one
// CKSyncEngine over the private database and a single custom zone
// `NineLibrary`; every LibraryEntry is one CKRecord (record name = entry uuid)
// carrying the SyncedEntry projection. No CKQuery polling — the engine's event
// stream drives fetch and send. This is the ONLY file in the app that imports
// CloudKit; the merge rules it applies live, tested, in the Engine.
#if os(iOS) || os(macOS) || os(tvOS)
import Foundation
import CloudKit
import OSLog
import CouchKit

@MainActor
final class LibraryCloudStore {
    nonisolated static let zoneName = "NineLibrary"
    nonisolated static let recordType = "LibraryEntry"
    /// PRD-26's immutable solve records, in the **same** zone.
    ///
    /// A new record type in an existing container needs **no entitlement change
    /// and no `match` re-mint** — EXECUTING-A-PRD §6's trap fires on
    /// capabilities, and a record type is schema. It does need the schema
    /// deployed to the CloudKit *production* environment before release, which
    /// is human-owned, like PRD-7 §5's container gate.
    nonisolated static let replayRecordType = "SolveReplay"
    nonisolated static let containerID = "iCloud.com.couchsuite.nine"

    /// A replay's record name is its board's uuid behind this prefix, so the
    /// two record types can share the zone without colliding on a name — and so
    /// a replay is findable from a board id without an index.
    nonisolated static let replayRecordPrefix = "replay-"

    var onRemoteEntry: (@MainActor (SyncedEntry) -> Void)?
    var onRemoteReplay: (@MainActor (SolveReplay) -> Void)?
    var onRemoteDeletion: (@MainActor (UUID) -> Void)?
    var onAccountReset: (@MainActor () -> Void)?

    private let database: CKDatabase
    private let zoneID: CKRecordZone.ID
    private var engine: CKSyncEngine?
    private let log = Logger(subsystem: "com.couchsuite.nine", category: "cloud-sync")

    private let stateStore = CouchStored(
        wrappedValue: LibrarySyncState(), "nine.cloudSyncState"
    )
    /// Snapshots the caller has handed us, so we can build records on demand
    /// when the engine asks for the next batch.
    private var pendingProjections: [CKRecord.ID: SyncedEntry] = [:]
    /// The same queue for replays. A second dictionary rather than an enum over
    /// both, because the two never key the same record name and every site that
    /// reads one is a site that would have had to switch on the other.
    private var pendingReplays: [CKRecord.ID: SolveReplay] = [:]

    init() {
        let container = CKContainer(identifier: Self.containerID)
        self.database = container.privateCloudDatabase
        self.zoneID = CKRecordZone.ID(zoneName: Self.zoneName, ownerName: CKCurrentUserDefaultName)
    }

    /// Whether the engine has ever persisted state (i.e. synced at least once).
    /// Nil serialization = a first run, so the caller seeds the whole library.
    var hasSyncedBefore: Bool { stateStore.wrappedValue.serialization != nil }

    /// Begin syncing (idempotent). Safe with no iCloud account: the engine
    /// simply emits no zone changes until an account appears.
    func start() {
        guard engine == nil else { return }
        var configuration = CKSyncEngine.Configuration(
            database: database,
            stateSerialization: stateStore.wrappedValue.engineState(),
            delegate: self
        )
        configuration.automaticallySync = true
        engine = CKSyncEngine(configuration)
    }

    func push(_ entry: LibraryEntry) {
        let projection = SyncedEntry(entry)
        let recordID = CKRecord.ID(recordName: entry.id.uuidString, zoneID: zoneID)
        pendingProjections[recordID] = projection
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    /// Send an immutable solve record (PRD-26 §4). Idempotent by construction:
    /// the record name is derived from the board id, so re-sending a replay
    /// overwrites the same record rather than accumulating one per attempt.
    func push(_ replay: SolveReplay) {
        let recordID = replayRecordID(replay.boardID)
        pendingReplays[recordID] = replay
        engine?.state.add(pendingRecordZoneChanges: [.saveRecord(recordID)])
    }

    /// Deleting a board takes its replay with it — the same rule
    /// `ReplayVault.prune` holds locally, so the two cannot disagree about
    /// whether a deleted board still has a memory.
    func delete(_ id: UUID) {
        let recordID = CKRecord.ID(recordName: id.uuidString, zoneID: zoneID)
        let replayID = replayRecordID(id)
        pendingProjections.removeValue(forKey: recordID)
        pendingReplays.removeValue(forKey: replayID)
        engine?.state.add(pendingRecordZoneChanges: [
            .deleteRecord(recordID), .deleteRecord(replayID)
        ])
    }

    private func replayRecordID(_ boardID: UUID) -> CKRecord.ID {
        CKRecord.ID(recordName: Self.replayRecordPrefix + boardID.uuidString, zoneID: zoneID)
    }

    /// Ask CloudKit to fetch now (called on foreground). Ambient: no engine /
    /// no account → no-op.
    func kick() {
        guard let engine else { return }
        Task { try? await engine.fetchChanges() }
    }

    // MARK: - Record <-> projection

    /// Build a CKRecord from a projection. `nonisolated static` so the engine's
    /// `@Sendable` record-provider closure can call it without a main-actor hop
    /// and without capturing any non-Sendable state (only the Sendable
    /// SyncedEntry crosses the boundary).
    nonisolated static func makeRecord(recordID: CKRecord.ID, projection: SyncedEntry) -> CKRecord {
        let record = CKRecord(recordType: recordType, recordID: recordID)
        // One blob field keeps the record robust against schema drift; a couple
        // of scalar fields stay queryable in the CloudKit console for debugging.
        if let payload = try? JSONEncoder().encode(projection) {
            record["payload"] = payload as CKRecordValue
        }
        record["updatedAt"] = projection.updatedAt as CKRecordValue
        record["status"] = projection.status.rawValue as CKRecordValue
        return record
    }

    /// The replay's twin. One blob field for the same reason: a record type
    /// this build has never seen a new field on still round-trips.
    nonisolated static func makeReplayRecord(recordID: CKRecord.ID, replay: SolveReplay) -> CKRecord {
        let record = CKRecord(recordType: replayRecordType, recordID: recordID)
        if let payload = try? CouchJSON.encode(replay) {
            record["payload"] = payload as CKRecordValue
        }
        record["solvedAt"] = replay.solvedAt as CKRecordValue
        record["band"] = replay.band as CKRecordValue
        return record
    }

    private func projection(from record: CKRecord) -> SyncedEntry? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? JSONDecoder().decode(SyncedEntry.self, from: data)
    }

    private func replay(from record: CKRecord) -> SolveReplay? {
        guard let data = record["payload"] as? Data else { return nil }
        return try? CouchJSON.decode(SolveReplay.self, from: data)
    }
}

extension LibraryCloudStore: CKSyncEngineDelegate {

    func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
        switch event {
        case .stateUpdate(let update):
            stateStore.wrappedValue = .from(update.stateSerialization)
            try? stateStore.flushNow()

        case .accountChange(let change):
            // Signed out / switched account: reset local send queue and let the
            // caller re-push. Signing in triggers a fresh push too.
            switch change.changeType {
            case .signOut, .switchAccounts:
                pendingProjections.removeAll()
                onAccountReset?()
            case .signIn:
                onAccountReset?()
            @unknown default:
                break
            }

        case .fetchedRecordZoneChanges(let changes):
            for modification in changes.modifications {
                // Discriminated on `recordType`, not on the name prefix: the
                // name is how the record is *addressed* and the type is what it
                // *is*, and a build that meets a third type must skip it rather
                // than mis-decode it as one of these two.
                switch modification.record.recordType {
                case Self.recordType:
                    if let projection = projection(from: modification.record) {
                        onRemoteEntry?(projection)
                    }
                case Self.replayRecordType:
                    if let replay = replay(from: modification.record) {
                        onRemoteReplay?(replay)
                    }
                default:
                    break
                }
            }
            for deletion in changes.deletions {
                // A replay deletion arrives alongside its board's; the board's
                // is the one that carries the id, and prefixed names are
                // deliberately not parsed back into one.
                if let id = UUID(uuidString: deletion.recordID.recordName) {
                    onRemoteDeletion?(id)
                }
            }

        case .sentRecordZoneChanges(let sent):
            for saved in sent.savedRecords {
                pendingProjections.removeValue(forKey: saved.recordID)
                pendingReplays.removeValue(forKey: saved.recordID)
            }
            for failed in sent.failedRecordSaves {
                log.error("record save failed: \(failed.error, privacy: .public)")
            }

        case .willFetchChanges, .didFetchChanges, .willSendChanges, .didSendChanges,
             .fetchedDatabaseChanges, .sentDatabaseChanges:
            break

        @unknown default:
            break
        }
    }

    func nextRecordZoneChangeBatch(
        _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
    ) async -> CKSyncEngine.RecordZoneChangeBatch? {
        let scope = context.options.scope
        let pending = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
        guard !pending.isEmpty else { return nil }
        // Snapshot only Sendable data (keyed by recordName String) so the
        // @Sendable provider closure captures nothing main-actor-isolated.
        let projectionsByName = Dictionary(
            pendingProjections.map { ($0.key.recordName, $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
        let replaysByName = Dictionary(
            pendingReplays.map { ($0.key.recordName, $0.value) },
            uniquingKeysWith: { _, latest in latest }
        )
        return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: pending) { recordID in
            if let projection = projectionsByName[recordID.recordName] {
                return LibraryCloudStore.makeRecord(recordID: recordID, projection: projection)
            }
            if let replay = replaysByName[recordID.recordName] {
                return LibraryCloudStore.makeReplayRecord(recordID: recordID, replay: replay)
            }
            return nil
        }
    }
}
#endif
