// CouchStore — persistence (PRD §5.5).
//
// `@CouchStored` writes Codable values as JSON under Application Support,
// debounced so gameplay can hammer a value without hammering the disk.
// tvOS local storage is purgeable, so anything precious (streaks, progress)
// should pass `cloudSynced: true` to mirror into NSUbiquitousKeyValueStore.
// Compiles identically on iOS and macOS (same container layout, same KVS
// mirroring — on macOS the Application Support path resolves inside the App
// Sandbox container), which is what lets a universal app share one save
// format across every platform.
#if os(tvOS) || os(iOS) || os(macOS)
import SwiftUI
import CouchCore

/// JSON-on-disk persistence for one Codable value.
///
/// ```swift
/// @CouchStored("streak", cloudSynced: true) var streak = 0
/// ```
///
/// Thread-safe; writes are debounced (0.6s quiet / 3s max latency) on a
/// background task. Call `$streak.flushNow()` before deliberate teardown.
@propertyWrapper
public final class CouchStored<Value: Codable & Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var value: Value
    private var debouncer: WriteDebouncer
    private var flushTask: Task<Void, Never>?

    private let key: String
    private let profile: String
    private let cloudSynced: Bool
    private let fileURL: URL
    private let cloudKey: String

    public init(
        wrappedValue defaultValue: Value,
        _ key: String,
        profile: String = "default",
        cloudSynced: Bool = false,
        debounce: TimeInterval = 0.6
    ) {
        self.key = key
        self.profile = profile
        self.cloudSynced = cloudSynced
        self.debouncer = WriteDebouncer(interval: debounce, maxLatency: max(debounce, 3))
        self.cloudKey = CouchKeyspace.namespacedKey(key, profile: profile)
        self.fileURL = Self.directory.appendingPathComponent(
            CouchKeyspace.filename(forKey: key, profile: profile)
        )

        if let data = try? Data(contentsOf: fileURL),
           let stored = try? CouchJSON.decode(Value.self, from: data) {
            self.value = stored
        } else if cloudSynced,
                  let data = NSUbiquitousKeyValueStore.default.data(forKey: cloudKey),
                  let stored = try? CouchJSON.decode(Value.self, from: data) {
            // Fresh install / purged local storage: recover from iCloud.
            self.value = stored
        } else {
            self.value = defaultValue
        }
    }

    deinit {
        flushTask?.cancel()
        // Best effort: don't lose a value that changed within the debounce
        // window right before teardown.
        if debouncer.isDirty { try? persist(value) }
    }

    public var wrappedValue: Value {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            debouncer.recordChange(at: Date())
            lock.unlock()
            scheduleFlush()
        }
    }

    public var projectedValue: CouchStored<Value> { self }

    /// Write synchronously, bypassing the debounce.
    public func flushNow() throws {
        lock.lock()
        let snapshot = value
        _ = debouncer.shouldFlush(at: .distantFuture) // mark clean
        lock.unlock()
        try persist(snapshot)
    }

    // MARK: Internals

    private func scheduleFlush() {
        flushTask?.cancel()
        let interval = debouncer.interval
        flushTask = Task.detached(priority: .utility) { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
            guard !Task.isCancelled, let self else { return }
            let (due, snapshot) = self.lock.withLock {
                (self.debouncer.shouldFlush(at: Date()), self.value)
            }
            if due { try? self.persist(snapshot) }
        }
    }

    private func persist(_ snapshot: Value) throws {
        let data = try CouchJSON.encode(snapshot)
        try FileManager.default.createDirectory(
            at: Self.directory, withIntermediateDirectories: true
        )
        try data.write(to: fileURL, options: .atomic)
        if cloudSynced {
            NSUbiquitousKeyValueStore.default.set(data, forKey: cloudKey)
            NSUbiquitousKeyValueStore.default.synchronize()
        }
    }

    /// `Application Support/CouchKit/` in the app container.
    static var directory: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("CouchKit", isDirectory: true)
    }
}
#endif
