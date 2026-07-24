// LibrarySyncState.swift — the CKSyncEngine state we must persist between
// launches (PRD-8 §2: "a small persisted sync-state blob, CouchStored,
// tolerant decoding"). CKSyncEngine hands us an opaque State.Serialization on
// every .stateUpdate event; we store its encoded form and feed it back at
// construction so the engine resumes its change-token position instead of
// re-fetching the whole zone.
#if os(iOS) || os(macOS) || os(tvOS)
import Foundation
import CloudKit

struct LibrarySyncState: Codable, Sendable {
    /// The engine's opaque serialized state, or nil before the first sync.
    var serialization: Data?

    init(serialization: Data? = nil) { self.serialization = serialization }

    enum CodingKeys: String, CodingKey { case serialization }

    /// Tolerant: a missing/garbled blob just means "start fresh", never a throw
    /// (a thrown decode makes CouchStored discard the whole value).
    init(from decoder: Decoder) throws {
        let c = try? decoder.container(keyedBy: CodingKeys.self)
        serialization = (try? c?.decodeIfPresent(Data.self, forKey: .serialization)) ?? nil
    }

    /// Decode into the CKSyncEngine type, tolerating shape drift.
    func engineState() -> CKSyncEngine.State.Serialization? {
        guard let serialization else { return nil }
        return try? JSONDecoder().decode(
            CKSyncEngine.State.Serialization.self, from: serialization
        )
    }

    /// Capture a new serialization from the engine.
    static func from(_ state: CKSyncEngine.State.Serialization) -> LibrarySyncState {
        LibrarySyncState(serialization: try? JSONEncoder().encode(state))
    }
}
#endif
